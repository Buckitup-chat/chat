All Electric /ingest operations should be verified with proof-of-possesion

I.e. client should retrieve the challenge and sign it with user and/or room sign key to make operations on their behalf.

Challenge should be a random string. And expire in 1 minute.
It can be retrieved from the /api/v1/challenge endpoint. Or from a responce to /api/v1/ingest

When client does user related operation (register, update, remove) it should sign a challenge with user sign key.
And put x-user-challange-id and x-user-signature headers to the request.
For room operations another challenge should be used. And x-room-challange-id and x-room-signature headers should be used.

When operation requires both user and room sign keys same challenge can be used.