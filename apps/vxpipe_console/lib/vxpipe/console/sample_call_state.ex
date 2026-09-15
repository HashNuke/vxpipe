defmodule Vxpipe.Console.SampleCallState do
  @moduledoc false

  @derive {Inspect, except: [:api_key, :initial_variables]}
  @enforce_keys [
    :backend,
    :definition,
    :initial_variables,
    :tenant_key,
    :transfer_participant,
    :status
  ]
  defstruct @enforce_keys ++
              [:api_key, :call_id, :participant_key, :transfer_participant_key]

  @type status :: :provisioning | :ready | {:failed, term()}

  @type t :: %__MODULE__{
          backend: {module(), term()},
          definition: map(),
          initial_variables: map(),
          transfer_participant: nil | String.t(),
          status: status(),
          api_key: nil | Vxpipe.Calls.IssuedApiKey.t(),
          call_id: nil | String.t(),
          participant_key: nil | String.t(),
          tenant_key: String.t(),
          transfer_participant_key: nil | String.t()
        }
end
