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

def gen_rand_block_range(limit):
  return [str(random.randint(0, max_block)) for i in range(limit)]

def get_acc_names(limit):
  return call_sql("SELECT name FROM hive.accounts", limit)

def generate_input_db():
  limit = db_size // 4
  data = gen_rand_block_range(limit)
  rand_block_arr_str = "'{%s}'" % ','.join(gen_rand_block_range(limit))
  data += call_sql("SELECT encode(hash, 'hex') FROM hive.blocks WHERE num = ANY(%s)" % rand_block_arr_str, limit)
  data += call_sql("SELECT encode(trx_hash, 'hex') FROM hive.transactions WHERE block_num = ANY(%s)" % rand_block_arr_str, limit)
  data += get_acc_names(limit)
  return data

def generate_db():
  rand_blocks = gen_rand_block_range(db_size)
  rand_block_arr_str = "'{%s}'" % ','.join(gen_rand_block_range(db_size))
  trx_hashes = call_sql("SELECT '\\x' || encode(trx_hash, 'hex') FROM hive.transactions WHERE block_num = ANY(%s)" % rand_block_arr_str, db_size)
  acc_names = get_acc_names(db_size)
  partial_acc_names = [el[:-1] for el in acc_names]
  input_data = generate_input_db()

  random.shuffle(rand_blocks)
  random.shuffle(trx_hashes)
  random.shuffle(acc_names)
  random.shuffle(partial_acc_names)
  random.shuffle(input_data)

  data = [f'{block},\{trx_hash},{name},{part_name},{input}' for block, trx_hash, name, part_name, input in zip(
    rand_blocks, trx_hashes, acc_names, partial_acc_names, input_data
  )]

  with open(os.path.join(db_dir, 'db.csv'), 'w') as f: f.write("\n".join(data))

if __name__ == '__main__':
  args = parse_args()
  db_size = args.db_size

  db_dir = os.path.join(os.getcwd(), 'tests', 'performance', 'result')

  psql_cmd = 'psql -d haf_block_log -c "%s LIMIT %d"'
  max_block = int(call_sql("SELECT num FROM hive.blocks ORDER BY num DESC", 1)[0])

  generate_db()