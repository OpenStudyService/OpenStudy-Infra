#!/usr/bin/env python3
"""Conservative monthly estimate, not an AWS billing cap. No credits assumed."""

import argparse
import json


# AWS Price List API, ap-northeast-2, Linux On-Demand, checked 2026-10-22.
RATES = {
    "EC2 t4g.medium": 0.0416,
    "EC2 c7i-flex.large": 0.09576,
    "Public IPv4": 0.005,
    "RDS db.t4g.micro Single-AZ": 0.025,
    "EBS gp3": 0.0912,
    "RDS gp3": 0.131,
    "Secrets Manager": 0.40,
    "ECR": 0.10,
    "CloudWatch ingest": 0.76,
    "CloudWatch storage": 0.0314,
    "Internet transfer": 0.126,
}


def estimate(weekdays=23, hours_per_day=7, exchange_rate=1500, instance_type="c7i-flex.large"):
    hours = weekdays * hours_per_day
    # Use a 31-day month for storage, even in shorter months.
    storage_factor = 744 / 730
    items = {
        f"EC2 {instance_type}": hours * RATES[f"EC2 {instance_type}"],
        "Public IPv4": hours * RATES["Public IPv4"],
        "RDS db.t4g.micro Single-AZ": hours * RATES["RDS db.t4g.micro Single-AZ"],
        "EBS gp3 30 GiB": 30 * RATES["EBS gp3"] * storage_factor,
        "RDS gp3 20 GiB": 20 * RATES["RDS gp3"] * storage_factor,
        "RDS master secret": RATES["Secrets Manager"] * storage_factor,
        "ECR 2 GB": 2 * RATES["ECR"] * storage_factor,
        "CloudWatch 1 GB ingest + storage": RATES["CloudWatch ingest"] + RATES["CloudWatch storage"] * storage_factor,
        "Internet transfer 1 GB": RATES["Internet transfer"],
        "S3, Lambda, Scheduler, API allowance": 0.20,
    }
    usd = sum(items.values())
    return {
        "rate_date": "2026-10-22", "region": "ap-northeast-2", "operating_hours": hours,
        "krw_per_usd_assumption": exchange_rate, "vat": 0.10,
        "items_usd": {key: round(value, 4) for key, value in items.items()},
        "total_usd_before_vat": round(usd, 4),
        "total_krw_with_vat": round(usd * exchange_rate * 1.10),
        "budget_krw": 50000,
        "headroom_krw": round(50000 - usd * exchange_rate * 1.10),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--weekdays", type=int, choices=range(1, 24), default=23)
    parser.add_argument("--hours-per-day", type=float, default=7)
    parser.add_argument("--krw-per-usd", type=float, default=1500)
    parser.add_argument("--instance-type", choices=["t4g.medium", "c7i-flex.large"], default="c7i-flex.large")
    args = parser.parse_args()
    if not 0 < args.hours_per_day <= 24 or args.krw_per_usd <= 0:
        parser.error("Hours must be in (0,24]; exchange rate must be positive.")
    result = estimate(args.weekdays, args.hours_per_day, args.krw_per_usd, args.instance_type)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if result["headroom_krw"] < 0:
        parser.exit(1, "Estimated monthly cost exceeds KRW 50,000.\n")


if __name__ == "__main__":
    main()
