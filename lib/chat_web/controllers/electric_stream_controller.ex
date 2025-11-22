defmodule ChatWeb.ElectricStreamController do
  @moduledoc """
  Controller for Electric SQL SSE streaming.
  Wraps Phoenix.Sync data in Server-Sent Events format for EventSource clients.
  """
  use ChatWeb, :controller

  alias Chat.Data.Schemas.User
  alias Chat.Repo

  @topic "users:updates"

  def stream(conn, _params) do
    # Subscribe to user updates via PubSub
    Phoenix.PubSub.subscribe(Chat.PubSub, @topic)

    conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> send_chunked(200)
    |> stream_users()
  end

  defp stream_users(conn) do
    # Send initial snapshot
    users = Repo.all(User)

    user_data =
      Enum.map(users, fn user ->
        %{
          "name" => user.name,
          "pub_key" => Base.encode16(user.pub_key, case: :lower),
          "hash" => Enigma.Hash.short_hash(user.pub_key)
        }
      end)

    # Send each user as SSE event
    conn =
      Enum.reduce(user_data, conn, fn user, acc_conn ->
        case send_sse_event(acc_conn, user) do
          {:ok, new_conn} -> new_conn
          {:error, _} -> acc_conn
        end
      end)

    # Send up-to-date marker
    conn =
      case send_sse_event(conn, %{"headers" => %{"control" => "up-to-date"}}) do
        {:ok, new_conn} -> new_conn
        {:error, _} -> conn
      end

    # Keep connection alive by sending periodic heartbeats
    keep_alive(conn)
  end

  defp keep_alive(conn) do
    receive do
      # Handle new user broadcast
      {:user_created, user} ->
        user_data = %{
          "name" => user.name,
          "pub_key" => Base.encode16(user.pub_key, case: :lower),
          "hash" => Enigma.Hash.short_hash(user.pub_key)
        }

        case send_sse_event(conn, user_data) do
          {:ok, conn} -> keep_alive(conn)
          {:error, _} -> conn
        end

      # Handle user updates (if needed in future)
      {:user_updated, user} ->
        user_data = %{
          "name" => user.name,
          "pub_key" => Base.encode16(user.pub_key, case: :lower),
          "hash" => Enigma.Hash.short_hash(user.pub_key)
        }

        case send_sse_event(conn, user_data) do
          {:ok, conn} -> keep_alive(conn)
          {:error, _} -> conn
        end
    after
      # Send heartbeat every 15 seconds if no messages
      15_000 ->
        case chunk(conn, ": heartbeat\n\n") do
          {:ok, conn} -> keep_alive(conn)
          {:error, _} -> conn
        end
    end
  end

  defp send_sse_event(conn, data) do
    case Jason.encode(data) do
      {:ok, json} ->
        chunk(conn, "data: #{json}\n\n")

      {:error, _} = error ->
        error
    end
  end
end
