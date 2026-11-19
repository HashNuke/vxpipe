# Telnyx fixture isolation

The umbrella's exact-body authentication test returned401 because the preceding
existing-leg test reused the same global application/leg locator with a different
per-test signing key. Registry owner cleanup is asynchronous. Independent Astra
review delayed cleanup and reproduced the exact401; draining that partition made
the same request succeed. No production signature-verification change is needed.

The existing-leg test now uses a unique leg identity in both registration and its
signed event. This preserves the authentication contract while isolating registry
lifetime from later fixtures. The reviewer red probe fails1/1 as expected; cleanup
comparison passes1/0. The existing file passes10/0 with the umbrella's seed520626,
and Astra review of the final diff is clean. Root static checks passed before this
mechanical fixture edit; formatting passes. The earlier mixed-source umbrella run
is not final acceptance evidence; the briefing-voice recovery timeout remains under
investigation and current frozen-source root checks are still required.
