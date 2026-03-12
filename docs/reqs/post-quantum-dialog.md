## Dialog

!!! Split into sides !!!

Dailog

### Table structure

- dialog_hash = [sender_hash, peer_hash] |> sort() |> concat() |> sha3_512()
- user_a_hash = [sender_hash, peer_hash] |> min()
- user_b_hash = [sender_hash, peer_hash] |> max()

Postgres domain types (prefix-versioned bytea):
CREATE DOMAIN dialog_hash AS bytea NOT NULL CHECK (substring(VALUE from 1 for 1) = '\x02'::bytea);

## Dialog Secrets

For message encryption we need `sender_message_secret` (randomly generated per side of dialog) It would be used to encrypt all the messages in the dialog from sender.

Sender needs to read it own messages and write new ones with same `sender_message_secret`
Peer needs to read sender messages encrypted with `sender_message_secret`

Each side has to

- For sender we generate(encapsulate) with KEM a pair `sender_enc_secret_b64` and `sender_random_secret`. `sender_random_secret` is used to encrypt `sender_message_secret` resulting `sender_msg_secret_b64`
- For peer we generate(encapsulate) with KEM a pair `peer_enc_secret_b64` and `peer_random_secret`. `peer_random_secret` is used to encrypt `sender_message_secret` resulting `peer_msg_secret_b64`

### Table structure

- dialog_hash
- sender_hash
- sender_enc_secret_b64
- sender_msg_secret_b64
- peer_enc_secret_b64
- peer_msg_secret_b64

## Dialog Message

Dialog Message

- dialog_hash
- message_uuid = uuid v7
- sender_hash
- author_sign_of
- message
- enc_shared_secret
- ...

# Problems

- message order mergeble
- message read status
- polymorphic/embdded content
- read versions?
- proves/ likes?
