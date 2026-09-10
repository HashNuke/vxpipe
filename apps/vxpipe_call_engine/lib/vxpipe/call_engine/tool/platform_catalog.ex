defmodule Vxpipe.CallEngine.Tool.PlatformCatalog do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{CurrentTime, Hangup}

  @tools %{
    "get_current_time" => CurrentTime,
    "hangup" => Hangup
  }

  @spec fetch(String.t()) :: {:ok, module()} | :error
  def fetch(name) when is_binary(name), do: Map.fetch(@tools, name)

  @spec action?(term()) :: boolean()
  def action?(action) when is_atom(action), do: action in Map.values(@tools)
  def action?(_action), do: false
end
