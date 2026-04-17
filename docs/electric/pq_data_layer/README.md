Here is the problems we are solving:

- Proof-of-Possession - clint confirms ownership on every write
- Integrity - storing data in the way that proves it is authentic
- Data Versioning - [signature hash + prev sign_hash]
- Ordering - [message_uuid and prev message_uuid]
- Branching - [responding to custom message_uuid]
- Reactions - including reading
- Content Polymorphism - text, image, video, audio, file
- Snapshoting - snapshot of conversation state signed by peer [full graph of message_uuids and sign_hashes]
