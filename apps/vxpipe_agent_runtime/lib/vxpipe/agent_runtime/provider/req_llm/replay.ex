defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.Replay do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Provider.ReqLLM.{
    ChatReasoningReplay,
    GoogleReplay,
    OpenAIReplay,
    RouterReplay
  }

  def capture(%LLMDB.Model{provider: provider} = model, response, text, calls, context)
      when provider in [:openrouter, :zenmux],
      do: RouterReplay.capture(model, response, text, calls, context)

  def capture(model, response, text, calls, _context), do: capture(model, response, text, calls)

  def restore(projected, source, model, options) do
    case source.provider_replay do
      %{"format" => "router_chat_v1"} -> RouterReplay.restore(projected, source, model, options)
      _other -> restore(projected, source, model)
    end
  end

  def capture(%LLMDB.Model{provider: :google} = model, response, text, calls),
    do: GoogleReplay.capture(model, response, text, calls)

  def capture(%LLMDB.Model{provider: provider} = model, response, text, calls)
      when provider in [:deepseek, :fireworks_ai],
      do: ChatReasoningReplay.capture(model, response, text, calls)

  def capture(model, response, text, calls),
    do: OpenAIReplay.capture(model, response, text, calls)

  def restore(
        projected,
        %{provider_replay: %{"format" => "google_generate_content_v1"}} = source,
        model
      ),
      do: GoogleReplay.restore(projected, source, model)

  def restore(
        projected,
        %{provider_replay: %{"format" => "chat_reasoning_v1"}} = source,
        model
      ),
      do: ChatReasoningReplay.restore(projected, source, model)

  def restore(projected, source, model), do: OpenAIReplay.restore(projected, source, model)
end
