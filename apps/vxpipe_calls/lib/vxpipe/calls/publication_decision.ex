defmodule Vxpipe.Calls.PublicationDecision do
  @moduledoc "A fake-clock-testable reporting-window decision for one ended call."

  alias Vxpipe.Calls.PublicationComponent

  @enforce_keys [
    :action,
    :completeness,
    :ended_at,
    :deadline,
    :assessed_at,
    :components,
    :pending_components,
    :incomplete_components
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          action: :wait | :publish,
          completeness: :complete | :incomplete,
          ended_at: DateTime.t(),
          deadline: DateTime.t(),
          assessed_at: DateTime.t(),
          components: [PublicationComponent.t()],
          pending_components: [String.t()],
          incomplete_components: [String.t()]
        }
end
