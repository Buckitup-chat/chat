## User

### User Card

- user_hash
- sign_pkey
- crypt_pkey
- crypt_cert
- contact_pkey
- contact_cert
- name

### User Identity [FE only or bots or tests]

- user_card
- sign_skey
- crypt_skey
- contact_skey
- is_trusted_origin

### User Storage

- user_hash
- uuid
- value

## Implementation

Postgres domain types (prefix-versioned bytea):

```SQL
  CREATE DOMAIN user_hash AS bytea NOT NULL CHECK (substring(VALUE from 1 for 1) = '\x01'::bytea);
```

Custom Ecto type:

```elixir
  defmodule Chat.Data.Types.UserHash do
    use Ecto.Type

    @impl true
    def type, do: :bytea

    @impl true
    def cast(<<0x01, _>> = hash) when is_binary(hash), do: {:ok, hash}
    def cast(_), do: :error

    @impl true
    def dump(value), do: cast(value)

    @impl true
    def load(value), do: cast(value)
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
      field(:crypt_pkey, :binary)
      field(:crypt_cert, :binary)
      field(:contact_pkey, :binary)
      field(:contact_cert, :binary)
      field(:name, :text)
    end

    def create_changeset(card, attrs) do
      card
      |> cast(attrs, [:user_hash, :sign_pkey, :crypt_pkey, :crypt_cert, :contact_pkey, :contact_cert, :name])
      |> validate_required([:user_hash, :sign_pkey, :crypt_pkey, :name])
    end

    def update_name_changeset(card, attrs) do
      card
      |> cast(attrs, [:user_hash, :name])
      |> validate_required([:user_hash, :name])
    end
  end
```

User Storage schema:

```elixir
  defmodule Chat.Data.Schemas.UserStorage do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false

    schema "user_storage" do
      field(:user_hash, Chat.Data.Types.UserHash, primary_key: true)
      field(:uuid, :uuid, primary_key: true)
      field(:value, :binary)
    end

    def changeset(storage, attrs) do
      storage
      |> cast(attrs, [:user_hash, :uuid, :value])
      |> validate_required([:user_hash, :uuid, :value])
    end
  end
```

**Hash Algorithm: SHA3-512**

- Use `:crypto.hash(:sha3_512, data)` for computing user hashes
- Output: 512 bits (64 bytes) with version prefix 0x01
- Security: NIST-approved, post-quantum resistant, suitable for long-term archival
- Final format: `<<0x01, sha3_512_digest::binary>>`

### Shortcode Display

For user-friendly display, user_hash is shortened to a 6-character hex code:

**Implementation:**
- Extract bytes 2-4 from user_hash (skipping the 0x01 prefix)
- Encode as lowercase hexadecimal
- Example: `0x01aabbccdddddddd...` → shortcode `"aabbcc"`

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
  def short_code(%Chat.Data.Schemas.UserCard{user_hash: user_hash}) do
    <<_prefix::binary-size(1), code::binary-size(3), _rest::binary>> = user_hash
    Base.encode16(code, case: :lower)
  end
end
```

**Usage:**
- UI displays: `Chat.Proto.Shortcode.short_code(user_card)`
- Provides collision-resistant identification (24 bits = 16.7M combinations)
- Used in LiveView pages like `/electric/user_cards`
