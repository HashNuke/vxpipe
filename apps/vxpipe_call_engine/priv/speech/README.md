# Local speech activity model

`silero_v6.2.3.onnx` is the unmodified CPU inference model from
[Silero v6.2.3](https://github.com/snakers4/silero-vad/tree/5cd7945676eb32225748052e2e6a0580e4686a08),
distributed under the adjacent `LICENSE.silero` notice.

SHA-256: `1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3`.
The loader verifies this digest before loading the packaged file. Application
startup does not load or download the model. A named lazy cache shares only the
public CPU model resource. Each allocation owns its inference worker and private
stream state in a separate supervision tree; the cache receives no PCM.

The stream wrapper accepts raw mono signed little-endian 16-bit PCM at 16 kHz.
Only complete 512-sample frames are classified. Each stream retains its own
64-sample context, recurrent state and incomplete frame; resetting drops them.
Acoustic boundaries require confirmed classifications and are separate from
transcript recognition and semantic completion.
