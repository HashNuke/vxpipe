# Get started with Docker

Docker is the primary way Vxpipe will be packaged for standalone deployment.
The planned image is `vxpipe/vxpipe`; the source repository remains
[`HashNuke/vxpipe`](https://github.com/HashNuke/vxpipe).

## Availability

Container packaging is not implemented yet. The README shows the planned command
shape, not a verified Docker installation for this checkout. To try Vxpipe now, follow
[Get started with Elixir](getting-started-elixir.md#run-the-voice-demo).

This guide will provide the image tag, configuration, provider-key setup, and
commands to start your first call when the Docker package is ready. The
[delivery milestone](milestones/embedded-and-container-delivery.md) tracks that work.

## Prepare your configuration

The planned quickstart injects platform settings from an ignored `.env` based on the visible
[`env.sample`](../env.sample). PostgreSQL stores provisioned tenant provider credentials and call
definitions; the operator supplies the encryption keyring separately from the database. There is
no deployment JSON/TOML loader. JSON remains a supported format for call-definition inputs.

The first Docker release will include a working minimal configuration and the
exact environment variable names. The example maps HTTP port 4000; the final
guide will also specify the WebRTC and telephony networking needed for calls.
The entrypoint, release tag, and port settings still require verification against
the built image.

## What the completed guide will cover

1. Pull the released `vxpipe/vxpipe` image.
2. Configure your call and supply provider credentials.
3. Start Vxpipe with the required HTTP and voice-media networking.
4. Open the Console and make your first call.

Database setup and other deployment options will be linked from that quickstart.
