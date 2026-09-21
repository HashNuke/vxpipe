# Setup catalog and runtime capability metadata

The Console setup catalog currently describes provider product offerings and future integrations.
Its capability badges are static frontend data, separate from the implemented capability manifests
in `Vxpipe.Providers.Registry`. For example, the setup dialog labels Google AI Studio with speech
capabilities and Rime with text-to-speech, while Vxpipe currently declares only their credential
schema/test capabilities. Google model inference uses the shared ReqLLM runtime. Connecting a
credential therefore does not make every badge usable by a call plan.

This difference predates the provider-package migration and does not change the call runtime. The
setup catalog has a separate `sampleCapabilities` filter, so sample recipes only use the configured
Deepgram speech and shared model capabilities. The backend manifest remains the authoritative
answer for Vxpipe-owned STT, TTS and telephony implementations.

To align the setup UI in a future slice, expose the implemented capability catalog to the Console
and separate those labels from future/provider-product offerings. Keep model inference's shared
ReqLLM support distinct. Verify provider cards, connection dialogs, sample readiness and a
rendered desktop/mobile pass. Do not infer runtime readiness from a manifest entry; configured
credentials and owning-runtime startup still decide whether a call can use it.

Verification: the provider registry contract suite asserts exact supported and absent
capabilities. On 2026-09-21, the rendered Google connection dialog displayed the four static
product badges at desktop and mobile widths, while the registry declared credential schema and
testing only. No credential was submitted during that inspection.
