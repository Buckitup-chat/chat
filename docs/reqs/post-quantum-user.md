## User


User Card
 - user_hash
 - sign_pkey
 - crypt_pkey
 - crypt_pkey_cert
 - name


User Identity [FE only or bots or tests]
 - user_card
 - sign_skey
 - crypt_skey
 - is_trusted_origin 


User Storage
 - user_hash
 - uuid
 - value



Postgres domain types (prefix-versioned bytea):
  CREATE DOMAIN user_hash        AS bytea NOT NULL CHECK (substring(VALUE from 1 for 1) = '\x01'::bytea);
  

Custom Ecto type:
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

User Card schema:
  defmodule Chat.Data.Schemas.UserCard do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:user_hash, Chat.Data.Types.UserHash, []}

    schema "user_cards" do
      field(:sign_pkey, :binary)
      field(:crypt_pkey, :binary)
      field(:crypt_pkey_cert, :binary)
      field(:name, :text)
    end

    def create_changeset(card, attrs) do
      card
      |> cast(attrs, [:user_hash, :sign_pkey, :crypt_pkey, :crypt_pkey_cert, :name])
      |> validate_required([:user_hash, :sign_pkey, :crypt_pkey, :name])
    end
    
    def update_name_changeset(card, attrs) do
      card
      |> cast(attrs, [:user_hash, :name])
      |> validate_required([:user_hash, :name])
    end
  end

User Storage schema:
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


**Hash Algorithm: SHA3-512**
- Use `:crypto.hash(:sha3_512, data)` for computing user hashes
- Output: 512 bits (64 bytes) with version prefix 0x01
- Security: NIST-approved, post-quantum resistant, suitable for long-term archival
- Final format: `<<0x01, sha3_512_digest::binary>>`

