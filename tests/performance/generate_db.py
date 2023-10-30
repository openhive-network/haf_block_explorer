import os
import random
import psycopg2
import argparse

def parse_args():
  parser = argparse.ArgumentParser()
  
  parser.add_argument('--database-size', type=int, default=1000, help="Database size (default: 1000)")
  parser.add_argument("--host", default="docker", help="PostgreSQL host (default: docker)")
  parser.add_argument("--port", type=int, default=5432, help="PostgreSQL port (default: 5432)")
  parser.add_argument("--database", default="haf_block_log", help="PostgreSQL database name (default: haf_block_log)")
  parser.add_argument("--user", default="haf_admin", help="PostgreSQL user (default: haf_admin)")
  parser.add_argument("--password", default="", help="PostgreSQL password (default: empty)")
  parser.add_argument("--debug", action="store_true", help="Run in debug mode (default: false)")
  
  return parser.parse_args()

def call_sql(args, query_without_limit, limit):
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

    query = "{query} LIMIT {limit:d}".format(query=query_without_limit, limit=limit)
    cursor.execute(query)
    response = cursor.fetchall()
    result = [row[0] for row in response] 

    connection.commit()
    cursor.close()
    connection.close()

    if args.debug:
      print("Query: '{query}', result:\n".format(query=query))
      print(*result, sep = ", ", end = "\n\n")

    return result

  except psycopg2.Error as e:
    print("Error: Unable to connect to the PostgreSQL database.")
    print(e)

def gen_rand_block_range(args, limit):
  max_block = int(call_sql(args, "SELECT num FROM hive.blocks_view ORDER BY num DESC", 1)[0])
  return [str(random.randint(0, max_block)) for i in range(limit)]

def get_acc_names(args, limit):
  return call_sql(args, "SELECT hav.name FROM hafbe_app.current_witnesses cw JOIN hive.accounts_view hav ON hav.id = cw.witness_id", limit)

def generate_input_db(args):
  db_size = args.database_size
  limit = db_size // 4
  data = gen_rand_block_range(args, limit)
  rand_block_arr_str = "'{{{}}}'".format(','.join(data))
  data += call_sql(args, "SELECT encode(hash, 'hex') FROM hive.blocks_view WHERE num = ANY({})".format(rand_block_arr_str), limit)
  data += call_sql(args, "SELECT encode(trx_hash, 'hex') FROM hive.transactions_view WHERE block_num = ANY({})".format(rand_block_arr_str), limit)
  data += get_acc_names(args, limit)
  return data

def generate_timestamps(args, rand_block_arr_str):
  return call_sql(args, "SELECT to_char(created_at, 'YYYY-MM-DDThh24:MI:SS') FROM hive.blocks_view WHERE num = ANY({})".format(rand_block_arr_str), args.database_size)

def generate_db(args):
  if args.debug:
    print("Generating database test data...")

  db_size = args.database_size
  if args.debug:
    print("Requested database size {size:d}".format(size=db_size))

  if args.debug:
    print("Generating random block range...")
  rand_blocks = gen_rand_block_range(args, db_size)
  rand_block_arr_str = "'{{{}}}'".format(','.join(rand_blocks))

  if args.debug:
    print("Fetching transaction hashes...")
  trx_hashes = call_sql(args, "SELECT encode(trx_hash, 'hex') FROM hive.transactions_view WHERE block_num = ANY({})".format(rand_block_arr_str), db_size)

  if args.debug:
    print("Fetching account names...")
  acc_names = get_acc_names(args, db_size)
  partial_acc_names = [el[:-1] for el in acc_names]

  if args.debug:
    print("Fetching block timestamps")
  timestamps = generate_timestamps(args, rand_block_arr_str)

  if args.debug:
    print("Generating input data...")
  input_data = generate_input_db(args)

  random.shuffle(rand_blocks)
  random.shuffle(trx_hashes)
  random.shuffle(acc_names)
  random.shuffle(partial_acc_names)
  random.shuffle(input_data)
  random.shuffle(timestamps)

  data = [f'{block},{trx_hash},{name},{part_name},{input},{timestamp}' for block, trx_hash, name, part_name, input, timestamp in zip(
    rand_blocks, trx_hashes, acc_names, partial_acc_names, input_data, timestamps
  )]

  db_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'result')
  with open(os.path.join(db_dir, 'db.csv'), 'w') as f: f.write("\n".join(data))
  
  if args.debug:
    print("Done.")

def main():
  args = parse_args()
  generate_db(args)

if __name__ == '__main__':
  main()