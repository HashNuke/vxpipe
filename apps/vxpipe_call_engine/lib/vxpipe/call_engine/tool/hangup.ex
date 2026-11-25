defmodule Vxpipe.CallEngine.Tool.Hangup do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition, PlatformResult}

  @impl true
  def definition do
    %Definition{
      name: "hangup",
      description: "End the current call immediately.",
      parameters: %{
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def execute(arguments, %Context{}) when map_size(arguments) == 0 do
    {:ok, %PlatformResult{effect: :hangup, result: %{"status" => "ending"}}}
  end

  def execute(%{"announcement" => _} = arguments, %Context{} = context) do
    with {:ok, text, rest} when map_size(rest) == 0 <-
           Vxpipe.CallEngine.Tool.Announcement.extract(arguments),
         :ok <- Vxpipe.CallEngine.RoomAuthority.announce_hangup(context, text) do
      {:ok, %PlatformResult{effect: :announced_hangup, result: %{"status" => "ending"}}}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_arguments}
    end
  end

  def execute(_arguments, %Context{}), do: {:error, :invalid_arguments}
end
