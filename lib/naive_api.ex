defmodule NaiveApi do
  @moduledoc "NaiveApi helpers"

  def resolver do
    quote do
      defp ok(result), do: {:ok, result}
      defp error(reason), do: {:error, reason}
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
