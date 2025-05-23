import json
import os
import psycopg2
import argparse

def main():
    parser = argparse.ArgumentParser(description="Script to process JSON data and interact with PostgreSQL")
    parser.add_argument("script_dir", help="Path to the directory containing 'accounts_dump.json'")
    parser.add_argument("--host", default="docker", help="PostgreSQL host (default: docker)")
    parser.add_argument("--port", type=int, default=5432, help="PostgreSQL port (default: 5432)")
    parser.add_argument("--database", default="haf_block_log", help="PostgreSQL database name (default: haf_block_log)")
    parser.add_argument("--user", default="haf_admin", help="PostgreSQL user (default: haf_admin)")
    parser.add_argument("--password", default="", help="PostgreSQL password (default: empty)")
    parser.add_argument("--debug", action="store_true", help="Run in debug mode (default: false)")
    parser.add_argument("--type", default="account", help="Which test is running (account or witness, default: account)")

    args = parser.parse_args()
    
    json_file_path = os.path.join(args.script_dir, "accounts_dump.json")

    if args.debug:
        print("Opening file {filename}".format(filename=json_file_path))
    with open(json_file_path) as file:
        data = json.load(file)

    if args.type == "account":
        accounts = data["result"]["accounts"]
    else:
        accounts = data["result"]

    try:
        if args.debug:
            print("""
            Database hostname: {hostname}
            Database port: {port}
            Database user: {username}
            Database password: {password}
            Database name: {database}
            """.format(
                    hostname=args.host,
                    port=args.port,
                    username=args.user,
                    password=args.password,
                    database=args.database))
        connection = psycopg2.connect(
            host=args.host,
            port=args.port,
            database=args.database,
            user=args.user,
            password=args.password
        )

        cursor = connection.cursor()

        if args.type == "account":
            query = "SELECT hafbe_backend.dump_current_account_stats(%s)"
        else:
            query = "SELECT hafbe_backend.dump_current_witness_props(%s)"

        # Iterate over objects inside 'accounts[]'
        for account in accounts:
            if args.debug: 
                if args.type == "account":
                    print("Processing account '{name}'".format(name=account["name"]))
                else:
                    print("Processing account '{name}'".format(name=account["owner"]))
            object_value = json.dumps(account)
            cursor.execute(query, (object_value,))

        connection.commit()
        cursor.close()
        connection.close()

    except psycopg2.Error as e:
        print("Error processing account dump file")
        print(e)
        exit(1)

if __name__ == "__main__":
    main()