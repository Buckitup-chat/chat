defmodule ChatWeb.ElectricLive.VouchSandboxLive.Index do
  @moduledoc "Interactive sandbox for vouch token operations via Electric API."

  use ChatWeb, :live_view

  alias Chat.Data.VouchToken

  alias ChatWeb.ElectricLive.DialogSandboxLive.Crypto
  alias ChatWeb.ElectricLive.VouchSandboxLive.ApiClient
  alias ChatWeb.ElectricLive.VouchSandboxLive.Render

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(
      identity: nil,
      tab: :by_me,
      users: [],
      vouches_by_me: [],
      vouches_for_me: [],
      request_log: [],
      error_message: nil,
      operation_in_progress: false,
      form_subject: "",
      scope_segments: [],
      scope_extra: ""
    )
    |> assign_scope_steps()
    |> allow_upload(:key_file, accept: ~w(.json), max_entries: 1, max_file_size: 100_000)
    |> ok()
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

        socket
        |> assign(identity: user_data, error_message: nil, users: ApiClient.list_users(base_url))
        |> load_vouches(base_url)
        |> noreply()

      {:error, reason} ->
        socket
        |> assign(error_message: "Import failed: #{reason}")
        |> noreply()
    end
  end

  def handle_event("form_change", params, socket) do
    target = params |> Map.get("_target", []) |> List.first()

    case target do
      "subject_hash" ->
        socket |> assign(form_subject: params["subject_hash"] || "") |> noreply()

      "scope_extra" ->
        extra = params["scope_extra"] || ""
        preview = assemble_kind(socket.assigns.scope_segments, extra)
        socket |> assign(scope_extra: extra, scope_preview: preview) |> noreply()

      "scope_" <> level_str ->
        level = String.to_integer(level_str)
        value = params["scope_#{level}"] || ""

        segs =
          Enum.take(socket.assigns.scope_segments, level) ++
            if(value == "", do: [], else: [value])

        socket
        |> assign(scope_segments: segs, scope_extra: "")
        |> assign_scope_steps()
        |> noreply()

      _ ->
        noreply(socket)
    end
  end

  def handle_event("create_vouch", params, socket) do
    base_url = public_url(socket)
    identity = socket.assigns.identity
    kind = build_kind_from_params(params)
    revoked? = params["revoked"] == "true"

    socket = assign(socket, operation_in_progress: true)

    case ApiClient.create_vouch(
           identity,
           String.trim(params["subject_hash"] || ""),
           kind,
           base_url,
           revoked: revoked?
         ) do
      {:ok, %{log_entries: logs}} ->
        socket
        |> assign(
          operation_in_progress: false,
          form_subject: "",
          scope_segments: [],
          scope_extra: ""
        )
        |> assign_scope_steps()
        |> append_logs(logs)
        |> load_vouches(base_url)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(error_message: reason, operation_in_progress: false)
        |> append_logs(logs)
        |> noreply()
    end
  end

  def handle_event(
        "revoke_vouch",
        %{"kind" => kind, "subject" => subject, "timestamp" => ts},
        socket
      ) do
    base_url = public_url(socket)
    identity = socket.assigns.identity

    vouch = %{
      kind: kind,
      subject_hash: subject,
      owner_timestamp: String.to_integer(ts)
    }

    socket = assign(socket, operation_in_progress: true)

    case ApiClient.revoke_vouch(identity, vouch, base_url) do
      {:ok, %{owner_timestamp: new_timestamp, log_entries: logs}} ->
        socket
        |> assign(operation_in_progress: false)
        |> mark_vouch_revoked(kind, subject, new_timestamp)
        |> append_logs(logs)
        |> noreply()

      {:error, %{reason: reason, log_entries: logs}} ->
        socket
        |> assign(error_message: reason, operation_in_progress: false)
        |> append_logs(logs)
        |> noreply()
    end
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    socket |> assign(tab: String.to_existing_atom(tab)) |> noreply()
  end

  def handle_event("refresh_vouches", _params, socket) do
    base_url = public_url(socket)
    socket |> load_vouches(base_url) |> noreply()
  end

  def handle_event("clear_error", _params, socket) do
    socket |> assign(:error_message, nil) |> noreply()
  end

  @impl true
  def render(assigns), do: Render.render_page(assigns)

  defp assign_scope_steps(socket) do
    {steps, at_leaf} = walk_forest(VouchToken.resource_forest(), socket.assigns.scope_segments)
    preview = assemble_kind(socket.assigns.scope_segments, socket.assigns.scope_extra)
    assign(socket, scope_steps: steps, scope_at_leaf: at_leaf, scope_preview: preview)
  end

  defp walk_forest(tree, segments), do: do_walk(tree, segments, 0, [])

  defp do_walk(tree, _segments, _level, acc) when is_map(tree) and map_size(tree) == 0 do
    {Enum.reverse(acc), true}
  end

  defp do_walk(tree, segments, level, acc) when is_map(tree) do
    case Enum.find(Map.keys(tree), &is_atom/1) do
      nil ->
        options = tree |> Map.keys() |> Enum.sort()
        value = Enum.at(segments, level, "")
        step = %{level: level, type: :select, options: options, value: value}

        if value != "" and Map.has_key?(tree, value) do
          do_walk(Map.fetch!(tree, value), segments, level + 1, [step | acc])
        else
          {Enum.reverse([step | acc]), false}
        end

      atom_key ->
        value = Enum.at(segments, level, "")
        placeholder = atom_key |> Atom.to_string() |> String.replace("_", " ")
        step = %{level: level, type: :text, placeholder: placeholder, value: value}

        if value != "" do
          do_walk(Map.fetch!(tree, atom_key), segments, level + 1, [step | acc])
        else
          {Enum.reverse([step | acc]), false}
        end
    end
  end

  defp do_walk(leaf, _segments, _level, acc) when is_atom(leaf) do
    {Enum.reverse(acc), true}
  end

  defp assemble_kind(segments, extra) do
    extra = String.trim(extra || "")
    parts = if extra != "", do: segments ++ [extra], else: segments
    Enum.join(parts, ".")
  end

  defp build_kind_from_params(params) do
    segments =
      Stream.iterate(0, &(&1 + 1))
      |> Stream.map(&params["scope_#{&1}"])
      |> Stream.take_while(&(is_binary(&1) and &1 != ""))
      |> Enum.to_list()

    assemble_kind(segments, params["scope_extra"])
  end

  defp mark_vouch_revoked(socket, kind, subject_hash, new_timestamp) do
    update(socket, :vouches_by_me, fn vouches ->
      Enum.map(vouches, fn v ->
        if v.kind == kind and v.subject_hash == subject_hash do
          %{v | deleted_flag: true, owner_timestamp: new_timestamp}
        else
          v
        end
      end)
    end)
  end

  defp load_vouches(socket, base_url) do
    hash = socket.assigns.identity.user_hash

    assign(socket,
      vouches_by_me: ApiClient.list_vouches_by_me(hash, base_url),
      vouches_for_me: ApiClient.list_vouches_for_me(hash, base_url)
    )
  end

  defp append_logs(socket, logs), do: update(socket, :request_log, &(logs ++ &1))
end
