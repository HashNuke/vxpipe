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
end
