defmodule Vxpipe.Gateway.MCP.AccountTools do
  @moduledoc "Platform-key MCP account operations over shared Identity workflows."

  alias Vxpipe.Gateway.{AccountErrors, AccountJSON, AccountManagement}

  @id %{
    type: "string",
    pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
  }
  @paging %{
    page: %{type: "integer", minimum: 1, maximum: 2_147_483_647, default: 1},
    page_size: %{type: "integer", minimum: 1, maximum: 50, default: 25}
  }
  @fields %{
    email: %{type: "string", minLength: 3, maxLength: 320},
    role_id: @id,
    memberships: %{
      type: "array",
      items: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          tenant_key: %{type: "string", pattern: "^[A-Za-z0-9_-]{16}$"},
          access: %{type: "string", enum: ["read", "read_write"]}
        },
        required: ["tenant_key", "access"]
      }
    }
  }
  @password %{type: "string", minLength: 15, maxLength: 128}
  @definitions [
    {"list_users",
     "List installation users with bounded pagination and optional email/role filtering.",
     Map.merge(@paging, %{query: %{type: "string", maxLength: 120}, role_id: @id}), [], true},
    {"list_role_options",
     "List safe role IDs, names and kinds for account assignment; excludes grants.", @paging, [],
     true},
    {"create_user",
     "Create an enabled user with a role and optional tenant memberships. Password inputs are never returned.",
     Map.merge(@fields, %{password: @password, password_confirmation: @password}),
     ["email", "password", "password_confirmation", "role_id"], false},
    {"update_user",
     "Partially update a user. Omitted fields remain unchanged. enabled:true reactivates; enabled:false disables and revokes sessions. Password changes are unsupported.",
     Map.merge(@fields, %{user_id: @id, enabled: %{type: "boolean"}}), ["user_id"], false},
    {"disable_user",
     "Disable a user and revoke their login sessions without deleting them. Safe to repeat.",
     %{user_id: @id}, ["user_id"], false}
  ]
  @tools Enum.map(@definitions, fn {name, description, properties, required, read?} ->
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
               readOnlyHint: read?,
               destructiveHint: not read?,
               idempotentHint: read? or name == "disable_user",
               openWorldHint: false
             }
           }
         end)

  def names, do: Enum.map(@tools, & &1.name)
  def list(actor), do: if(AccountManagement.authorize_machine(actor) == :ok, do: @tools, else: [])

  def authorize(actor, name, arguments) when is_map(arguments) do
    with %{inputSchema: schema} <- Enum.find(@tools, &(&1.name == name)),
         {:ok, validated} <- ExMCP.Server.Tools.Helpers.validate_arguments(arguments, schema) do
      case AccountManagement.authorize_machine(actor) do
        :ok -> {:ok, validated}
        {:error, _reason} -> {:error, :forbidden}
      end
    else
      _invalid -> {:error, :invalid_tool_arguments}
    end
  end

  def authorize(_actor, _name, _arguments), do: {:error, :invalid_tool_arguments}

  def call(actor, "list_users", args, options) do
    with {:ok, page} <- AccountManagement.list_users(actor, args, options),
         do: {:ok, AccountJSON.user_page(page, :mcp)}
  end

  def call(actor, "list_role_options", args, options) do
    with {:ok, page} <- AccountManagement.list_role_options(actor, args, options),
         do: {:ok, AccountJSON.role_page(page, :mcp)}
  end

  def call(actor, "create_user", args, options) do
    with {:ok, user} <- AccountManagement.create_user(actor, args, options),
         do: {:ok, AccountJSON.user(user, :mcp)}
  end

  def call(actor, "update_user", args, options) do
    with {:ok, user} <-
           AccountManagement.update_user(
             actor,
             args["user_id"],
             Map.delete(args, "user_id"),
             options
           ),
         do: {:ok, AccountJSON.user(user, :mcp)}
  end

  def call(actor, "disable_user", args, options) do
    with {:ok, user} <- AccountManagement.disable_user(actor, args["user_id"], options),
         do: {:ok, AccountJSON.user(user, :mcp)}
  end

  def error(_name, reason) do
    {_status, projected} = AccountErrors.response(reason)
    projected
  end
end
