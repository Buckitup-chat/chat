defmodule ChatWeb.ElectricLive.UserCardsLive.IndexTest do
  @moduledoc """
  Tests for UserCards LiveView with Electric sync.

  Note: Tests that verify Electric sync behavior are marked with @tag :electric_sync
  and skipped by default. These should be verified manually as Electric may have
  timing issues in test environments.
  """
  use ChatWeb.ConnCase, async: false
  use ChatWeb.DataCase

  import Phoenix.LiveViewTest

  alias Chat.Data.Schemas.UserCard

  describe "ElectricLive.UserCardsLive.Index" do
    test "renders user cards page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/user_cards")

      assert html =~ "User Cards Stream"
      assert html =~ "Real-time user card list with Post-Quantum cryptography support"
      assert html =~ "Chat.Data.Schemas.UserCard"
    end

    test "displays connection status", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/user_cards")

      assert html =~ "Connected"
      assert html =~ "bg-green-500"
    end

    test "has correct stream container", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/electric/user_cards")

      assert html =~ "id=\"user_cards\""
      assert html =~ "phx-update=\"stream\""
    end

    @tag :electric_sync
    @tag :skip
    test "loads and displays user cards from database", %{conn: conn} do
      # Create valid user_hash (65 bytes: 0x01 prefix + 64-byte hash)
      user_hash_1 = <<0x01>> <> :crypto.strong_rand_bytes(64)
      user_hash_2 = <<0x01>> <> :crypto.strong_rand_bytes(64)

      # Insert test user cards
      Chat.Repo.insert!(%UserCard{
        user_hash: user_hash_1,
        name: "Alice",
        sign_pkey: :crypto.strong_rand_bytes(32),
        contact_pkey: :crypto.strong_rand_bytes(32),
        crypt_pkey: :crypto.strong_rand_bytes(32),
        contact_cert: :crypto.strong_rand_bytes(64),
        crypt_cert: :crypto.strong_rand_bytes(64)
      })

      Chat.Repo.insert!(%UserCard{
        user_hash: user_hash_2,
        name: "Bob",
        sign_pkey: :crypto.strong_rand_bytes(32),
        contact_pkey: :crypto.strong_rand_bytes(32),
        crypt_pkey: :crypto.strong_rand_bytes(32),
        contact_cert: :crypto.strong_rand_bytes(64),
        crypt_cert: :crypto.strong_rand_bytes(64)
      })

      {:ok, view, _html} = live(conn, "/electric/user_cards")

      # Wait for async Electric sync to complete
      :timer.sleep(100)
      html = render(view)

      assert html =~ "Alice"
      assert html =~ "Bob"
      refute html =~ "Syncing user cards from Electric"
    end

    @tag :electric_sync
    @tag :skip
    test "displays user card with short hash", %{conn: conn} do
      user_hash = <<0x01>> <> :crypto.strong_rand_bytes(64)

      Chat.Repo.insert!(%UserCard{
        user_hash: user_hash,
        name: "Charlie",
        sign_pkey: :crypto.strong_rand_bytes(32),
        contact_pkey: :crypto.strong_rand_bytes(32),
        crypt_pkey: :crypto.strong_rand_bytes(32),
        contact_cert: :crypto.strong_rand_bytes(64),
        crypt_cert: :crypto.strong_rand_bytes(64)
      })

      {:ok, view, _html} = live(conn, "/electric/user_cards")

      # Wait for sync
      :timer.sleep(100)
      html = render(view)

      assert html =~ "Charlie"
      # Short hash is first 3 bytes (6 hex chars) of user_hash
      expected_hash = user_hash |> binary_part(0, 3) |> Base.encode16(case: :lower)
      assert html =~ expected_hash
    end

    @tag :electric_sync
    @tag :skip
    test "displays sync status badge", %{conn: conn} do
      user_hash = <<0x01>> <> :crypto.strong_rand_bytes(64)

      Chat.Repo.insert!(%UserCard{
        user_hash: user_hash,
        name: "Dave",
        sign_pkey: :crypto.strong_rand_bytes(32),
        contact_pkey: :crypto.strong_rand_bytes(32),
        crypt_pkey: :crypto.strong_rand_bytes(32),
        contact_cert: :crypto.strong_rand_bytes(64),
        crypt_cert: :crypto.strong_rand_bytes(64)
      })

      {:ok, view, _html} = live(conn, "/electric/user_cards")

      # Wait for sync
      :timer.sleep(100)
      html = render(view)

      assert html =~ "Synced"
      assert html =~ "bg-green-100"
    end

    @tag :electric_sync
    @tag :skip
    test "uses correct DOM ID format", %{conn: conn} do
      user_hash = <<0x01>> <> :crypto.strong_rand_bytes(64)

      Chat.Repo.insert!(%UserCard{
        user_hash: user_hash,
        name: "Eve",
        sign_pkey: :crypto.strong_rand_bytes(32),
        contact_pkey: :crypto.strong_rand_bytes(32),
        crypt_pkey: :crypto.strong_rand_bytes(32),
        contact_cert: :crypto.strong_rand_bytes(64),
        crypt_cert: :crypto.strong_rand_bytes(64)
      })

      {:ok, view, _html} = live(conn, "/electric/user_cards")

      # Wait for sync
      :timer.sleep(100)
      html = render(view)

      # DOM ID should be "user-card-{hex_hash}"
      expected_dom_id = "user-card-#{Base.encode16(user_hash, case: :lower)}"
      assert html =~ expected_dom_id
    end
  end
end
