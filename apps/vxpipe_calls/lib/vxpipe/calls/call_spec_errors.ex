defmodule Vxpipe.Calls.CallSpecErrors do
  @moduledoc """
  Shared, value-free public errors for call-spec authoring transports.

  Only validator/compiler details supply reason text. Service failures use fixed
  explanations; exception messages, provider payloads and arbitrary details never
  enter the response. Historical compiler errors use the same projection.
  """
  alias Vxpipe.CallEngine.Error

  @failures %{
    provider_service_forbidden: {403, "This tenant cannot use the selected provider service."},
    provider_credential_unavailable:
      {422, "No usable credential is available for this provider."},
    telephony_caller_id_missing: {422, "The telephony service has no outbound caller ID number."},
    invalid_telephony_route:
      {422, "The phone number is not routable through the selected service."},
    private_call_spec_material: {422, "must not contain credentials or secrets"},
    revision_conflict: {409, "The call spec changed while saving. Reload the latest revision."}
  }

  @spec response(term()) :: {pos_integer(), map()}
  def response(%Error{code: code} = error) do
    case Map.fetch(@failures, code) do
      {:ok, {status, reason}} -> {status, field_error(code, error.details, reason)}
      :error -> {422, project(error)}
    end
  end

  def response({:call_spec_not_publishable, errors}) do
    first = errors |> validation_errors() |> List.first()

    error =
      first || field_error(:call_spec_not_publishable, %{}, "The revision cannot be published.")

    {409, Map.put(error, :code, "call_spec_not_publishable")}
  end

  def response(:revision_generation_exhausted), do: response(:revision_conflict)

  def response(code) when is_map_key(@failures, code) do
    {status, reason} = Map.fetch!(@failures, code)
    {status, field_error(code, %{}, reason)}
  end

  def response(:invalid_call_spec_source),
    do: {422, field_error(:invalid_call_spec, %{}, "must be a JSON object")}

  def response(:invalid_api_key), do: {401, %{code: "invalid_api_key"}}

  def response(reason)
      when reason in [
             :insufficient_scope,
             :tenant_access_forbidden,
             :authoring_authority_required
           ],
      do: {403, %{code: "authoring_forbidden"}}

  def response(reason) when reason in [:invalid_request, :invalid_tenant_key],
    do: {400, %{code: "invalid_request"}}

  def response(reason) when reason in [:not_found, :tenant_not_found],
    do: {404, %{code: "call_spec_not_found"}}

  def response(_reason), do: {503, %{code: "call_spec_authoring_unavailable"}}

  @doc "Projects the first fail-fast compiler error, including older stored error maps."
  def validation_errors([]), do: []
  def validation_errors([first | _rest]), do: [project(first)]
  def validation_errors(_invalid), do: []

  defp project(%Error{code: code, details: details})
       when code in [:invalid_call_spec, :unsupported_call_plan],
       do: validator_error(code, details)

  defp project(%{"code" => code, "details" => details})
       when code in ["invalid_call_spec", "unsupported_call_plan"],
       do: validator_error(code, details)

  defp project(_error),
    do: field_error(:invalid_call_spec, %{}, "The call spec could not be validated.")

  defp validator_error(code, details) when is_map(details) do
    reason = Map.get(details, "reason")
    reason = if is_binary(reason), do: reason, else: "The call spec could not be validated."
    field_error(code, details, reason)
  end

  defp validator_error(code, _details),
    do: field_error(code, %{}, "The call spec could not be validated.")

  defp field_error(code, details, reason) do
    path = if is_map(details), do: Map.get(details, "path", []), else: []
    path = if is_list(path), do: Enum.map(path, &path_segment/1), else: []
    %{code: to_string(code), path: path, reason: reason}
  end

  # Unknown source keys can themselves contain a URL or secret payload. Only
  # identifier-shaped path segments are useful for locating an editor field.
  defp path_segment(segment) when is_binary(segment) do
    if Regex.match?(~r/\A[A-Za-z0-9_-]{1,128}\z/, segment), do: segment, else: "<invalid-key>"
  end

  defp path_segment(_segment), do: "<invalid-key>"
end
