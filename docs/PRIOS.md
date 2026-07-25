# Priorities


13. Discover industrial / high-endurance SD cards. Consumer cards wear out under PostgreSQL write load (WAL + ~4MB file-chunk inserts) and fail with `mmc_erase` / "Card stuck being busy" errors, which crashes PostgreSQL init and leaves Electric unable to start. Evaluate industrial (pSLC/SLC) cards and/or moving the PG data directory to a USB SSD.

2. Deprecate `sync` routes in favor of `v1/shapes`

