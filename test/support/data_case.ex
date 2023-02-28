defmodule ChatWeb.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import ChatWeb.DataCase
    end
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  def assert_has_error(changeset, field, error_message) do
    assert is_struct(changeset, Ecto.Changeset)
    refute changeset.valid?
    assert error_message in Map.get(errors_on(changeset), field, [])
  end
end
