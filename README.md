## About

haf block explorer is a web app for viewing information in transactions and operations of accounts and blocks, as well as block witness (creator) information.<br>Search can be performed by `_account`, `_block_num`, `_block_hash`, `_trx_hash`.

API docs for **devs** can be found [here](https://gitlab.syncad.com/hive/haf_block_explorer/-/wikis/New-API-Calls)

## Requirements

Node: `latest`<br>
npm: `latest`

## Setup

To start using haf block explorer, first
```
./scripts/setup_dependancies.sh all
./scripts/setup_db.sh all
```
This will create required postgres schemas and roles, also [indexes](https://gitlab.syncad.com/hive/haf_block_explorer/-/blob/22-create-witness-table/db/indexes.sql#L20) on haf db.


Then install gui dependancies
```
cd gui ; npm install ; cd ..
```

## Block processing

hafbe will process blocks from haf db to own tables
```
./run.sh process-blocks
```
Until hafbe catches up to head block on haf db, it will do massive processing


If you need to stop and restart processing
```
./run.sh stop-processing
./run.sh continue-processing
```

If you want to destroy hafbe db:
```
./run.sh drop-db
```

## Starting

When hafbe is in live sync mode (processing block-by-block), create indexes for it's tables:
```
./run.sh create-hafbe-indexes
```

After setup start postgREST server with:
```
sudo su - hafbe_owner
cd <hafbe_dir>
./run.sh start <PORT>
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
./run.sh run-tests <THREAD_NUM> <LOOP_NUM> <DB_SIZE>
```

E.g. this will run 20 threads (THREAD_NUM * SUITE_NUM) with 200 loops and with unique params for each request:
```
./run.sh run-tests 2 200 4000
```

Read test result in Apache JMeter Dashboard, generated at `tests/performance/result/result_report/index,html`
