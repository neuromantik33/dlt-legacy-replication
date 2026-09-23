# Postgres legacy replication
A dlt source that reads table changes (Change Data Capture) out of a Postgres write-ahead log using
[logical decoding](https://www.postgresql.org/docs/current/logicaldecoding.html) and the `decoderbufs`
[output plugin](https://github.com/debezium/postgres-decoderbufs), a shared library that has to be built or enabled
server-side.

| Source             | Description                                                    |
|--------------------|----------------------------------------------------------------|
| init_replication   | Creates the slot, optionally snapshots the tables it will track |
| replication_source | Loads published messages from a replication slot                |

## Install decoderbufs

Instructions can be found [here](https://github.com/debezium/postgres-decoderbufs?tab=readme-ov-file#building)

Below is an example installation in a docker image:
```Dockerfile
FROM postgres:14

# Install dependencies required to build decoderbufs
RUN apt-get update
RUN apt-get install -f -y \
      software-properties-common \
      build-essential \
      pkg-config \
      git

RUN apt-get install -f -y \
      postgresql-server-dev-14 \
      libprotobuf-c-dev && \
    rm -rf /var/lib/apt/lists/*

ARG decoderbufs_version=v1.7.0.Final
RUN git clone https://github.com/debezium/postgres-decoderbufs -b $decoderbufs_version --single-branch && \
    cd postgres-decoderbufs && \
    make && make install && \
    cd .. && \
    rm -rf postgres-decoderbufs
```

## Add the source to your project

There is no package to install. Copy the `pg_legacy_replication` folder next to your pipeline script,
as `dlt init` would, and depend on `dlt[sql-database]`, `psycopg2-binary` and `protobuf>=5`. Any of the
supported [destinations](https://dlthub.com/docs/dlt-ecosystem/destinations/) works.

## Set up user

The Postgres user needs to have the `LOGIN` and `REPLICATION` attributes assigned:

```sql
CREATE ROLE replication_user WITH LOGIN REPLICATION;
```

It also needs various read only privileges on the database (by first connecting to the database):

```sql
\connect dlt_data
GRANT USAGE ON SCHEMA schema_name TO replication_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO replication_user;
```

## Add credentials
1. Open `.dlt/secrets.toml`.
2. Enter your Postgres credentials:

    ```toml
    [sources.pg_legacy_replication]
    credentials="postgresql://replication_user:<<password>>@localhost:5432/dlt_data"
    ```
3. Enter credentials for your chosen destination as per the [docs](https://dlthub.com/docs/dlt-ecosystem/destinations/).

## Run the pipeline

```bash
python pg_legacy_replication_pipeline.py   # the worked example at the repo root
dlt pipeline pg_replication_pipeline show  # inspect what landed
```

## Slot position and failed loads

The slot is never flushed while the stream is being consumed. Each run records the LSN of the last
commit it processed in dlt state, which the destination only stores once the load package lands, and
the *next* run advances the slot to that LSN. A failed load therefore replays instead of losing the
WAL. Pass `flush_slot=False` to `replication_source` and the slot never advances at all.

`init_replication(take_snapshots=True)` keeps a replication connection open to hold the exported
snapshot. Call `cleanup_snapshot_resources` in a `finally` once the snapshot has loaded, or that
connection's transaction blocks the next `CREATE_REPLICATION_SLOT` until the process exits.

# Differences between `pg_legacy_replication` and `pg_replication`

## Overview

`pg_legacy_replication` is a fork of the verified `pg_replication` source. The primary goal of this fork is to provide logical replication capabilities for Postgres instances running versions
earlier than 10, when the `pgoutput` plugin was not yet available. This fork draws inspiration from the original `pg_replication` source and the `decoderbufs` library,
which is actively maintained by Debezium.

## Key Differences from `pg_replication`

### Replication User Ownership Requirements
One of the limitations of native Postgres replication is that the replication user must **own** the tables in order to add them to a **publication**.
Additionally, once a table is added to a publication, it cannot be removed, requiring the creation of a new replication slot, which results in the loss of any state tracking.

### Limitations in `pg_replication`
The current pg_replication implementation has several limitations:
- It supports only a single initial snapshot of the data.
- It requires `CREATE` access to the source database in order to perform the initial snapshot.
- **Superuser** access is required to replicate entire Postgres schemas.
  While the `pg_legacy_replication` source theoretically reads the entire WAL across all schemas, the current implementation using dlt transformers restricts this functionality.
  In practice, this has not been a common use case.
- The implementation is opinionated in its approach to data transfer. Specifically, when updates or deletes are required, it defaults to a `merge` write disposition,
  which replicates live data without tracking changes over time.

### Features of `pg_legacy_replication`

This fork of `pg_replication` addresses the aforementioned limitations and introduces the following improvements:
- Adheres to the dlt philosophy by treating the WAL as an upstream resource. This replication stream is then transformed into various DLT resources, with customizable options for write disposition,
  file formats, type hints, etc., specified at the resource level rather than at the source level.
- Supports an initial snapshot of all tables using the transaction slot isolation level. Additionally, ad-hoc snapshots can be performed using the serializable deferred isolation level,
  similar to `pg_dump`.
- Emphasizes the use of `pyarrow` and parquet formats for efficient data storage and transfer. A dedicated backend has been implemented to support these formats.
- Replication messages are decoded using Protocol Buffers (protobufs) in C, rather than relying on native Python byte buffer parsing. This ensures greater efficiency and performance.

## Next steps
- Add support for the [wal2json](https://github.com/eulerto/wal2json) replication plugin. **Amazon RDS** offers `wal2json`
  and not `decoderbufs`, which on-premise and Google Cloud SQL instances do offer.