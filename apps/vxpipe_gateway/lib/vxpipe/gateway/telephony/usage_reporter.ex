defmodule Vxpipe.Gateway.Telephony.UsageReporter do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.Observation

  @type reporter :: {module(), term()}

  @callback report(term(), [Observation.t()]) :: :ok | {:error, term()}

  @spec report(reporter(), [Observation.t()]) :: :ok
  def report(_reporter, []), do: :ok

  def report({module, context}, observations) when is_atom(module) and is_list(observations) do
    _result = module.report(context, observations)
    :ok
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end
end
