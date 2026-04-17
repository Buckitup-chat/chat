Here is the problems we are solving:

- [Proof-of-Possession](./01_proof_of_possession.md) — client confirms ownership on every write **(solved)**
- [Integrity](./02_integrity.md) — storing data in the way that proves it is authentic **(solved)**
- [Data Versioning](./03_data_versioning.md) — `[signature hash + prev sign_hash]` **(solved for user storage)**
- [Ordering](./04_ordering.md) — `[message_uuid and prev message_uuid]`
- [Branching](./05_branching.md) — responding to custom `message_uuid`
- [Reactions](./06_reactions.md) — including reading
- [Content Polymorphism](./07_content_polymorphism.md) — text, image, video, audio, file
- [Snapshoting](./08_snapshots.md) — snapshot of conversation state signed by peer `[full graph of message_uuids and sign_hashes]`

See also: [SCHEMAS.md](./SCHEMAS.md) for the tables backing the solved problems.
