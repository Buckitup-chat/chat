# pq/reqs — PostgreSQL Requirements

Semantically grouped requirements for PostgreSQL-related features.

## Structure

Every requirement file **must** carry a status suffix:

```
<name>.<status>.md
```

Files **may** be organized into `<topic>/` subfolders, but this is optional:

```
pq/reqs/
  <name>.<status>.md          # flat — fine
  <topic>/
    <name>.<status>.md         # grouped — also fine
```

## Status Lifecycle

| Suffix        | Meaning                                              |
|---------------|------------------------------------------------------|
| `.proposed`   | New feature plan, not yet started                    |
| `.in_progress`| Partially implemented                               |
| `.done`       | Fully implemented                                    |
| `.obsolete`   | Superseded or replaced; candidate for refactor       |

Progression: `proposed` -> `in_progress` -> `done` -> `obsolete`

When a requirement changes status, rename the file to reflect the new suffix.
