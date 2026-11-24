# Speech overflow test

The seventeenth unresolved speech start intentionally terminates the capability and its provider subtree. The umbrella run failed when the provider died after emitting that event but before acknowledging the fixture's synchronous request. The exception carried the GenServer call context and bypassed the fixture's bare `:killed` catch.

The test now issues an asynchronous OTP request. It requires the capability's overflow notification and monitored exit with the exact overflow reason, then accepts either a successful provider acknowledgement or the monitored provider's killed result. The focused case passed 501 consecutive runs. All 33 cases in the capability origins suite passed.
