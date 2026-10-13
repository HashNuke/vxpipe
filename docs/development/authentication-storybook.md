# Authentication Storybook review

This prototype implements the UI review checkpoint in the
[authentication milestone](../../labnotes/milestones/console-authentication-and-user-management.md).
It includes component, composed-page and connected-journey stories.
Storybook remains a deterministic mock. The Console now uses the implemented Identity
backend for login, password storage, session revocation and authorization.
The user authorized backend implementation while reserving UI review for later.

## Open the stories

Run `bin/storybook` from the checkout. Use the URL it prints; `bin/worktree-port storybook`
reports the isolated port. In the sidebar, open **Vxpipe → Console → Authentication**:

- **Full journey → Superadmin**: the connected user/role workflow.
- **Full journey → Admin**: the same flow with protected privileged accounts.
- **Full journey → First installation**: create the first Superadmin and enter Account.
- **Components**: password/confirmation, role badges/selection, tenant assignment and
  permission editors, including mixed/all/empty/read-only states.
- **Pages**: all eleven planned routes, including local recovery, and their error, loading, read-only and pending states.

The full journey story ID is `vxpipe-console-authentication-full-journey--superadmin`.
Page IDs begin `vxpipe-console-authentication-pages--`; examples include `setup`,
`create-user`, `user-details`, `reset-password`, `create-role` and `role-details`.
Component IDs begin `vxpipe-console-authentication-components--`.

## Try the workflow

1. Open Roles, create a custom role and choose read/write permissions with all/assigned
   tenant scope. Selecting Write also selects the required Read permission.
2. Open Users and create a member with email, a chosen password and confirmation.
   Passwords must match and contain 15–128 characters. No emails are sent.
3. Open Add tenants, select tenants in the dialog, change one to Read & write, then save. Read the resulting user details. Tenant Manager has calls, call specs, services and API keys within assigned tenants.
4. Search/filter Users by role; open the same user, change access or disable them.
5. Reset a permitted user's password. The form clears password fields after submission.
   Resetting the acting account returns it to login; resetting another account preserves
   the actor. Session revocation is represented by feedback only, not implemented.
6. Switch to the Admin journey: Admin/Superadmin rows remain visible but cannot be edited
   or reset. Try the protected-account page and member-denied page stories directly.
7. Open a built-in role: its policy is read-only. Try disabling the only Superadmin;
   the fixture rejects the change. Role deletion is disabled while users reference it.

## Mock behavior and limits

Fixture emails use `example.test`. `owner@example.test`, `admin@example.test` and
`member@example.test` demonstrate the principal account categories. Mock login accepts
any nonempty password for an active fixture account: this is not a password verifier.
Entered passwords are not retained by the mock store, sent, logged or persisted.
Creation/reset validation runs in the UI; the Console independently validates and authenticates against the backend. Self-service requires a current-password field but does not verify it.

Changes are held only in React memory and reset on reload or story-control changes.
Storybook uses `#/admin/...` links to model the proposed Console routes. It does not
install production routes or use cookies/local storage. Query strings inside the hash
retain user search/role filters through browser history. Unknown or unauthorized
resources display an unavailable state. The prototype has no live provider calls.

Use Controls to change the actor/theme and select `saveBehavior=success`, `failure`
or `pending`. Pending deliberately keeps the submitted form busy for state review;
reset the story to leave it. Loading/unavailable scenarios apply to the user directory.
Browser viewport resizing covers phone layouts; both dark and light themes are available.

The picker uses a bounded local fixture list; the Console uses server search/pagination and transactional mutation/revocation. Call/session authority and
all permission checks in this prototype describe UI behavior, not a security boundary.

Verification on 2026-10-13: 664 frontend tests, TypeScript, lint and Storybook/Console
asset builds pass. Headless Chrome review covered the original ten pages, both themes,
and the final recovery and tenant-dialog layouts at desktop and phone sizes. The
[implementation labnote](../../labnotes/20261013-0423-authentication-storybook-ui.md)
records interactions, corrections and test evidence. UI review is still pending.
