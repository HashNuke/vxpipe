# Integrations review fixes

## Requested changes

- Remove visible inherited-source labels from connected and directory rows,
  including remote categories. Gate inherited connection management with the
  existing platform_services.write permission (installation scope).
- Use skeletons only for pending directory content. The preview resolves after
  1.2 seconds; local connected inventory and native categories remain immediate.
- Simplify MCP manage dialogs to Authentication and Tools tabs. Put account context
  and an auth-mechanism tooltip in the header, expose reconnect/editable credentials
  directly, and move refresh beside the tool heading with independent list scrolling.

## Implementation and scope

- Storybook workflows only; shared SetupServiceCard also loses its inherited-source
  text. Existing backend platform credential routes already require
  platform_services.write; no backend API changes were required or implemented.
- Management gates cover connected inventory, hosted search/category results,
  native fallback and modal opening. NavigationJourney uses the existing permission
  helper and checks tenant_services.write for tenant management.
- Directory loading uses a cancellable preview timer, accessible loading status,
  reduced-motion support and stable row/category placeholders.
- All connected indicators now use the same double checkmark with an accessible
  hidden label. The sidebar issue card is recorded in the preceding labnote.

## Evidence

- New IntegrationStates tests: 6 red / 1 green before implementation, then all
  7 pass. Focused integration/navigation suite: 97 passed. TypeScript passed.
- Full frontend suite before modal refactor: 895 passed in 116 files.
- New ManageMcpConnection tests: all 3 failed before the modal implementation.
- Full umbrella checks for the accumulated checkpoint: format, compilation with
  warnings as errors, strict Credo, 4,470 tests (zero failures, 156 excluded),
  and unused dependency check passed.
- Final modal tests and rendered verification completed; see checkpoint below.

## Review follow-up

- User requested a stable modal size when switching tabs and left-aligned tabs.
  The manage dialog uses a 580px height capped by available viewport height;
  Authentication and Tools own their internal overflow. Tab labels align left.
- Reused the existing tooltip surface styles after rendered inspection showed
  portal text lacked a readable background. Manage opens with focus on the active
  Authentication tab; a focused test failed before the autofocus fix.
- User clarified the modal header alignment: name and close button share row one,
  account/auth info spans row two. Used a scoped two-row grid so the close control
  aligns with the name rather than centering over both lines.

## Final checkpoint evidence

- All 898 frontend tests across 117 files pass; TypeScript passes. Static Storybook
  build passes (existing chunk-size warning). Dev server remains HTTP 200 on 6006.
- Browser confirms Authentication and Tools each measure 580px in the desktop
  viewport, tabs align flex-start, and name/close centers both measure y=101.
  Tool list overflow is auto. Mobile and loading screenshots captured for review.
- Milestone design review: permission contract reuses the existing installation
  permission rather than inventing a renamed key; production MCP work remains
  unchecked. Local inventory and remote fetch lifecycles remain independent.

- Final screenshots inspected for dark desktop/mobile Cal.com tabs and light
  desktop/mobile HubSpot registered-client fields. Title/close alignment is correct;
  mobile authentication content scrolls independently above the persistent footer.
  Skeleton screenshots show content placeholders during the finite loading state.
