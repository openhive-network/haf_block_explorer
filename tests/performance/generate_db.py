import os
import subprocess
import random
import argparse

def parse_args():
  parser = argparse.ArgumentParser()
  parser.add_argument('--db_size', type=int, default=1000)
  return parser.parse_args()

def call_sql(cmd, limit):
  return [el.strip() for el in subprocess.check_output(psql_cmd % (cmd, limit), shell=True).decode('utf-8').strip().split("\n")[2:-1]]

def get_input_type():
  limit = db_size // 4

  data = [str(random.randint(0, max_block)) for i in range(limit)]
  rand_block_arr_str = "'{%s}'" % ','.join(data)

  data += call_sql("SELECT encode(hash, 'escape') FROM hive.blocks WHERE num = ANY(%s)" % rand_block_arr_str, limit)
  data += call_sql("SELECT encode(trx_hash, 'escape') FROM hive.transactions WHERE block_num = ANY(%s)" % rand_block_arr_str, limit)
  data += call_sql("SELECT name FROM hive.accounts", limit)
  random.shuffle(data)
  with open(os.path.join(db_dir, 'get_input_type.csv'), 'w') as f: f.write("\n".join(data))

def get_block_num():
  rand_block_arr_str = "'{%s}'" % ','.join(
    [str(random.randint(0, max_block)) for i in range(db_size)]
  )
  data = call_sql("SELECT encode(hash, 'escape') FROM hive.blocks WHERE num = ANY(%s)" % rand_block_arr_str, db_size)
  with open(os.path.join(db_dir, 'get_block_num.csv'), 'w') as f: f.write("\n".join(data))

def find_matching_accounts():
  data = [el[:-1] for el in call_sql("SELECT name FROM hive.accounts", db_size)]
  with open(os.path.join(db_dir, 'find_matching_accounts.csv'), 'w') as f: f.write("\n".join(data))

def get_ops_by_account():
  account_data = call_sql("SELECT name FROM hive.accounts", db_size)
  start_data = [random.randint(0, max_block) for i in range(db_size)]
  lim_data = [1000 if start >= 1000 - 1 else start + 1 for start in start_data]
  data = ["%s,%s,%s" % (account, start, limit) for account, start, limit in zip(account_data, start_data, lim_data)]
  with open(os.path.join(db_dir, 'get_ops_by_account.csv'), 'w') as f: f.write("\n".join(data))

if __name__ == '__main__':
  args = parse_args()
  db_size = args.db_size

  performance_dir = os.path.join(os.getcwd(), 'tests', 'performance')
  db_dir = os.path.join(performance_dir, 'db')
  if os.path.isdir(db_dir) is False: os.mkdir(db_dir)

  psql_cmd = 'psql -d haf_block_log -c "%s LIMIT %d"'
  max_block = int(call_sql("SELECT num FROM hive.blocks ORDER BY num DESC", 1)[0])

  get_input_type()
  get_block_num()
  find_matching_accounts()
  get_ops_by_account()