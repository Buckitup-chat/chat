defmodule ChatWeb.ElectricLive.ModerationSandboxLive.Manage do
  @moduledoc false

  alias ChatWeb.ElectricLive.ModerationSandboxLive.ReviewBot
  alias ChatWeb.ElectricLive.ModerationSandboxLive.ReviewBotClient
  alias ChatWeb.ElectricLive.ModerationSandboxLive.Settings
  alias ChatWeb.ElectricLive.ModerationSandboxLive.WriteToken

  @events ~w(refresh_settings setting_form_change set_setting tombstone_setting create_review_bot start_review_bot stop_review_bot revoke_review_bot refresh_bots create_write_token refresh_tokens)

  def events, do: @events

  def handle_event(event, params, socket, base_url)
      when event in ~w(refresh_settings setting_form_change set_setting tombstone_setting) do
    auth = origin_auth(socket.assigns.identity)
    Settings.handle_event(event, params, socket, base_url, auth)
  end

  def handle_event("create_review_bot", _params, socket, base_url) do
    identity = socket.assigns.identity
    origin = socket.assigns.origin
    origin_card = socket.assigns.origin_card

    origin_identity = %{
      origin_hash: identity.origin_hash,
      name: origin.name,
      sign_skey: identity.sign_skey,
      sign_pkey: origin_card.sign_pkey,
      crypt_skey: identity.crypt_skey,
      crypt_pkey: origin_card.crypt_pkey
    }

    auth = origin_auth(identity)

    case ReviewBotClient.create_bot(origin_identity, base_url) do
      {:ok, %{log_entries: logs}} ->
        bots = ReviewBotClient.list_origin_bots(identity.origin_hash, base_url, auth)

        {:noreply,
         socket
         |> Phoenix.Component.assign(origin_bots: bots)
         |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> Phoenix.Component.assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("start_review_bot", %{"hash" => bot_hash}, socket, _base_url) do
    identity = socket.assigns.identity

    case Enum.find(socket.assigns.origin_bots, &(&1.bot_hash == bot_hash)) do
      nil ->
        {:noreply, Phoenix.Component.assign(socket, error_message: "Bot not found")}

      bot ->
        case ReviewBot.decrypt_and_start(bot, identity[:crypt_skey]) do
          {:ok, _pid} ->
            {:noreply, Phoenix.Component.assign(socket, origin_bots: socket.assigns.origin_bots)}

          {:error, reason} ->
            {:noreply,
             Phoenix.Component.assign(socket,
               error_message: "Start failed: #{inspect(reason)}"
             )}
        end
    end
  end

  def handle_event("stop_review_bot", %{"hash" => bot_hash}, socket, _base_url) do
    case ReviewBot.stop(bot_hash) do
      :ok ->
        {:noreply, Phoenix.Component.assign(socket, origin_bots: socket.assigns.origin_bots)}

      {:error, _} ->
        {:noreply, Phoenix.Component.assign(socket, error_message: "Bot not running")}
    end
  end

  def handle_event("revoke_review_bot", %{"hash" => bot_hash}, socket, base_url) do
    identity = socket.assigns.identity
    auth = origin_auth(identity)

    ReviewBot.stop(bot_hash)

    case Enum.find(socket.assigns.origin_bots, &(&1.bot_hash == bot_hash)) do
      nil ->
        {:noreply, Phoenix.Component.assign(socket, error_message: "Bot not found")}

      bot ->
        case ReviewBotClient.tombstone_bot(bot, identity.sign_skey, base_url) do
          {:ok, %{log_entries: logs}} ->
            bots = ReviewBotClient.list_origin_bots(identity.origin_hash, base_url, auth)

            {:noreply, socket |> Phoenix.Component.assign(origin_bots: bots) |> append_logs(logs)}

          {:error, %{reason: reason, log_entries: logs}} ->
            {:noreply,
             socket |> Phoenix.Component.assign(error_message: reason) |> append_logs(logs)}
        end
    end
  end

  def handle_event("refresh_bots", _params, socket, base_url) do
    identity = socket.assigns.identity
    auth = origin_auth(identity)

    bots = ReviewBotClient.list_origin_bots(identity.origin_hash, base_url, auth)

    {:noreply, Phoenix.Component.assign(socket, origin_bots: bots)}
  end

  def handle_event("create_write_token", params, socket, base_url) do
    WriteToken.handle_create(params, base_url, socket)
  end

  def handle_event("refresh_tokens", _params, socket, base_url) do
    auth = origin_auth(socket.assigns.identity)
    WriteToken.handle_refresh(base_url, auth, socket)
  end

  def load_all(identity, base_url) do
    auth = origin_auth(identity)

    %{
      origin_settings: Settings.load_settings(identity.origin_hash, base_url, auth),
      origin_bots: ReviewBotClient.list_origin_bots(identity.origin_hash, base_url, auth),
      write_tokens: WriteToken.list_tokens(identity.origin_hash, base_url, auth)
    }
  end

  def origin_auth(identity) do
    %{user_hash: identity.origin_hash, sign_skey: identity.sign_skey}
  end

  defp append_logs(socket, logs),
    do: Phoenix.Component.update(socket, :request_log, &(logs ++ &1))
end
