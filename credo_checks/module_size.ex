defmodule Vxpipe.Credo.Check.Design.ModuleSize do
  @moduledoc false

  use Credo.Check,
    id: "VX2001",
    category: :design,
    base_priority: :high,
    param_defaults: [max_lines: 800],
    explanations: [
      check: """
      Reports source modules that have grown beyond the repository's emergency
      size ceiling. Line count is only a backstop: passing this check does not
      establish that a module follows the Single Responsibility Principle.
      """,
      params: [max_lines: "Maximum physical lines allowed in one module file."]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    max_lines = Params.get(params, :max_lines, __MODULE__)
    actual_lines = source_file |> SourceFile.lines() |> length()

    if actual_lines > max_lines do
      [
        format_issue(
          issue_meta,
          message:
            "Module file is too large (max is #{max_lines} lines, was #{actual_lines}); split cohesive responsibilities.",
          line_no: 1,
          trigger: "defmodule"
        )
      ]
    else
      []
    end
  end
end
