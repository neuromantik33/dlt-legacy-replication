# pg_legacy_replication

A [dlt](https://dlthub.com) source that replicates a Postgres database via logical
decoding, using Debezium's `decoderbufs` output plugin. That plugin is what lets it run
against **Postgres < 10**, where `pgoutput` does not exist.

Server-side plugin setup, credentials and the differences from dlt's own `pg_replication`
source: [`sources/pg_legacy_replication/README.md`](sources/pg_legacy_replication/README.md).

Extracted from a fork of `dlt-hub/verified-sources`, which no longer accepts new sources.

## Using it

There is no package to install. Copy `sources/pg_legacy_replication/` into your project
next to your pipeline script, as `dlt init` would, and depend on
`dlt[sql-database]`, `psycopg2-binary` and `protobuf>=5`.
`pg_legacy_replication_pipeline.py` is a worked example.

## Developing

Needs [uv](https://docs.astral.sh/uv/) and docker.

```bash
make dev        # uv sync
make lint       # ruff check
make format     # ruff format
make typecheck  # pyrefly check
make test       # pytest
make ci         # typecheck, lint, test with coverage
```

Credentials: copy `sources/.dlt/example.secrets.toml` to `sources/.dlt/secrets.toml`.

### Postgres versions

The test server runs in docker and defaults to **9.6**, which is what exercises the pre-10
code paths this source exists for. The image is `debezium/postgres`, which ships
`decoderbufs` prebuilt.

```bash
make pg-up                  # 9.6 on localhost:5432
make test
make pg-up PG_VERSION=14    # each major gets its own compose project and volume
make pg-down PG_VERSION=14  # also removes that volume
```

`PG_VERSION` picks the image, nothing else. The `pg_version` fixture asks the running
server for `server_version_num`, so the tests branch on what they are actually talking to
rather than on what the variable says.

Two code paths differ by version. `advance_slot` uses `pg_replication_slot_advance` on 11
and up, and `pg_logical_slot_get_binary_changes` below that, where the function does not
exist yet. `get_max_lsn` reads the `lsn` column on 10 and up, `location` below.

## Destinations

`ALL_DESTINATIONS` is `["duckdb"]`, carried over from the monorepo.
`DESTINATION__POSTGRES__CREDENTIALS` still has to be set, because the `src_config` fixture
runs a Postgres pipeline for the *source* database whatever the destination is. To test
another destination, add it to `PG_TEST_ENV` in the `Makefile`.

The postgres destination is off because the four `test_mapped_data_types[pyarrow-*]` cases
fail there, inherited and not fixed here: dlt normalizes the arrow batch to csv and refuses
the `col7` binary column, `Arrow data contains string or binary columns with invalid UTF-8
characters`. The other 25 pass.

Leaked replication slots starve later runs. The compose file allows 10, up from the
image's 4. Check with `SELECT * FROM pg_replication_slots;`, reset with `make pg-down`.
