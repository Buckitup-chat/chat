# PostgreSQL Constraints

General PostgreSQL data constraints relevant to BuckitUp platform. Hardware-specific PostgreSQL configuration (shared_buffers, ports, lifecycle) is documented in `platform/docs/reqs/postgresql-management.md`.

## 1. TOAST (The Oversized-Attribute Storage Technique)

### 1.1 When It Kicks In

PostgreSQL targets rows to fit within one 8 KB page. When a row's variable-length fields push it past ~2 KB, Postgres applies TOAST:

1. **Compress** the value (LZ4 by default in PG17)
2. If still too large, **store out-of-line** in a per-table TOAST table, replacing the inline value with an 18-byte pointer

This applies to all varlena types: `bytea`, `text`, `varchar`, `jsonb`, `xml`, etc.

### 1.2 Hard Limits

| Limit | Value |
|---|---|
| Max field size | 1 GB |
| Max row size (non-TOASTed) | ~8 KB (one page) |
| TOAST chunk size | ~2 KB (stored in TOAST table pages) |

### 1.3 Storage Strategies

Per-column setting via `ALTER TABLE ... ALTER COLUMN ... SET STORAGE`:

| Strategy | Behavior |
|---|---|
| `EXTENDED` (default) | Compress first, then store out-of-line |
| `EXTERNAL` | Out-of-line without compression |
| `MAIN` | Try to compress and keep inline |
| `PLAIN` | No TOAST at all (fails if value won't fit in page) |

### 1.4 Encrypted Data

Ciphertext is high-entropy and will not compress. Postgres will waste CPU attempting LZ4 compression on every write, then store uncompressed anyway. For columns holding encrypted blobs, set storage to `EXTERNAL`:

```sql
ALTER TABLE chunks ALTER COLUMN data SET STORAGE EXTERNAL;
```

## 2. WAL Amplification

Every write to a table goes through the WAL (Write-Ahead Log) before being applied to the heap. For large values this means:

- **2x write amplification** — data is written to WAL, then to the heap page
- Full-page writes after checkpoint add another copy — up to **3x** in worst case
- On USB flash storage, this accelerates wear and halves effective write throughput

### 2.1 Impact on Electric

Electric consumes the logical replication WAL. Columns with large values inflate WAL volume, which:

- Increases replication slot lag
- Grows `pg_wal/` directory if consumers fall behind
- Can trigger `max_slot_wal_keep_size` limits, disconnecting Electric

## 3. VACUUM and Large Values

Deleted or updated rows with TOASTed values leave dead tuples in both the main table and TOAST table. Autovacuum must process both:

- TOAST table vacuum is proportionally expensive for large values
- Competes for shared RAM (4 GB total on RPi4)
- Long-running transactions block vacuum, causing table bloat

## 4. Column Size Monitoring

Track TOASTed column sizes to detect growth before it impacts performance:

```sql
-- average and max size of a bytea/text column
SELECT
  avg(octet_length(data)) AS avg_bytes,
  max(octet_length(data)) AS max_bytes,
  count(*) AS row_count
FROM target_table;

-- TOAST table size vs main table
SELECT
  pg_size_pretty(pg_relation_size('target_table')) AS main_size,
  pg_size_pretty(pg_table_size('target_table') - pg_relation_size('target_table')) AS toast_size;
```

### 4.1 Thresholds to Watch

| Metric | Concern threshold | Notes |
|---|---|---|
| Single field size | > 10 MB | High TOAST overhead per read |
| TOAST table size | > main table size x10 | Vacuum cost dominates |
| `pg_wal` directory | > 1 GB | Replication consumers may be lagging |
| Dead tuple ratio | > 20% of live tuples | Autovacuum can't keep up |

## 5. Practical Limits for BuckitUp

| Constraint | Limit | Impact |
|---|---|---|
| Max field size | 1 GB | File chunks must stay under this |
| RAM for queries | ~1-2 GB (shared with app) | Large bytea reads evict cache |
| WAL on USB | Limited by write endurance | Prefer filesystem for bulk blob storage |
| Autovacuum | Competes for RAM/IO | High-churn large-value tables need tuned vacuum settings |
