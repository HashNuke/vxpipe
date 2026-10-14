# Authentication page spacing and recovery copy

- Reproduced the white band above setup in Storybook. The auth form's top
  margin collapsed outside the dark shell. Converted vertical margin to top
  padding, preserving intentional form positioning while keeping the shell's
  background at the viewport top. Shared styles cover setup, login and recovery.
- Verified the real command in the recovery Mix task and operations documentation.
  Changed the recovery instruction to run `mix vxpipe.recover` on the Vxpipe server
  and paste its token. Renamed the field to Recovery token; removed the redundant
  operator hint and recovery footer as requested. Protocol field names remain intact.
- Copy/CSS-only changes; adjusted existing tests to the new accessible field name.
- Initial frontend command ran from the wrong directory; reran from Console assets.
- Headless Chrome screenshots inspected for all three modes at 1440px and 390px:
  consistent dark background, readable copy and no horizontal overflow.
- 25 focused tests, TypeScript, ESLint, formatting, compilation and Credo passed.
- Full root suite passed (3,788 tests, zero failures, 134 excluded), as did the
  unused-dependency gate. All five required root checks passed.
