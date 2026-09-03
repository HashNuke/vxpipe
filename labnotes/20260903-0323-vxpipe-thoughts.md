Gateway (Call Router)
> Responsible for receving call audio via websockets/SIP and call events/webhooks from telephony providers, and handing it to the reception to route the audio to the Call Engine to be able to further route to the appropriate call.

* Receive input audio via AudioProducer, which can be telephony or websockets endpoint or SIP.
* Route it to the appropriate call.
* Can be a separate OTP service and be aware of which nodes are active to be able to pass calls to them.

## Call Engine
> Services that receives call audio and events from Call Router and orchestrates calls appropriately.
> Also provides an API to create call rooms and initiating calls.

## Add participant: Human
* Will publish both the live audio of the human
* And the transcription of the speech
* Remember that the transcription is always published AFTER a turn is complete. Please verify this with our implementation/code in `callpipe` project.

Services:
* STT: Because we need to know what the human spoke.

## Add participant: AI
Service:
* Input guardrail:
  * Helps check if the input to the AI is something we allow or block.
  * After this we transfer to LLM
* LLM: Helps process the input
  * We need this structured. Whether the call needs a response, needs to hangup or transfer to another participant (which may be human or AI)
* Output guardrail:
  * Helps check if the input to the AI is something we allow or block.
  * After this we transfer to TTS to generate audio to publish to the room.
* TTS:
  * Helps generate audio for the LLM output

Notes:
* We should be able to play audio before the call is recorded and participants are activated. This audio can be TTS or can be a call recording.

## Add Room Monitor
Manage the room. Listen to room events. And provide APIs to manage the room from the outside.

Services:
* AudioStreamPublisher: Lets say I want to store call audio on S3.
* RoomTranscript: Collect all room transcript in structured form so that it can be made available for other activities.

## Pending responsibilities/questions
* Latency/Duration/Token/Cost Metrics - what metrics, track where? I would love for it to be exported to any storage or published as an event to sqs. So probably plan for a common exporter for data? We have an AudioStream publisher, but that has to be encompass more things?
* The call audio coming to the gateway might initiate a new call. 
* This call audio may also be meant as an invite to join a call - one more leg/participant of an existing call.
* How do we identify which call the audio input is for? Or we need to use something to denote to the call the audio is meant for?
* We also need a call registry. So we know what calls are ongoing and what proceses they point to (atleast the room monitor).
* We have no auth for now for our web endpoints We’ll decide that later.
* Do we call the services as capabilities or retain services as the terminology? Define contracts, events to publish, etc.
* I also think we need instrumentation. I want to listen to an ongoing call to be able to debug it.

We have to include this in our library so that we can using this for demos and testing. Easier to assert morse code and verlfy our output.
* MorseCodeTTS
* MorseCodeSTT
