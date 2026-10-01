# Source arm test deadline

## Observed failure

The scoped STT umbrella gate runs 1,812 CallEngine tests and reports one failure,
seed 232973: the existing source-arm rejection check waits five seconds for the
arm request and receives none. A separately selected rerun passes one test,
36 excluded, in 4.6 seconds. That total duration does not isolate arm latency
or establish the original scheduling cause.

## Proportionate correction

The production source-cutover state machine allows a nine-second room transition
deadline and eight-second source connection budget. Successful cutover cases in
the same test module already observe arm with a ten-second bound. Align only the
rejection test's observation bound with that existing contract so it can inject
the intended failure after a permitted transition. Preserve the rejection reason,
closed ingress, retired allocation and monitored termination assertions. No
production timeout or source-cutover behavior changes.

The owning module passes all 37 checks with the original root seed 232973,
in 6.2 seconds. The final same-seed umbrella run passes all 3,020 reported tests, zero failures
and 96 exclusions, including all 1,812 CallEngine and 522 Gateway checks.
The original scheduling cause remains unproven; this correction aligns the
test observation with the existing production deadline.
