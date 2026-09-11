# Audio pipeline readiness

## 2026-09-11: child-ready barrier

The complete umbrella suite exposed a gateway audio-pipeline startup race while verifying the
streaming-recording runtime checkpoint. `AudioPipeline` announced readiness from the pipeline's
`handle_playing/2`, but a following push could reach its custom source before that child entered
playing state. Membrane correctly rejected the source's buffer action while stopped and terminated
the pipeline. The failure occurred in the existing two-packet accumulation test with
`Membrane.ActionError`; it was not caused by recording configuration.

The pipeline now tracks its nine named children and announces readiness only after every child has
reported playing. This matches the established readiness barrier used by the repository's outbound
Membrane pipelines. The public push contract and media chain are unchanged.

The pre-change failure is retained in `/tmp/vxpipe-m19-runtime-full-test.log` for this workspace. The
focused gateway test is the regression boundary:

```text
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/webrtc/audio_pipeline_test.exs --max-cases 1
# 4 tests, 0 failures
```

The complete umbrella rerun passed all 818 tests. Root formatting, compilation with warnings as
errors, strict Credo over 642 source files, and the unused-dependency check also pass.
