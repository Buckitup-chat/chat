# CLAUDE.md

Guidance for Claude Code in `chat/`. See the monorepo root `CLAUDE.md` for commands and architecture.

## Testing

- `make test` / `make test-brief` need a local PostgreSQL (`postgres`/`postgres` on `localhost`).
- **`:pg_pair` tests** (`Chat.Test.PgPairCase`) use two extra databases, `chat_test_unit_a` and
  `chat_test_unit_b`, served by `Chat.Test.UnitARepo` / `Chat.Test.UnitBRepo`. They are created
  and migrated on the first `:pg_pair` module, then dropped after the suite together with any
  subscriptions, publications and slots.
  - Host PG must run with **`wal_level = logical`**; otherwise these tests fail with a clear
    message. Skip them with `mix test --exclude pg_pair`.
  - `mode: :sandbox` — rolled-back transactions, for diff-copy (`BatchSync`) tests.
  - `mode: :committed, async: false` — no transaction, for logical replication and `Link`
    tests; cleanup runs in `on_exit`.
  - Same-cluster replication: create the slot separately and subscribe with
    `create_slot = false` (`PgPairHelper.subscribe/4`). `CREATE SUBSCRIPTION` with
    `create_slot = true` hangs on the same cluster.
  - Both databases share one cluster, so `PgPairHelper.system_id/1` is the same for both.
