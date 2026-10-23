import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock

SPEC = importlib.util.spec_from_file_location(
    "operating_schedule", Path(__file__).resolve().parents[1] / "terraform/aws/lambda/operating_schedule.py"
)
schedule = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(schedule)


class ScheduleTests(unittest.TestCase):
    def clients(self, ec2_state="stopped", db_state="stopped"):
        ec2, rds = Mock(), Mock()
        ec2.describe_instances.return_value = {"Reservations": [{"Instances": [{"State": {"Name": ec2_state}}]}]}
        rds.describe_db_instances.return_value = {"DBInstances": [{"DBInstanceStatus": db_state}]}
        return ec2, rds

    def test_starts_both_stopped_resources(self):
        ec2, rds = self.clients()
        schedule.apply_action("start", ec2, rds, "i-test", "db-test")
        ec2.start_instances.assert_called_once_with(InstanceIds=["i-test"])
        rds.start_db_instance.assert_called_once_with(DBInstanceIdentifier="db-test")

    def test_stop_is_safe_to_repeat(self):
        ec2, rds = self.clients("stopping", "stopped")
        schedule.apply_action("stop", ec2, rds, "i-test", "db-test")
        ec2.stop_instances.assert_not_called()
        rds.stop_db_instance.assert_not_called()

    def test_one_failure_does_not_leave_other_resource_running(self):
        ec2, rds = self.clients("running", "backing-up")
        with self.assertRaisesRegex(RuntimeError, "backing-up"):
            schedule.apply_action("stop", ec2, rds, "i-test", "db-test")
        ec2.stop_instances.assert_called_once()

    def test_start_in_progress_will_retry_stop(self):
        ec2, rds = self.clients("pending", "starting")
        with self.assertRaisesRegex(RuntimeError, "retry stop"):
            schedule.apply_action("stop", ec2, rds, "i-test", "db-test")

    def test_no_database_does_not_call_rds(self):
        ec2, rds = self.clients("running")
        schedule.apply_action("stop", ec2, rds, "i-test", "")
        rds.describe_db_instances.assert_not_called()

    def test_invalid_action_has_no_side_effects(self):
        ec2, rds = self.clients()
        with self.assertRaises(ValueError):
            schedule.apply_action("destroy", ec2, rds, "i-test", "db-test")
        ec2.describe_instances.assert_not_called()
        rds.describe_db_instances.assert_not_called()
