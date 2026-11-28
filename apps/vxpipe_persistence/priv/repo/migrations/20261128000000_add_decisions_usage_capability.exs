defmodule Vxpipe.Persistence.Repo.Migrations.AddDecisionsUsageCapability do
  use Ecto.Migration

  @existing "'model_inference', 'speech_to_text', 'text_to_speech', 'speech_to_speech', " <>
              "'output_speech_to_text', 'tool', 'telephony'"

  def up do
    replace_constraints(@existing <> ", 'decisions'")
  end

  # Existing Decisions rows deliberately prevent downgrade; never delete usage
  # to force an older contract onto data it cannot represent.
  def down do
    replace_constraints(@existing)
  end

  defp replace_constraints(capabilities) do
    for {table, name} <- [
          {:usage_observations, :usage_observations_capability},
          {:usage_amounts, :usage_amounts_capability}
        ] do
      drop(constraint(table, name))
      create(constraint(table, name, check: "capability IN (#{capabilities})"))
    end
  end
end
