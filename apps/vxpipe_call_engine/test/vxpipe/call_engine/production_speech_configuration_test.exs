defmodule Vxpipe.CallEngine.ProductionSpeechConfigurationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, PlanStartup}

  @configuration Path.expand("../../../../../config/config.exs", __DIR__)

  test "a phone receptionist does not require application speech configuration" do
    plan = compile_plan(source())

    settings =
      @configuration
      |> Config.Reader.read!(env: :prod, target: :host)
      |> Keyword.fetch!(:vxpipe_call_engine)
      |> Keyword.fetch!(Vxpipe.CallEngine.Application)

    for kind <- [:speech_to_text, :text_to_speech, :speech_to_speech] do
      refute Keyword.has_key?(settings, kind)
    end

    assert :ok = PlanStartup.validate(plan, settings)
  end

  test "room startup ignores retired application speech settings" do
    source = source()
    morse = %{provider: "morse", model: "morse", options: %{}}

    source =
      source
      |> put_in([:defaults, :capabilities, :model_inference], %{
        provider: "fixture",
        model: "test"
      })
      |> put_in([:participants, "caller", :capabilities, :speech_to_text], morse)
      |> put_in([:participants, "receptionist", :capabilities, :text_to_speech], morse)
      |> put_in([:participants, "receptionist", :first_message], %{mode: "wait_for_input"})

    plan = compile_plan(source)
    previous = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, previous)
    end)

    poisoned =
      Keyword.merge(previous,
        speech_to_text: :obsolete,
        text_to_speech: :obsolete,
        speech_to_speech: :obsolete
      )

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, poisoned)

    assert {:ok, room} = Vxpipe.CallEngine.start_call(plan)

    on_exit(fn ->
      Vxpipe.CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id)
    end)

    assert :ok = Vxpipe.CallEngine.TestCallStartup.await_prepared(plan)
  end

  defp compile_plan(source) do
    assert {:ok, spec} = CallSpec.new(source, resource_id: "receptionist", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "receptionist", revision: 1}, transport: %{type: "telephony"}},
               tenant_id: "tenant-phone",
               actor_id: "actor-phone"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})

    plan
  end

  defp source do
    %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "receptionist"},
      defaults: %{
        capabilities: %{
          model_inference: %{
            provider: "google",
            model: "gemini-2.5-flash",
            credential_name: "google"
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{
            service: "telnyx",
            mode: "receive",
            admission: "start_call",
            number: "+15550001000"
          },
          capabilities: %{
            speech_to_text: %{
              provider: "elevenlabs",
              model: "scribe_v2_realtime",
              credential_name: "elevenlabs"
            }
          }
        },
        "receptionist" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "fixed", text: "Hello! How can I help?"},
          capabilities: %{
            text_to_speech: %{
              provider: "elevenlabs",
              model: "eleven_flash_v2_5",
              credential_name: "elevenlabs",
              options: %{voice: "JBFqnCBsd6RMkjVDRZzb"}
            }
          },
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
