defmodule Vxpipe.CallEngine.Provider.MorseCode.Alphabet do
  @moduledoc false

  @symbols %{
    "A" => ".-",
    "B" => "-...",
    "C" => "-.-.",
    "D" => "-..",
    "E" => ".",
    "F" => "..-.",
    "G" => "--.",
    "H" => "....",
    "I" => "..",
    "J" => ".---",
    "K" => "-.-",
    "L" => ".-..",
    "M" => "--",
    "N" => "-.",
    "O" => "---",
    "P" => ".--.",
    "Q" => "--.-",
    "R" => ".-.",
    "S" => "...",
    "T" => "-",
    "U" => "..-",
    "V" => "...-",
    "W" => ".--",
    "X" => "-..-",
    "Y" => "-.--",
    "Z" => "--..",
    "0" => "-----",
    "1" => ".----",
    "2" => "..---",
    "3" => "...--",
    "4" => "....-",
    "5" => ".....",
    "6" => "-....",
    "7" => "--...",
    "8" => "---..",
    "9" => "----.",
    "." => ".-.-.-",
    "," => "--..--",
    ":" => "---...",
    "?" => "..--..",
    "'" => ".----.",
    "-" => "-....-",
    "/" => "-..-.",
    "(" => "-.--.",
    ")" => "-.--.-",
    "\"" => ".-..-.",
    "=" => "-...-",
    "+" => ".-.-.",
    "@" => ".--.-."
  }

  @characters Map.keys(@symbols) |> Enum.sort()
  @signals Map.new(@symbols, fn {character, signal} -> {signal, character} end)

  @spec encode(String.t()) :: {:ok, String.t()} | {:error, :unsupported_character}
  def encode(character) when is_binary(character) do
    case Map.fetch(@symbols, character) do
      {:ok, signal} -> {:ok, signal}
      :error -> {:error, :unsupported_character}
    end
  end

  @spec decode(String.t()) :: {:ok, String.t()} | {:error, :unsupported_signal}
  def decode(signal) when is_binary(signal) do
    case Map.fetch(@signals, signal) do
      {:ok, character} -> {:ok, character}
      :error -> {:error, :unsupported_signal}
    end
  end

  @spec characters() :: [String.t()]
  def characters, do: @characters
end
