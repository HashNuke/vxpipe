defmodule Vxpipe.CallEngine.Provider.ModelInference.Message do
  @moduledoc false

  @enforce_keys [:role, :content]
  defstruct [:role, :content]

  @type role :: :system | :user | :assistant
  @type t :: %__MODULE__{role: role(), content: String.t()}
end
