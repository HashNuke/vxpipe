defmodule Vxpipe.CallEngine.Tool.Idle do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}
  alias Vxpipe.CallEngine.Tool.Idle.Request

  @impl true
  def definition do
    %Definition{
      name: "idle",
      description:
        "Give the participant a moment. Stop eligible old speech, optionally acknowledge, " <>
          "then wait this many seconds after playback settles. New input resumes immediately; " <>
          "otherwise idle_timeout requests a follow-up.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "duration_seconds" => %{
            "type" => "integer",
            "minimum" => Request.minimum_seconds(),
            "maximum" => Request.maximum_seconds()
          }
        },
        "required" => ["duration_seconds"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def execute(arguments, %Context{} = context) do
    with {:ok, request} <- Request.new(arguments, context) do
      Vxpipe.CallEngine.RoomAuthority.idle(request)
    end
  end
end
