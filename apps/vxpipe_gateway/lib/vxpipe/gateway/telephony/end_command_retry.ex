defmodule Vxpipe.Gateway.Telephony.EndCommandRetry do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Submission

  defstruct timer: nil, delay_ms: 250

  def accepted?(:ok), do: true
  def accepted?({:ok, %Submission{status: :accepted}}), do: true
  def accepted?(_result), do: false

  def schedule(%__MODULE__{timer: timer} = retry) when not is_nil(timer), do: retry

  def schedule(%__MODULE__{} = retry) do
    token = make_ref()
    timer = Process.send_after(self(), {:retry_carrier_end, token}, retry.delay_ms)
    %{retry | timer: {token, timer}, delay_ms: min(retry.delay_ms * 2, 5_000)}
  end

  def take(%__MODULE__{timer: {token, _timer}} = retry, token),
    do: {:ok, %{retry | timer: nil}}

  def take(%__MODULE__{}, _token), do: :stale

  def cancel(%__MODULE__{timer: nil} = retry), do: retry

  def cancel(%__MODULE__{timer: {_token, timer}} = retry) do
    Process.cancel_timer(timer)
    %{retry | timer: nil}
  end
end
