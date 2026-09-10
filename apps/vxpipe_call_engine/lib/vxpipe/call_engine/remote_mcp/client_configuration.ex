defmodule Vxpipe.CallEngine.RemoteMCP.ClientConfiguration do
  @moduledoc false

  alias Vxpipe.MCP.ClientOptions

  @spec validate(keyword()) :: :ok | {:error, :invalid_client_configuration}
  def validate(config) when is_list(config) do
    case ClientOptions.build(config) do
      {:ok, _options} -> :ok
      {:error, _reason} -> {:error, :invalid_client_configuration}
    end
  end

  def validate(_config), do: {:error, :invalid_client_configuration}
end
