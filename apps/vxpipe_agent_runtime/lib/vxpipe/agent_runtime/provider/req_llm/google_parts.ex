defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.GoogleParts do
  @moduledoc false

  alias Elixir.ReqLLM.Message.ReasoningDetails

  def capture(details, text, calls) do
    raw =
      Enum.map(details, fn
        %ReasoningDetails{
          provider: :google,
          format: "google-generate-content-parts-v1",
          provider_data: %{"part" => part} = data
        }
        when map_size(data) == 1 ->
          part

        _ ->
          invalid!()
      end)

    {parts, offset, count} =
      Enum.reduce(raw, {[], 0, 0}, fn part, {parts, offset, count} ->
        {entry, offset, count} = capture_part(part, text, calls, offset, count)
        {[entry | parts], offset, count}
      end)

    require!(offset == byte_size(text) and count == length(calls))
    {:ok, Enum.reverse(parts)}
  rescue
    _ -> {:error, :invalid_provider_replay}
  catch
    :invalid_google_parts -> {:error, :invalid_provider_replay}
  end

  def restore(parts, text, calls) when is_list(parts) do
    {raw, offset, count} =
      Enum.reduce(parts, {[], 0, 0}, fn entry, {raw, offset, count} ->
        {part, offset, count} = restore_part(entry, text, calls, offset, count)
        {[part | raw], offset, count}
      end)

    require!(offset == byte_size(text) and count == length(calls))
    {:ok, Enum.reverse(raw)}
  rescue
    _ -> {:error, :invalid_provider_replay}
  catch
    :invalid_google_parts -> {:error, :invalid_provider_replay}
  end

  def restore(_parts, _text, _calls), do: {:error, :invalid_provider_replay}

  defp capture_part(part, text, calls, offset, count) when is_map(part) do
    require!(
      Enum.all?(Map.keys(part), &(&1 in ["text", "functionCall", "thought", "thoughtSignature"]))
    )

    attributes = Map.take(part, ["thought", "thoughtSignature"])
    validate_attributes!(attributes)

    case {Map.fetch(part, "text"), Map.fetch(part, "functionCall")} do
      {{:ok, value}, :error} when is_binary(value) ->
        if attributes["thought"] == true do
          {%{"kind" => "thinking", "text" => value, "attributes" => attributes}, offset, count}
        else
          require!(slice!(text, offset, byte_size(value)) == value)

          {%{
             "kind" => "public",
             "offset" => offset,
             "bytes" => byte_size(value),
             "attributes" => attributes
           }, offset + byte_size(value), count}
        end

      {:error, {:ok, function}} when is_map(function) ->
        call = Enum.at(calls, count)
        require!(Enum.all?(Map.keys(function), &(&1 in ["id", "name", "args"])))

        require!(
          function["name"] == call.name and Map.get(function, "args", %{}) == call.arguments
        )

        has_id = Map.has_key?(function, "id")
        require!(not has_id or function["id"] == call.id)
        validate_call_attributes!(attributes, call, has_id)

        {%{
           "kind" => "call",
           "index" => count,
           "has_id" => has_id,
           "has_args" => Map.has_key?(function, "args"),
           "attributes" => attributes
         }, offset, count + 1}

      {:error, :error} ->
        require!(Map.has_key?(attributes, "thoughtSignature"))
        {%{"kind" => "empty", "attributes" => attributes}, offset, count}

      _ ->
        invalid!()
    end
  end

  defp capture_part(_part, _text, _calls, _offset, _count), do: invalid!()

  defp restore_part(
         %{"kind" => "public", "offset" => offset, "bytes" => bytes, "attributes" => attributes} =
           entry,
         text,
         _calls,
         offset,
         count
       )
       when map_size(entry) == 4 do
    validate_attributes!(attributes)
    require!(attributes["thought"] != true)
    {Map.put(attributes, "text", slice!(text, offset, bytes)), offset + bytes, count}
  end

  defp restore_part(
         %{"kind" => "thinking", "text" => text, "attributes" => attributes} = entry,
         _text,
         _calls,
         offset,
         count
       )
       when map_size(entry) == 3 and is_binary(text) do
    validate_attributes!(attributes)
    require!(attributes["thought"] == true)
    {Map.put(attributes, "text", text), offset, count}
  end

  defp restore_part(
         %{
           "kind" => "call",
           "index" => count,
           "has_id" => has_id,
           "has_args" => has_args,
           "attributes" => attributes
         } = entry,
         _text,
         calls,
         offset,
         count
       )
       when map_size(entry) == 5 and is_boolean(has_id) and is_boolean(has_args) do
    validate_attributes!(attributes)
    call = Enum.at(calls, count)
    validate_call_attributes!(attributes, call, has_id)
    require!(has_args or call.arguments == %{})
    function = %{"name" => call.name}
    function = if has_args, do: Map.put(function, "args", call.arguments), else: function
    function = if has_id, do: Map.put(function, "id", call.id), else: function
    {Map.put(attributes, "functionCall", function), offset, count + 1}
  end

  defp restore_part(
         %{"kind" => "empty", "attributes" => attributes} = entry,
         _text,
         _calls,
         offset,
         count
       )
       when map_size(entry) == 2 do
    validate_attributes!(attributes)
    require!(Map.has_key?(attributes, "thoughtSignature"))
    {attributes, offset, count}
  end

  defp restore_part(_entry, _text, _calls, _offset, _count), do: invalid!()

  defp validate_attributes!(attributes) when is_map(attributes) do
    require!(
      Enum.all?(attributes, fn
        {"thought", value} -> is_boolean(value)
        {"thoughtSignature", value} -> is_binary(value)
        _ -> false
      end)
    )
  end

  defp validate_attributes!(_), do: invalid!()

  defp validate_call_attributes!(attributes, call, has_id) do
    metadata = call.provider_metadata
    signature = Map.get(metadata, :thought_signature) || Map.get(metadata, "thought_signature")
    native_id = Map.get(metadata, :google_call_id) || Map.get(metadata, "google_call_id")
    require!(attributes["thoughtSignature"] == signature)
    require!(if(has_id, do: native_id == call.id, else: is_nil(native_id)))
  end

  defp slice!(text, offset, bytes)
       when is_integer(offset) and is_integer(bytes) and offset >= 0 and bytes >= 0 do
    value = binary_part(text, offset, bytes)
    require!(String.valid?(value))
    value
  end

  defp slice!(_text, _offset, _bytes), do: invalid!()
  defp require!(true), do: :ok
  defp require!(_), do: invalid!()
  defp invalid!, do: throw(:invalid_google_parts)
end
