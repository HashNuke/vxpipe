defmodule Vxpipe.Console.SampleCallState do
  @moduledoc false

  @derive {Inspect, except: [:api_key, :initial_variables]}
  @enforce_keys [:backend, :definition, :initial_variables, :tenant_name, :status]
  defstruct @enforce_keys ++ [:api_key, :participant_key, :tenant_key]

  @type status :: :provisioning | :ready | {:failed, term()}

  @type t :: %__MODULE__{
          backend: {module(), term()},
          definition: map(),
          initial_variables: map(),
          tenant_name: String.t(),
          status: status(),
          api_key: nil | Vxpipe.Calls.IssuedApiKey.t(),
          participant_key: nil | String.t(),
          tenant_key: nil | String.t()
        }
end
