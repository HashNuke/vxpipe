# Participant description review

- User asked to commit the accumulated editor changes and questioned whether
  participant descriptions only help people reading the Console.
- Traced optional description parsing in CallSpec.Participant, copying into
  ResolvedCallPlan.Participant and transfer bindings in CallSpecCompiler, and
  ParticipantTransfer.destination_schema/1 / describe_target/1.
- Transfer tool destination text includes each permitted participant's key and
  optional description. This applies to AI and human destinations; absent
  descriptions fall back to the key. ToolDescriptors passes this definition to
  the agent runtime. Existing descriptions therefore affect model context.
- Kept the existing UI and source contract. Added a short guide clarification
  distinguishing description from an agent prompt or human transfer notice.
- Documentation-only verification: checked the guide against these implementation
  boundaries and ran the diff whitespace check. No runtime changes or new tests.
- Committed the accumulated implementation as separate model-default and voice
  picker checkpoints, including their tests, docs and labnotes. Their previous
  frontend/browser checks pass; known Ortex and configured ElevenLabs failures
  are recorded in the checkpoint evidence. No live-provider environment was read.
- Left the pre-existing untracked vxpipe-docs directory outside these commits.
