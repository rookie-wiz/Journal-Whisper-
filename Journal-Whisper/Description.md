Project: Journal Whisper (private On Device AI powered journal)

Users write freely. The app suggests reflection prompts, tags moods and summarizes the week, all offline.
Week 1: Journal storage, a clean editor and a Face ID lock.
Week 2: Mood tagging and reflective prompts via LanguageModelSession, with safety-minded instructions (no medical advice).
Week 3: Weekly summary, streaks and mood charts. Handle the guardrail errors gracefully.
Week 4: Privacy policy, a crisis-resources screen, TestFlight and submit.


General Tips for the project

Check SystemLanguageModel.availability and always have a non-AI fallback.
Use the new Evaluations framework to test prompt changes instead of eyeballing them (Apple's iOS 27 tooling includes it).
If you target iOS 27, the new LanguageModel protocol lets you swap providers with a one-line change.
Apple reviews take a few days, so submit by Nov 25.

