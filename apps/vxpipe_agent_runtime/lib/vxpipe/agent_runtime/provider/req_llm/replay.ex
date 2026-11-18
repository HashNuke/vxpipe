defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.Replay do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Provider.ReqLLM.{GoogleReplay, OpenAIReplay}

  def capture(%LLMDB.Model{provider: :google} = model, response, text, calls),
    do: GoogleReplay.capture(model, response, text, calls)

  def capture(model, response, text, calls),
    do: OpenAIReplay.capture(model, response, text, calls)

  def restore(
        projected,
        %{provider_replay: %{"format" => "google_generate_content_v1"}} = source,
        model
      ),
      do: GoogleReplay.restore(projected, source, model)

  def restore(projected, source, model), do: OpenAIReplay.restore(projected, source, model)
end
