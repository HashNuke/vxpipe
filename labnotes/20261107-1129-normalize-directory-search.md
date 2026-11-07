# Normalize directory search queries

The required authenticated T3 browser pass reproduced an uppercase-search failure.
For q=CIMD, Console inventory returns HTTP 200 with directory_error invalid_page and
fallback, while the actual Go publisher returns HTTP 200, query.q cimd and the
matching Listed CIMD tools entry. Both public responses are retained in ignored
listed-directory/navigation-search-{console,publisher}.json. The publisher lowercases
and trims q in internal/httpapi/list.go; Console currently only trims, then Page
requires an exact echoed query.

Add a focused client regression against a publisher-style lowercase echo and make
the existing request-normalization case mixed-case. Normalize the outbound query
before caching/validation while preserving strict response-identity checks. Real
search/history acceptance and independent reproduction/review remain pending.

The first focused run reproduces two failures out of nine cases: the request retains
mixed case and Client returns invalid_page for the publisher's lowercase echo.
Astra independently reproduced uppercase and padded uppercase rejection against an
actual publisher response. Initial lowercase correction passes the directory suite,
but review also reproduced the publisher rejecting 202 Unicode codepoints that
Console counted as 101 grapheme clusters. Plain String.downcase also expands dotted
capital I to i plus combining dot, unlike the publisher's simple lowercase i.

Two additional regression cases first fail for those exact reasons (seven request
tests, two failures). The final change maps U+0130 to i before lowercase conversion
and limits normalized UTF-8 queries to 200 codepoints after trimming. Strict Page
query identity checks remain unchanged. All 61 directory tests pass (seed 730557).
Astra independently validates the corrected actual response and Unicode boundaries
without application or database startup; no further code change requested. Installed
OTP and Go use different Unicode data versions, so this is not a claim of universal
version-independent mapping equivalence. The Unicode distinction is documented in
[SpecialCasing](https://www.unicode.org/Public/UCD/latest/ucd/SpecialCasing.txt).

Actual Chrome against the Go publisher and local TLS proxy now renders CIMD and
dotted-I results. At 1280x900 and 390x844, direct category navigation works and
Connected → Back restores the uppercase query and matching result; Forward returns
to Connected. Screenshots navigation-{category,back}-{desktop,mobile}.png and
navigation-dotted-i-desktop.png are retained privately and visually inspected.
Two driver mistakes (expecting /services rather than /services/connected, and an
unsupported select command) were corrected; neither was a product failure.

All five root gates are running serially in /tmp/vxpipe-search-root-20261107.log.
The prior outage root run was deliberately interrupted when this bug was found;
it is not counted as green evidence. No speech/source-cutover implementation changed.

Final serial root verification exits zero: mix format --check-formatted,
mix compile --warnings-as-errors, mix credo --strict, mix test --seed 774698
and mix deps.unlock --check-unused all pass. The umbrella reports 5,000 tests,
zero failures and 264 exclusions. This includes the reconnect/outage/search
checkpoint; the five-case tagged saved runtime lane passes separately. Frontend
source has not changed since all 1,065 tests, TypeScript and ESLint passed.
Authenticated rendered acceptance and final Astra adversarial review are complete.
External publication and user approval remain open; this is not milestone completion.
