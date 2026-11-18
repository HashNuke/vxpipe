---
title: Call spec publications
description: Separate working drafts and published version numbers while preserving immutable call identities.
---

# Call spec publications

The editor presents one working draft and numbered publications. Saving updates the visible working draft; publishing changed content advances the published version. Unsaved browser edits, saved unpublished changes and live publication are distinct states.

Internal source revisions remain immutable. Their IDs continue to identify API reads, selected publish requests, provider preparation and pinned calls. A separate publication ledger assigns user-facing version numbers and stores actual publication timestamps. This preserves recovery and API compatibility without presenting each save as a release.

We rejected overwriting revision rows: calls, prepared capabilities and integration authorizations already rely on immutable revision identity. We also rejected deriving publication history from every saved revision or its creation timestamp: saving is not publishing, and those dates do not prove publication.

The publication transaction serializes counter allocation with live-pointer and route updates. A request with source equal to the current live source does not allocate a version, move routes or change its publication timestamp. Successful responses retain the requested internal revision and carry authoritative publication metadata separately. Saved changes compare source content against the live source, not revision numbers.

Migration preserves the known current publication's existing number and date. Previously published revisions whose publication dates were overwritten cannot be reconstructed reliably; the initial history may therefore have fewer than three rows. Historical call references remain unchanged. Newly created specs publish as version 1; subsequent publications advance by one.

The UI uses `v6 Published` or `v6 · Unpublished changes`, and `Draft` before the first publication. The badge opens a reference-only history of at most three publications, plus the latest saved changes and save date if they differ from live. History contains no source, credentials or editing controls. Existing revision APIs remain the source-retrieval interface.

Implementation and verification evidence lives in the [milestone](../../../labnotes/milestones/call-spec-drafts-and-publications.md).
