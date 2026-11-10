# Documentation table of contents

The canonical handbook has **21 English pages** under `en/`: Getting started at the
root, 11 further usage guides and nine development guides. Architecture belongs in development.
`locales.json` selects `en` as the default; future translations mirror these paths.

Website import copies the localized pages and `assets/` into `vxpipe-web`.
This file is repository navigation and is not a published page. Publication and
acceptance progress live in the [handbook milestone](../labnotes/milestones/consolidated-handbook-and-publication.md).

## Usage

- [Getting started](en/index.md)
- [Install with Docker](en/usage/install/docker.md)
- [Install on Railway](en/usage/install/railway.md)
- [Core concepts](en/usage/concepts.md)
- [Configuration](en/usage/configuration.md)
- [Accounts, tenants and access](en/usage/administration.md)
- [Integrations and credentials](en/usage/integrations.md)
- [Call specs and variables](en/usage/call-specs.md)
- [Telephony and transfers](en/usage/telephony.md)
- [Agents, tools and MCPs](en/usage/agents-and-tools.md)
- [HTTP API and platform MCP](en/usage/api-and-mcp.md)
- [Operations and troubleshooting](en/usage/operations.md)

## Development

- [Development workflow](en/development/local-development.md)
- [Architecture](en/development/architecture.md)
- [Call runtime and lifecycle](en/development/call-runtime.md)
- [Speech and media runtime](en/development/speech-runtime.md)
- [Agent runtime, tools and outbound MCP](en/development/agents-and-mcp.md)
- [Identity, persistence and security boundaries](en/development/security-and-persistence.md)
- [Adding providers and integrations](en/development/providers-and-integrations.md)
- [Console and client development](en/development/console-and-clients.md)
- [Testing and verification](en/development/testing.md)

## Reference assets and history

Directory API schemas/examples live in `assets/integrations/` and are linked from
the provider guide. The historical Boruta probe lives in `labnotes/experiments/`;
it is not run or published by the documentation build.

The [original inventory](https://github.com/HashNuke/vxpipe/blob/1914be98/docs/_TOC.md)
maps all 120 previous files to the consolidated topics. Superseded designs and
dated implementation evidence remain available at that revision; historical
labnotes link to it directly. Current behavior belongs in the handbook.
