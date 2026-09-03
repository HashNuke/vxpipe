# Vxpipe

**TODO: Add description**

## Development

The development stack requires Elixir, Node.js and npm, and
[Goreman](https://github.com/mattn/goreman). Vite 8 requires Node.js 20.19.x or
Node.js 22.12 or newer.

Install the sample frontend dependencies once:

```shell
npm install --prefix samples
```

Then start the Vxpipe umbrella and sample frontend together:

```shell
bin/dev
```

Goreman runs the `call_engine` and `gateway` applications in one BEAM instance
and serves the Vite playground at <http://localhost:5173>. The playground sends
`/api` requests to the gateway at `http://127.0.0.1:4000` by default. Set
`VXPIPE_GATEWAY_URL` to change the proxy target.

The first playground uses the Pipecat Voice UI Kit console and Small WebRTC. It
targets `/api/rtvi/offer`; the gateway must implement that endpoint before a
voice connection can succeed. Set `VITE_VXPIPE_RTVI_OFFER_URL` in
`samples/.env.local` to test a different offer endpoint.
