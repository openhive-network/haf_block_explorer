# HAF Block Explorer

1. [About](#about)
1. [Setup](#setup)
1. [Block processing](#block-processing)
1. [Startup](#startup)
1. [Performance tests](#performance-tests)

## About

HAF block explorer is an API for querying information about transactions/operations included in Hive blocks, as well as block producer (i.e. witness) information.

Searches can be performed by `_account`, `_block_num`, `_block_hash`, `_trx_hash`.

## Setup

NOTE: haf_block_explorer uses balance_tracker as a sub-app and provides all the functionality of balance_tracker, so there is no need to install balance_tracker as a separate app if you have installed haf_block_explorer. In fact, trying to install both will cause a problem because both apps use the same schema name to store balance_tracker data. If you are running balance_tracker on your haf server and decide to later upgrade to running haf_block_explorer, be sure you uninstall balance_tracker first.

Like all HAF apps, HAF Block Explorer must be installed on a HAF server. The easiest and recommended way to setup and maintain a HAF server and apps like haf_block_explorer is using the scripts in this repo: https://gitlab.syncad.com/hive/haf_api_node/

However, for completeness, below are instructions for manually installing haf_block_explorer on a HAF server (again, this is NOT the recommended approach to maintaining a node that runs haf_block_explorer).

First, set up its dependencies:

```bash
./scripts/setup_dependencies.sh --install-all
```

Next, install haf_block_explorer on the database:

```bash
./scripts/install_app.sh --fetch-app-versions
```

You can use `./scripts/install_app.sh --help` to see available options.

## Block processing

Before it can be used, HAF Block Explorer needs to process blocks available in HAF database.

```bash
./scripts/process_blocks.sh
```

Again, you can use `./scripts/process_blocks.sh --help` to see available options.

If you want to uninstall HAF Block Explorer and remove its data from the database:

```bash
./scripts/uninstall_app.sh
```

As before, use `./scripts/uninstall_app.sh --help` to see available options.

## Startup

After setup, start the postgREST server with:

```bash
./scripts/start_postgrest.sh
```

You can type `./scripts/start_postgrest.sh --help` to see available options.

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
