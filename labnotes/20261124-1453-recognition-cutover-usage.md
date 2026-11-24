# Recognition cutover usage

The cutover regression exercised final transcripts on both sides of the serialized replacement decision. Its assertions now also follow the usage observations emitted to the owner. It observes one failed old attempt, a distinct fresh attempt, and a single batch containing the fresh audio duration and text length. It gives the stale final a different nonzero duration so stray usage from the retired generation would fail the check.

All ten conversational STT usage tests passed. Earlier configured phone tests cover the interrupted prompt and model history, including one response submitted for synthesis. The new assertions exercise existing runtime behavior. A listener still needs to confirm the repeated question and audible answer on a real handset.

The configured phone test now submits an Opus packet through the Telnyx media socket during repeat playout and observes PCM at the replacement Scribe wire before injecting the fresh question. Two output-arbiter tests cover native clear acknowledgement and protection of queued and active private output. All 32 arbiter tests and the focused phone case passed.

The phone-ingress case passed four consecutive runs. A signed caller hangup during replacement admission ended the room, replacement recognizer and original carrier leg without another recognition attempt, callback recording or hangup command.
