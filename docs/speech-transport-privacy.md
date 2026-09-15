# Speech transport privacy

The installed WebSockex 0.5.1 client emits its full connection, including authorization
headers, in connection and frame telemetry. Local STT and TTS wire tests reproduced
this disclosure. Vxpipe's Deepgram transports now use the existing Mint/Mint.WebSocket
dependencies directly, keeping authentication in the HTTP upgrade only.

## Responsibility and behavior

`SocketConnection` owns connection, upgrade and frame encoding/decoding. `Socket` owns
the supervised process, close, ping replies and TTS acknowledgements. The existing
Flux facades retain their speech transport contracts. Connect, upgrade, send and output
acknowledgement are bounded. Failures return safe reasons without provider response data.
The transport does not reconnect automatically.

TTS acknowledgements are asynchronous so closing a connection remains responsive while
output is pending. Active-once socket delivery pauses reads while audio is unacknowledged;
the existing 15-second output deadline closes a stalled stream. Upgrade handling preserves
provider frames that arrive in the same read as the HTTP upgrade. Routine inspection and
crash status exclude buffered payloads; STT capability state inspection also excludes its
connection headers and transport settings.

Filtering one telemetry subscriber was rejected because other subscribers would still
receive the credentials. Patching the installed dependency was rejected because the fix
would not survive a dependency reinstall. Mint owns the WebSocket protocol implementation;
Vxpipe owns its speech lifecycle. ReqLLM still needs WebSockex transitively, so its lock
entry remains unchanged.

## Verification

The explicitly tagged local integration tests cover wire authentication, telemetry privacy,
text/binary frames, ping/pong, close, acknowledgement ownership and failure, the output
deadline, rejected/stalled upgrades, coalesced initial frames and private state inspection.
They use synthetic credentials and local servers. No live provider acceptance is claimed.
Red/green results and checkpoint verification are recorded in the
[transport labnote](../labnotes/20260915-1902-speech-transport-privacy.md).
