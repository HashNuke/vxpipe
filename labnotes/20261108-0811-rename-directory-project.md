# Rename the directory Railway project

The user requested that the Railway application name match its supporting GitHub
repository. MCP inspection identifies `vxpipe-integrations` as the project, with
the existing `integrations-api` service in production. Renamed only the project
to `vxpipe-integrations-web`; retained its ID, service, domain, deployment, SQLite
volume and configuration.

The available Railway MCP tools can inspect projects but expose no project-name
mutation. After inspecting the live `Mutation.projectUpdate` and
`ProjectUpdateInput` schema, used the authenticated Railway CLI API with only the
`name` input. The mutation returns the existing project ID and requested name.
Updated the sibling publisher's `.railway/railway.ts` declaration and
`.railway/README.md` to match. `node --check .railway/railway.ts` and
`git diff --check` pass. This metadata/documentation change needs no runtime test
or redeployment; the existing successful deployment remains active.

Post-change MCP inspection confirms the renamed project, unchanged production
service and deployment, one replica and the same 100 MB volume at `/data`.
The public hostname is unchanged and its health endpoint returns HTTP 200.
Requested the existing GPT-6 Astra xhigh reviewer to inspect the exact two-file
configuration/documentation diff before commit and push.

The exact-diff review is clean: only the project label and its documentation
change, with resource, service, domain and secret references untouched. The
original milestone's separate workflow approval remains pending.
