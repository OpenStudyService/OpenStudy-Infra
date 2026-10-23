"""Start or stop the two budget resources. AWS retries transient state conflicts."""

import os


def change_ec2(client, instance_id, action):
    response = client.describe_instances(InstanceIds=[instance_id])
    state = response["Reservations"][0]["Instances"][0]["State"]["Name"]
    if action == "start" and state == "stopped":
        client.start_instances(InstanceIds=[instance_id])
    elif action == "stop" and state == "running":
        client.stop_instances(InstanceIds=[instance_id])
    elif state not in ({"running", "pending"} if action == "start" else {"stopped", "stopping"}):
        raise RuntimeError(f"EC2 is {state}; retry {action} later")
    return state


def change_rds(client, identifier, action):
    state = client.describe_db_instances(DBInstanceIdentifier=identifier)["DBInstances"][0]["DBInstanceStatus"]
    if action == "start" and state == "stopped":
        client.start_db_instance(DBInstanceIdentifier=identifier)
    elif action == "stop" and state == "available":
        client.stop_db_instance(DBInstanceIdentifier=identifier)
    elif state not in ({"available", "starting"} if action == "start" else {"stopped", "stopping"}):
        raise RuntimeError(f"RDS is {state}; retry {action} later")
    return state


def apply_action(action, ec2, rds, instance_id, database_identifier):
    if action not in {"start", "stop"}:
        raise ValueError("action must be start or stop")
    states, errors = {}, []
    # One failed API call must not prevent an attempt to stop the other resource.
    resources = [("ec2", lambda: change_ec2(ec2, instance_id, action))]
    if database_identifier:
        resources.insert(0, ("rds", lambda: change_rds(rds, database_identifier, action)))
    for name, operation in resources:
        try:
            states[name] = operation()
        except Exception as error:
            errors.append(f"{name}: {error}")
    if errors:
        raise RuntimeError("; ".join(errors))
    return {"action": action, "previous_states": states}


def handler(event, context):
    import boto3

    result = apply_action(
        event["action"], boto3.client("ec2"), boto3.client("rds"),
        os.environ["INSTANCE_ID"], os.environ.get("DATABASE_IDENTIFIER", ""),
    )
    print(result)
    return result
