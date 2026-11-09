defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.Readiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner

  def readiness(capability) do
    with {:ok, resource, status, remote_owner} <-
           GenServer.call(capability, :readiness_binding, 5_000),
         {:ok, remote, remote_status} <- remote_readiness(remote_owner) do
      resource =
        if remote do
          %{resource | configuration: Resource.signature({resource.configuration, remote})}
        else
          resource
        end

      status = if status == :ready and remote_status == :ready, do: :ready, else: :preparing
      {:ok, resource, status}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp remote_readiness(nil), do: {:ok, nil, :ready}
  defp remote_readiness(owner), do: IntegrationOwner.readiness(owner)
end
