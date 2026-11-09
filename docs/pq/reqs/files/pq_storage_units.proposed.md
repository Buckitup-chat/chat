# Storage Units — Drive/Role Clusters as a First-Class Aggregate

A **Storage Unit** is one `(drive, role)` cluster: the internal SD storage, or a USB drive in its role. Everything attached to it is derived from the unit: directories, PG cluster, repo, CubDB instance, chunk pipeline, LEDs, sync links and status. Nothing reconstructs it from fragments.

The system works through two layers:

- **Default** — the unit the system currently writes to. One pointer, switched atomically.
- **Targeted** — specific units named explicitly (syncs, copies, per-unit pipelines). They never consult Default.

**Compatibility:** the CubDB generation stays compatible, because its paths are unchanged (§2.2). The PostgreSQL generation (PG clusters, PQ blobs, Electric storage) is dropped and recreated; see §7.

Motivating symptom: [#795](https://github.com/Buckitup-chat/chat/issues/795). Backup restore copies PQ rows, but the blobs are never found. The root cause is not a single wrong path: the unit concept is missing, so `DriveCopySource` re-derives unit → dir by globbing `/root/media/sd*` and querying repos, and it only knows the `main_db/…` layout.

---

## 1. Current State

### 1.1 The unit is spread over five unrelated keys

| Facet | What | Keyed by today |
|---|---|---|
| Identity | role marker dir `<mount>/<role>_db`; `DbType` inside CubDB (checked by `Bouncer`, a duplicate of role); PG `system_identifier` | dir name · CubDB value · PG |
| Location | CubDB data, CubDB files (FileFs), PG cluster, PQ blobs | ad hoc `Path.join` in ~12 modules |
| Engines | PG daemon, port, run dir (`/tmp/pg_run/<device>`), repo module (`Module.create Platform.Dev.SdX.Repo` at runtime), CubDB instance, chunk pipeline (7 procs), boot stages | **device letter** (port, repo) · **role atom** (`Chat.Db.MainDb`, `BackupDb`, `CargoDb`, `OnlinersDb`, `InternalDb`) · **device** (pipeline registry, stage names) |
| Links to other units | PG publications/slots/subscriptions; CubDB mirrors (`Switching.mirror`); BatchSync direction; `missing_chunks.source_drive_id` | **role pair**, hardcoded strings |
| State | `Platform.Storage.Sync` status (one `persistent_term`), `:flags` (`backup: true`), `:mode` (`:internal` / `:main` / `:main_to_internal`) | global singletons |

### 1.2 Paths

| Resource | Built by | Path today |
|---|---|---|
| CubDB internal | `Chat.Db.file_path/0` | `/root/db/v.10.1` |
| CubDB USB | `Main/Backup/Cargo/OnlinersDbSupervisor` (each its own join) | `<mount>/<role>_db/v.10.1` |
| CubDB files | `CubDB.data_dir(db) <> "_files"` in `chat.ex`, `read_stream.ex`, `copying/progress.ex`, `db.ex`, `switching.ex` | `…/v.10.1_files` |
| PQ blobs | `DriveDirs` (**main_db only**), `BackupDbSupervisor`, `ChunkStore.pq_dir/1`, `Chat.Debug` | `…/v.10.1_files/pq_files` |
| PQ blobs "current" | `:files_base_dir`, set by **CubDB** `Switching.set_default/2` | follows CubDB default |
| PG | `BootSupervisor`, `DatabaseSupervisor @pg_dir` | `<mount>/pg`, `/root/pg` |
| Unused attempt | `Dev.path/3` — disagrees with reality | — |

### 1.3 Default is six fields switched at different moments

| Field | Set by | When (internal → main) |
|---|---|---|
| CubDB `:data_queue` / `:data_pid` | `Switching.set_default/2` | `InternalToMain.Copier`, after copy + PG sync |
| `:files_base_dir` | same | same |
| `:active_drive_id` (upload writer) | same | same |
| `:repo` | `Chat.Db.set_repo/1` | `InternalToMain.Switcher` — **later stage** |
| Electric stack | `PhoenixSyncReinit` | `PhoenixSyncInit` — **even later stage** |
| `DbBrokers` | `refresh/0` | several places |

Between those stages, an upload writes its blob to main (`active_drive_id`) and its manifest to internal (`repo`).

### 1.4 Links are implicit

| Scenario | CubDB | PG bootstrap | PG replication | Chunk blobs |
|---|---|---|---|---|
| internal → main (attach) | mirror + `await_copied` | `Sync.run_local_sync` (+ missing_chunks backfill) | pub `internal_to_main` / sub `main_from_internal` | `DriveCopySource` on main |
| main → internal (switched) | mirror back | `Sync.run_local_sync` main→internal | pub `main_to_internal` / sub `internal_from_main` | `DriveCopySource` on internal |
| backup (both ways) | `await_copied` ×2 | **`BatchSync` directly, no backfill** | continuous: pub `internal_to_backup` / sub `backup_from_internal` | backup → default **never** (dir not discoverable, no missing_chunks) |
| cargo / onliners | scoped CubDB `Copier` | — | — | — (PG boots anyway, unused) |

The same operation ("bring unit B up to date from unit A") has two implementations. One of them misses the blob half.

### 1.5 Boot order hides a defect

`BootSupervisor`: Healer → Mount → InternalDbAwaiter → **PG init/daemon/DB/repo/migrations** → `Decider`.

- PG starts before the role is known, for **every** drive (including dump and cargo).
- `Decider.drive_blank?/1` runs after PG has created `<mount>/pg`, so a drive never looks blank and `optimize_fs` (mkfs) never fires. If it did, it would format a drive with a live PG on it.
- `Decider` mixes **role** (persistent, on disk) with **scenario** (runtime: `UsbDriveDumpRoom` override, `main_db_scenario_when_internal` → `nil` for a second main).

### 1.6 Other findings

- **Continuous backup assumes main is default.** It calls `Switching.mirror(Chat.Db.MainDb, [InternalDb, BackupDb])` even when the system runs on internal only.
- **Continuous backup PG replication always publishes from `Chat.Repo` (internal), not from Default.** Internal (SD) tends to overflow while on main, so it is not a complete copy, and the backup silently misses whatever internal could not hold.
- **`ChunkAwaiter` treats restored chunks as present on internal.** They have `file_chunks` rows without `missing_chunks`, but no blob exists. It also awaits only the default → backup direction.
- **Unbounded WAL retention from idle Electric slots.** `Platform.Storage.Repo.MigrationRunner.ensure_electric_slot_if_needed/1` pre-creates a **permanent** `electric_slot_default` on every unit's PG, backup included. Only the Electric stack connected to Default consumes it, and `max_slot_wal_keep_size` is not set (`Postgres.Lifecycle @pg_minimal_settings`). An inactive slot retains WAL forever:
  - internal while on main: main→internal replication keeps writing, so WAL grows on the SD card;
  - backup in continuous mode: internal→backup replication keeps writing, so WAL grows on the backup drive.
- **Electric cache lives on internal SD regardless of Default.** `storage_dir: "/root/electric"` (`shapes/` = shape snapshots and logs, `state/` = PersistentKV including `timeline_id_<stack>` = `{pg_system_id, timeline}`). On every Default switch, `Electric.Timeline.check/2` sees a different `pg_system_id`, returns `:timeline_changed` and purges all shapes. That is correct, but the cache is always written to SD, and every switch forces every client into a 409 refetch.
- **Replicated chunks are stamped with the wrong source.** `ReplicationListener` (one per unit) inserts `missing_chunks` with `source_drive_id: state.system_id`, which is the *listening* unit's own id. `DriveCopySource` on that unit then looks up `other_drives[own_id]`, gets `nil` → `:no_source`, and falls back to a **random** other drive. With two units this works by accident; with internal + main + backup it can pick the wrong one. A trigger cannot know the origin of a row; a link can (§2.7.1).

---

## 2. Model

### 2.1 StorageUnit

```elixir
defmodule Chat.Storage.Unit do
  @enforce_keys [:id, :role, :root]
  defstruct [:id, :role, :root, :system_id]
  # id:        :internal | "sdb1"         (device name — transient between plug-ins)
  # role:      :internal | :main | :backup | :cargo | :onliners
  # root:      /root | <media_root>/<device>
  # system_id: PG system_identifier — the STABLE identity; nil until the PG engine is up
end
```

All facets are **pure derivations** of the struct:

| Function | Result |
|---|---|
| `Unit.path(u, :cub_db \| :cub_files \| :pg \| :pq_files)` | see §2.2 |
| `Unit.role_dir(u)` | `"db"`, `"main_db"`, `"backup_db"`, … |
| `Unit.pg_port(u)` | `5432` internal; `5432 + 1 + (letter - ?a)` USB |
| `Unit.pg_run(u)` | `/tmp/pg_run/<id>` |
| `Unit.repo(u)` | `Chat.Repo` internal; `Platform.Dev.Sd<L>.Repo` USB |
| `Unit.cub_name(u)` | `Chat.Db.InternalDb`, `MainDb`, `BackupDb`, … (one per role — see §2.4) |
| `Unit.via(u, component)` | registry name for pipeline/stage processes |
| `Unit.capabilities(u)` | from `Role` (§2.3) |

Exactly one module holds path segments and naming conventions: `Chat.Storage.Unit` (or a `Unit.Layout` submodule). Roots come from one config entry:

```elixir
config :chat, Chat.Storage,
  internal_root: "/root",       # priv/db (dev), priv/test_db (test)
  media_root: "/root/media"     # priv/media (host); nil for standalone chat
```

This replaces `:cub_db_file`, `:files_base_dir`, `:usb_media_root`, `:internal_root` and platform's `:mount_path_media`. The Mounter reads its target from `Unit.root/1`.

### 2.2 Layout

```
<root>/<role_dir>/
├── v.10.1/          :cub_db      CubDB generation, versioned
├── v.10.1_files/    :cub_files   FileFs, versioned
├── pg/              :pg          PG cluster (pg/data), NOT versioned
├── pq_files/        :pq_files    chunk blobs <shard>/f_<hex>/<idx>, NOT versioned
└── electric/        :electric    Electric shape cache — used only while this unit is Default

/tmp/pg_run/<id>/                 :pg_run
<internal_root>/admin_db_v2/      AdminDB — system-level, not part of any unit (see §8)
```

- **Electric storage is a Default-bound engine cache, not a per-unit resource.** It lives at `<role_dir>/electric` (`:electric`), which only the **Default** unit uses. Shape logs are written to the active drive, not to SD.
  - It is persistent (it survives reboot) but derived. It is valid for one PG only: Electric keys it by `pg_system_id` and purges it on mismatch.
  - Keeping a per-unit cache *across* switches is deliberately not attempted. Resuming shapes would require the unit's Electric slot to retain WAL for the whole time away (see §1.6).
  - Electric's PG-side state (`electric_slot_default`, `electric_publication_default`) exists **only on the Default unit**. `Default.switch_to/1` manages it (§2.6); `MigrationRunner` no longer pre-creates it.

- **Role-based.** Everything a unit owns lives under its `role_dir`. Role is fixed on first use.
- **PQ resources are versionless.** PG has its own versioning (migrations, `PG_VERSION`). A CubDB version bump leaves `pg` and `pq_files` intact.
- **Host:** PG is external, so `:pg` and `:pg_run` are `nil` for the internal unit on host.

### 2.3 Role

```elixir
defmodule Chat.Storage.Role do
  @capabilities %{
    internal: [:cub, :pg, :pq_files, :pipeline],
    main:     [:cub, :pg, :pq_files, :pipeline],
    backup:   [:cub, :pg, :pq_files, :pipeline],
    cargo:    [:cub],
    onliners: [:cub]        # planned: [:cub, :pg, :pq_files, :pipeline]
  }
  @dirs %{internal: "db", main: "main_db", backup: "backup_db", cargo: "cargo_db", onliners: "onliners_db"}
  @priority [:cargo, :onliners, :backup, :main]   # Decider's current order

  def capabilities(role)
  def dir(role)
  def from_mount(mount_path)   # -> {:ok, role} | :blank | {:error, {:multiple_roles, [role]}}
end
```

- **One `role_dir` per drive.** `from_mount/1` returns an error for multiple roles instead of silently picking by priority, because each role dir with a `pg/` is a separate cluster.
- **Role vs `DbType`.** The directory is the source of truth for role. `Bouncer`'s `DbType` check (backup's CubDB typed as `"main_db"`) is about CubDB *content* compatibility, not role. It stays CubDB-only and disappears with CubDB.
- **Onliners will get PG** (planned). Enabling it means changing its capabilities entry and adding a link plan (§2.7). No layout, naming or boot changes are needed. That is the test of this model. Cargo stays CubDB-only until decided.
- **Dump** is a scenario, not a role (it has no `role_dir`, and it reads `DCIM/`).

### 2.4 Cardinality

**At most one unit per role** (internal is always exactly one). This rule already exists implicitly through role-atom names (`Chat.Db.MainDb`, link names) and through `main_db_scenario_when_internal` returning `nil` for a second main. Now it is explicit:

- `Units.register/1` refuses a second unit with the same role.
- The boot sequence checks it at role resolution, before starting any engine (§3).
- **A duplicate is ignored, as today.** No scenario runs and nothing is indicated. The difference from today is that its PG is no longer started either. Today, a second backup only fails because `BackupDbSupervisor` has a fixed name, and a second main gets a `nil` scenario. Both become one explicit rule.

Role-derived names (`cub_name`, link names) are valid **because of** this invariant.

### 2.5 Units — the targeted registry

```elixir
defmodule Chat.Storage.Units do
  def register(%Unit{system_id: sid} = u)   # sid required when :pg in capabilities
  def unregister(%Unit{})
  def by_id(id)
  def by_role(role)
  def by_system_id(system_id)
  def list()
  def others(%Unit{})
end
```

- **Backing:** `Registry`, unique key = `role` (enforces §2.4), value = `%Unit{}`.
- **Registered** by the unit's `UnitAnnouncer` (renamed `DriveAnnouncer`), the last child of the unit's engine tree. It broadcasts `{:unit_up, unit}` and `{:unit_down, unit}` on `"storage"`.
- **Invariant:** a registered unit has all capability engines running.

### 2.6 Default — the pointer

```elixir
defmodule Chat.Storage.Default do
  def unit()                         # %Unit{}; internal at boot
  def switch_to(%Unit{} = unit)      # the ONLY setter
end
```

`switch_to/1` runs these steps in order, as one call:

1. Stop the Electric stack.
2. On the **old** unit: drop `electric_slot_default` and `electric_publication_default`, and remove `Unit.path(old, :electric)`. If the old unit is gone (ejected), skip this; its PG is not running, so it generates no WAL, and the leftovers are cleaned the next time it becomes Default.
3. Set the CubDB write queue/pid (`Chat.Db.Switching` keeps only queue plumbing).
4. Set the PG repo.
5. Set the upload chunk writer.
6. On the **new** unit: ensure the Electric slot, then start the Electric stack with `storage_dir: Unit.path(new, :electric)` and the new repo's connection opts. This absorbs `PhoenixSyncReinit`.
7. `DbBrokers.refresh/0`.
8. Broadcast `{:default_switched, unit}`.

Safety net, independent of this flow: `-c max_slot_wal_keep_size=<N>MB` in `@pg_minimal_settings`. A forgotten slot (Electric or link) is then invalidated instead of filling the disk.

- **Storage:** `:persistent_term`.
- **Removed:** `:files_base_dir`, `:active_drive_id`, `:repo` env keys, `Chat.Db.set_repo/1`, `ChunkPipeline.set_active_drive_id/1`, `Platform.Storage.PhoenixSyncInit` as a separate stage, and `:mode`. `:mode` becomes `Default.unit().role` plus link state (§2.7).
- **Read only at edges:** controllers, shapes, top-level chat API. Code under `Chat.Data.File.*`, `Platform.Storage.*` and `Platform.App.Drive.*` receives a `%Unit{}` and never calls `Default`.

| Edge | Today | After |
|---|---|---|
| `FileChunkController` download | `ChunkStore.fetch(fid, idx)` → `:files_base_dir` | `ChunkStore.fetch(Default.unit(), fid, idx)` |
| `FileChunkController` upload | `ChunkPipeline.active_drive_id()` | `Default.unit()` |
| `Shapes.FileChunk`, `NetworkSynchronization` | `active_drive_id()` | `Default.unit()` |
| `Chat.FileFs` readers, `chat.ex` | `CubDB.data_dir(Chat.Db.db()) <> "_files"` | `Unit.path(Default.unit(), :cub_files)` |
| `Chat.Db.repo/0` | app env | `Unit.repo(Default.unit())` |

### 2.7 Link — unit-to-unit data flow

A **Link** is a directed flow of data `from ~> to` between two units. It carries **all three layers** at once (CubDB, PG rows, chunk blobs), so no scenario can move rows and forget blobs.

```elixir
defmodule Chat.Storage.Link do
  @enforce_keys [:from, :to]
  defstruct [:from, :to, filter: :all]   # from/to: %Unit{}; filter: :all | %Link.Filter{}

  def new(from, to, opts \\ [])
  def id(link)                                   # {from.role, to.role}
  def name(link, :publication)                   # "internal_to_main"
  def name(link, :subscription | :slot)          # "main_from_internal"

  def bootstrap(link)                            # one-shot catch-up
  def replicate(link)                            # live follow
  def await(links, :chunks)                      # until `to` holds the blobs `from` provided
  def stop(link)                                 # tear down whatever replicate/bootstrap left
end
```

#### 2.7.1 Operations

| Operation | CubDB | PG | Blobs |
|---|---|---|---|
| `bootstrap/1` | `Copying.await_copied(from, to)` (scope = filter) | `BatchSync` from → to (schemas/rows = filter) | backfill `missing_chunks` on `to` for rows whose blob is absent, `source_drive_id = from.system_id` |
| `replicate/1` | `Switching.mirror(from, to)` | publication + slot on `from`, subscription on `to` (row filter = filter) | registers `from` as the replication source of `to`. `ReplicationListener` on `to` stamps `source_drive_id = from.system_id` |
| `await/2` | — | — | no `missing_chunks` on `to` with `source_drive_id = from.system_id` (bounded by a stall timeout, as `ChunkAwaiter` today) |
| `stop/1` | remove mirror | drop subscription on `to` (if up) and slot on `from` (always) | unregister replication source |

- **A link never writes blobs.** It only tells `to` what is missing and where to get it. The bytes are pulled by `to`'s own chunk pipeline (`DriveCopySource` → `Units.by_system_id/1` → `ChunkWriter`). Pull stays link-agnostic.
- **A link never switches Default.** `{:switch_default, unit}` in a plan calls `Default.switch_to/1`.
- **`stop/1` always cleans the `from` side.** If `to` was ejected, the slot on `from` would otherwise retain WAL (same disease as #796).

#### 2.7.2 Filter

`filter: :all` is the default. A `%Link.Filter{}` narrows **all three layers consistently**:

```elixir
%Link.Filter{
  cub_scope: ScopeProvider,                         # CubDB keys (today's onliners/cargo Copier `get_db_keys_from`)
  schemas: [UserCard, File, FileChunk, ...],        # PG tables
  rows: %{UserCard => &OnlinersScope.users/1, ...}, # per-schema row predicate (query fn)
  files: :referenced                                # blobs only for files referenced by the selected rows
}
```

- **`bootstrap`** applies `schemas` and `rows` to `BatchSync`. `missing_chunks` are created only for `FileChunk` rows that made it through.
- **`replicate`** maps the filter to a PG publication row filter (`CREATE PUBLICATION … FOR TABLE t WHERE (…)`, PG ≥ 15). If a predicate is not expressible there, the link is bootstrap-only.
- **The filter belongs to the link, not the role.** It describes this flow. The same role can receive different scopes from different plans.

#### 2.7.3 Plans

A scenario is a list of steps, not a bespoke GenServer:

```elixir
def plan(:main_attach, internal, main), do: [
  {:bootstrap, internal ~> main},
  {:replicate, internal ~> main},     # keep USB fresh while internal is still Default
  {:bootstrap, main ~> internal},     # pull USB-only data back
  {:stop,      internal ~> main},
  {:replicate, main ~> internal},     # internal becomes the mirror of main
  {:switch_default, main}
]

def plan(:main_eject, internal, main), do: [
  {:stop, main ~> internal},
  {:switch_default, internal}
]

def plan(:backup_once, default, backup), do: [
  {:bootstrap, backup ~> default},    # restore — rows + missing_chunks(source = backup)  ← #795
  {:bootstrap, default ~> backup},
  {:await, [backup ~> default, default ~> backup], :chunks},
  :eject
]

def plan(:backup_continuous, default, backup),
  do: (plan(:backup_once, default, backup) -- [:eject]) ++ [{:replicate, default ~> backup}]

# re-home on {:default_switched, new} while continuous backup is up
def plan(:backup_rehome, old, new, backup), do: [
  {:stop,      old ~> backup},
  {:bootstrap, new ~> backup},        # diff only — backup already holds most of it
  {:replicate, new ~> backup}
]

def plan(:onliners, internal, onliners), do: [            # with :pg (planned)
  {:bootstrap, Link.new(internal, onliners, filter: Onliners.filter())},
  {:await, [internal ~> onliners], :chunks},
  :eject
]
```

**Backup follows Default.** Internal (SD) tends to overflow, so while running on main it is **not** a reliable complete copy, and a backup fed from it would silently miss data. Backup links therefore use Default as their counterpart:

- **One-shot backup** binds to the Default at plan start.
- **Continuous backup** re-homes on `{:default_switched, new}` by running `plan(:backup_rehome, old, new, backup)`. `stop` drops the slot on the old Default, so no WAL is retained on internal. `bootstrap` is a diff, so re-homing is cheap.
- **Both cases:** the `PlanRunner` of the backup scenario subscribes to `{:default_switched, _}`. A one-shot plan still running at switch time is restarted against the new Default.

#### 2.7.4 Runtime

```
<Role>DbSupervisor (rest_for_one)
├─ …engines (CubDB, PG, pipeline, UnitAnnouncer)…
└─ PlanRunner  plan(:main_attach)
     ├─ LinkRunner internal~>main    bootstrap → replicate → stop
     └─ LinkRunner main~>internal    bootstrap → replicate
```

- **`LinkRunner`** (GracefulGenServer) owns one link. `on_exit` → `Link.stop/1`. Eject, crash and restart all clean up through the same path.
- **`Links` registry**, keyed by `Link.id/1`, holds the status: `:idle | {:bootstrapping, progress} | :replicating | {:awaiting, {done, total}} | :stopped | {:partial, map} | {:error, term}`, plus `lag_bytes` for replicating links.

```elixir
Links.list()
#=> [%{id: {:main, :internal},   status: :replicating, lag_bytes: 1_204},
#    %{id: {:internal, :backup}, status: {:bootstrapping, %{rows: :done, chunks: {120, 400}}}}]
```

It replaces `:flags` (`backup:`, `replication:`), `:mode`, the global `Platform.Storage.Sync` status and `Platform.Storage.Logic.info/0`. Admin UI and LEDs read one place.

#### 2.7.5 What it replaces

| Today | With Link |
|---|---|
| `Sync.run_local_sync/1` (with backfill), `Backup.Copier.sync_pg/1` (without), `InternalToMain.Copier.sync_pg_to_main/1` | `Link.bootstrap/1` |
| `InternalToMain.Copier`, `InternalToMain.Switcher`, `Backup.Copier`, `Backup.ChunkAwaiter` | plans + `LinkRunner` |
| `Storage.Logic.do_replicate_to_internal/0` (`Process.whereis(backup)` picks mirrors; `TODO: continuous backup need a way for new changes`) | the set of active links |
| hardcoded `"internal_to_main"`, `"backup_from_internal"`, … | `Link.name/2` |
| `ChatBridge.Logic.unmount_main/0` (parses the device from `MainDb`'s CubDB path) | `Units.by_role(:main).id` |
| onliners/cargo `Copier get_db_keys_from:` | `Link.Filter.cub_scope` |

**Testing:** one host integration test per operation, with `Platform.Test.InternalRepo` / `MainRepo` and temporary `pq_files` dirs. Plans are pure lists, tested as data.

---

## 3. Unit Lifecycle (boot order)

```
Healer → Mount
  → Resolve   Role.from_mount/1
                :blank            → maybe optimize_fs (nothing on disk yet) → pick role from MediaSettings → mkdir role_dir   ← role sticks here
                {:ok, role}       → check cardinality (Units.by_role) — conflict → stop, no engines
                {:error, multi}   → stop, log
  → Scenario  dump override (UsbDriveDumpRoom) → dump scenario, no engines
  → Engines   per Role.capabilities:  :cub → CubDB  ·  :pg → PG init/daemon/db/repo/migrations  ·  :pipeline → ChunkPipelineSupervisor
  → Announce  query system_id → Units.register → {:unit_up, unit}
  → Links     run the scenario's link plan (§2.7)
```

- `optimize_fs` runs before anything is written, so the blank check is meaningful again and never formats under a live PG.
- PG starts only for roles with `:pg`. Today that excludes dump, cargo and onliners; onliners joins when its capability flips. PG also never starts for a rejected duplicate role.
- `BootWatchdog` watches stages keyed by `Unit.via/2`.
- Eject reverses the order: links stop → `Default.switch_to(internal)` if needed → unregister → engines stop.

The internal unit follows the same sequence. Its root and role are fixed (`/root`, `:internal`), and there is no mount or resolve step.

---

## 4. Targeted API Rule

Functions that act on a unit take `%Unit{}` as the **first** argument. There is no `base_dir \\ nil`, and no `repo` / `drive_id` / `base_dir` triple in opts.

| Module | Today | After |
|---|---|---|
| `ChunkStore` | `put/fetch/count_on_disk/delete_file/sweep_tmp_files/sync_dir(…, base_dir \\ nil)`, `available_space/0` | `put(unit, fid, idx, bin)`, `fetch(unit, fid, idx)`, …, `available_space(unit)` |
| `ChunkPipelineSupervisor` + children | `drive_id:, base_dir:, repo:` | `unit:` |
| `DriveCopySource` | `DriveDirs.list_usb_drive_dirs/0` + `query_system_id/1` + `device_repo/1` | `Units.others(unit)`, `Units.by_system_id/1`; subscribes to `{:unit_up / :unit_down, unit}` |
| `ReplicationListener` | own `query_system_id/1` | `unit.system_id` |
| `MissingChunksBackfill` | `source_drive_id: nil` | unchanged semantics (`nil` = "any unit") |
| `Backup.Copier`, `Backup.ChunkAwaiter`, `InternalToMain.*`, `Storage.Sync` | repos, `backup_base_dir`, global status | `Link` plans |
| `*DbSupervisor`, `BootSupervisor`, `DatabaseSupervisor`, `RunDir`, `Decider` | joins, `@pg_dir`, `pg_port_for_device`, `Module.concat`, path parsing | `Unit.*`, `Role.*` |
| CubDB `Copying.Progress`, `WriteQueue.ReadStream`, `Pipeline.Writer` | `CubDB.data_dir(db) <> "_files"` | `Unit.path(unit, :cub_files)` |
| `Chat.Debug` | own `pq_files` join | `Unit.path(unit, :pq_files)` |

**Deleted:** `Chat.Data.File.DriveDirs`, `Dev.path/3`, `Platform.Storage.Sync` (absorbed by `Link`), `Platform.Storage.PhoenixSyncInit` (absorbed by `Default.switch_to/1`), every `<> "_files"`, hardcoded publication/slot/subscription strings.

---

## 5. Invariants

1. **Only `Chat.Storage.Unit` / `Role` / `Link` contain** path segments (`"pg"`, `"pq_files"`, `"_files"`, `"_db"`, version) and link-name strings. A test greps `lib/` of chat and platform for these literals.
2. **At most one registered unit per role.** Exactly one internal.
3. **A registered unit has all its capability engines running.** If it has `:pg`, its `system_id` is non-nil.
4. **`Default.unit()` is always a registered unit.** CubDB queue, repo, upload writer and Electric always point at it. They never diverge observably.
5. **`Default` is read only at edges.** Below the edge, units are passed explicitly.
6. **Every `Link.bootstrap/1` leaves `to` with `missing_chunks`** for each `file_chunks` row (within the link's filter) whose blob is absent from `Unit.path(to, :pq_files)`, with `source_drive_id = from.system_id`.
7. **`missing_chunks.source_drive_id`** is `nil` or a `system_id` resolvable via `Units.by_system_id/1` while that unit is up.

---

## 6. Follow-ups Unlocked (separate issues)

- **#795:** backup → Default blobs. Comes from `Link.bootstrap` (invariant 6) plus `Units.by_system_id`.
- **`ChunkAwaiter`:** await both `to` units. "Present" means the blob is on disk, not "no missing_chunks row".
- **Upload/manifest split window:** closed by invariant 4.
- **Continuous backup:** a `default ~> backup` link that re-homes on Default switch (§2.7.3), instead of hardcoded `Chat.Repo` / `Switching.mirror(Chat.Db.MainDb, …)`.
- **Replicated chunk source:** `ReplicationListener` stamps `from.system_id` registered by `Link.replicate/1` instead of its own id (§1.6).
- **`DriveCopySource` fallback:** iterate `Units.others/1` instead of picking one random dir.
- **Idle Electric slots retain WAL** (§1.6). Can ship before this refactor: stop pre-creating `electric_slot_default` on non-Default units, drop it on the unit left behind, and set `max_slot_wal_keep_size`.

## 7. Migration — keep CubDB, drop PostgreSQL

### 7.1 Compatibility

| Generation | Policy | Why it works |
|---|---|---|
| CubDB (`v.10.1`, `v.10.1_files`) | **kept** | paths are identical: internal `role_dir = "db"` → `/root/db/v.10.1`; USB `<mount>/<role>_db/v.10.1`. `@db_version` unchanged. `Bouncer` / `DbType`, `Copying`, `Switching.mirror` unchanged. |
| PostgreSQL (`pg`, `pq_files`, Electric storage) | **dropped** | early stage; recreated on first boot by Engines + migrations |

Rules that keep existing CubDB drives working:

- **Role resolution accepts legacy multi-role drives.** If several `*_db` dirs exist, keep the current priority (cargo > onliners > backup > main). Return `{:error, :multiple_roles}` only when more than one of them contains `pg/`.
- **Blank detection** stays "mount root is empty". A legacy drive with only `<mount>/pg` gets that dir removed by the reset below, then is treated as blank.
- **CubDB copy order inside `Link.bootstrap/1`** is exactly the current `Copying.await_copied` / `Switching.mirror` sequence. Only the PG and blob halves are new.
- **CubDB process names** (`Chat.Db.MainDb`, …) are runtime-only. Deriving them via `Unit.cub_name/1` has no on-disk effect.

### 7.2 One-time PQ reset

A step in Resolve (§3) runs before engines start. It is idempotent and is removed once the fleet is migrated.

| Unit | Removes |
|---|---|
| internal | `/root/pg`, `/root/db/v.10.1_files/pq_files`, `/root/electric` |
| USB | `<mount>/pg`, `<mount>/<role_dir>/v.10.1_files/pq_files` |

Removing `pq_files` from inside `v.10.1_files` also cleans the CubDB generation. FileFs walks `v.10.1_files/<hc>/<key>` two levels deep (`list_all_db_keys/1`, `list_file_errors/1`). Today it descends into `pq_files/<shard>/f_…` too, and only a `rescue` keeps it from crashing.

**Lost by the reset:** everything that exists only in PQ — PQ users (`UserCard`), PQ-uploaded files, vouch tokens, reviews, origins. Electric clients get 409 / must-refetch and resync against the empty stack.

### 7.3 Steps

1. **Model:** `Unit`, `Role`, `Units`, `Default`, `Link` with pure unit tests (derivation table per role × resource, host/target roots, link names).
2. **Platform boot:** Resolve → Scenario → Engines → Announce → Links. `Decider` splits into role resolution and scenario choice.
3. **Chunk pipeline + `ChunkStore` on `%Unit{}`.** Delete `DriveDirs`.
4. **`Default.switch_to/1`.** Remove the env keys, `set_repo`, `set_active_drive_id`, `PhoenixSyncInit`.
5. **`Link`.** Port the main and backup scenarios to link plans. Delete `Storage.Sync`, `Backup.Copier.sync_pg/1` and `InternalToMain.Copier.sync_pg_to_main/1`.
6. **CubDB file paths via `Unit`.**
7. **Literal-grep invariant test.**
8. **PQ reset step (§7.2).** Verify on a device with a legacy main drive and a legacy backup drive that CubDB data and files survive and the PQ generation rebuilds.

## 8. Decisions

| Topic | Decision |
|---|---|
| **AdminDB** | Device (system) level. Stays at `<internal_root>/admin_db_v2`, outside any unit. |
| **CubDB generation** | Stays. `:cub_db` / `:cub_files` remain regular `Unit` resources; there is no legacy module. |
| **Media root ownership** | Chat config (`config :chat, Chat.Storage, media_root: …`). Platform reads it from there. |
| **Scoped data (onliners, later cargo)** | A `filter` parameter on `Link` (§2.7.2), not a role property. |
| **Duplicate role on insert** | Keep current behavior: the second drive of an occupied role is ignored (no scenario, no indication). It is now detected at Resolve, so no engines (PG) start for it either (§2.4, §3). |

## 9. Open Questions

- **Onliners filter contents:** which schemas and row predicates define the onliners scope in PG terms, and whether they are expressible as publication row filters (otherwise onliners stays bootstrap-only).
- **Internal overflow vs `main ~> internal` (out of scope).** Internal (SD) tends to overflow while running on main. A full disk makes the `main ~> internal` subscription fail. Internal PG may then halt on apply errors, and the slot on main retains WAL until `max_slot_wal_keep_size` invalidates it (#796). This is likely addressed by a separate rollover/retention plan (deleting old data on internal), possibly combined with a `filter` on that link (§2.7.2). This proposal only requires that the link surfaces it as `{:error, :disk_full}` in `Links` rather than failing silently.
- **Cargo:** CubDB-only for now. If it gains `:pg`, it follows the same path as onliners.
- **Electric `storage_dir` on reinit:** verify that `Phoenix.Sync.Application.children/0` picks up a changed `storage_dir` from app env (today `PhoenixSyncReinit` only updates `:repo` and `:connection_opts`). If not, pass it explicitly when building the stack children.
- **`max_slot_wal_keep_size` value:** it must exceed the worst-case gap for a legitimate link slot (e.g. a backup drive reconnecting), yet stay well below free space on SD. Tracked in [#796](https://github.com/Buckitup-chat/chat/issues/796).
