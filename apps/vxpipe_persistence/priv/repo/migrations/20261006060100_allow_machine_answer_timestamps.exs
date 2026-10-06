defmodule Vxpipe.Persistence.Repo.Migrations.AllowMachineAnswerTimestamps do
  use Ecto.Migration

  def up, do: replace_constraint("outgoing_outcome IN ('answered', 'machine')")
  def down, do: replace_constraint("outgoing_outcome = 'answered'")

  defp replace_constraint(answer_outcomes) do
    drop(constraint(:calls, :calls_outgoing_times))

    create(
      constraint(:calls, :calls_outgoing_times,
        check:
          "(dial_submitted_at IS NULL OR (started_at IS NOT NULL AND dial_submitted_at >= started_at)) AND " <>
            "(answered_at IS NULL OR (outgoing_outcome IS NOT NULL AND #{answer_outcomes} AND dial_submitted_at IS NOT NULL AND answered_at >= dial_submitted_at)) AND " <>
            "(dial_ended_at IS NULL OR (dial_submitted_at IS NOT NULL AND outgoing_outcome IS NOT NULL AND dial_ended_at >= dial_submitted_at AND (answered_at IS NULL OR dial_ended_at >= answered_at)))"
      )
    )
  end
end
