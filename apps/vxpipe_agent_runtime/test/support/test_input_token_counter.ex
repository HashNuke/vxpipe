defmodule Vxpipe.AgentRuntime.TestInputTokenCounter do
  @behaviour Vxpipe.AgentRuntime.InputTokenCounter

  @impl true
  def count(%{owner: owner, result: result}, request) do
    send(owner, {:input_tokens_counted, self(), request})

    case result do
      :manual ->
        receive do
          {:input_token_count, count} -> {:ok, count}
          {:input_token_error, reason} -> {:error, reason}
        end

      fixed ->
        fixed
    end
  end
end
