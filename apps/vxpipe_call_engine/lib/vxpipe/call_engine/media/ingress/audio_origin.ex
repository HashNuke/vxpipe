defmodule Vxpipe.CallEngine.Media.Ingress.AudioOrigin do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Snapshot, SpeechToTextDemand}

  def valid?(nil, _agent), do: true

  def valid?(
        %{
          allocation_generation: generation,
          audio_input_interval: input,
          audio_output_interval: output,
          agent_id: agent
        } = origin,
        agent
      )
      when is_binary(agent) and is_reference(generation) and
             is_integer(input) and input >= 0 and is_integer(output) and output >= 0 and
             map_size(origin) == 4,
      do: true

  def valid?(_origin, _agent), do: false

  def current?(_origin, _policy, _source, nil), do: true

  def current?(origin, %Snapshot{} = policy, source, agent)
      when is_map(origin) and is_binary(agent) do
    origin.agent_id == agent and
      origin.audio_input_interval == Snapshot.interval(policy, :audio_input, source) and
      origin.audio_output_interval == Snapshot.interval(policy, :audio_output, source) and
      SpeechToTextDemand.required?(policy, source, agent)
  end

  def current?(_origin, _policy, _source, _agent), do: false

  def delivery_intervals(intervals, nil), do: intervals

  def delivery_intervals(intervals, origin),
    do: Map.put(intervals, :allocation_generation, origin.allocation_generation)
end
