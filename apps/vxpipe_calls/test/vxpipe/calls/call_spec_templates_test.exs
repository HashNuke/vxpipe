defmodule Vxpipe.Calls.CallSpecTemplatesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.CallSpecTemplate

  describe "template loading" do
    @describetag :tmp_dir

    test "rejects output that bypasses the json filter", %{tmp_dir: dir} do
      write_template(dir, ~s({"schema_version": "20261004.01", "name": "{{ name }}"}))

      assert {:error, {:invalid_call_spec_template, "sample", :unescaped_output}} =
               CallSpecTemplate.load(Path.join(dir, "sample"))
    end

    test "rejects unescaped output inside blocks and filters after json", %{tmp_dir: dir} do
      for source <- [
            ~s({% for x in list %}{{ x }}{% endfor %}),
            ~s({% for x in list %}{% else %}{{ name }}{% endfor %}),
            ~s({% if name %}{% elsif name %}{% else %}{{ name }}{% endif %}),
            ~s({% unless name %}{{ name }}{% endunless %}),
            ~s({% case name %}{% when "a" %}{{ name }}{% endcase %}),
            ~s({% capture text %}{{ name }}{% endcapture %}{{ text }}),
            ~s({{ name | json | append: "x" }})
          ] do
        write_template(dir, source)

        assert {:error, {:invalid_call_spec_template, "sample", :unescaped_output}} =
                 CallSpecTemplate.load(Path.join(dir, "sample")),
               source
      end
    end

    test "rejects tags that can emit text or read files", %{tmp_dir: dir} do
      for source <- [
            ~s({% echo name %}),
            ~s({% render "other" %}),
            ~s({% raw %}{{ name }}{% endraw %}),
            ~s({% increment n %})
          ] do
        write_template(dir, source)

        assert {:error, {:invalid_call_spec_template, "sample", :invalid_template_syntax}} =
                 CallSpecTemplate.load(Path.join(dir, "sample"))
      end
    end

    test "reports undefined template variables instead of rendering blanks", %{tmp_dir: dir} do
      write_template(dir, ~s({"schema_version": "20261004.01", "name": {{ nmae | json }}}))
      assert {:ok, template} = CallSpecTemplate.load(Path.join(dir, "sample"))

      assert {:error, {:call_spec_template_render_failed, _errors}} =
               CallSpecTemplate.render(template, %{})
    end

    test "rejects a manifest whose ID does not match its directory", %{tmp_dir: dir} do
      write_template(dir, "{}", %{"id" => "other"})

      assert {:error, {:invalid_call_spec_template, "sample", :invalid_manifest}} =
               CallSpecTemplate.load(Path.join(dir, "sample"))
    end
  end

  defp write_template(dir, template, manifest_overrides \\ %{}) do
    path = Path.join(dir, "sample")
    File.mkdir_p!(path)

    manifest =
      Map.merge(
        %{
          "id" => "sample",
          "name" => "Sample",
          "description" => "Sample template",
          "template_version" => 1,
          "call_spec_schema_version" => "20261004.01",
          "inputs" => %{
            "type" => "object",
            "properties" => %{"name" => %{"type" => "string", "default" => "Sample"}}
          },
          "examples" => [%{}]
        },
        manifest_overrides
      )

    File.write!(Path.join(path, "manifest.json"), JSON.encode!(manifest))
    File.write!(Path.join(path, "template.json.liquid"), template)
  end
end
