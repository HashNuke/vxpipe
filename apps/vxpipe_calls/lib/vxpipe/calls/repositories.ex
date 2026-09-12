defmodule Vxpipe.Calls.Repositories do
  @moduledoc false

  @spec fetch(
          keyword(),
          :archive_repository
          | :artifact_repository
          | :usage_repository
          | :credential_repository
          | :definition_repository
          | :call_repository
          | :call_details_inspection_repository
          | :inspection_repository
          | :publication_repository
        ) ::
          {:ok, {module(), term()}} | {:error, :repository_unavailable}
  def fetch(options, key) do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])

    case Keyword.get(options, key, Keyword.get(configured, key)) do
      {module, context} when is_atom(module) -> {:ok, {module, context}}
      _unavailable -> {:error, :repository_unavailable}
    end
  end

  @spec call({module(), term()}, atom(), list()) :: term()
  def call({module, context}, function, arguments) do
    apply(module, function, [context | arguments])
  end
end
