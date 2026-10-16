# After-hours dental line

A caller reaches a dental clinic outside office hours. The `receptionist` agent:

- collects appointment requests (new, reschedule or cancel) into the
  `appointment_request` call variables, reads them back and promises a callback;
- transfers billing and insurance questions to the `billing` agent, which can hand
  the caller back;
- transfers dental emergencies to the `on_call_dentist` human.

This exercises the following:

- a fixed opening message;
- agent-to-agent handoff in both directions;
- a human transfer;
- variable writes and reads;
- hangup.

Spoken names, phone numbers and times, plus deciding whether a call is an emergency,
make differences between providers easy to hear.

## Inputs

| Input | Required | Purpose |
| --- | --- | --- |
| `voice_pipeline` | yes | `cascade` or `speech_to_speech` |
| `speech_to_text`, `model_inference`, `text_to_speech` | for `cascade` | Capability selections: `provider`, `model`, optional `credential_name`, `options` and, for STT only, `vad` |
| `speech_to_speech` | for `speech_to_speech` | Capability selection. `speech_to_text` is optional here |
| `output_speech_to_text` | no | `speech_to_speech` only: transcribes agent audio when the model provides no output transcript |
| `telephony` | no | `service`, `inbound_number` and `on_call_number`. When omitted, the caller and the on-call dentist use browser connections |
| `name` | no | Call spec name. Defaults to `After-hours dental line` |
| `clinic_name`, `office_hours` | no | Text the agents speak |

Credential names refer to the tenant's configured credentials, and `telephony.service`
refers to a configured telephony service. Missing ones are rejected on save or reported
in the install result's `validation_errors`.

## Example

```elixir
alias Vxpipe.Calls

Calls.install_call_spec_template(
  Vxpipe.Calls.InstallationOperator.authority(),
  tenant_key,
  "dental-after-hours",
  %{
    "name" => "Dental line (Deepgram + Gemini, phone)",
    "telephony" => %{
      "service" => "clinic-phone",
      "inbound_number" => "+15550001000",
      "on_call_number" => "+15550002000"
    },
    "voice_pipeline" => "cascade",
    "speech_to_text" => %{"provider" => "deepgram", "model" => "flux-general-en", "credential_name" => "deepgram"},
    "model_inference" => %{"provider" => "google", "model" => "gemini-2.5-flash", "credential_name" => "google"},
    "text_to_speech" => %{"provider" => "deepgram", "model" => "flux", "credential_name" => "deepgram", "options" => %{"voice" => "haley"}}
  },
  publish: true
)
```

Every install creates a new call spec. To compare providers, install it again with
different selections and a descriptive `name`.
