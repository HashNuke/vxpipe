defmodule Vxpipe.Calls.OperatorLoginChallengeRepository do
  @moduledoc "Persistence port for durable one-time operator login challenges."

  alias Vxpipe.Calls.OperatorLoginChallenge

  @type context :: term()

  @callback insert(context(), OperatorLoginChallenge.t()) ::
              {:ok, OperatorLoginChallenge.t()} | {:error, term()}

  @callback consume(context(), binary(), binary()) ::
              :ok | {:error, term()}
end
