defmodule ChatWeb.ElectricLive.DialogSandboxLive.ContentTest do
  use ExUnit.Case, async: true

  alias ChatWeb.ElectricLive.DialogSandboxLive.Content

  @envelopes %{
    "inline_file" => ["a.txt", 5, "text/plain", 1_700_000_000, "aGVsbG8"],
    "inline_image" => [4, 3, "dGh1bWI", "a.png", 5, "image/png", 1_700_000_000, "aGVsbG8"],
    "file" => ["a.pdf", 5, "application/pdf", 1_700_000_000, "file_1", "c2VjcmV0"],
    "image" => [4, 3, "dGh1bWI", "a.png", 5, "image/png", 1_700_000_000, "file_1", "c2VjcmV0"],
    "video" => [
      16,
      9,
      "dGh1bWI",
      "a.mp4",
      5,
      "video/mp4",
      1_700_000_000,
      42,
      "file_1",
      "c2VjcmV0"
    ],
    "review_list_key" => ["a2V5"]
  }

  describe "round-trip / known types" do
    for {type, fields} <- @envelopes do
      test "#{type} parses to its own type and re-encodes unchanged" do
        json = envelope(unquote(type), unquote(Macro.escape(fields)))
        parsed = Content.parse(json)

        assert elem(parsed, 0) == String.to_existing_atom(unquote(type))
        assert_round_trip(json)
      end

      test "#{type} with appended fields keeps its type and the extra fields" do
        json = envelope(unquote(type), unquote(Macro.escape(fields)) ++ ["future", 7])
        parsed = Content.parse(json)

        assert elem(parsed, 0) == String.to_existing_atom(unquote(type))
        assert_round_trip(json)
      end
    end
  end

  describe "round-trip / other shapes" do
    test "text" do
      assert Content.parse(~s("hello")) == {:text, "hello"}
      assert_round_trip(~s("hello"))
    end

    test "unknown type is kept verbatim" do
      json = envelope("quote", ["author", "dmsg_1", "dms_1", "quoted"])

      assert {:unknown, _} = Content.parse(json)
      assert_round_trip(json)
    end

    test "known type with too few fields falls back to unknown" do
      json = envelope("file", ["a.pdf", 5, "application/pdf"])

      assert {:unknown, _} = Content.parse(json)
      assert_round_trip(json)
    end

    test "composed content of text and a typed part" do
      json = Jason.encode!(["caption", %{"image" => @envelopes["image"] ++ ["future"]}])

      assert {:composed, [{:text, "caption"}, {:image, _}]} = Content.parse(json)
      assert_round_trip(json)
    end
  end

  # Helpers

  defp envelope(type, fields), do: Jason.encode!(%{type => fields})

  defp assert_round_trip(json) do
    assert json |> Content.parse() |> Content.to_json() |> Jason.decode!() == Jason.decode!(json)
  end
end
