# Vxpipe

**Build voice agents that can talk, take action, and bring in the right person.**

Build conversations for the browser and phone, connect agents to your tools,
and hand callers between agents and people. Vxpipe handles streaming speech,
interruptions, and call visibility so you can focus on what your agents do.

## Quickstart

Docker release coming soon; this command is a preview.

```shell
docker run --rm -p 4000:4000 --env-file .env \
  -v "$PWD/vxpipe.json:/etc/vxpipe/config.json:ro" \
  vxpipe/vxpipe --config /etc/vxpipe/config.json
```

Then open the [voice console](http://localhost:4000/pipecat-console).

## Get started

- **[Get started with Docker](docs/getting-started-docker.md)** — configuration, credentials, and running Vxpipe as a service.
- **[Get started with Elixir](docs/getting-started-elixir.md)** — run from source and explore components for your own Elixir applications.

## License

```
Copyright 2026 Akash Manohar John

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
