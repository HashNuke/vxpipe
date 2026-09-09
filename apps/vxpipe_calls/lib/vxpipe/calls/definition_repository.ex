defmodule Vxpipe.Calls.DefinitionRepository do
  @moduledoc "Persistence port for immutable definitions and deployment routes."

  alias Vxpipe.Calls.{DefinitionRevision, ParticipantRoute}

  @type context :: term()

  @callback next_revision(context(), String.t(), String.t()) ::
              {:ok, pos_integer()} | {:error, term()}
  @callback insert_revision(
              context(),
              String.t(),
              DefinitionRevision.t(),
              [ParticipantRoute.t()]
            ) :: {:ok, DefinitionRevision.t()} | {:error, term()}
  @callback fetch_revision(context(), String.t(), String.t(), pos_integer()) ::
              {:ok, DefinitionRevision.t()} | {:error, :not_found}
  @callback publish_revision(context(), String.t(), String.t(), pos_integer(), DateTime.t()) ::
              {:ok, DefinitionRevision.t()} | {:error, term()}
  @callback resolve_route(context(), String.t(), String.t()) ::
              {:ok, ParticipantRoute.t()} | {:error, :route_unavailable}
end
