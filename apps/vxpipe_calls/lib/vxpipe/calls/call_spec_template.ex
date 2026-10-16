defmodule Vxpipe.Calls.CallSpecTemplate do
  @moduledoc """
  One portable call spec template: a Liquid JSON document and a manifest whose
  `inputs` JSON Schema describes the values a tenant supplies when rendering it.
  """

  alias Solid.Tags
  alias Vxpipe.CallEngine.CallSpec
  alias Vxpipe.Calls.CallSpecTemplateFilters

  @manifest_file "manifest.json"
  @template_file "template.json.liquid"
  @id_pattern ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  # `echo`, `raw` and `render` are excluded so a `{{ ... | json }}` object is the only
  # way to emit a value and templates cannot read other files. Counters and cycles
  # are excluded because they emit text implicitly.
  @tags %{
    "#" => Tags.InlineCommentTag,
    "assign" => Tags.AssignTag,
    "break" => Tags.BreakTag,
    "capture" => Tags.CaptureTag,
    "case" => Tags.CaseTag,
    "comment" => Tags.CommentTag,
    "continue" => Tags.ContinueTag,
    "for" => Tags.ForTag,
    "if" => Tags.IfTag,
    "unless" => Tags.IfTag
  }

  @derive {Inspect, except: [:validator, :template]}
  @enforce_keys [
    :id,
    :name,
    :description,
    :template_version,
    :call_spec_schema_version,
    :input_schema,
    :examples,
    :validator,
    :template
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          template_version: pos_integer(),
          call_spec_schema_version: String.t(),
          input_schema: map(),
          examples: [map()],
          validator: JSV.Root.t(),
          template: Solid.Template.t()
        }

  @spec valid_id?(term()) :: boolean()
  def valid_id?(id), do: is_binary(id) and Regex.match?(@id_pattern, id)

  @doc "Loads the template stored in `directory`, whose basename is the template ID."
  @spec load(Path.t()) :: {:ok, t()} | {:error, {:invalid_call_spec_template, String.t(), atom()}}
  def load(directory) do
    id = Path.basename(directory)

    with {:ok, manifest} <- read_manifest(directory),
         {:ok, fields} <- manifest_fields(manifest, id),
         {:ok, validator} <- build_validator(fields.input_schema),
         {:ok, template} <- parse_template(directory),
         :ok <- escaped_outputs(template.parsed_template) do
      {:ok, struct!(__MODULE__, Map.merge(fields, %{validator: validator, template: template}))}
    else
      {:error, reason} -> {:error, {:invalid_call_spec_template, id, reason}}
    end
  end

  @doc """
  Renders call spec source from JSON-compatible inputs. The result has passed the
  production call spec parser; tenant services and credentials are checked on save.
  """
  @spec render(t(), map()) :: {:ok, map()} | {:error, term()}
  def render(%__MODULE__{} = template, inputs) when is_map(inputs) do
    with {:ok, inputs} <- json_inputs(inputs),
         :ok <- validate_inputs(template, inputs),
         {:ok, rendered} <- render_text(template, bindings(template, inputs)),
         {:ok, source} <- decode(rendered),
         :ok <- schema_version(template, source),
         {:ok, _call_spec} <-
           CallSpec.new(source, resource_id: "call-spec-template", revision: 1) do
      {:ok, source}
    end
  end

  def render(%__MODULE__{}, _inputs),
    do: {:error, {:invalid_call_spec_template_inputs, %{"valid" => false}}}

  defp read_manifest(directory) do
    with {:ok, text} <- read(Path.join(directory, @manifest_file)),
         {:ok, %{} = manifest} <- JSON.decode(text) do
      {:ok, manifest}
    else
      {:error, :missing_file} -> {:error, :missing_manifest}
      _invalid -> {:error, :invalid_manifest}
    end
  end

  defp manifest_fields(manifest, id) do
    with %{
           "id" => ^id,
           "name" => name,
           "description" => description,
           "template_version" => version,
           "call_spec_schema_version" => schema_version,
           "inputs" => %{"type" => "object"} = input_schema,
           "examples" => examples
         } <- manifest,
         true <- valid_id?(id),
         true <- is_binary(name) and is_binary(description),
         true <- is_integer(version) and version > 0,
         true <- CallSpec.supported_schema_version?(schema_version),
         true <- is_list(examples) and Enum.all?(examples, &is_map/1) do
      {:ok,
       %{
         id: id,
         name: name,
         description: description,
         template_version: version,
         call_spec_schema_version: schema_version,
         input_schema: input_schema,
         examples: examples
       }}
    else
      _invalid -> {:error, :invalid_manifest}
    end
  end

  defp build_validator(schema) do
    case JSV.build(schema, atoms: false, resolver: [], warnings: :silent) do
      {:ok, validator} -> {:ok, validator}
      {:error, _reason} -> {:error, :invalid_input_schema}
    end
  end

  defp parse_template(directory) do
    with {:ok, text} <- read(Path.join(directory, @template_file)),
         {:ok, template} <- Solid.parse(text, tags: @tags) do
      {:ok, template}
    else
      {:error, :missing_file} -> {:error, :missing_template}
      {:error, _reason} -> {:error, :invalid_template_syntax}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, _reason} -> {:error, :missing_file}
    end
  end

  # Captured and assigned text is not output until it passes through an object,
  # which this check covers wherever that object appears.
  defp escaped_outputs(%Solid.Object{filters: filters}) do
    case List.last(filters) do
      %Solid.Filter{function: "json"} -> :ok
      _other -> {:error, :unescaped_output}
    end
  end

  defp escaped_outputs(%Tags.CaptureTag{}), do: :ok
  defp escaped_outputs(%Tags.AssignTag{}), do: :ok

  defp escaped_outputs(%_{} = node),
    do: node |> Map.from_struct() |> Map.values() |> escaped_outputs()

  defp escaped_outputs(nodes) when is_list(nodes) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case escaped_outputs(node) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp escaped_outputs(node) when is_tuple(node), do: node |> Tuple.to_list() |> escaped_outputs()
  defp escaped_outputs(_value), do: :ok

  defp json_inputs(inputs) do
    {:ok, inputs |> JSON.encode!() |> JSON.decode!()}
  rescue
    _exception -> {:error, {:invalid_call_spec_template_inputs, %{"valid" => false}}}
  end

  defp validate_inputs(template, inputs) do
    case JSV.validate(inputs, template.validator, cast: false) do
      {:ok, _inputs} ->
        :ok

      {:error, error} ->
        {:error, {:invalid_call_spec_template_inputs, JSV.normalize_error(error, keys: :strings)}}
    end
  end

  # Every declared top-level input is bound, using its default or nil, so templates
  # can test optional inputs while strict rendering still rejects misspelled names.
  defp bindings(template, inputs) do
    template.input_schema
    |> Map.get("properties", %{})
    |> Map.new(fn {name, schema} -> {name, default(schema)} end)
    |> Map.merge(inputs)
  end

  defp default(%{"default" => value}), do: value
  defp default(_schema), do: nil

  defp render_text(template, bindings) do
    case Solid.render(template.template, bindings,
           custom_filters: CallSpecTemplateFilters,
           strict_variables: true,
           strict_filters: true
         ) do
      {:ok, rendered, []} -> {:ok, IO.iodata_to_binary(rendered)}
      {:ok, _rendered, errors} -> render_failed(errors)
      {:error, errors, _partial} -> render_failed(errors)
    end
  end

  defp render_failed(errors) do
    messages =
      Enum.map(errors, fn
        error when is_exception(error) -> Exception.message(error)
        error -> inspect(error)
      end)

    {:error, {:call_spec_template_render_failed, messages}}
  end

  defp decode(rendered) do
    case JSON.decode(rendered) do
      {:ok, %{} = source} -> {:ok, source}
      _invalid -> {:error, :call_spec_template_invalid_json}
    end
  end

  defp schema_version(%{call_spec_schema_version: version}, %{"schema_version" => version}),
    do: :ok

  defp schema_version(_template, _source), do: {:error, :call_spec_template_schema_mismatch}
end
