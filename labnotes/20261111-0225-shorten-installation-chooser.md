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
confirmed the replacement first-account target exists. The existing publishing
workflow will validate the handbook build; inspect the published page on desktop
and mobile after deployment. No new automated tests are needed for this copy edit.
