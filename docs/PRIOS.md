# Priorities

9. Integrate external frontend ([external_frontend_integration.md](proposal/external_frontend_integration.md))

10. ~~Editing only one version~~
11. ~~Reactions should be tied to reacted version~~

12. Reviews planning: to_public / to_owner / to_contacts. SaaS. Pre/moderation on public?

13. Discover industrial / high-endurance SD cards. Consumer cards wear out under PostgreSQL write load (WAL + ~4MB file-chunk inserts) and fail with `mmc_erase` / "Card stuck being busy" errors, which crashes PostgreSQL init and leaves Electric unable to start. Evaluate industrial (pSLC/SLC) cards and/or moving the PG data directory to a USB SSD.

14. Fix bugs
15. Update SQL structure
1. Deal with upload speed
2. Update .xyz (+ BE -> /trusted)
