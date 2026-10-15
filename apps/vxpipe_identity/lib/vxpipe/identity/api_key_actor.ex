defmodule Vxpipe.Identity.ApiKeyActor do
  @moduledoc "Verified platform-key identity for account operations; carries no client-supplied grants."
  @enforce_keys [:api_key_id]
  defstruct [:api_key_id]

  def new(id) do
    if valid_id?(id), do: {:ok, %__MODULE__{api_key_id: id}}, else: {:error, :forbidden}
  end

  def valid_id?(id) when is_binary(id),
    do:
      Regex.match?(
        ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/,
        id
      )

  def valid_id?(_id), do: false
end
