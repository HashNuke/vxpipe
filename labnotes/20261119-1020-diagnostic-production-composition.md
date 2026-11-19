# Diagnostic production composition

Coordinator checkpoint84ce2f83 is pushed, with Engine149/0, clean Astra review,
static checks and Lean. Prior startup checkpointfb21396f has a frozen passing full
umbrella suite. This checkpoint connects the reviewed components to application
startup while leaving the durable setting as the sole capture authority.

Red/green evidence prepared while the previous full suite ran:
- Parent composition probe red1/1: no source coordinator existed. The Calls
  diagnostics parent now injects its real Attachment factory, selected projection,
  repository and writer/collector/task pools into Engine SourceSupervisor.
- One parent-owned startup gate is retained across source subtree/destination
  restarts. Replacing the whole parent replaces all destinations and the gate.
- Application composition red2/2: missing child_specs route. Calls.Application now
  reads optional diagnostics configuration and starts that parent when configured.
- Astra xhigh parent/Application review is clean: six independent cases, including
  off/no model work, source-child restart, whole-parent replacement, abrupt writer
  supervisor failure, custom factory pools/projection/repository and capacity.
  The four substantive parent cases are retained in composition_test.exs and now
  start through Application.child_specs.

Actual production runtime regression red12/1 confirmed absent Calls.Application
configuration for database-backed hosts. runtime.exs now injects {LatencyStore,Repo}
and the fixed Engine source-pool names under the existing database-enabled branch.
Test/hosts without persistence omit the pipeline. There is no configuration enable
boolean: SettingsProjection still gates every capture and lazy model admission.
Actual Calls diagnostics46/0 and Console runtime configuration12/0 pass. Final
runtime-inclusive Astra review and static gates are pending. No deployment.

Next acceptance: a real configured LLM/Scribe fixture call must persist linked turn
revisions and drain on retirement. Existing Console configured-Scribe test exercises
a human-to-human room and a transport emitting only readiness, so it cannot prove
LLM-only diagnostics or acknowledged profile capture unchanged. Use actual wire
receipt/profile callbacks and durable call admission in the new acceptance fixture.

Final actual runtime-inclusive Astra xhigh review is clean: independent Console
runtime12/0 and retained composition4/0, including repository contract, unique
process names, database guard and fail-closed settings startup before Repo readiness.
Root format/compile/strict Credo/unused-lock gates pass. Lean passed for the identical
Engine code in the preceding coordinator checkpoint. Updated the durable design to
reflect current parent ownership, helper deadlines and conservative capacity debt.
A new frozen root suite will verify coordinator and production composition together.

Docs review reproduced three stale descriptions of unwired runtime components;
all are corrected and final Astra text re-review is clean. The current frozen root
suite is running in /tmp/vxpipe-production-composition-umbrella.log. No runtime,
test or build files have changed since it began. No combined C acceptance task is
checked off by component composition alone.
