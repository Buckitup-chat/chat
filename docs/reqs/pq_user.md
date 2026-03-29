## Purpose

Users are identified by a post-quantum keypair they generate locally. There is no registration — a user proves identity by signing a challenge with their `sign_skey`. The server only stores public keys.

Once registered, users can:
- Store arbitrary encrypted data (User Storage)
- Communicate with other users (planned)

Secret keys never leave the Frontend. If the server is compromised, it holds no private keys and no plaintext data.

---

## Algorithms & Fields

### Fields

| Field | Size | Algorithm / Format | Notes |
|---|---|---|---|
| `user_hash` | 130 chars | `"u_" + hex(SHA3-512(sign_pkey))` | URL-friendly hex string with prefix |
| `sign_pkey` | ~2592 bytes | ML-DSA-87 (FIPS 204) | Post-quantum signing public key |
| `sign_skey` | ~4896 bytes | ML-DSA-87 (FIPS 204) | Post-quantum signing private key; FE/bots only |
| `crypt_pkey` | ~1568 bytes | ML-KEM-1024 (FIPS 203) | Post-quantum KEM encapsulation key |
| `crypt_skey` | ~3168 bytes | ML-KEM-1024 (FIPS 203) | Post-quantum KEM decapsulation key; FE/bots only |
| `crypt_cert` | ~4627 bytes | ML-DSA-87 signature of `crypt_pkey` | Binds encryption key to identity |
| `contact_pkey` | 33 bytes | secp256k1 compressed | Classical key exchange (Curvy) |
| `contact_skey` | 32 bytes | secp256k1 | Classical private key; FE/bots only |
| `contact_cert` | ~4627 bytes | ML-DSA-87 signature of `contact_pkey` | Binds contact key to identity |
| `name` | text | UTF-8 | Display name |
| `deleted_flag` | boolean | true/false | Soft delete marker; true indicates deleted |
| `owner_timestamp` | integer | Monotonic counter | Prevents replay attacks; must increase on updates |
| `sign_b64` | ~4627 bytes | ML-DSA-87 signature | Signature of all fields except sign_b64 itself |

### Algorithms

| Purpose | Algorithm | Standard | Library |
|---|---|---|---|
| Identity hash | SHA3-512 + `0x01` prefix | NIST FIPS 202 | OTP 28 `:crypto` |
| Signing | ML-DSA-87 | NIST FIPS 204 | OTP 28 `:crypto` |
| Key encapsulation | ML-KEM-1024 | NIST FIPS 203 | OTP 28 `:crypto` |
| Contact key exchange | secp256k1 ECDH | SEC 2 | Curvy ~> 0.3 |
| Symmetric encryption | AES-256-GCM | NIST SP 800-38D | OTP 28 `:crypto` |
| Secret sharing | Shamir's Secret Sharing | — | KeyX ~> 0.4 |

### Certificate format

Both `crypt_cert` and `contact_cert` are raw ML-DSA-87 signatures:

```
cert = ML-DSA-87.sign(public_key_bytes, sign_skey)
```

Verification: `ML-DSA-87.verify(public_key_bytes, cert, sign_pkey)`

No X.509 or ASN.1 wrapping — bare binary signatures bound by identity via `user_hash`.

---

## User

### User creation

All keys are generated locally on the Frontend. There is no server-side registration step — the user submits their User Card and is immediately recognized by `user_hash` on future visits.

Authentication is implicit: the server trusts whoever can produce a valid ML-DSA-87 signature with `sign_skey` matching a known `sign_pkey`.

Key generation:

- sign keypair — ML-DSA-87 (FIPS 204)
- crypt keypair — ML-KEM-1024 (FIPS 203)
- contact keypair — secp256k1

Derived values:

- `user_hash` = `"u_" + Base.encode16(SHA3-512(sign_pkey), case: :lower)`
- `crypt_cert` = `ML-DSA-87.sign(crypt_pkey, sign_skey)`
- `contact_cert` = `ML-DSA-87.sign(contact_pkey, sign_skey)`

Secret keys (`sign_skey`, `crypt_skey`, `contact_skey`) are stored in the User Identity on the Frontend only and never sent to the server.


### User Card

User card is stored in the database.

- user_hash
- sign_pkey
- crypt_pkey
- crypt_cert
- contact_pkey
- contact_cert
- name
- deleted_flag
- owner_timestamp
- sign_b64

### User Identity [FE only or bots or tests]

User identity is stored by Frontend.

- user_card (embeded or linked)
- sign_skey
- crypt_skey
- contact_skey
- is_trusted_origin

### User Storage

User storage is a simple key-value store.
`user_hash` is used to scope a user specific storage.
`uuid` is for Frontend to distinguich different pieces of data.
`value_b64` is the value stored in the storage. It is not encrypted on server side. It is the duty of the Frontend to encrypt it.

- user_hash
- uuid
- value_b64

## Implementation

PostgreSQL custom domain types with format validation:

```SQL
CREATE DOMAIN user_hash_type AS TEXT
  CHECK (VALUE ~ '^u_[a-f0-9]{128}$');
```

Custom Ecto type:

```elixir
  defmodule Chat.Data.Types.UserHash do
    use Ecto.Type
    alias Chat.Data.Types.Consts

    @prefix Consts.user_prefix()  # "u_"
    @expected_hex_length 128  # 64 bytes * 2

    @impl true
    def type, do: :string

    @impl true
    def cast(@prefix <> hex_string) when byte_size(hex_string) == @expected_hex_length do
      case Base.decode16(hex_string, case: :mixed) do
        {:ok, _binary} -> {:ok, @prefix <> String.downcase(hex_string)}
        :error -> :error
      end
    end

    def cast(_), do: :error

    @impl true
    def dump(@prefix <> hex_string) do
      {:ok, @prefix <> String.downcase(hex_string)}
    end

    def dump(_), do: :error

    @impl true
    def load(@prefix <> _hex_string = value), do: {:ok, value}
    def load(_), do: :error

    @doc "Convert binary hash to string format"
    def from_binary(binary) when byte_size(binary) == 64 do
      @prefix <> Base.encode16(binary, case: :lower)
    end

    @doc "Convert string hash to binary format"
    def to_binary(@prefix <> hex_string) do
      case Base.decode16(hex_string, case: :mixed) do
        {:ok, binary} -> binary
        :error -> nil
      end
    end
  end
```

User Card schema:

```elixir
  defmodule Chat.Data.Schemas.UserCard do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:user_hash, Chat.Data.Types.UserHash, []}

    schema "user_cards" do
      field(:sign_pkey, :binary)
      field(:contact_pkey, :binary)
      field(:contact_cert, :binary)
      field(:crypt_pkey, :binary)
      field(:crypt_cert, :binary)
      field(:name, :string)
      field(:deleted_flag, :boolean)
      field(:owner_timestamp, :integer)
      field(:sign_b64, :binary)
    end

    def create_changeset(card, attrs) do
      card
      |> cast(attrs, [:user_hash, :sign_pkey, :contact_pkey, :contact_cert, :crypt_pkey, :crypt_cert, :name, :deleted_flag, :owner_timestamp, :sign_b64])
      |> validate_required([:user_hash, :sign_pkey, :contact_pkey, :contact_cert, :crypt_pkey, :crypt_cert, :name, :deleted_flag, :owner_timestamp, :sign_b64])
      |> unique_constraint(:user_hash, name: :user_cards_pkey)
    end

    def update_name_changeset(card, attrs) do
      card
      |> cast(attrs, [:name, :owner_timestamp, :sign_b64])
      |> validate_required([:name, :owner_timestamp, :sign_b64])
    end

    def update_deleted_flag_changeset(card, attrs) do
      card
      |> cast(attrs, [:deleted_flag, :owner_timestamp, :sign_b64])
      |> validate_required([:deleted_flag, :owner_timestamp, :sign_b64])
    end
  end
```

User Storage schema:

```elixir
  defmodule Chat.Data.Schemas.UserStorage do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    @max_value_size 10_485_760

    schema "user_storage" do
      field(:user_hash, Chat.Data.Types.UserHash, primary_key: true)
      field(:uuid, Ecto.UUID, primary_key: true)
      field(:value_b64, :binary)
    end

    def create_changeset(storage, attrs) do
      storage
      |> cast(attrs, [:user_hash, :uuid, :value_b64])
      |> validate_required([:user_hash, :uuid, :value_b64])
      |> validate_value_size()
      |> unique_constraint([:user_hash, :uuid], name: :user_storage_pkey)
    end

    def update_changeset(storage, attrs) do
      storage
      |> cast(attrs, [:value_b64])
      |> validate_required([:value_b64])
      |> validate_value_size()
    end

    def delete_changeset(storage, _attrs), do: storage

    defp validate_value_size(changeset) do
      case get_field(changeset, :value_b64) do
        nil ->
          changeset

        value when byte_size(value) <= @max_value_size ->
          changeset

        _ ->
          add_error(changeset, :value_b64, "exceeds 10 MB limit")
      end
    end
  end
```

**Hash Algorithm: SHA3-512**

- Use `:crypto.hash(:sha3_512, data)` for computing user hashes
- Output: 512 bits (64 bytes) encoded as hex with "u_" prefix
- Security: NIST-approved, post-quantum resistant, suitable for long-term archival
- Final format: `"u_" <> Base.encode16(sha3_512_digest, case: :lower)` (130 characters total)

### Shortcode Display

For user-friendly display, user_hash is shortened to a 6-character hex code:

**Implementation:**
- Extract first 3 bytes from the hex portion (after "u_" prefix)
- Take first 6 hex characters
- Example: `"u_aabbccdddddddd..."` → shortcode `"aabbcc"`

**Protocol:**

```elixir
defprotocol Chat.Proto.Shortcode do
  @moduledoc """
  Protocol for extracting a short code from entities with user_hash.

  Skips the first byte (prefix) and takes the next 3 bytes, encoded as hex.
  Example: user_hash 0x01aabbccdddddddd... => shortcode "aabbcc"
  """

  @doc """
  Returns a 6-character hex string representing bytes 2-4 of the user_hash.
  """
  def short_code(entity)
end

defimpl Chat.Proto.Shortcode, for: Chat.Data.Schemas.UserCard do
  def short_code(%Chat.Data.Schemas.UserCard{user_hash: "u_" <> hex_string}) do
    # Take first 6 hex characters (3 bytes worth)
    String.slice(hex_string, 0, 6)
  end
end
```

**Usage:**
- UI displays: `Chat.Proto.Shortcode.short_code(user_card)`
- Provides collision-resistant identification (24 bits = 16.7M combinations)
- Used in LiveView pages like `/electric/user_cards`
