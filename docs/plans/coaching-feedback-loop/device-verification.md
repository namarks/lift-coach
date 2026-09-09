# Physical iPhone feedback verification

Use a future Tres Fort TestFlight build containing PR #163 after separate
release authorization. Deploy the compatible Worker before distributing that
build: older Workers can reject its `expected_feedback` finish field. Record
the app version/build, device, iOS version and observed permission state with
the results. Use short test phrases rather than sensitive details.

The canonical plan records the owner decision to defer these checks until
TestFlight. These instructions do not authorize deployment or distribution.

1. Open workout feedback and type a short note before choosing **Talk about
   your workout**. Deny speech or microphone access when prompted. Confirm the
   note remains, **Type instead** works, and **Skip** permits completion without
   adding or clearing feedback. Record which permission was denied; check the
   other prompt when available. Do not describe an existing permission setting
   as a fresh-install prompt.
2. With speech and microphone permissions enabled in Settings, choose **Talk
   about your workout**, speak a short phrase, then **Stop recording**. Confirm
   the final words arrive and microphone capture stops. Edit the transcript and
   optionally choose a fatigue rating. Only **Save feedback** approves the words.
3. Start another recording and **Cancel recording**. Confirm the earlier text
   returns. Start again, switch apps, then return. Capture must have stopped;
   a typed correction must not be replaced by a late recognition result.
4. Save feedback, leave and relaunch before finishing. Resume the workout and
   confirm the approved words remain. Finish, then verify the exact words and
   optional rating in private history and the coach's session/brief reads.
   Check the last-completed brief path when a newer session is unfinished or
   skipped. The production app intentionally preserves approved feedback
   through relaunch; recording audio must not be retained.

An unavailable language/model is a fallback observation, not evidence of
successful on-device transcription. Report the failing step and any visible
message. Automated simulator recognition substitutes and D1/MCP fixtures cover
delivery, conflicts and delayed acknowledgments separately; they do not prove
physical microphone or fresh-permission behavior.
