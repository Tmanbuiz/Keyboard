# WianTribe Keyboard

iOS custom keyboard app by WianTribe Inc. Meant to be a worldwide keyboard, like Samsung Keyboard on Android, not a Nigeria-only product.

- Repo: github.com/Tmanbuiz/Keyboard
- Goal: list it on the Apple App Store
- Apple Developer Program: enrolled (paid), Oct 2026
- Owner has limited coding background. Claude writes the code; the owner builds and submits.

## How to work here

- Every feature must be App Store compliant. Do not propose sideload-only tricks, private APIs or anything Apple's review would reject. If a feature is risky for review, say so before building it.
- Respect iOS custom keyboard limits: keyboard extensions have strict memory limits, cannot read the host app's text beyond what the text input API gives, and cannot use the microphone or network unless the user grants "Allow Full Access". Say when a feature needs Full Access.
- Privacy comes first. A keyboard sees everything the user types. Never log, store or send typed text without explicit, plain-language consent. Keep the privacy policy and App Store privacy answers in step with what the code actually does.
- Keep the keyboard fast and small. Lag on key press or a crash from memory use gets the keyboard switched off by users.
- Support multiple languages and layouts from the start. Do not hard-code English or Nigerian layouts.
- Say plainly what the owner must do by hand (Xcode setting, signing, App Store Connect step).
- Deliver complete files and name the path of each.

## Agents and skills to use

- Agents: planner (before big features), code-reviewer (before each build), security-reviewer (anything that touches typed text, Full Access, or network calls), build-error-resolver (Xcode build errors)
- Commands: /plan, /code-review, /verify

## Keep sessions cheap

- Work on one task per session. When a task is finished, tell the owner to run `/clear` before starting the next.
- If the conversation has gone long (many file edits, repeated debugging), tell the owner to run `/compact` before continuing.
- Read only the files the task needs. Ask which file to change if unsure; do not scan the whole repo.
- Do not start a subagent for small jobs. Use one only for a planning, review or security pass, and only when asked.
- Do not paste whole files or long logs back into the chat. Show only the changed lines and the result.
