defmodule Vxpipe.Providers.Google.STSResponses do
  @moduledoc """
  Bounded Google model-response assembly, independent of the playback slot.

  This pure owner preserves a supplied authorization origin; it neither grants
  policy authority nor chooses when the upstream interaction may change origin.
  The session owns wire semantics and the engine owns admission. A record retires
  only after its model boundary and its local playback/discard obligation settle.
  """

  @maximum_records 16
  @maximum_pending_chunks 16
  @maximum_chunk_bytes 131_072
  @maximum_text_bytes 65_536
  @maximum_index 9_223_372_036_854_775_807

  @derive {Inspect, only: [:last_index]}
  defstruct last_index: 0, wire: nil, active: nil, records: %{}

  def new, do: %__MODULE__{}

  def fetch(state, reference), do: Map.fetch(state.records, reference)

  def counts(state) do
    Enum.reduce(Map.values(state.records), %{records: 0, pending_chunks: 0, text_bytes: 0}, fn
      response, totals ->
        %{
          records: totals.records + 1,
          pending_chunks: totals.pending_chunks + length(response.queue),
          text_bytes: totals.text_bytes + byte_size(response.text || "")
        }
    end)
  end

  def idle?(state), do: state.wire == nil and state.active == nil and state.records == %{}

  def ensure_wire(state, context) when is_reference(context) do
    case fetch(state, state.wire) do
      {:ok, %{context: ^context} = response} -> {:ok, state, response}
      {:ok, _other} -> {:error, :context_mismatch}
      :error -> new_response(state, context)
    end
  end

  def ensure_wire(_state, _context), do: {:error, :invalid_context}

  defp new_response(state, context) do
    if map_size(state.records) >= @maximum_records or state.last_index >= @maximum_index do
      {:error, :response_overflow}
    else
      response = %{
        ref: make_ref(),
        index: state.last_index + 1,
        context: context,
        queue: [],
        text: nil,
        announced?: false,
        generation_done?: false,
        model_done?: false,
        discarded?: false,
        output_ref: nil,
        awaiting: nil,
        completed?: false,
        played?: false
      }

      state = put_response(%{state | wire: response.ref, last_index: response.index}, response)
      {:ok, state, response}
    end
  end

  def append_text(state, text) do
    case fetch(state, state.wire) do
      {:ok, %{discarded?: true}} ->
        {:ok, state}

      {:ok, %{generation_done?: true}} ->
        {:ok, state}

      {:ok, response} ->
        if counts(state).text_bytes + byte_size(text) <= @maximum_text_bytes do
          {:ok, put_response(state, %{response | text: (response.text || "") <> text})}
        else
          {:error, :text_overflow}
        end

      :error ->
        {:error, :no_wire_response}
    end
  end

  def append_audio(state, pcm) do
    case fetch(state, state.wire) do
      {:ok, %{discarded?: true}} ->
        {:ok, state, nil}

      {:ok, %{generation_done?: true}} ->
        {:error, :generation_completed}

      {:ok, response} ->
        with {:ok, queue} <- pending_audio(state, response, pcm) do
          announcement =
            if not response.announced?, do: Map.take(response, [:ref, :index, :context])

          response = %{response | queue: queue, announced?: true}
          {:ok, put_response(state, response), announcement}
        end

      :error ->
        {:error, :no_wire_response}
    end
  end

  defp pending_audio(state, response, pcm) do
    pending = counts(state).pending_chunks

    if pending < @maximum_pending_chunks do
      {:ok, response.queue ++ [pcm]}
    else
      # Wire packet boundaries do not identify responses. Compact only this
      # response's pending PCM, preserving order and the original byte budget.
      queue = compact_audio(IO.iodata_to_binary(response.queue ++ [pcm]))

      if pending - length(response.queue) + length(queue) <= @maximum_pending_chunks,
        do: {:ok, queue},
        else: {:error, :audio_overflow}
    end
  end

  defp compact_audio(pcm) when byte_size(pcm) <= @maximum_chunk_bytes, do: [pcm]

  defp compact_audio(pcm) do
    <<chunk::binary-size(@maximum_chunk_bytes), rest::binary>> = pcm
    [chunk | compact_audio(rest)]
  end

  def generation_end(state) do
    case fetch(state, state.wire) do
      {:ok, response} -> {:ok, put_response(state, %{response | generation_done?: true})}
      :error -> {:ok, state}
    end
  end

  def model_end(state) do
    case fetch(state, state.wire) do
      {:ok, response} ->
        response = %{
          response
          | model_done?: true,
            played?: response.played? or not response.announced?
        }

        {:ok, retire(put_response(%{state | wire: nil}, response), response.ref)}

      :error ->
        {:ok, state}
    end
  end

  def grant(state, turn, output) when is_reference(output) do
    case fetch(state, turn) do
      {:ok, response} -> grant_response(state, response, output)
      :error -> {:error, :stale_response}
    end
  end

  defp grant_response(state, response, output) do
    cond do
      response.discarded? or response.played? or response.output_ref != nil ->
        {:error, :stale_response}

      not response.announced? ->
        {:error, :not_announced}

      state.active != nil ->
        {:error, :busy}

      true ->
        {:ok, put_response(%{state | active: response.ref}, %{response | output_ref: output})}
    end
  end

  def sent_audio(state, turn, output, credit) when is_reference(credit) do
    with {:ok, response} <- active_response(state, turn, output),
         %{queue: [_pcm | rest], awaiting: nil, discarded?: false} <- response do
      {:ok, put_response(state, %{response | queue: rest, awaiting: credit})}
    else
      _other -> {:error, :stale_credit}
    end
  end

  def ack_credit(state, output, credit) when is_reference(credit) do
    case fetch(state, state.active) do
      {:ok, %{output_ref: ^output, awaiting: ^credit} = response} ->
        {:ok, put_response(state, %{response | awaiting: nil})}

      _other ->
        {:error, :stale_credit}
    end
  end

  def completed(state, turn, output) do
    with {:ok, response} <- active_response(state, turn, output),
         %{queue: [], awaiting: nil, generation_done?: true, completed?: false} <- response do
      {:ok, put_response(state, %{response | completed?: true})}
    else
      _other -> {:error, :not_completed}
    end
  end

  def settle(state, turn, output) do
    with {:ok, response} <- active_response(state, turn, output) do
      if response.completed? do
        response = %{response | played?: true, queue: [], text: nil}
        {:ok, retire(put_response(%{state | active: nil}, response), turn)}
      else
        {:error, :not_completed}
      end
    end
  end

  def discard(state, turn) do
    case fetch(state, turn) do
      {:ok, response} ->
        response = %{
          response
          | discarded?: true,
            generation_done?: true,
            queue: [],
            text: nil,
            played?: response.played? or response.output_ref == nil
        }

        {:ok, retire(put_response(state, response), turn)}

      :error ->
        {:error, :stale_response}
    end
  end

  defp active_response(state, turn, output) do
    case fetch(state, turn) do
      {:ok, %{output_ref: ^output} = response} when state.active == turn -> {:ok, response}
      _other -> {:error, :stale_response}
    end
  end

  defp put_response(state, response),
    do: %{state | records: Map.put(state.records, response.ref, response)}

  defp retire(state, turn) do
    case fetch(state, turn) do
      {:ok, %{model_done?: true, played?: true}} ->
        %{state | records: Map.delete(state.records, turn)}

      _pending ->
        state
    end
  end
end
