defmodule Vxpipe.Persistence.ResolvedPlanCodec do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan

  @spec encode(ResolvedCallPlan.t()) :: binary()
  def encode(%ResolvedCallPlan{} = plan), do: :erlang.term_to_binary(plan, [:deterministic])

  @spec decode(binary()) :: {:ok, ResolvedCallPlan.t()} | {:error, :invalid_stored_call_plan}
  def decode(encoded) when is_binary(encoded) do
    ResolvedCallPlan.ensure_data_loaded!()

    case :erlang.binary_to_term(encoded, [:safe]) do
      %ResolvedCallPlan{} = plan -> {:ok, plan}
      _invalid -> {:error, :invalid_stored_call_plan}
    end
  rescue
    ArgumentError -> {:error, :invalid_stored_call_plan}
  end
end
