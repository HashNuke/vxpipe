defmodule Vxpipe.CallEngine.Provider.ReqLLM do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Provider.ModelInference

  alias Elixir.ReqLLM.Context
  alias Elixir.ReqLLM.Response
  alias Vxpipe.CallEngine.Provider.ModelInference.Message
  alias Vxpipe.CallEngine.Provider.ReqLLM.Config

  @impl true
  def new(options) do
    with {:ok, options} <-
           Keyword.validate(options, api_key: nil, model: nil, generation_options: []),
         api_key when is_binary(api_key) <- Keyword.fetch!(options, :api_key),
         true <- String.trim(api_key) != "",
         model_spec when is_binary(model_spec) <- Keyword.fetch!(options, :model),
         true <- String.trim(model_spec) != "",
         generation_options when is_list(generation_options) <-
           Keyword.fetch!(options, :generation_options),
         true <- Keyword.keyword?(generation_options),
         false <- Keyword.has_key?(generation_options, :api_key),
         {:ok, model} <- Elixir.ReqLLM.model(model_spec) do
      {:ok,
       %Config{
         api_key: api_key,
         model: model,
         generation_options: generation_options
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def generate(%Config{} = config, messages) when is_list(messages) do
    {model, context, options} = prepare_request(config, messages)

    case Elixir.ReqLLM.generate_text(model, context, options) do
      {:ok, %Response{} = response} ->
        case Response.text(response) do
          text when is_binary(text) -> {:ok, text}
          _missing_text -> {:error, :invalid_response}
        end

      {:error, _reason} ->
        {:error, :provider_unavailable}
    end
  end

  @doc false
  def prepare_request(%Config{} = config, messages) when is_list(messages) do
    context =
      messages
      |> Enum.map(&to_req_llm_message/1)
      |> Context.new()

    options = Keyword.put(config.generation_options, :api_key, config.api_key)
    {config.model, context, options}
  end

  defp to_req_llm_message(%Message{role: :system, content: content}),
    do: Context.system(content)

  defp to_req_llm_message(%Message{role: :user, content: content}),
    do: Context.user(content)

  defp to_req_llm_message(%Message{role: :assistant, content: content}),
    do: Context.assistant(content)
end
