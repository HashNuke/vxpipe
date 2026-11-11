# Shorten installation chooser

The user wants the handbook root to provide installation choices only. Keep its
title, a one-line prompt and the two existing cards; rename Railway to “Deploy
on Railway”. Remove the repeated configuration, account, call and development
instructions, which already have dedicated sidebar pages. Disable this page's
table of contents and next-page shortcut so they do not compete with the choices.

Both installation guides linked a removed setup heading. Point them directly to
the existing first-account instructions instead. No stylesheet, importer or
runtime behavior changes are needed.

Verification: reviewed the existing hosted page, checked the source diff and
confirmed the replacement first-account target exists. No new automated tests
were added for this copy edit.

- Canonical commit `3261655e` and generated website commit `ca448a2` are pushed.
- [Documentation publication](https://github.com/HashNuke/vxpipe/actions/runs/42945993198)
  passed, including the handbook build. Cloudflare build
  `a3b1a8ca-27e5-4b1c-8ae6-547cad7e4d21` succeeded.
- Hosted Chrome screenshots at 1440×900 and 390×844 show only the prompt and
  cards, with no horizontal overflow. Both installation links return HTTP 200;
  the page has no remaining section headings or browser errors.
