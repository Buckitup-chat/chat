defmodule ChatSupport.Mocks.NetworkSynchronization.Electric.ElectricClientMock do
  @moduledoc """
  Mock for Electric.Client used in ShapeConsumer tests.

  Returns a finite stream of messages stored in Application env under
  `:electric_mock_messages`. The stream terminates naturally, causing
  the Task in ShapeConsumer to exit (triggering the retry backoff path).
  """

  alias Electric.Client.Message

  def new!(opts) when is_list(opts), do: :mock_client

  def stream(:mock_client, _schema, _opts) do
    Application.get_env(:chat, :electric_mock_messages, [])
  end

  def default_messages(user_card) do
    [
      %Message.ChangeMessage{headers: %{operation: :insert}, value: user_card},
      %Message.ResumeMessage{shape_handle: "test_handle", offset: nil, schema: %{}}
    ]
  end
end
