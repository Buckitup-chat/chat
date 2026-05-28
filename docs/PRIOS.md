# Priorities

8. ~~Implement dialog shapes ([pq_dialogs.md](reqs/pq_dialogs.md))~~ ✅
10. Integrate external frontend ([external_frontend_integration.md](proposal/external_frontend_integration.md))
15. ~~Decide how to group tests to use ExUnit :group option~~ ✅
16. ~~Use REST file_chunks for file download/streaming~~ ✅
17. ~~Ensure files and chunks are network syncronizable~~ ✅
18. ~~Dialog sandbox: message edits (version chain with parent_sign_hash, archive to dialog_messages_versions)~~ ✅
19. ~~Dialog sandbox: encrypted emoji reactions (HMAC hash, AES-GCM encrypted type)~~ ✅
20. ~~Dialog sandbox: delivered/read receipts (unencrypted, signed)~~ ✅
21. ~~Dialog sandbox: message deletion (signed tombstone with deleted_flag)~~ ✅
~~22. Dialog sandbox: non-text content types (media, attachments via content polymorphism)~~ ✅
~~23. File sandbox: bake content polymorphism types into file_sandbox.html — upload file/image/video, produce JSON content objects per [07_content_polymorphism.md](electric/pq_data_layer/07_content_polymorphism.md), copy-paste into dialog sandbox; extract content from dialog and download via file_sandbox~~ ✅