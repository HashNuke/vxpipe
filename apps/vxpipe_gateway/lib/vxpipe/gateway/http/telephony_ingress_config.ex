defmodule Vxpipe.Gateway.HTTP.TelephonyIngressConfig do
  @moduledoc false

  alias Vxpipe.Gateway.CallAdmission

  alias Vxpipe.Gateway.Telephony.{
    CallIngress,
    MediaAdmission,
    ServiceRegistry
  }

  @default_maximum_body_bytes 131_072

  @spec init(keyword()) :: map()
  def init(options) do
    options =
      Keyword.validate!(options,
        enabled: false,
        services: [],
        handler: {CallIngress, []},
        media_admission: MediaAdmission,
        clock: &__MODULE__.system_time_seconds/0,
        maximum_body_bytes: @default_maximum_body_bytes
      )

    registry =
      ServiceRegistry.init!(
        enabled: Keyword.fetch!(options, :enabled),
        services: Keyword.fetch!(options, :services)
      )

    handler =
      registry.enabled?
      |> handler!(Keyword.fetch!(options, :handler))
      |> configure_default_backend(registry, Keyword.fetch!(options, :media_admission))

    %{
      registry: registry,
      handler: handler,
      media_admission: Keyword.fetch!(options, :media_admission),
      clock: options |> Keyword.fetch!(:clock) |> clock!(),
      maximum_body_bytes: options |> Keyword.fetch!(:maximum_body_bytes) |> maximum_body_bytes!()
    }
  end

  @doc false
  @spec system_time_seconds() :: non_neg_integer()
  def system_time_seconds, do: System.system_time(:second)

  defp handler!(false, _handler), do: nil
  defp handler!(true, {module, _context} = handler) when is_atom(module), do: handler

  defp handler!(true, _invalid),
    do: raise(ArgumentError, "telephony ingress handler is required")

  defp configure_default_backend({CallIngress, options}, registry, media_admission) do
    backend =
      options
      |> Keyword.get(:backend, {CallAdmission, []})
      |> configure_call_admission(registry, media_admission)

    {CallIngress, Keyword.put(options, :backend, backend)}
  end

  defp configure_default_backend(handler, _registry, _media_admission), do: handler

  defp configure_call_admission({CallAdmission, options}, registry, media_admission) do
    {CallAdmission, CallAdmission.configure_telephony(options, registry, media_admission)}
  end

  defp configure_call_admission(backend, _registry, _media_admission), do: backend

  defp clock!(clock) when is_function(clock, 0), do: clock
  defp clock!(_invalid), do: raise(ArgumentError, "telephony ingress clock must be a function/0")

  defp maximum_body_bytes!(value) when is_integer(value) and value > 0, do: value

  defp maximum_body_bytes!(_invalid),
    do: raise(ArgumentError, "telephony maximum_body_bytes must be a positive integer")
end
