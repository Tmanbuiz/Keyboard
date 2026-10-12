# Use your Groq account in WianTribe

Build 4 adds Groq as an explicit AI provider and a writing panel inspired by the layout in the supplied Samsung screenshots. It includes Spelling and grammar, Writing style, Summarize, Bullet point, Table and Composer, plus a result card with Edit, Copy and Replace.

## Set it up on your iPhone

1. Install build 4 through Sideloadly, keeping the keyboard and clipboard-reader extensions, just as for the working build 3.
2. Create or use a Groq API key at <https://console.groq.com/keys>. Enter it only in your WianTribe app.
3. Open **WianTribe → Tools → AI setup**. Enter the key and choose a model. The initial model is `openai/gpt-oss-20b`; another model can be selected if your account supports it. **Test Groq connection** checks your key and model list without submitting any writing.
4. Tap **Save Groq and use it**, then **Copy AI connection for keyboard**.
5. Switch to WianTribe in any text field. Tap **✦ → Auto/Groq → Import AI connection**. This saves the key in the keyboard's own Keychain and selects Groq there too.
6. Enable **Settings → General → Keyboard → Keyboards → WianTribe → Allow Full Access** for online requests.
7. Type or select text, open **✦**, and choose a writing tool. Review the result, edit it if necessary, then tap **Replace**. Composer uses the current text as the topic or request for a draft.

The companion app and keyboard can have separate Keychains after sideloading. Copy/import is therefore necessary even if shared clipboard storage works. Connections are marked as concealed, local to the iPhone, expire after two minutes and are removed from the pasteboard after a successful import. They are excluded from WianTribe clipboard history.

## Provider choices

| Choice | Behavior |
| --- | --- |
| Groq | Calls only Groq for writing and translation. Errors do not trigger Apple's AI. |
| Apple | Calls only Apple's local models. |
| My writing service | Calls only the existing private `/write` service. |
| Automatic | Preserves the previous behavior: Apple first, then the private writing service. |

Groq requires internet and is subject to your Groq account's usage limits and billing settings. No Groq key is included in the IPA or source. The fixed HTTPS host is `api.groq.com`; request redirects are rejected, keys are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and raw provider error bodies are not shown or logged. Only text submitted by a deliberate writing-tool action is sent; normal typing does not generate AI requests. Provider data policies apply to submitted text.

**Edit** opens an internal result buffer. Typing there does not change the host app until **Replace** is tapped. Replacement checks that the original selected text or preceding paragraph has not changed. On hiding the keyboard, the preview and edit buffer are cleared from memory.

## Verification and remaining check

Automated checks cover Groq request/response handling with a mocked transport, provider routing policy, settings migration, Unicode result editing and backend boundaries. The iOS UI check adds and selects the actual keyboard, types text, opens the new menu and verifies the Groq setup requirement without replacing text. It then uses a public dummy key and a Debug/simulator-only result fixture to check key import and Edit/Replace. The fixture is excluded from the device Release IPA. These checks do not use a real Groq key. A live writing request still needs to be tried on the user's signed iPhone after setup.

Official references: [Groq API reference](https://console.groq.com/docs/api-reference), [available models](https://console.groq.com/docs/models), [API compatibility](https://console.groq.com/docs/openai).
