defmodule Vxpipe.Calls.CallHangups do
  @moduledoc "Authorizes and persists whole-call cancellation intent; it does not stop runtime resources."

  alias Vxpipe.Calls.{CallManagementAuthorization, PreparedCall, Repositories}

  def request(actor, tenant, id, options) when is_list(options) do
    with :ok <- CallManagementAuthorization.authorize(actor, tenant),
         :ok <- identifier(id),
         {:ok, now} <- request_time(options) do
      persist(tenant, id, now, options)
    end
  end

  def request(_actor, _tenant, _id, _options), do: {:error, :invalid_call_hangup}

  defp persist(tenant, id, now, options) do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      case Repositories.call(repository, :request_call_hangup, [tenant, id, now]) do
        {:ok, %PreparedCall{tenant_key: ^tenant, id: ^id} = call} -> {:ok, call}
        {:error, reason} when reason in [:not_found, :invalid_call_hangup] -> {:error, reason}
        _unavailable -> {:error, :call_hangup_unavailable}
      end
    else
      _unavailable -> {:error, :call_hangup_unavailable}
    end
  rescue
    _error -> {:error, :call_hangup_unavailable}
  catch
    _kind, _reason -> {:error, :call_hangup_unavailable}
  end

  defp identifier(id) when is_binary(id) and byte_size(id) in 1..256 do
    if String.valid?(id) and not String.contains?(id, [<<0>>, "\n", "\r"]),
      do: :ok,
      else: {:error, :invalid_call_hangup}
  end

  defp identifier(_id), do: {:error, :invalid_call_hangup}

  defp request_time(options) do
    case Keyword.get_lazy(options, :now, &DateTime.utc_now/0) do
      %DateTime{calendar: Calendar.ISO, utc_offset: 0, std_offset: 0} = now ->
        _ = DateTime.to_unix(now, :microsecond)
        {:ok, now}

      _invalid ->
        {:error, :invalid_call_hangup}
    end
  rescue
    _error -> {:error, :invalid_call_hangup}
  end
end
