defmodule Vxpipe.Calls.CallSpecTemplatesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec
  alias Vxpipe.Calls.{CallSpecTemplate, CallSpecTemplates}

  @cascade %{
    "voice_pipeline" => "cascade",
    "speech_to_text" => %{"provider" => "morse", "model" => "morse"},
    "model_inference" => %{"provider" => "fixture", "model" => "fixture"},
    "text_to_speech" => %{"provider" => "morse", "model" => "morse"}
  }

  describe "checked-in library" do
    test "every manifest example renders a call spec accepted by the production parser" do
      assert {:ok, templates} = CallSpecTemplates.list()
      assert "dental-after-hours" in Enum.map(templates, & &1.id)

      for template <- templates do
        assert template.examples != [], "#{template.id} needs at least one example"

        for inputs <- template.examples do
          assert {:ok, source} = CallSpecTemplate.render(template, inputs)
          assert source["schema_version"] == template.call_spec_schema_version
          assert {:ok, %CallSpec{}} = CallSpec.new(source, resource_id: "sample", revision: 1)
        end
      end
    end
  end

  describe "dental-after-hours" do
    test "applies manifest defaults and selects browser connections without telephony" do
      assert {:ok, source} = CallSpecTemplates.render("dental-after-hours", @cascade)

      assert source["name"] == "After-hours dental line"
      assert source["defaults"]["capabilities"]["model_inference"] == @cascade["model_inference"]
      refute Map.has_key?(source["defaults"]["capabilities"], "speech_to_speech")

      assert %{"service" => "web", "admission" => "start_call"} =
               source["participants"]["caller"]["connection"]

      assert %{"service" => "web", "admission" => "transfer"} =
               source["participants"]["on_call_dentist"]["connection"]
    end

    test "routes the caller and on-call transfer through the selected telephony service" do
      inputs =
        Map.put(@cascade, "telephony", %{
          "service" => "clinic-phone",
          "inbound_number" => "+15550001000",
          "on_call_number" => "+15550002000"
        })

      assert {:ok, source} = CallSpecTemplates.render("dental-after-hours", inputs)

      assert source["participants"]["caller"]["connection"] == %{
               "service" => "clinic-phone",
               "mode" => "receive",
               "admission" => "start_call",
               "number" => "+15550001000"
             }

      assert source["participants"]["on_call_dentist"]["connection"] == %{
               "service" => "clinic-phone",
               "mode" => "dial",
               "number" => "+15550002000"
             }
    end

    test "keeps text inputs as JSON strings even when they contain JSON syntax" do
      name = ~s(Dr. "Smile" O'Neil\n}, "x": {)
      inputs = Map.merge(@cascade, %{"clinic_name" => name, "name" => name})

      assert {:ok, source} = CallSpecTemplates.render("dental-after-hours", inputs)
      assert source["name"] == name
      assert source["participants"]["receptionist"]["prompt"] =~ name
      assert source["participants"]["receptionist"]["first_message"]["text"] =~ name
    end

    test "renders speech-to-speech over telephony without cascade selections" do
      inputs = %{
        "voice_pipeline" => "speech_to_speech",
        "speech_to_speech" => %{"provider" => "morse", "model" => "morse"},
        "telephony" => %{
          "service" => "clinic-phone",
          "inbound_number" => "+15550001000",
          "on_call_number" => "+15550002000"
        }
      }

      assert {:ok, source} = CallSpecTemplates.render("dental-after-hours", inputs)

      assert source["defaults"]["capabilities"] == %{
               "speech_to_speech" => %{"provider" => "morse", "model" => "morse"}
             }

      assert source["participants"]["on_call_dentist"]["connection"]["mode"] == "dial"
    end

    test "passes an output transcription fallback to speech-to-speech agents" do
      silent = %{
        "provider" => "morse",
        "model" => "morse",
        "options" => %{"output_transcript" => false}
      }

      fallback = %{"provider" => "morse", "model" => "morse"}

      inputs = %{
        "voice_pipeline" => "speech_to_speech",
        "speech_to_speech" => silent,
        "output_speech_to_text" => fallback
      }

      assert {:ok, source} = CallSpecTemplates.render("dental-after-hours", inputs)
      assert source["defaults"]["capabilities"]["output_speech_to_text"] == fallback
    end

    test "rejects inputs that do not match the manifest schema" do
      phone = %{
        "service" => "clinic-phone",
        "inbound_number" => "+15550001000",
        "on_call_number" => "+15550002000"
      }

      for inputs <- [
            Map.put(@cascade, "telephony", %{phone | "inbound_number" => "555-0100"}),
            Map.put(@cascade, "telephony", %{phone | "service" => "web"}),
            Map.put(@cascade, "output_speech_to_text", %{
              "provider" => "morse",
              "model" => "morse"
            }),
            Map.delete(@cascade, "model_inference"),
            Map.put(@cascade, "unexpected", true),
            Map.put(@cascade, "speech_to_speech", %{"provider" => "morse", "model" => "morse"}),
            Map.put(@cascade, "telephony", %{"service" => "clinic-phone"})
          ] do
        assert {:error, {:invalid_call_spec_template_inputs, errors}} =
                 CallSpecTemplates.render("dental-after-hours", inputs)

        assert %{"valid" => false} = errors
      end
    end

    test "reports call spec validation failures from the rendered source" do
      inputs = put_in(@cascade, ["model_inference", "provider"], "unknown-provider")

      assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec}} =
               CallSpecTemplates.render("dental-after-hours", inputs)
    end
  end

  describe "install" do
    setup do
      alias Vxpipe.Calls.{Administration, Principal, TestMemoryRepository}
      repository = start_supervised!(TestMemoryRepository)

      options = [
        credential_repository: {TestMemoryRepository, repository},
        call_spec_repository: {TestMemoryRepository, repository},
        registries: %{host_tools: %{}}
      ]

      {:ok, tenant, _key} = Administration.bootstrap_tenant("Templates", [:admin], options)
      author = %Principal{tenant_key: tenant.key, api_key_id: "key", scopes: MapSet.new([:admin])}
      %{options: options, tenant: tenant.key, author: author}
    end

    test "creates a new call spec on every install, even for the same inputs", context do
      %{options: options, tenant: tenant, author: author} = context

      assert {:ok, %{call_spec_id: first, revision: 1, published: false}} =
               CallSpecTemplates.install(author, tenant, "dental-after-hours", @cascade, options)

      assert {:ok, %{call_spec_id: second, revision: 1, published: true}} =
               CallSpecTemplates.install(
                 author,
                 tenant,
                 "dental-after-hours",
                 @cascade,
                 Keyword.put(options, :publish, true)
               )

      assert first != second
      assert {:ok, rendered} = CallSpecTemplates.render("dental-after-hours", @cascade)

      for id <- [first, second] do
        assert {:ok, stored} = Vxpipe.Calls.CallSpecs.fetch(tenant, id, 1, options)
        assert stored.source == rendered
        assert {:error, :not_found} = Vxpipe.Calls.CallSpecs.fetch(tenant, id, 2, options)
      end
    end

    test "stores nothing when the rendering fails tenant validation", context do
      %{options: options, tenant: tenant, author: author} = context

      silent = %{
        "voice_pipeline" => "speech_to_speech",
        "speech_to_speech" => %{
          "provider" => "morse",
          "model" => "morse",
          "options" => %{"output_transcript" => false}
        }
      }

      assert {:error, {:call_spec_template_invalid, [_ | _]}} =
               CallSpecTemplates.install(author, tenant, "dental-after-hours", silent, options)

      corrected =
        Map.put(silent, "output_speech_to_text", %{"provider" => "morse", "model" => "morse"})

      assert {:ok, %{revision: 1, published: true}} =
               CallSpecTemplates.install(
                 author,
                 tenant,
                 "dental-after-hours",
                 corrected,
                 Keyword.put(options, :publish, true)
               )
    end

    test "ignores a caller-supplied call spec ID", context do
      %{options: options, tenant: tenant, author: author} = context
      other = Map.put(@cascade, "name", "Unrelated spec")

      assert {:ok, %{call_spec_id: unrelated}} =
               CallSpecTemplates.install(author, tenant, "dental-after-hours", other, options)

      assert {:ok, %{revision: 1, call_spec_id: id}} =
               CallSpecTemplates.install(
                 author,
                 tenant,
                 "dental-after-hours",
                 @cascade,
                 Keyword.put(options, :call_spec_id, unrelated)
               )

      assert id != unrelated
    end

    test "requires tenant authoring authority before rendering or storage", context do
      %{options: options, tenant: tenant, author: author} = context
      calls_only = %{author | scopes: MapSet.new([:calls])}

      assert {:error, :insufficient_scope} =
               CallSpecTemplates.install(calls_only, tenant, "missing", %{}, options)

      assert {:error, :authoring_authority_required} =
               CallSpecTemplates.install(nil, tenant, "dental-after-hours", @cascade, options)
    end
  end

  test "unknown template IDs are not found" do
    assert {:error, :call_spec_template_not_found} = CallSpecTemplates.render("missing", %{})
    assert {:error, :call_spec_template_not_found} = CallSpecTemplates.render("../x", %{})
  end

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
