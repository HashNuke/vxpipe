# Stabilize catalog timeout fixture

- During the phone-readiness root checks, CatalogRefresherTest failed waiting for the blocking
  configuration source to announce that its worker had started. The fixture's 100 ms refresh
  deadline could expire before that announcement under concurrent umbrella load; the mailbox
  contained no matching notification. The previous common-input root run had passed this test.
- Increased only this fixture's refresh deadline to 1,000 ms and its waiting call timeout to
  2,000 ms. The test still checks callback responsiveness and the actual bounded refresh-timeout
  result; production settings and timer behavior are unchanged. This is scheduling headroom for
  verification, not an extension of a live call or transfer deadline.
- The four focused catalog checks pass. All five root gates pass with the phone-readiness
  checkpoint in the same worktree: formatting, warnings-as-errors compilation, strict Credo,
  1,122 umbrella tests with zero failures (15 integrations excluded), and unused-dependency checks.
  Commit this fixture separately from phone readiness so its purpose and production impact remain
  clear.
