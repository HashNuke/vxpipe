defmodule Vxpipe.CallEngine.Speech.Opening do
  @moduledoc "An engine-owned STS opening, separate from caller input."

  @type t :: :generated | {:fixed, String.t()}

  def valid?(:generated), do: true

  def valid?({:fixed, text}) when is_binary(text) and byte_size(text) in 1..4_096,
    do: String.valid?(text)

  def valid?(_opening), do: false
end
