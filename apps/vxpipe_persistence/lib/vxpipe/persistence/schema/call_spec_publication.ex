defmodule Vxpipe.Persistence.Schema.CallSpecPublication do
  use Ecto.Schema

  schema "call_spec_publications" do
    field(:version, :integer)
    field(:published_at, :utc_datetime_usec)
    belongs_to(:call_spec, Vxpipe.Persistence.Schema.CallSpec)
    belongs_to(:call_spec_revision, Vxpipe.Persistence.Schema.CallSpecRevision)
  end
end
