defmodule Chat.Data.PqConformanceTest do
  @moduledoc """
  Cross-implementation conformance vectors, shared with the reference client.

  `docs/pq/conformance/vectors.json` pins the byte-exact derivations both sides
  must agree on: the canonical signature payload per relation and the prefixed
  hash / HKDF constructions. The same file is asserted by the frontend
  (`chat-frontend tests/pqConformance.test.ts`, which also generates it under
  `WRITE_VECTORS=1`); a deliberate protocol change regenerates the file there
  and carries it here in the same change. A mismatch that was not deliberate is
  a broken client-server contract.

  Payload cases build real schema structs, so they also pin each relation's
  signable field SET: a column added to a schema changes the payload (its
  default leaks in), a column removed makes `struct!/2` raise.
  """
  use ExUnit.Case, async: true

  alias Chat.Data.Integrity
  alias Chat.Data.Schemas

  @vectors "docs/pq/conformance/vectors.json"
           |> File.read!()
           |> Jason.decode!()

  @schema_by_relation %{
    "user_cards" => Schemas.UserCard,
    "user_storage" => Schemas.UserStorage,
    "dialog_messages" => Schemas.DialogMessage,
    "dialog_keys" => Schemas.DialogKey,
    "dialog_message_reactions" => Schemas.DialogMessageReaction,
    "dialog_message_receipts" => Schemas.DialogMessageReceipt,
    "files" => Schemas.File
  }

  defp decode_field(%{"t" => "b64", "v" => b64}), do: Base.decode64!(b64)
  defp decode_field(%{"t" => "b64[]", "v" => list}), do: Enum.map(list, &Base.decode64!/1)
  defp decode_field(%{"t" => "str", "v" => v}), do: v
  defp decode_field(%{"t" => "int", "v" => v}), do: v
  defp decode_field(%{"t" => "bool", "v" => v}), do: v
  defp decode_field(%{"t" => "null"}), do: nil

  defp build_struct(relation, fields) do
    module = Map.fetch!(@schema_by_relation, relation)

    attrs =
      Map.new(fields, fn {name, spec} ->
        {String.to_existing_atom(name), decode_field(spec)}
      end)

    struct!(module, attrs)
  end

  for %{"name" => name} <- @vectors["payload_cases"] do
    @case_name name
    test "payload: #{name}" do
      case_data =
        Enum.find(@vectors["payload_cases"], &(&1["name"] == @case_name))

      row = build_struct(case_data["relation"], case_data["fields"])

      assert Integrity.signature_payload(row) == case_data["expected_payload"]
    end
  end

  for %{"name" => name} <- @vectors["hash_cases"] do
    @case_name name
    test "hash: #{name}" do
      case_data = Enum.find(@vectors["hash_cases"], &(&1["name"] == @case_name))
      input = case_data["input"]

      actual =
        case case_data["kind"] do
          "sign_hash" ->
            input["prefix"] <>
              Base.encode16(EnigmaPq.hash(Base.decode64!(input["sign_b64"])), case: :lower)

          "dialog_hash" ->
            [a, b] = Enum.sort([input["user_a"], input["user_b"]])
            "di_" <> Base.encode16(EnigmaPq.hash(a <> b), case: :lower)

          "receipt_hash" ->
            data =
              input["message_id"] <>
                input["message_sign_hash"] <> input["peer_hash"] <> input["type"]

            "dmrc_" <> Base.encode16(EnigmaPq.hash(data), case: :lower)

          "reaction_hash" ->
            key = Base.decode64!(input["key_b64"])
            data = input["message_id"] <> input["reactor_hash"] <> input["type_plaintext"]
            "dmr_" <> Base.encode16(EnigmaPq.hmac_sha3_512(key, data), case: :lower)

          "hkdf" ->
            ikm = Base.decode64!(input["ikm_b64"])

            ikm
            |> EnigmaPq.hkdf_derive(input["salt"], input["info"], input["length"])
            |> Base.encode64()

          "hmac_sha3_512" ->
            key = Base.decode64!(input["key_b64"])

            key
            |> EnigmaPq.hmac_sha3_512(input["data"])
            |> Base.encode16(case: :lower)
        end

      assert actual == case_data["expected"]
    end
  end
end
