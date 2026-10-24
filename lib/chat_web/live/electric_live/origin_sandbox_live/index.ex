defmodule ChatWeb.ElectricLive.OriginSandboxLive.Index do
  @moduledoc "Interactive sandbox for testing origin owner operations via Electric API."

  use ChatWeb, :live_view

  alias Chat.Proto.Shortcode
  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.IdentityCheck
  alias ChatWeb.ElectricLive.OriginSandboxLive.ApiClient
  alias ChatWeb.ElectricLive.OriginSandboxLive.Render
  alias ChatWeb.ElectricLive.OriginSandboxLive.ReviewBot
  alias ChatWeb.ElectricLive.OriginSandboxLive.ReviewBotClient
  alias ChatWeb.ElectricLive.OriginSandboxLive.WriteToken

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        owner: nil,
        origin: nil,
        origins: [],
        origin_bots: [],
        write_tokens: [],
        last_token_result: nil,
        request_log: [],
        error_message: nil,
        pending_reviews: nil
      )
      |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_key_file", _params, socket), do: {:noreply, socket}

  def handle_event("import_keys", _params, socket) do
    [result] =
      consume_uploaded_entries(socket, :key_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case Crypto.parse_and_validate_identity(result) do
      {:ok, user_data} ->
        base_url = public_url(socket)
        owner = IdentityCheck.mark_on_server(user_data, base_url)
        auth = %{user_hash: owner.user_hash, sign_skey: owner.sign_skey}
        origins = ApiClient.list_owner_origins(owner.user_hash, base_url, auth)
        {:noreply, assign(socket, owner: owner, origins: origins, error_message: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error_message: "Import failed: #{reason}")}
    end
  end

  def handle_event("create_origin", %{"name" => name, "moderation" => mode}, socket) do
    base_url = public_url(socket)
    owner = socket.assigns.owner

    case ApiClient.create_origin(owner, name, mode, base_url) do
      {:ok, %{origin: origin, log_entries: logs}} ->
        auth = %{user_hash: owner.user_hash, sign_skey: owner.sign_skey}
        origins = ApiClient.list_owner_origins(owner.user_hash, base_url, auth)
        pending = ApiClient.has_pending_reviews?(origin.origin_hash, base_url, auth)
        bots = ReviewBotClient.list_origin_bots(origin.origin_hash, base_url, auth)

        {:noreply,
         socket
         |> assign(
           origin: origin,
           origins: origins,
           pending_reviews: pending,
           origin_bots: bots,
           write_tokens: [],
           last_token_result: nil
         )
         |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("select_origin", %{"hash" => hash}, socket) do
    base_url = public_url(socket)

    case Enum.find(socket.assigns.origins, &(&1.origin_hash == hash)) do
      nil ->
        {:noreply, socket}

      found ->
        auth = auth(socket)

        {:noreply,
         assign(socket,
           origin: found,
           pending_reviews: ApiClient.has_pending_reviews?(hash, base_url, auth),
           origin_bots: ReviewBotClient.list_origin_bots(hash, base_url, auth),
           write_tokens: fetch_tokens(hash, base_url, auth),
           last_token_result: nil
         )}
    end
  end

  def handle_event("refresh_origins", _params, socket) do
    base_url = public_url(socket)
    auth = auth(socket)
    origins = ApiClient.list_owner_origins(socket.assigns.owner.user_hash, base_url, auth)
    origin = refresh_selected_origin(socket.assigns.origin, origins)
    {:noreply, assign(socket, origins: origins, origin: origin)}
  end

  def handle_event("refresh_pending_reviews", _params, socket) do
    base_url = public_url(socket)
    %{origin: origin} = socket.assigns
    auth = auth(socket)
    pending = ApiClient.has_pending_reviews?(origin.origin_hash, base_url, auth)
    {:noreply, assign(socket, pending_reviews: pending)}
  end

  def handle_event("update_origin", %{"name" => name, "moderation" => mode}, socket) do
    base_url = public_url(socket)
    %{origin: origin, owner: owner} = socket.assigns

    case ApiClient.update_origin(origin, owner, name, mode, base_url) do
      {:ok, %{origin: updated, log_entries: logs}} ->
        origins = update_in_list(socket.assigns.origins, updated)
        {:noreply, socket |> assign(origin: updated, origins: origins) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("delete_origin", _params, socket) do
    base_url = public_url(socket)
    %{origin: origin, owner: owner} = socket.assigns

    case ApiClient.delete_origin(origin, owner, base_url) do
      {:ok, %{origin: updated, log_entries: logs}} ->
        origins = update_in_list(socket.assigns.origins, updated)
        {:noreply, socket |> assign(origin: updated, origins: origins) |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("export_origin_identity", _params, socket) do
    origin = socket.assigns.origin
    filename = "origin_identity_#{Shortcode.short_code(origin.origin_hash)}.json"

    data =
      Jason.encode!(
        %{
          type: "buckitup_origin_identity",
          version: 1,
          origin_hash: origin.origin_hash,
          name: origin.name,
          sign_skey: Base.encode64(origin.origin_sign_skey, padding: false),
          crypt_skey: Base.encode64(origin[:origin_crypt_skey] || "", padding: false)
        },
        pretty: true
      )

    {:noreply, push_event(socket, "download_file", %{data: data, filename: filename})}
  end

  def handle_event("create_review_bot", _params, socket) do
    base_url = public_url(socket)
    origin = socket.assigns.origin
    origin_card = Chat.Data.User.get_card(origin.origin_hash)

    origin_identity = %{
      origin_hash: origin.origin_hash,
      name: origin.name,
      sign_skey: origin.origin_sign_skey,
      sign_pkey: origin_card.sign_pkey,
      crypt_skey: origin[:origin_crypt_skey],
      crypt_pkey: origin_card.crypt_pkey
    }

    case ReviewBotClient.create_bot(origin_identity, base_url) do
      {:ok, %{log_entries: logs}} ->
        bots = ReviewBotClient.list_origin_bots(origin.origin_hash, base_url, auth(socket))

        {:noreply,
         socket
         |> assign(origin_bots: bots)
         |> append_logs(logs)}

      {:error, %{reason: reason, log_entries: logs}} ->
        {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
    end
  end

  def handle_event("start_review_bot", %{"hash" => bot_hash}, socket) do
    origin = socket.assigns.origin

    case Enum.find(socket.assigns.origin_bots, &(&1.bot_hash == bot_hash)) do
      nil ->
        {:noreply, assign(socket, error_message: "Bot not found")}

      bot ->
        case ReviewBot.decrypt_and_start(bot, origin[:origin_crypt_skey]) do
          {:ok, _pid} ->
            {:noreply, assign(socket, origin_bots: socket.assigns.origin_bots)}

          {:error, reason} ->
            {:noreply, assign(socket, error_message: "Start failed: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("stop_review_bot", %{"hash" => bot_hash}, socket) do
    case ReviewBot.stop(bot_hash) do
      :ok -> {:noreply, assign(socket, origin_bots: socket.assigns.origin_bots)}
      {:error, _} -> {:noreply, assign(socket, error_message: "Bot not running")}
    end
  end

  def handle_event("revoke_review_bot", %{"hash" => bot_hash}, socket) do
    base_url = public_url(socket)
    origin = socket.assigns.origin

    ReviewBot.stop(bot_hash)

    case Enum.find(socket.assigns.origin_bots, &(&1.bot_hash == bot_hash)) do
      nil ->
        {:noreply, assign(socket, error_message: "Bot not found")}

      bot ->
        case ReviewBotClient.tombstone_bot(bot, origin.origin_sign_skey, base_url) do
          {:ok, %{log_entries: logs}} ->
            bots = ReviewBotClient.list_origin_bots(origin.origin_hash, base_url, auth(socket))
            {:noreply, socket |> assign(origin_bots: bots) |> append_logs(logs)}

          {:error, %{reason: reason, log_entries: logs}} ->
            {:noreply, socket |> assign(error_message: reason) |> append_logs(logs)}
        end
    end
  end

  def handle_event("refresh_bots", _params, socket) do
    base_url = public_url(socket)
    origin = socket.assigns.origin
    bots = ReviewBotClient.list_origin_bots(origin.origin_hash, base_url, auth(socket))
    {:noreply, assign(socket, origin_bots: bots)}
  end

  def handle_event("create_write_token", params, socket) do
    WriteToken.handle_create(params, public_url(socket), socket)
  end

  def handle_event("refresh_tokens", _params, socket) do
    WriteToken.handle_refresh(public_url(socket), auth(socket), socket)
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
  end

  defp refresh_selected_origin(nil, _origins), do: nil

  defp refresh_selected_origin(current, origins) do
    case Enum.find(origins, &(&1.origin_hash == current.origin_hash)) do
      nil -> nil
      found -> Map.merge(found, Map.take(current, [:origin_sign_skey, :origin_crypt_skey]))
    end
  end

  defp update_in_list(origins, updated) do
    Enum.map(origins, fn o ->
      if o.origin_hash == updated.origin_hash, do: updated, else: o
    end)
  end

  defp auth(socket) do
    owner = socket.assigns.owner
    %{user_hash: owner.user_hash, sign_skey: owner.sign_skey}
  end

  defp fetch_tokens(origin_hash, base_url, auth) do
    WriteToken.list_tokens(origin_hash, base_url, auth)
  end

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))

  @impl true
  def render(assigns), do: Render.render_page(assigns)
end
