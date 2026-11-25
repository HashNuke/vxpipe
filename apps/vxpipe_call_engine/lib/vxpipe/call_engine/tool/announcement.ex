defmodule Vxpipe.CallEngine.Tool.Announcement do
  @moduledoc false

  @maximum_length 240
  @budget_ms 20_000

  def budget_ms, do: @budget_ms

  def parameters(schema, true) do
    put_in(schema, ["properties", "announcement"], %{
      "type" => "string",
      "minLength" => 1,
      "maxLength" => @maximum_length,
      "description" => "Optional short sentence to play to the caller before this action."
    })
  end

  def parameters(schema, false), do: schema

  def extract(arguments) do
    case Map.pop(arguments, "announcement", :absent) do
      {:absent, rest} ->
        {:ok, nil, rest}

      {text, rest} when is_binary(text) ->
        if String.valid?(text) and String.trim(text) != "" and
             String.length(text) <= @maximum_length,
           do: {:ok, String.trim(text), rest},
           else: {:error, :invalid_arguments}

      _invalid ->
        {:error, :invalid_arguments}
    end
  end
end
