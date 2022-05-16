## About

haf block explorer is a web app for viewing information in transactions and operations of accounts and blocks, as well as block witness (creator) information.<br>Search can be performed by `_account`, `_block_num`, `_block_hash`, `_trx_hash`.

API docs for **devs** can be found [here](https://gitlab.syncad.com/hive/haf_block_explorer/-/wikis/New-API-Calls)

## Requirements

Node: `latest`<br>
npm: `latest`

## Setup

To start using haf block explorer, first
```
./run.sh install-postgrest
./run.sh install-plpython
```
then install gui dependancies
```
cd gui ; npm install ; cd ..
```
finally start server with:
```
./run.sh re-start
```
This will create required postgres schemas and roles.

## Starting 

After setup start postgREST server with:
```
./run.sh start <PORT>
```
`PORT` is optional, default is 3000.

Run web app with:
```
cd gui ; npm start
```

## Testing performance

haf block explorer has 6 performance/load test suites ready in `tests/performance/endpoints.jmx`.<br>To run tests you must have JMeter installed:
```
./run.sh install-jmeter
```
then run tests with:
```
./run.sh run-tests <PORT> <THREAD_NUM> <LOOP_NUM> <DB_SIZE>
```

E.g. this will run 12 threads (THREAD_NUM * SUITE_NUM) with 200 loops and with unique params for each request:
```
./run.sh run-tests 3000 2 200 2400
```

Read test result in Apache JMeter Dashboard, generated at `tests/performance/result/result_report/index,html`
