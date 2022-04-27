import os
import subprocess
import random
import argparse

def parse_args():
  parser = argparse.ArgumentParser()
  parser.add_argument('--db_size', type=int, default=1000)
  return parser.parse_args()

def get_input_type():
  psql_cmd = 'psql -d haf_block_log -c "%s LIMIT %d"'

  out = subprocess.check_output(
    psql_cmd % ('SELECT name FROM hive.accounts', db_size),
    shell=True
  ).decode('utf-8')
  
  data = [el.strip() + ',' for el in out.strip().split("\n")[2:-1]]
  random.shuffle(data)
  with open(os.path.join(db_dir, 'get_input_type.csv'), 'w') as f:
    f.write("\n".join(data))

if __name__ == '__main__':
  args = parse_args()
  db_size = args.db_size

  performance_dir = os.path.join(os.getcwd(), 'tests', 'performance')
  db_dir = os.path.join(performance_dir, 'db')
  if os.path.isdir(db_dir) is False: os.mkdir(db_dir)

  get_input_type()