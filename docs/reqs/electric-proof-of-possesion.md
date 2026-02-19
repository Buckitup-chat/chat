All Electric /ingest operations should be verified with proof-of-possesion

I.e. client should retrieve the challenge and sign it with user and/or room sign key to make operations on their behalf.

Challenge should be a random string. And expire in 1 minute.
It can be retrieved from the /api/v1/challenge endpoint. Or from a responce to /api/v1/ingest

When client does user related operation (register, update, remove) it should sign a challenge with user sign key.
And put the challenge_id and signature in the request body under `auth.challenge_id` and `auth.signature` (base64-encoded).

When operation requires both user and room sign keys same challenge can be used.