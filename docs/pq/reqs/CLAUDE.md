# pq/reqs — PostgreSQL Requirements

Semantically grouped requirements for PostgreSQL-related features.

## Structure

Each document lives in a subfolder by topic and carries a status suffix:

```
pq/reqs/
  <topic>/
    <name>.<status>.md
```

Existing files here predate this convention and haven't been moved into `<topic>/` subfolders yet.

## Status Lifecycle

| Suffix        | Meaning                                              |
|---------------|------------------------------------------------------|
| `.proposed`   | New feature plan, not yet started                    |
| `.in_progress`| Partially implemented                               |
| `.done`       | Fully implemented                                    |
| `.obsolete`   | Superseded or replaced; candidate for refactor       |

Progression: `proposed` -> `in_progress` -> `done` -> `obsolete`

When a requirement changes status, rename the file to reflect the new suffix.
