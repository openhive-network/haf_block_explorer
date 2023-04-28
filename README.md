## About

haf block explorer is a web app for viewing information in transactions and operations of accounts and blocks, as well as block witness (creator) information.<br>Search can be performed by `_account`, `_block_num`, `_block_hash`, `_trx_hash`.

API docs for **devs** can be found [here](https://gitlab.syncad.com/hive/haf_block_explorer/-/wikis/New-API-Calls)

## Requirements

Node: `latest`<br>
npm: `latest`

## Setup
To see available list of commands with parameters use:
```
./run.sh --help
```
To start using haf block explorer, on first setup use:
```
./scripts/setup_dependancies.sh
./scripts/setup_db.sh

```
If u want setup db only in case dependancies are already set up, use only:
```
./scripts/setup_db.sh
```
Then install gui dependancies
```
cd gui ; npm install ; cd ..
```

## Block processing

hafbe will process blocks from haf db to own tables
```
./scripts/process-blocks.sh
```
Until hafbe catches up to head block on haf db, it will do massive processing


If you want to destroy hafbe db:
```
./scripts/drop-db.sh
```

## Starting


After setup start postgREST server with:
```
sudo su - hafbe_owner
cd <hafbe_dir>
./run.sh --c=start <PORT>
```
`PORT` is optional, default is 3000.

Run web app with:
```
cd gui ; npm start
```

## Testing performance

Install JMeter if not yet installed
```
./scripts/setup_dependancies.sh jmeter
```
then run tests with:
```
./run.sh --c=run-tests <THREAD_NUM> <LOOP_NUM> <DB_SIZE>
```

E.g. this will run 30 threads (THREAD_NUM * SUITE_NUM) with 200 loops and with unique params for each request:
```
./run.sh --c=run-tests <PORT> 2 200 6000
```
Server port must be specified as first arg.

Read test result in Apache JMeter Dashboard, generated at `tests/performance/result/result_report/index.html`
