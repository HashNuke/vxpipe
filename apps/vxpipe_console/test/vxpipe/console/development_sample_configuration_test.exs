defmodule Vxpipe.Console.DevelopmentSampleConfigurationTest do
  use ExUnit.Case, async: true

  test "each development agent can end the sample call through the platform hangup tool" do
    participants = development_participants()

    for participant_ref <- ["reception", "billing"] do
      assert %{type: "platform", tool: "hangup"} =
               participants
               |> Map.fetch!(participant_ref)
               |> Map.fetch!(:tools)
               |> Map.fetch!("hangup")
    end
  end

  defp development_participants do
    config_path = Path.expand("../../../../../config/dev.exs", __DIR__)

    config_path
    |> Config.Reader.read!()
    |> Keyword.fetch!(:vxpipe_gateway)
    |> Keyword.fetch!(Vxpipe.Gateway.Application)
    |> Keyword.fetch!(:http)
    |> Keyword.fetch!(:room_creation)
    |> Keyword.fetch!(:trusted_call)
    |> Keyword.fetch!(:definition)
    |> Map.fetch!(:participants)
  end
end
