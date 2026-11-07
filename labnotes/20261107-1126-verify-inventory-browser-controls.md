# Verify inventory browser controls

Astra final audit found no recorded real-browser pass for T3 direct URL/Back/Forward,
read-only permissions and platform MCP exclusion, despite existing automated cases.
Use the current isolated Console, real publisher proxy and actual identity store
to close that explicit acceptance gap. No product bug is asserted. Create only an
isolated fixture user/role, keep its generated password private and remove/revoke
its access after inspection. Record both desktop/mobile states and public receipts.

The actual Go publisher and TLS proxy supply seven controlled listed MCP recipes.
Chrome at 1280x900 and 390x844 passes direct category URLs, uppercase search,
Connected navigation, Back restoring the query/result and Forward restoring
Connected. This pass exposed the independently reproduced search bug, corrected
in c1060d04 with focused red/green and adversarial verification; see
[search evidence](20261107-1129-normalize-directory-search.md).

Platform Connected and search render no tenant MCPs or MCP creation control at
both viewports. The actual authenticated platform-search receipt is HTTP 200,
directory available, scope platform, zero items, zero saved MCPs and
can_connect_mcp false. The MCP-only controlled catalog has no AI category; its
category-unavailable response is expected and does not establish public native
catalog acceptance. That remains in the external release gate.

Created a temporary ordinary role through Identity with only tenant_services.read
for assigned tenants and read membership in the isolated acceptance tenant. Its
real browser login can list all eight saved MCPs, inspect Authentication and cached
Tools, and search the directory. Replacement is disabled; Test, Disconnect and
Refresh actions are absent. Native fallback renders all 11 AI entries with Connect
disabled. Both viewport states are recorded and inspected. The authenticated
reader-inventory receipt confirms native/MCP writes false and can_edit false on
every saved MCP. A final identical receipt confirms the complete public inventory
is unchanged by viewing and navigation.

Driver corrections were not product failures: the named role locator requires
--name; omitting it selected Logout instead of Manage. Relogged and repeated all
read-only checks with exact locators. A tool-name wait was corrected from a guessed
name to the actual list_events. Desktop/mobile history was repeated with exact
selectors after the correction and passes (reader-navigation-back screenshots).

Current architecture/UI/OAuth/storage/runtime summaries and the milestone index
now link completed evidence and distinguish historical checkpoint scope from final
release readiness. Astra independently reviewed those summaries, verified local
links and approved closing both overlapping T5 browser/node boxes. No new runtime
change was required. Final root gates and release/approval remain open.

The final exact-selector history rerun passes both viewports. The temporary user
was disabled and all memberships removed through the authorized Identity API; its
existing browser session subsequently returns 401/session_required. The directory
proxy is restored to healthy with a cold cache. Astra independently reviewed all
read-only, platform and final history evidence plus exact inventory equality, and
confirms the local browser gap is closed with no further correction.
