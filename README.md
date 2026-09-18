# pg_legacy_replication

A [dlt](https://dlthub.com) source that replicates a Postgres database via logical
decoding, using Debezium's `decoderbufs` output plugin — so it works on **Postgres < 10**,
where `pgoutput` does not exist.

Source docs, including the server-side plugin setup and credentials:
[`sources/pg_legacy_replication/README.md`](sources/pg_legacy_replication/README.md).

Extracted from a fork of `dlt-hub/verified-sources`, which no longer accepts new sources.

## Using it

There is no package to install. Copy `sources/pg_legacy_replication/` into your project
next to your pipeline script, exactly as `dlt init` would, and install its
`requirements.txt`. `sources/pg_legacy_replication_pipeline.py` is a worked example.

## Developing

Needs [uv](https://docs.astral.sh/uv/) and docker.

```bash
make dev        # uv sync
make lint       # ruff check
make format     # ruff format
make test       # brings Postgres up, then the full suite
make test-unit  # no database needed
```

Credentials: copy `sources/.dlt/example.secrets.toml` to `sources/.dlt/secrets.toml`.

### Postgres versions

`make test` defaults to **9.6** — what exercises the pre-10 code paths this source
exists for. The image is `debezium/postgres`, which ships `decoderbufs` prebuilt.

```bash
make test PG_VERSION=14
make pg-down            # also removes the volume
```

The `pg_version` fixture asks the running server for `server_version_num` rather than
trusting `PG_VERSION`.

## State of the port

This repo is a deliberate straight move. Everything under `sources/` and
`tests/pg_legacy_replication/` is byte-identical to the monorepo, and
`tests/utils.py`, `tests/conftest.py`, `tests/__init__.py` and `pytest.ini` are verbatim
copies of the monorepo's shared test files. Only the tooling changed:

| was | now |
|---|---|
| poetry + `poetry.lock` (36 sources) | uv + `uv.lock` (this source only) |
| black, flake8 (configured in `tox.ini`) | ruff |
| mypy | *nothing yet* |
| 7 workflows | one lint workflow |

Deliberately **not** done yet, so that each is its own change with its own blame:

- **No formatting pass.** `ruff format` has not been run; the source is as it was under
  black. `make format` when you want it.
- **Narrow lint rules.** Only `E4,E7,E9,F` plus the banned-imports carried over from
  `tox.ini`. Turning on `I` (import sorting), `B` (bugbear) or `UP` (pyupgrade) will each
  produce real findings — see below.
- **No type checker.** mypy is gone, pyrefly not yet added.
- **dlt still pinned to 1.8.1**, exactly as the monorepo resolved it. Bump after the
  suite is trusted.

### Known failures, inherited

Running the suite in the *monorepo* at PG 9.6, twice, gives the same result both times:

```
28 passed, then
tests/pg_legacy_replication/test_pg_replication.py::test_mapped_data_types[pyarrow-True-True-postgres] FAILED
```

and the run then **hangs** on the next test. A session is left `idle in transaction`
while the next test blocks on `Lock`; `consume_stream` sits in a C call with the GIL
held, so `pytest-timeout` cannot interrupt it. This predates the move and is the first
thing to chase.

If a run stalls: kill it, then `make pg-down && make test`. Leaked replication slots
starve later runs — the container allows 10, check with
`SELECT * FROM pg_replication_slots;`.
