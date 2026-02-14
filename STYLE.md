# Code Style Guide

This document captures coding patterns and conventions used in this project, derived from the codebase history. Use these guidelines when refactoring or writing new code.

## Elixir Code Style

### Pipeline Preference

**Prefer pipelines over nested function calls.** Transform data through clear, readable chains:

```elixir
# Preferred
message
|> Chat.SignedParcel.wrap_dialog_message(dialog, me)
|> Chat.store_parcel()
|> Chat.run_when_parcel_stored(fn parcel ->
  parcel
  |> Chat.Dialogs.parsel_to_indexed_message()
  |> broadcast_new_message(dialog, me, time)
end)

# Avoid
broadcast_new_message(
  Chat.Dialogs.parsel_to_indexed_message(
    Chat.run_when_parcel_stored(
      Chat.store_parcel(
        Chat.SignedParcel.wrap_dialog_message(message, dialog, me)
      ),
      fn parcel -> ... end
    )
  ),
  dialog, me, time
)
```

### Use `then/2` for Single-Value Transformations

When you need to transform a value inline within a pipeline:

```elixir
data
|> Actor.from_json()
|> then(&{&1.me, &1.rooms})
```

### Use `tap/2` for Side Effects

When you need to perform an action but return the original value:

```elixir
message
|> Chat.SignedParcel.wrap_room_message(room_identity, alice)
|> tap(fn parcel ->
  assert Chat.SignedParcel.sign_valid?(parcel, alice.public_key)
end)
|> Chat.store_parcel(await: true)
```

### Pattern Matching in Function Heads

**Prefer `case` over multiple function clauses when logic spans 30+ lines:**

```elixir
# Preferred for complex branching
def handle_message(msg) do
  case msg do
    %{type: :text, content: content} -> process_text(content)
    %{type: :file, path: path} -> process_file(path)
    _ -> {:error, :unknown_type}
  end
end

# Multiple clauses OK for short, distinct behaviors
defp format_value(nil), do: ""
defp format_value(value) when is_binary(value), do: value
defp format_value(value), do: inspect(value)
```

### Anonymous Functions in Pattern Matching

Use `&` capture syntax for simple transformations, full `fn` for complex ones:

```elixir
# Simple - use capture
rooms |> Enum.map(& &1.private_key)
Enum.map(list, &Identity.from_strings/1)

# Complex - use fn
Enum.filter(shares, fn
  {_key, [_, _ | _]} -> true
  {_key, _shares} -> false
end)
```

### Extract Small Helper Functions

Extract small private functions for clarity, especially for predicates:

```elixir
# Preferred
|> Enum.filter(&duplicated_share?/1)

defp duplicated_share?({_key, shares}), do: match?([_, _ | _], shares)

# Instead of inline
|> Enum.filter(fn
  {_key, _shares = [_, _ | _]} -> true
  {_key, _shares} -> false
end)
```

### Guard Clauses and `when`

Use guards for type checks and simple conditions:

```elixir
defp maybe_redirect_to_file(%{type: type, content: json}, socket)
     when type in [:audio, :file, :image, :video] do
  # ...
end

def key_value_data(args) do
  args
  |> case do
    binary when is_binary(binary) -> Proxy.Serialize.deserialize(binary)
    x -> x
  end
  |> Chat.db_get()
end
```

### Rescue Blocks for Graceful Fallback

Use rescue with fallback for operations that might fail:

```elixir
def accept_room_invite(%{assigns: %{me: me, dialog: dialog, rooms: rooms}} = socket, message_id) do
  # ... main logic ...
  socket
  |> assign(:rooms, [new_room_identity | rooms])
  |> Page.Login.store()
rescue
  _ -> socket
end
```

### Struct Updates

Use `Map.put/3` or struct update syntax appropriately:

```elixir
# For adding/updating a field
full_room_identity =
  identity
  |> Map.put(:name, room_name)

# For multiple updates, use struct syntax
%{room | name: new_name, type: new_type}
```

### Conditional Assignment with `if/else` in Expressions

For short one-line blocks, prefer inline format:

```elixir
# Preferred for short expressions
delay =
  if total == 0,
    do: 100,
    else: trunc(100 - left * 100 / total)

result = if valid?, do: :ok, else: :error

# Use block format only for multi-line bodies
result =
  if complex_condition do
    value
    |> transform()
    |> validate()
  else
    default_value
  end
```

### Module Aliases

Group related aliases together, use multi-alias syntax when importing from same namespace:

```elixir
alias Chat.{ChunkedFiles, ChunkedFilesMultisecret, FileIndex, Identity, Log, Messages, Rooms}
alias Chat.Db.ChangeTracker
alias Chat.Sync.UsbDriveDumpFile
```

### LiveView/Phoenix Patterns

#### Socket Pipelines

Chain socket transformations:

```elixir
socket
|> assign(:messages, messages)
|> assign(:message_update_mode, :append)
|> assign(:page, 0)
|> push_event("chat:scroll-down", %{})
```

#### Component Attributes

Use `attr` declarations for component props:

```elixir
attr :class, :string, default: nil, doc: "classes to append"
attr :rest, :global, doc: "rest of the attrs"
slot :inner_block, required: true

defp upload_control(assigns) do
  ~H"""
  <.link class={"flex text-xs" <> if(@class, do: " #{@class}", else: "")} href="#" {@rest}>
    <%= render_slot(@inner_block) %>
  </.link>
  """
end
```

#### Event Handling Router Pattern

Organize event handlers in dedicated router modules:

```elixir
defmodule ChatWeb.MainLive.Page.DialogRouter do
  @moduledoc "Route dialog events"

  alias ChatWeb.MainLive.Page

  def event(socket, event) do
    case event do
      {"accept-room-invite", %{"id" => id, "time" => time}} ->
        socket |> Page.Dialog.accept_room_invite({time |> String.to_integer(), id})
    end
  end
end
```

### Testing Patterns

#### Use Rewire for Mocking

```elixir
import Rewire

defmodule DbMock do
  def data_dir(_), do: "priv/test_admin_db"
  def has_key?(_, _), do: true
end

rewire(Progress, [{CubDB, DbMock}, {Chat.FileFs, FileFsMock}])
```

#### Test Structure

Keep tests focused and use descriptive names:

```elixir
test "empty progress should be complete" do
  assert Progress.new([], :db?) |> Progress.complete?()
end

test "should return correct percentage" do
  assert 10 =
           Progress.new([{:any_data}, {:file_chunk, nil, nil, nil}], :db?)
           |> Progress.eliminate_written()
           |> Progress.done_percent()
end
```

### Naming Conventions

- **Modules**: PascalCase, descriptive (`Chat.Db.Scope.KeyScope`)
- **Functions**: snake_case, verb-first for actions (`add_new_message`, `read_message`)
- **Private functions**: Prefix with purpose when helpful (`defp hash_pubkeys`, `defp just_keys`)
- **Boolean functions**: End with `?` (`complete?`, `valid?`)
- **Variables**: snake_case, descriptive (`room_identity`, `pub_key_hex`)

### Documentation

- Use `@moduledoc` for module purpose
- Use `@doc` for public functions
- Keep docs concise and practical

```elixir
@moduledoc "Multisecret handler for chunks ciphering of large files (>~1GB)"

@doc """
Generates a confirmation token for API authentication.

Returns:
  %{
    token_key: "hex_encoded_token_key",
    token: "hex_encoded_token"
  }
"""
```

### Error Handling

Use `with` for multiple operations that can fail:

```elixir
with %{"pub_key" => pub_key_hex, "token_key" => token_key, "signature" => signature_hex} <- params,
     {:ok, pub_key} <- Base.decode16(pub_key_hex, case: :lower),
     {:ok, signature} <- Base.decode16(signature_hex, case: :lower),
     token <- Broker.get(token_key),
     false <- is_nil(token) && {:error, "Invalid or expired token key"},
     true <- Enigma.valid_sign?(signature, token, pub_key) || {:error, "Invalid signature"} do
  # success path
else
  {:error, reason} ->
    conn |> put_status(:unauthorized) |> json(%{error: reason})
end
```

#### Tag `with` preconditions with tuples

When a `with` step is validating shape/booleans (not returning `{:ok, ...}`), wrap the expression in a tagged tuple so the failing value keeps context:

```elixir
with {_, %{"mutations" => mutations}} <- {:correct_params, params},
     {_, true} <- {:is_mutation_list, is_list(mutations)},
     {:ok, mutations} <- normalize_mutations(mutations) do
  # success path
else
  error -> handle_error(conn, error)
end
```

### Inverted `with` for Special Cases

When a function has a common return value but a specific condition requires special handling (like adding an error), use `with` to isolate the special case in the `do` block and let the common case fall through to `else`.

```elixir
# Preferred
with true <- changeset.valid?,
     false <- is_special_condition?(changeset) do
  # Special case: modify return value
  add_error(changeset, :field, "error")
else
  # Common case: return original value
  _ -> changeset
end
```

### Code Organization

1. **Imports/aliases** at the top
2. **Module attributes** next
3. **Public functions** before private
4. **Helper functions** at the bottom
5. **Keep related functions together**

### Formatting

- Run `mix format` before committing
- Use `mix credo --strict` for style checks
- Maximum line length: follow formatter defaults

### Polymorphic Function Arguments

Accept multiple input types using pattern matching or conditionals:

```elixir
def clear_approved_request(room_identity_or_pub_key, person_identity) do
  case room_identity_or_pub_key do
    %Identity{} = identity -> identity |> Identity.pub_key()
    pub_key when is_binary(pub_key) -> pub_key
  end
  |> get()
  |> Room.clear_approved_request(person_identity)
  |> update()
end
```

### Inline `if` with `match?/2`

Use `match?/2` for concise conditional checks:

```elixir
ciphered <-
  if(match?(%Identity{}, room_identity_or_ciphered),
    do: cipher_identity_with_key(room_identity_or_ciphered, user_public_key),
    else: room_identity_or_ciphered
  )
```

### Metaprogramming for Repetitive API Handlers

Use `Enum.each` with `def unquote` for generating similar functions:

```elixir
%{
  select: &Api.select_data/1,
  key_value: &Api.key_value_data/1,
  confirmation_token: fn _ -> Api.confirmation_token() end,
  register_user: &Api.register_user/1,
  save_parcel: &Api.save_parcel/1
}
|> Enum.each(fn {name, action} ->
  def unquote(name)(conn, params) do
    run_and_respond(conn, params, unquote(action))
  end
end)
```

### Callback Functions as Parameters

Pass callback functions for flexible behavior:

```elixir
def add_request(room_key, user_identity, time, message_added_fn \\ fn _ -> :ok end) do
  room_key
  |> get()
  |> Room.add_request(user_identity)
  |> tap(fn room ->
    if room do
      time
      |> Messages.RoomRequest.new()
      |> add_new_message(user_identity, room.pub_key)
      |> tap(message_added_fn)
    end
  end)
  |> update()
end
```

### Defdelegate for Module Facades

Use `defdelegate` to expose functions from submodules:

```elixir
defdelegate add_image(dialog, src, data, now \\ DateTime.utc_now()), to: Dialog
defdelegate glimpse(dialog), to: Dialog
```

### Stream Processing for Large Data

Use `Stream` for lazy evaluation with large datasets:

```elixir
snap
|> db_keys_stream({:dialog_message, 0, 0, 0}, {:"dialog_message\0", 0, 0, 0})
|> Stream.filter(fn {:dialog_message, binhash} ->
  MapSet.member?(dialog_binhashes, binhash)
end)
|> union_set(dialog_keys)
```

### Deprecation Annotations

Mark deprecated functions clearly:

```elixir
@deprecated "should use Chat.store_parcel"
def on_saved({next, %{id: id}}, dialog, ok_fn) do
  dialog
  |> msg_key(next, id)
  |> ChangeTracker.promise(ok_fn)
end
```

### Verified Sigils for Paths

Use verified sigils `~p` for routes:

```elixir
# Preferred
push_event(socket, "chat:redirect", %{url: ~p"/get/zip/#{key}"})

# Instead of
push_event(socket, "chat:redirect", %{url: url(~p"/get/zip/#{key}")})
```

### Alphabetical Alias Ordering

Keep aliases in alphabetical order within groups:

```elixir
alias Chat.Dialogs
alias Chat.Dialogs.DialogMessaging
alias Chat.Rooms
alias Chat.Utils.StorageId
alias ChatWeb.Utils
alias Phoenix.LiveView.JS
alias Proxy
```

### LiveComponent Update Pattern

Handle different update scenarios in `update/2`:

```elixir
def update(new_assigns, socket) do
  new_assigns
  |> case do
    %{server: server, me: me, id: id} ->
      request_user_list(server, me, id)
      new_assigns

    %{users: users} when is_list(users) ->
      new_assigns
      |> Map.drop([:users])
      |> Map.put(:users, Map.new(users, fn card -> {hash_card(card), card} end))

    %{new_user: card} ->
      new_assigns
      |> Map.drop([:new_user])
      |> Map.put(:users, Map.put(socket.assigns.users, hash_card(card), card))

    x ->
      x
  end
  |> then(&assign(socket, &1))
  |> ok()
end
```

### Struct Field Defaults

Use sensible defaults in struct definitions:

```elixir
defstruct [:me, rooms: [], contacts: %{}, payload: %{}]

def new(%Identity{} = me, rooms, contacts \\ %{}, payload \\ %{}) do
  %__MODULE__{
    me: me,
    rooms: rooms,
    contacts: contacts,
    payload: payload
  }
end
```

### Case Expression for Type Dispatch

Use case for handling different input types:

```elixir
def serialize_key(key) do
  case key do
    <<_::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96>> = uuid -> uuid
    b when is_bitstring(b) -> b |> bits_encode()
    t when is_tuple(t) -> t |> serialize_key()
    l when is_list(l) -> l |> Jason.encode!() |> bits_encode()
  end
end
```

### Test Helper Pipelines

Chain test setup operations (keep under 10-15 lines, extract to named functions for longer chains):

```elixir
# Good - concise pipeline
%{}
|> set_participants(persons)
|> init_views(persons)
|> create_room_and_upload_image()
|> send_room_invitation()

# For longer setups, extract to named helper
defp setup_full_room_scenario(persons) do
  %{}
  |> set_participants(persons)
  |> init_views(persons)
  |> create_room_and_upload_image()
  |> send_room_invitation()
  |> open_dialog_and_upload_image()
  |> accept_room_invitation()
  |> open_room_image_gallery()
end
```

### Keyword Options with Defaults

Use `Keyword.get/3` for optional parameters:

```elixir
def approve_request(room, user_public_key, room_identity, opts) do
  with public_only? <- Keyword.get(opts, :public_only, false),
       false <- public_only? and type != :public do
    # ...
  end
end
```
