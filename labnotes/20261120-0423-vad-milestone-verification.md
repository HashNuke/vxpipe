# VAD milestone verification

The first room-service browser run in final verification passed in 35.6 seconds with five canonical
human turns. It recorded four speech-end-to-STT delays (2168.639, 2404.649,
1942.086 and 2549.799 ms), one explicitly unavailable endpoint and a 1036.152 ms
barge-in stop acknowledgement. The test compared the stored measurements with
the authenticated API and rendered admin page after hangup.

The Console assets passed TypeScript checking, ESLint (two warnings) and 1187
tests. All eight core tests passed. The Metrics story responded through the
existing Tailscale Storybook server.

The first operational run on the completed endpoint change recorded two
endpoint delays. Its barge-in had no complete onset when the fixture interrupted
immediately after the browser observed playback start. The test failed its
barge-in assertion. The revised scenario interrupts one second into continuous
playback of the 15-second base response. On rerun, all five canonical turns
were present. Four endpoint delays measured 2112.609, 2028.284, 2386.507 and
2348.145 ms, one endpoint was partial, and the acknowledged interruption delay
was 148.966 ms. The full live test passed in 37.4 seconds, including the exact
response identity, arithmetic, API and UI comparisons.

The room-service rerun with the same sustained-playback fixture passed in 48.0 s.
It recorded endpoint delays of 2452.983, 2447.605, 2062.696 and 1954.948 ms,
one partial endpoint and a 1135.930 ms acknowledged barge-in delay. Neither
mode requires a target duration or measurement rate.
