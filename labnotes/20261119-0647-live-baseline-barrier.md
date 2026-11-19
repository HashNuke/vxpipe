# Live baseline barrier

The umbrella gate at seed241896 timed out while waiting for initial live Call
Variables revision zero. Astra's controlled probe paused handle_continue baseline
publication: room startup still returned, and the old 100-read helper exhausted
its attempts in6.25ms with no rejected/dropped records. Releasing the producer
made the baseline visible. This establishes a test synchronization race.

The existing test now resolves CallVariables immediately after startup and uses
:sys.get_state as a publication barrier before inspecting the projection. No
runtime behavior changed. The controlled barrier waits through the held producer
and then sees revision0 with no loss. Actual focused file3/0 at seed241896;
format check and Astra xhigh final diff review are clean. Full root acceptance
remains pending and the active run predates this test correction.
