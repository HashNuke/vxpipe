defmodule Vxpipe.Gateway.MCP.CallTools do
  @moduledoc "MCP adapters for shared call creation and pinned participant token issuance."

  alias Vxpipe.Calls

  alias Vxpipe.Gateway.{
    CallCreation,
    CallCreationErrors,
    CallJoinTokenErrors,
    CallJoinTokenJSON,
    CallHangup,
    CallHangupErrors
  }

  @id %{type: "string", minLength: 1, maxLength: 128, pattern: "^[^\\x00\\r\\n]+$"}
  @tenant %{tenant_key: %{type: "string", pattern: "^[A-Za-z0-9_-]{16}$"}}
  @definitions [
    {"create_call",
     "Create a call from its published spec. Web calls remain prepared; outgoing calls submit a dial. Reuse idempotency_key when retrying the same request.",
     Map.merge(@tenant, %{
       call_spec_id: @id,
       variables: %{type: "object", default: %{}},
       to: %{type: "string", minLength: 1, maxLength: 16},
       idempotency_key: %{type: "string", minLength: 1, maxLength: 256}
     }), ["tenant_key", "call_spec_id"], true},
    {"create_join_token",
     "Issue a single-use web join token for an existing call. Omit participant_key only for an eligible pinned web entry. Keep the returned token secret.",
     Map.merge(@tenant, %{
       call_id: @id,
       participant_key: @id,
       join_token_ttl_seconds: %{type: "integer", minimum: 300, maximum: 86_400, default: 300}
     }), ["tenant_key", "call_id"], false},
    {"hangup_call",
     "Request whole-call shutdown. Returns ending while owned cleanup drains, or ended with durable terminal evidence. Unknown cleanup remains an error; no automatic retries.",
     Map.merge(@tenant, %{call_id: @id}), ["tenant_key", "call_id"], true}
  ]
  @tools Enum.map(@definitions, fn {name, description, properties, required, external?} ->
           %{
             name: name,
             description: description,
             inputSchema: %{
               type: "object",
               additionalProperties: false,
               properties: properties,
               required: required
             },
             annotations: %{
               readOnlyHint: false,
               destructiveHint: true,
               idempotentHint: name == "hangup_call",
               openWorldHint: external?
             }
           }
         end)

  def names, do: Enum.map(@tools, & &1.name)

  def list(actor), do: if(Calls.authorize_call_management(actor) == :ok, do: @tools, else: [])

  def authorize(actor, name, arguments) when is_map(arguments) do
    with %{inputSchema: schema} <- Enum.find(@tools, &(&1.name == name)),
         {:ok, validated} <- ExMCP.Server.Tools.Helpers.validate_arguments(arguments, schema) do
      case Calls.authorize_call_management(actor) do
        :ok -> {:ok, validated}
        {:error, _reason} -> {:error, :forbidden}
      end
    else
      _invalid -> {:error, :invalid_tool_arguments}
    end
  end

  def authorize(_actor, _name, _arguments), do: {:error, :invalid_tool_arguments}

  def call(actor, "create_call", args, options) do
    with {:ok, _outcome, call} <-
           CallCreation.create(
             options,
             actor,
             args["tenant_key"],
             args["call_spec_id"],
             args["variables"],
             args["to"],
             args["idempotency_key"]
           ),
         do: {:ok, %{call_id: call.id}}
  end

  def call(actor, "create_join_token", args, options) do
    with {:ok, token} <-
           Calls.issue_call_join_token(
             actor,
             args["tenant_key"],
             args["call_id"],
             args["participant_key"],
             Keyword.put(options, :join_token_ttl_seconds, args["join_token_ttl_seconds"])
           ),
         do: {:ok, CallJoinTokenJSON.result(token)}
  end

  def call(actor, "hangup_call", args, options),
    do: CallHangup.request(actor, args["tenant_key"], args["call_id"], options)

  def error("hangup_call", reason) do
    {_status, projected} = CallHangupErrors.response(reason)
    projected
  end

  def error("create_call", reason) do
    {_status, projected} = CallCreationErrors.response(reason)
    projected
  end

  def error("create_join_token", reason) do
    {_status, projected} = CallJoinTokenErrors.response(reason)
    projected
  end
end
