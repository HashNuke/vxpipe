defmodule Vxpipe.AgentRuntime.RoundAdmission do
  @moduledoc """
  The host admits one tentative model round before speech or tools are released.
  It can accept the candidate, request a private repair, or end the response.
  Sessions without a host admit each round immediately.
  """

  alias Vxpipe.AgentRuntime.RoundCandidate

  @type bind :: %{required(:invocation_id) => String.t(), optional(atom()) => term()}
  @type failure_detail :: %{event: atom(), messages: [String.t()]}
  @type repair ::
          %{
            required(:messages) => [String.t()],
            optional(:failures) => [failure_detail()],
            optional(:on_dispatch) => (-> term())
          }
  @type failure :: :blocked | :error | :cancelled | :stale | :oversized
  @type verdict ::
          {:accept}
          | {:accept, %{binds: [bind()]}}
          | {:repair, repair()}
          | {:failure, failure()}
  @type context :: %{correlation: map(), history_mode: atom(), reply_protocol: atom()}

  @callback admit(RoundCandidate.t(), context(), term()) :: verdict()

  @spec validate(term()) :: {:ok, nil | {module(), term()}} | {:error, :invalid_configuration}
  def validate(nil), do: {:ok, nil}

  def validate({module, state}) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :admit, 3) do
      {:ok, {module, state}}
    else
      {:error, :invalid_configuration}
    end
  end

  def validate(_invalid), do: {:error, :invalid_configuration}

  @spec admit(nil | {module(), term()}, RoundCandidate.t(), context()) :: verdict()
  def admit(nil, _candidate, _context), do: {:accept}

  def admit({module, state}, %RoundCandidate{} = candidate, context)
      when is_atom(module) and is_map(context) do
    case apply(module, :admit, [candidate, context, state]) do
      {:accept} ->
        {:accept}

      {:accept, %{binds: binds}} ->
        if valid_binds?(binds) do
          {:accept, %{binds: binds}}
        else
          {:failure, :error}
        end

      {:repair, %{messages: messages} = repair} ->
        failures = Map.get(repair, :failures)

        callback = Map.get(repair, :on_dispatch)

        if valid_repair_lines?(messages) and valid_failures?(failures, messages) and
             (is_nil(callback) or is_function(callback, 0)) do
          {:repair,
           repair
           |> Map.take([:on_dispatch, :messages])
           |> Map.put(:failures, normalize_failures(failures))}
        else
          {:failure, :error}
        end

      {:failure, reason}
      when reason in [:blocked, :error, :cancelled, :stale, :oversized] ->
        {:failure, reason}

      _invalid ->
        {:failure, :error}
    end
  rescue
    _error -> {:failure, :error}
  catch
    _kind, _reason -> {:failure, :error}
  end

  defp valid_repair_lines?(messages) when is_list(messages) and messages != [] do
    Enum.all?(messages, &(is_binary(&1) and String.trim(&1) != ""))
  end

  defp valid_repair_lines?(_messages), do: false

  defp valid_binds?(binds) when is_list(binds) do
    Enum.all?(binds, fn
      %{invocation_id: id} when is_binary(id) and id != "" -> true
      _bind -> false
    end)
  end

  defp valid_binds?(_binds), do: false

  defp valid_failures?(nil, _messages), do: true

  defp valid_failures?(failures, _messages) when is_list(failures) and failures != [] do
    Enum.all?(failures, fn
      %{event: event, messages: lines} when is_atom(event) ->
        valid_repair_lines?(lines)

      _invalid ->
        false
    end)
  end

  defp valid_failures?(_failures, _messages), do: false

  defp normalize_failures(nil), do: nil

  defp normalize_failures(failures) when is_list(failures) do
    Enum.map(failures, fn %{event: event, messages: messages} ->
      %{event: event, messages: messages}
    end)
  end
end
