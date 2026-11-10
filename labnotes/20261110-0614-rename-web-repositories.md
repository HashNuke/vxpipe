# Rename web repositories

The user requested renaming `HashNuke/vxpipe-docs` and its Cloudflare application
to `vxpipe-web`, and updating the local checkout's remote. They also explicitly
requested deleting both the remote `vxpipe/vxpipe-integrations` repository and
its local checkout after confirming the catalog has moved into `vxpipe`.

GitHub repository rename succeeded, retaining repository ID `1411574649`.
The existing `../vxpipe-docs` checkout now uses
`git@github.com:HashNuke/vxpipe-web.git`; no local directory rename was requested.
Updated package metadata/lockfile, Wrangler name, README and the existing test's
temporary-directory prefix. No new tests or application behavior changes.

The previous successful GitHub check identifies Cloudflare Workers Builds,
Worker `vxpipe-docs`, account `98ceddea8225e2c34f6ccbdd842aa6be`. Wrangler config
uses Workers Static Assets. Wrangler has no current authentication or named
profiles; a device login was requested. The Cloudflare API supports renaming an
existing Worker by PATCHing only `name` on its stable ID, preserving omitted
settings. Do not deploy the new name as a separate Worker.

The old integration checkout is clean, has no ignored/untracked files or
unpushed commits, and its sole remote branch matches local `main` at `bb09fd4`.
The remote has no forks or open issues. All sixteen definitions are present in
the main repo; changes are limited to schema paths and the previously documented
Cal.com icon refresh. Discovery evidence and requirements match, validation
files/workflow are present, and the root Apache license matches apart from a
leading blank line. The production catalog already imports from `HashNuke/vxpipe`.
Deleted only the verified standalone local checkout. GitHub's current token lacks
`delete_repo`; remote deletion awaits the requested scope refresh.

Verification so far: eleven existing Node tests pass, Astro static build passes,
and Wrangler deployment dry-run succeeds for all 62 assets. The build retains
existing warnings for empty localization content and the missing sitemap site URL.
Headless Chrome loaded both the built homepage and English documentation page.

With GitHub access restored, completed the previously authorized catalog webhook
registration on `HashNuke/vxpipe`: hook `709735353`, active push events, JSON,
TLS verification, and the existing Railway signing secret transferred in memory
without printing or persisting it. GitHub ping delivery returned 200. Push
delivery `b38654aa-dcce-11f1-8d7f-bee4a969bf6a` for commit `816b945c` returned
202. Railway logged one failed import attempt, then completed the automatic
retry at 06:19:53 UTC. Automatic GitHub-to-catalog refresh is verified.

Reference: [Cloudflare partial Worker update](https://developers.cloudflare.com/api/resources/workers/subresources/beta/subresources/workers/methods/edit/).

## Cloudflare rename completed — 2026-11-10

After the user authorized Wrangler's device login, renamed the existing Worker
`vxpipe-docs` to `vxpipe-web` with a name-only PATCH. Worker identity
`8628f213d46a477d8e1a6fcad5d8acf5` is unchanged; an in-memory settings comparison
confirmed other settings were preserved. The new public URL is
https://vxpipe-web.akash-98c.workers.dev/ and Wrangler configuration already uses
that name. Credentials were obtained through Wrangler and used only in memory.

Website commit `2e2bbc5` triggered `Workers Builds: vxpipe-web` and deployed
successfully, proving the GitHub build connection survived the rename. Chrome
loaded the new URL, all 22 handbook pages and four asset downloads. This closes
the Cloudflare rename portion of this record.
