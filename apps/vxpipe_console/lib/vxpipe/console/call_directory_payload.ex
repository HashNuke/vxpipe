defmodule Vxpipe.Console.CallDirectoryPayload do
  @moduledoc "Payload-free public call rows shared by the directory and tenant dashboard."

  def call(call) do
    %{
      id: call.id,
      call_spec_id: call.call_spec_id,
      call_spec_name: call.call_spec_name,
      call_spec_revision: call.call_spec_revision,
      state: directory_state(call.state),
      created_at: DateTime.to_iso8601(call.created_at),
      duration_ms: duration(call)
    }
  end

  defp duration(%{state: state, started_at: %DateTime{} = started, ended_at: %DateTime{} = ended})
       when state in [:ended, :failed], do: max(DateTime.diff(ended, started, :millisecond), 0)

  defp duration(_call), do: nil

  defp directory_state(state) when state in [:prepared, :admitting, :running], do: "ongoing"
  defp directory_state(state) when state in [:ended, :failed], do: "ended"
end
