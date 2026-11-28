defmodule Vxpipe.CallEngine.CallSpec.GuardrailQuestion do
  @moduledoc false

  @enforce_keys [:id, :question, :required_answer, :threshold_hundredths]
  defstruct @enforce_keys ++ [response: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          question: String.t(),
          required_answer: :yes | :no,
          threshold_hundredths: 0..100,
          response: nil | String.t()
        }

  @doc "Returns the exact model feedback line and its origin for a failed question."
  def feedback(text, required_answer, response) do
    if is_binary(response) and String.trim(response) != "" do
      {response, "authored"}
    else
      required = if required_answer in [:yes, "yes"], do: "Yes", else: "No"
      {"Failed guardrail: #{text} Required: #{required}.", "fallback"}
    end
  end
end
