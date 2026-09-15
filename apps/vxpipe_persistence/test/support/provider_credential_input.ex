defmodule Vxpipe.Persistence.Test.ProviderCredentialInput do
  @moduledoc false
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def init(options), do: {:ok, options}

  @impl true
  def handle_info({:io_request, from, reply_as, :getopts}, options) do
    send(from, {:io_reply, reply_as, [binary: true, encoding: :latin1, stdin: true]})
    {:noreply, options}
  end

  def handle_info({:io_request, from, reply_as, {:get_chars, _, _, _}}, options) do
    send(Keyword.fetch!(options, :owner), :credential_input_read)
    send(from, {:io_reply, reply_as, ~s({"api_key":"terminal-secret"})})
    {:noreply, options}
  end
end
