#!/bin/bash

set -e
set -o pipefail

cleanup() {
  echo "This will delete previous test result!"
  echo "Press ENTER to continue, ^C to cancel."
  read dummy
  
  rm -rf $RESULT_DIR
  mkdir $RESULT_DIR
  mkdir $RESULT_REPORT_DIR
}
generate_db() {
  DB_SIZE=$1
  python3 $PWD/tests/performance/generate_db.py --db_size=$DB_SIZE
}

set_config_values() {
  PORT=$1
  THREAD_NUM=$2
  LOOP_COUNT=$3

  sed "s/ENTER PORT HERE/$PORT/g" $JMX_IN > $JMX_OUT
  sed "s/ENTER THREAD NUM HERE/$THREAD_NUM/g" $JMX_OUT > $JMX_OUT.v0
  sed "s/ENTER LOOP COUNT HERE/$LOOP_COUNT/g" $JMX_OUT.v0 > $JMX_OUT.v1
  sed "s|ENTER PERFORMANCE DATA DIR HERE|$PERFORMANCE_DATA_DIR|g" $JMX_OUT.v1 > $JMX_OUT

  rm $JMX_OUT.v0 $JMX_OUT.v1
}

run_jmeter() {
  $JMETER -n -t $JMX_OUT -l $JTL_PATH 2>&1 | grep 'Warning' -v
}

generate_report() {
  $JMETER -g $JTL_PATH -o $RESULT_REPORT_DIR 2>&1 | grep 'Warning' -v
}

PERFORMANCE_DIR=$PWD/tests/performance
RESULT_DIR=$PWD/tests/performance/result
RESULT_REPORT_DIR=$RESULT_DIR/result_report
PERFORMANCE_DATA_DIR=$PWD/tests/performance/db

JMX_FILE="endpoints.jmx"
JMX_IN=$PERFORMANCE_DIR/$JMX_FILE
JMX_OUT=$RESULT_DIR/$JMX_FILE

JTL_PATH=$RESULT_DIR/"report.jtl"

JMETER=jmeter-5.4.3

args=("${@:2}") 

cleanup
generate_db ${args[3]}
set_config_values ${args[@]:0:3}
run_jmeter
generate_report