defmodule Vxpipe.AgentRuntime.ProviderSelection do
  @moduledoc "Validates public model selections and translates them to internal provider options."

  @google_endpoint "https://generativelanguage.googleapis.com/v1beta"
  @common [:temperature, :top_p, :top_k, :max_tokens, :seed, :stop]
  @google [:google_thinking_budget, :google_thinking_level]

  @spec translate(String.t(), String.t(), map(), map()) ::
          {:ok, keyword()} | {:error, :invalid_provider_selection}
  def translate("google", model, common, specific) when is_binary(model) do
    with true <- local_model?(model),
         {:ok, common} <- options(common, @common),
         true <- Enum.all?(common, &valid_common?/1),
         {:ok, specific} <- options(specific, @google),
         true <- valid_google?(specific),
         {:ok, resolved} <- ReqLLM.model("google:" <> model),
         true <- resolved.provider == :google,
         generation <-
           common ++
             [
               base_url: @google_endpoint,
               provider_options: Keyword.put(specific, :google_auth_header, true)
             ],
         {:ok, provider} <- ReqLLM.provider(:google),
         {:ok, _validated} <-
           ReqLLM.Provider.Options.process(
             provider,
             :chat,
             resolved,
             Keyword.put(generation, :on_unsupported, :error)
           ) do
      {:ok, [model: "google:" <> model, generation_options: generation, streaming: true]}
    else
      _invalid -> {:error, :invalid_provider_selection}
    end
  rescue
    _exception -> {:error, :invalid_provider_selection}
  end

  def translate(_provider, _model, _common, _specific),
    do: {:error, :invalid_provider_selection}

  defp local_model?(model) do
    byte_size(model) in 1..256 and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._\/-]*\z/, model)
  end

  defp options(%_struct{}, _allowed), do: :error

  defp options(input, allowed) when is_map(input) do
    Enum.reduce_while(input, {:ok, []}, fn {key, value}, {:ok, acc} ->
      case Enum.find(allowed, &(Atom.to_string(&1) == key)) do
        nil -> {:halt, :error}
        key -> {:cont, {:ok, [{key, value} | acc]}}
      end
    end)
  end

  defp options(_input, _allowed), do: :error

  defp valid_common?({:temperature, value}), do: is_number(value) and value >= 0 and value <= 2
  defp valid_common?({:top_p, value}), do: is_number(value) and value > 0 and value <= 1
  defp valid_common?({:top_k, value}), do: is_integer(value) and value in 1..100
  defp valid_common?({:max_tokens, value}), do: is_integer(value) and value in 1..1_048_576
  defp valid_common?({:seed, value}), do: is_integer(value) and value in 0..2_147_483_647

  defp valid_common?({:stop, values}) do
    is_list(values) and length(values) in 1..16 and
      Enum.all?(values, &(is_binary(&1) and String.valid?(&1) and byte_size(&1) in 1..256))
  end

  defp valid_google?(options) do
    not (Keyword.has_key?(options, :google_thinking_budget) and
           Keyword.has_key?(options, :google_thinking_level)) and
      Enum.all?(options, fn
        {:google_thinking_budget, value} -> is_integer(value) and value in 0..65_536
        {:google_thinking_level, value} -> value in ["minimal", "low", "medium", "high"]
      end)
  end
end
