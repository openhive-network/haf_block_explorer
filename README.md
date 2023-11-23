# HAF Block Explorer

1. [About](#about)
1. [Setup](#setup)
1. [Block processing](#block-processing)
1. [Startup](#startup)
1. [Performance tests](#performance-tests)

## About

haf block explorer is a web app for viewing information in transactions and operations of accounts and blocks, as well as block witness (creator) information.  
Search can be performed by `_account`, `_block_num`, `_block_hash`, `_trx_hash`.

## Setup

HAF Block Explorer requires an instance of HAF.

First set up its dependencies:

```bash
./scripts/setup_dependencies.sh --install-all
```

Next, set up the database:

```bash
./scripts/install_app.sh
```

You can use `./scripts/install_app.sh --help` to see available options.

## Block processing

Before it can be used, HAF Block Explorer needs to process blocks available in HAF database.

```bash
./scripts/process_blocks.sh
```

Again, you can use `./scripts/process_blocks.sh --help` to see available options.

If you want to destroy HAF Block Explorer database use:

```bash
./scripts/uninstall_app.sh
```

As before, use `./scripts/uninstall_app.sh --help` to see available options.

## Startup

After setup start postgREST server with:

```bash
./scripts/start_postgrest.sh
```

One more, use `./scripts/start_postgrest.sh --help` to see available options.

## Dockerized setup

The steps above can also be performed using Docker. The details are in a separate [README](docker/README.md).

## Performance tests

Run tests by running the following commands (requires installing depencencies):

```bash
source .tests/bin/activate
./tests/run_performance_tests.sh
deactivate
```

You can see all test options using command `./tests/run_performance_tests.sh --help`

After the tests are completed, a report will be generated at `tests/performance/result/result_report/index.html`
