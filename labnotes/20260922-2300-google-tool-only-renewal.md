# Google tool-only renewal

Baseline `48c6cd81`: the local opted-in Google controller uses bounded
independent response records; reviewer-reproduced tool/caller identity and
unfinished-caller interruption defects are fixed. The full call-engine child
suite passes 1,391 tests. Root static gates pass, while the umbrella suite
cannot enter Persistence without a local PostgreSQL test password. No hosted
Google calls or manifest enablement.

Reviewed the milestone's continued-response, model-boundary and renewal tasks,
the response-ownership design, `STSSession`, `STSResponseDelivery`,
`STSResponses`, `STSResumption`, and existing controller cases. Added two
specific acceptance subtasks before test changes. A real-controller tool-only
case confirms no public speech turn, non-speaking record retirement at model
end, pending-tool renewal denial, and fresh-idle requirement after tool result.
An overlapping A-playback/B-generated case confirms neither model idle nor A
settlement alone permits renewal; B must be credited and settled too. Both new
focused tests passed on the first run, so no runtime implementation changed.
The eight-file local STS regression group passes 212 tests, zero failures.
Independent read-only review is pending. These checks do not prove safe
cross-origin wire cutover, a resumption coverage watermark, hosted history
behavior, or the final umbrella gate.
