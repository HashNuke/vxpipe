defmodule Vxpipe.CallEngine.Telephony.OutboundLegConnector do
  @moduledoc """
  Host boundary for opening and closing one authorized outbound phone connection.

  Call Engine owns the request and deadline. The embedding transport application owns
  provider configuration, network submission, media attachment, and the returned reference.
  """

  alias Vxpipe.CallEngine.Telephony.{OutboundLegHandle, OutboundLegRequest}

  @type context :: term()
  @type connection_reference :: term()

  @callback connect(context(), OutboundLegRequest.t(), timeout()) ::
              {:ok, connection_reference()}
              | {:ok, connection_reference(), :unknown}
              | {:error, term()}
  @callback disconnect(context(), connection_reference()) :: :ok | {:error, term()}
  @callback owner(context(), connection_reference()) :: {:ok, pid()} | {:error, term()}

  @spec connect(term(), OutboundLegRequest.t(), timeout()) ::
          {:ok, OutboundLegHandle.t()} | {:error, :outbound_connection_unavailable}
  def connect({connector, context}, %OutboundLegRequest{} = request, timeout)
      when is_atom(connector) and is_integer(timeout) and timeout > 0 do
    with true <- Code.ensure_loaded?(connector),
         true <- function_exported?(connector, :connect, 3),
         true <- function_exported?(connector, :disconnect, 2),
         true <- function_exported?(connector, :owner, 2),
         {:ok, reference, status} <- submission(connector.connect(context, request, timeout)),
         {:ok, owner} when is_pid(owner) <- connector.owner(context, reference) do
      {:ok,
       %OutboundLegHandle{
         connector: connector,
         context: context,
         owner: owner,
         reference: reference,
         submission_status: status
       }}
    else
      _unavailable -> {:error, :outbound_connection_unavailable}
    end
  catch
    :exit, _reason -> {:error, :outbound_connection_unavailable}
  end

  def connect(_configuration, %OutboundLegRequest{}, _timeout) do
    {:error, :outbound_connection_unavailable}
  end

  defp submission({:ok, reference}), do: {:ok, reference, :accepted}
  defp submission({:ok, reference, :unknown}), do: {:ok, reference, :unknown}
  defp submission(_failure), do: {:error, :outbound_connection_unavailable}

  @spec disconnect(OutboundLegHandle.t()) :: :ok
  def disconnect(%OutboundLegHandle{} = handle) do
    case handle.connector.disconnect(handle.context, handle.reference) do
      :ok -> :ok
      {:error, _reason} -> :ok
      _invalid -> :ok
    end
  catch
    :exit, _reason -> :ok
  end
end
