# Morse origin restart acceptance

Checkpoint G now has an explicitly tagged `morse_code_api_restart` integration
test. It builds a stdlib-only Go test proxy and starts two instances of the
selected Morse API binary on separate ephemeral loopback ports. One proxy is
HTTP and the other TLS. Only origin labels, methods and paths are observed;
headers, query strings and bodies never enter its evidence stream.

The test creates a uniquely named PostgreSQL database using the configured PG
connection, applies existing migrations and seeds one encrypted platform service
and one published call through ordinary Calls APIs. Independent `mix run`
processes then fetch that same service and publication for HTTP, HTTPS/WSS and
HTTP rollback. Credential ID/version and source digest remain unchanged; the
fixture never republishes during switching. Each process probes discovery and
service reachability, recognizes independently generated E E through the room,
and decodes its Go-generated TEST reply. The test observes every request at the
selected origin, not just a constructor URL. No production runtime code changed.

The TLS fixture generates a root CA and a separately signed server certificate.
Only the fresh TLS test VM loads that root through Erlang's
[`cacerts_load/1`](https://www.erlang.org/doc/apps/public_key/public_key.html#cacerts_load/1).
The ordinary Req/Mint and speech socket paths keep peer verification enabled.
A fresh VM without the fixture CA rejects both HTTPS and WSS. Inspected the
installed Mint source and OTP 28.5 certificate loader as well as the official
public_key reference; no CA files or TLS settings on the development host were
changed.

Initial runs exposed fixture assumptions: a fixed count of four requests was
too strict because session preparation may create multiple allocations. The
assertion now requires exactly the expected route families and checks the origin
of every request. A self-signed server certificate produced `selfsigned_peer`,
including after loading it as a CA. Using an actual root/leaf chain fixed the
fixture without disabling verification. The complete cutover/rollback test then
passed in 21.2 seconds against Go `b922e71`. Discovery and the reachability probe
were then changed to use the decrypted persisted credential, as ordinary room
startup does; the final test passes in 20.9 seconds (seed 523186).

The fixture closes its proxies and sends SIGTERM to both owned Go processes;
stdin EOF also invokes cleanup if the test owner exits. The database drop is
registered only after the uniquely generated database is confirmed created.
Post-run process and PostgreSQL checks found no leftover Morse fixture processes
or databases. The existing main-branch live-test reservation was preserved by
using a separate local-only runner state directory and a comment-only credential
file. The protected live-provider file was not accessed.

Root formatting, warnings-as-errors compilation, strict Credo and unused-dependency
checks pass; the Go fixture builds and vets. The STT integration umbrella run
completed with explicit exit status zero: 3,841 tests, zero failures and 148
excluded. This verifies the committed STT runtime integration; the separately
selected local restart test supplies network/TLS evidence excluded from that run.
No speech state-machine implementation changed in this test-only checkpoint.

Design review: temporary Vxpipe persistence is necessary to prove actual service
and publication reuse; it does not introduce storage in Go. The two servers,
certificate trust and database are fixture-owned. No real credentials, hosted
service or paid model are required. G's catalog/startup/restart and origin-switch
tasks are now complete; room failure/revocation/replacement and rendered
transcript/error acceptance remain. H and I are still open.

To reproduce, first build the service from its separate Go checkout:

```sh
go build -o /tmp/morsecode-audio-restart ./cmd/morsecode-audio
```

Then from Vxpipe, with Go on PATH and the local PostgreSQL role prepared by
`bin/setup` (including CREATEDB). The fixture selects its own database name using
PG connection settings; it does not reuse `VXPIPE_TEST_DATABASE_URL`:

```sh
printf '# The local test provisions synthetic keys.\n' > /tmp/morse-restart.env
morse_restart_state="$(mktemp -d)"
VXPIPE_LIVETESTS_STATE_DIR="$morse_restart_state" \
VXPIPE_LIVE_PROVIDERS_ENV_FILE=/tmp/morse-restart.env \
MORSE_CODE_API_TEST_BINARY=/tmp/morsecode-audio-restart \
  bin/livetests run --only morse_code_api_restart \
  apps/vxpipe_console/test/integration/morse_code_api_origin_restart_test.exs
VXPIPE_LIVETESTS_STATE_DIR="$morse_restart_state" bin/livetests release
```
