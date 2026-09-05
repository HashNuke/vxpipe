defmodule Vxpipe.CallEngine.Tool do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

  @callback definition() :: Definition.t()
  @callback execute(map(), Context.t()) :: {:ok, term()} | {:error, atom()}
end
