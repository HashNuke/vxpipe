defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.RouterReplay do
  @moduledoc false

  alias Elixir.ReqLLM.Message.{ContentPart, ReasoningDetails}
  alias Vxpipe.AgentRuntime.{Message, ProviderReplay}

  @keys ~w(format provider model wire_model source_digest options_digest response_model reasoning details)

  def native_tools(options, %{provider: provider}, :mode_message_v1)
      when provider in [:openrouter, :zenmux] do
    Keyword.update(
      options,
      :provider_options,
      [vxpipe_native_tool_calls_only: true],
      &Keyword.put(&1, :vxpipe_native_tool_calls_only, true)
    )
  end

  def native_tools(options, _model, _protocol), do: options

  def context(config, request) do
    %{
      generation_options: config.generation_options,
      required_model: required_model(request.messages)
    }
  end

  def project(model, options, messages) do
    case required_model(messages) do
      nil ->
        {model, options}

      target ->
        {%{model | id: target, provider_model_id: target}, constrain(options, model.provider)}
    end
  end

  def capture(model, response, text, calls, context) do
    message = response.message

    reasoning =
      message.content |> Enum.filter(&(&1.type == :thinking)) |> Enum.map_join("", & &1.text)

    with true <- compatible_response?(response, context),
         true <- Enum.all?(message.content, &valid_part?/1),
         {:ok, details} <- details(message.reasoning_details, model.provider, reasoning) do
      if reasoning == "" and details == [] do
        {:ok, %{}}
      else
        capture_private(model, response, text, calls, context, reasoning, details)
      end
    else
      _invalid -> {:error, :invalid_provider_replay}
    end
  end

  def restore(projected, %Message{} = source, model, options) do
    replay = source.provider_replay

    with true <- model.provider in [:openrouter, :zenmux],
         :ok <- ProviderReplay.validate(replay),
         true <- Enum.sort(Map.keys(replay)) == Enum.sort(@keys),
         true <- replay["format"] == "router_chat_v1",
         true <- replay["provider"] == Atom.to_string(model.provider),
         true <- replay["model"] == model.id,
         true <- replay["wire_model"] == (model.provider_model_id || model.id),
         true <- replay["source_digest"] == digest_source(source.content, source.tool_calls),
         true <- replay["options_digest"] == digest(options),
         true <- valid_model?(replay["response_model"]),
         reasoning when is_binary(reasoning) <- replay["reasoning"],
         details when is_list(details) <- replay["details"],
         true <- Enum.all?(details, &valid_detail?/1) do
      content =
        if reasoning == "",
          do: projected.content,
          else: [ContentPart.thinking(reasoning) | projected.content]

      %{projected | content: content, reasoning_details: details}
    else
      _invalid -> raise ArgumentError, "invalid or incompatible provider replay"
    end
  end

  defp capture_private(model, response, text, calls, context, reasoning, details) do
    reported = Map.get(response.provider_meta, :router_response_model)
    required = Map.get(context, :required_model)

    with true <- valid_model?(reported),
         true <- is_nil(required) or reported == required do
      replay = %{
        "format" => "router_chat_v1",
        "provider" => Atom.to_string(model.provider),
        "model" => model.id,
        "wire_model" => model.provider_model_id || model.id,
        "source_digest" => digest_source(text, calls),
        "options_digest" => digest(Map.get(context, :generation_options, [])),
        "response_model" => reported,
        "reasoning" => reasoning,
        "details" => details
      }

      with :ok <- ProviderReplay.validate(replay), do: {:ok, replay}
    else
      _invalid -> {:error, :invalid_provider_replay}
    end
  end

  defp compatible_response?(response, %{required_model: required}) when is_binary(required),
    do: Map.get(response.provider_meta, :router_response_model) == required

  defp compatible_response?(_response, _context), do: true

  defp required_model(messages) do
    origins =
      for %Message{provider_replay: %{"format" => "router_chat_v1", "response_model" => target}} <-
            messages,
          do: target

    case Enum.uniq(origins) do
      [] ->
        nil

      [target] ->
        if valid_model?(target), do: target, else: raise(ArgumentError, "invalid replay origin")

      _conflict ->
        raise ArgumentError, "incompatible replay origins"
    end
  end

  defp constrain(options, :openrouter) do
    options
    |> Keyword.drop([:openrouter_models, :openrouter_route])
    |> Keyword.update(
      :provider_options,
      [],
      &Keyword.drop(&1, [:openrouter_models, :openrouter_route])
    )
  end

  defp constrain(options, :zenmux) do
    options
    |> Keyword.delete(:model_routing_config)
    |> Keyword.update(
      :provider_options,
      [provider: %{fallback: "false"}],
      fn provider_options ->
        provider_options
        |> Keyword.delete(:model_routing_config)
        |> Keyword.update(
          :provider,
          %{fallback: "false"},
          &(&1 |> Map.delete("fallback") |> Map.put(:fallback, "false"))
        )
      end
    )
  end

  defp constrain(_options, _provider), do: raise(ArgumentError, "incompatible replay provider")

  defp details(value, _provider, _reasoning) when value in [nil, []], do: {:ok, []}

  defp details(value, provider, reasoning) when is_list(value) do
    cond do
      Enum.all?(value, &valid_detail?/1) -> {:ok, value}
      equivalent_thinking?(value, provider, reasoning) -> {:ok, []}
      true -> {:error, :invalid_provider_replay}
    end
  end

  defp details(_value, _provider, _reasoning), do: {:error, :invalid_provider_replay}

  defp equivalent_thinking?(details, provider, reasoning) do
    valid? =
      details
      |> Enum.with_index()
      |> Enum.all?(fn
        {%ReasoningDetails{
           provider: ^provider,
           format: "openai-reasoning-content-v1",
           index: index,
           text: text,
           signature: nil,
           provider_data: nil,
           encrypted?: false
         }, index} ->
          is_binary(text)

        _invalid ->
          false
      end)

    valid? and Enum.map_join(details, "", & &1.text) == reasoning
  end

  defp valid_part?(%ContentPart{type: type, text: text, metadata: metadata})
       when type in [:text, :thinking],
       do: is_binary(text) and metadata == %{}

  defp valid_part?(_part), do: false

  defp valid_detail?(%{"type" => type} = value) when is_binary(type) and type != "",
    do:
      not is_struct(value) and ProviderReplay.validate(value) == :ok and
        valid_fields?(type, value)

  defp valid_detail?(_value), do: false

  defp valid_fields?(type, value) do
    common? =
      Enum.all?(~w(id format signature text), &(is_nil(value[&1]) or is_binary(value[&1])))

    index? = is_nil(value["index"]) or (is_integer(value["index"]) and value["index"] >= 0)
    encrypted? = is_nil(value["signature_encrypted"]) or is_boolean(value["signature_encrypted"])

    payload? =
      case type do
        "reasoning.text" -> true
        "reasoning.summary" -> is_binary(value["summary"])
        "reasoning.encrypted" -> is_binary(value["data"])
        _unknown -> false
      end

    common? and index? and encrypted? and payload?
  end

  defp valid_model?(value),
    do:
      is_binary(value) and byte_size(value) in 1..256 and String.valid?(value) and
        String.trim(value) != ""

  defp digest_source(text, calls),
    do: digest({text, Enum.map(calls, &{&1.id, &1.name, &1.arguments, &1.provider_metadata})})

  defp digest(value),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))
      |> Base.encode16(case: :lower)
end
