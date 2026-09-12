defmodule Vxpipe.Calls.CallDetailsSnapshot do
  @moduledoc "Canonical immutable contents proposed for one call-details publication record."

  alias Vxpipe.Calls.{
    CallDetailsSource,
    CanonicalJSON,
    PublicationComponent,
    PublicationDecision
  }

  @schema_version "20260912.01"

  @derive {Inspect, except: [:contents, :document]}
  @enforce_keys [
    :publication_id,
    :recorded_at,
    :filename,
    :completeness,
    :source_digest,
    :checksum,
    :contents,
    :document
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          publication_id: String.t(),
          recorded_at: DateTime.t(),
          filename: String.t(),
          completeness: :complete | :incomplete,
          source_digest: binary(),
          checksum: binary(),
          contents: binary(),
          document: map()
        }

  @spec new(String.t(), DateTime.t(), CallDetailsSource.t(), PublicationDecision.t()) ::
          {:ok, t()} | {:error, :invalid_call_details_snapshot}
  def new(
        publication_id,
        %DateTime{} = recorded_at,
        %CallDetailsSource{} = source,
        %PublicationDecision{action: :publish} = decision
      )
      when is_binary(publication_id) and publication_id != "" and byte_size(publication_id) <= 256 do
    if utc?(recorded_at) do
      build(publication_id, recorded_at, source, decision)
    else
      {:error, :invalid_call_details_snapshot}
    end
  rescue
    _error -> {:error, :invalid_call_details_snapshot}
  end

  def new(_publication_id, _recorded_at, _source, _decision),
    do: {:error, :invalid_call_details_snapshot}

  defp build(publication_id, recorded_at, source, decision) do
    components = Map.new(decision.components, &{&1.name, PublicationComponent.document(&1)})
    source_document = CallDetailsSource.document(source)

    document =
      source_document
      |> Map.put("schema_version", @schema_version)
      |> Map.put("publication", publication(publication_id, recorded_at, decision, components))

    contents = CanonicalJSON.encode!(document)

    {:ok,
     %__MODULE__{
       publication_id: publication_id,
       recorded_at: recorded_at,
       filename: filename(recorded_at),
       completeness: decision.completeness,
       source_digest:
         :crypto.hash(
           :sha256,
           CanonicalJSON.encode!(%{
             "schema_version" => @schema_version,
             "components" => components,
             "source" => source_document
           })
         ),
       checksum: :crypto.hash(:sha256, contents),
       contents: contents,
       document: document
     }}
  end

  defp publication(publication_id, recorded_at, decision, components) do
    %{
      "id" => publication_id,
      "recorded_at" => DateTime.to_iso8601(recorded_at),
      "completeness" => Atom.to_string(decision.completeness),
      "components" => components
    }
  end

  defp filename(recorded_at) do
    milliseconds = recorded_at.microsecond |> elem(0) |> div(1_000)

    base =
      recorded_at
      |> DateTime.to_naive()
      |> Calendar.strftime("%Y%m%d%H%M%S")

    "details-#{base}#{milliseconds |> Integer.to_string() |> String.pad_leading(3, "0")}.json"
  end

  defp utc?(recorded_at), do: recorded_at.utc_offset == 0 and recorded_at.std_offset == 0
end
