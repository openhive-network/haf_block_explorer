#!/usr/bin/env python3
# =============================================================================
# HAF Block Explorer Regression Test - Data Loader
# =============================================================================
#
# PURPOSE:
#   Loads expected account or witness data from hived JSON dumps into the
#   hafbe_test schema for regression comparison.
#
# USAGE:
#   python3 load_expected_data.py <script_dir> --type account [OPTIONS]
#   python3 load_expected_data.py <script_dir> --type witness [OPTIONS]
#
# =============================================================================

import json
import os
import sys
import argparse

try:
    import psycopg2
except ImportError:
    print("ERROR: psycopg2 is required. Install with: pip install psycopg2-binary")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Load expected data from hived JSON dumps into hafbe_test schema"
    )
    parser.add_argument(
        "script_dir",
        help="Path to the directory containing the JSON dump file"
    )
    parser.add_argument(
        "--host",
        default="localhost",
        help="PostgreSQL host (default: localhost)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=5432,
        help="PostgreSQL port (default: 5432)"
    )
    parser.add_argument(
        "--database",
        default="haf_block_log",
        help="PostgreSQL database name (default: haf_block_log)"
    )
    parser.add_argument(
        "--user",
        default="haf_admin",
        help="PostgreSQL user (default: haf_admin)"
    )
    parser.add_argument(
        "--password",
        default="",
        help="PostgreSQL password (default: empty)"
    )
    parser.add_argument(
        "--type",
        choices=["account", "witness"],
        default="account",
        help="Type of data to load: account or witness (default: account)"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug output"
    )

    args = parser.parse_args()

    # Determine JSON file path based on type
    if args.type == "account":
        json_filename = "accounts_dump.json"
    else:
        json_filename = "witnesses_dump.json"

    json_file_path = os.path.join(args.script_dir, json_filename)

    if args.debug:
        print(f"Opening file: {json_file_path}")

    if not os.path.exists(json_file_path):
        print(f"ERROR: File not found: {json_file_path}")
        sys.exit(1)

    with open(json_file_path, 'r') as file:
        data = json.load(file)

    # Extract records based on type
    if args.type == "account":
        records = data.get("result", {}).get("accounts", [])
        query = "SELECT hafbe_test.load_expected_account_stats(%s)"
        name_field = "name"
    else:
        records = data.get("result", [])
        query = "SELECT hafbe_test.load_expected_witness_props(%s)"
        name_field = "owner"

    if not records:
        print(f"ERROR: No {args.type} records found in JSON file")
        sys.exit(1)

    print(f"Found {len(records)} {args.type} records to load")

    try:
        if args.debug:
            print(f"""
            Database hostname: {args.host}
            Database port: {args.port}
            Database user: {args.user}
            Database name: {args.database}
            """)

        connection = psycopg2.connect(
            host=args.host,
            port=args.port,
            database=args.database,
            user=args.user,
            password=args.password
        )
        cursor = connection.cursor()

        # Process records with progress reporting
        for i, record in enumerate(records, 1):
            if args.debug:
                record_name = record.get(name_field, f"record_{i}")
                print(f"Processing {args.type}: {record_name}")

            record_json = json.dumps(record)
            cursor.execute(query, (record_json,))

            # Progress report every 1000 records
            if i % 1000 == 0:
                print(f"  Processed {i}/{len(records)} {args.type}s...")

        connection.commit()
        cursor.close()
        connection.close()

        print(f"Successfully loaded {len(records)} {args.type} records")

    except psycopg2.Error as e:
        print(f"ERROR: Database error while loading {args.type} data")
        print(e)
        sys.exit(1)


if __name__ == "__main__":
    main()
