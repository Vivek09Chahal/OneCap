# OneCap

A native macOS workspace for agent harnesses and user-supplied model providers. All external agent harnesses connect through ACP. Built with Swift 6, SwiftUI, Observation, AppKit, Foundation, CryptoKit, and Security. The embedded login terminal uses the pinned SwiftTerm 1.20.0 package.

Open `OneCap.xcodeproj` in Xcode 27.1 or later and run the **OneCap** scheme on **My Mac**. Deployment target: macOS 26.0. This is a developer MVP, not a notarized distribution.

## Use

1. **Agent Harnesses:** browse supported native Mac and managed CLI agents together, grouped under **Installed** and **Available**. These binaries run inside OneCap rather than installing standalone `.app` bundles. OneCap selects the Mac architecture, prefers a native binary when both distributions exist, and manages Node.js for CLI packages.
2. **Workspace → Agent harness:** select an installed agent. OneCap connects automatically, checks existing credentials, and starts agent-managed sign-in if required. Browser login requests open in your default browser. A project folder is optional; add one above the message box when you want to work with project files. Authentication and model availability remain agent-specific.
3. **Providers:** add a name, HTTPS API base URL, model ID, and API key. The endpoint must support OpenAI-compatible Chat Completions. Keys go to macOS Keychain; metadata goes to Application Support.
4. **Workspace → Provider chat:** choose a provider and send a message. Command-Return also sends. Direct provider chat does not run coding tools.

The DeepSeek form is a preset, not a bundled credential or subscription. Other compatible endpoints can be entered manually. API base URLs may include `/v1`; OneCap appends `/chat/completions`.

## What works in this first build

- An icon-only navigation rail and a separate history sidebar with project groups, recent chats, and search. New chat lives on the left of the chat toolbar (Command-N). Reopen a conversation by selecting it; right-click a row to rename, pin, copy, archive, or delete it. Use the sidebar header menu to view archived chats. History saves locally on this Mac.
- Live catalog with native toolbar search and refresh, separate Installed/Available sections, persistent install records, explicit updates, and a trash-icon uninstall action on installed cards.
- Checksum-verified Mac binary archives and raw binaries; staged installation preserves prior versions on failure.
- Managed Node.js LTS downloaded from nodejs.org with SHA-256 verification, local npm installation, and direct execution of the package entry point.
- ACP v1 initialization, automatic session setup, text updates, permission choices, agent-managed authentication and URL login elicitation, timeouts, and disconnect cleanup.
- All external agent harnesses use ACP, including Codex. Saved Codex launch records from the previous native integration are restored to their bundled ACP adapter when available; native-only installations require reinstalling Codex from Agent Harnesses.
- Provider management with toolbar search and Add provider, readable model/endpoint details, direct Open chat actions, and a removal confirmation. The add-provider sheet offers DeepSeek and custom presets.
- Direct provider chat with Keychain credentials. Authorization is not forwarded through HTTP redirects.
- A centered conversation column and aligned rounded composer, warm user message bubbles, turn dividers, compact copy/edit actions, and inline editing of the latest user message. Save & resend replaces its response while preserving earlier turns and the composer draft.
- A live thinking timer freezes on the first answer text and stays visible afterward. Stop and failure also freeze the timer.

## Current boundaries

- Agent Harnesses downloads agent software or adapters, not cloud model weights. Each agent controls supported models and billing.
- Amp’s adapter requires an external Amp CLI, which OneCap does not manage. It is excluded from available installs and chat selection for now. Existing copies remain removable. Registry manifests do not describe every external dependency, so filtering is not a guarantee of account-level compatibility.
- Unsupported distributions are hidden from available installs: Python/uvx-only packages, native binaries without valid registry or pinned checksums, and unsupported binary launch configurations. Gemini CLI is temporarily excluded because its individual-account Google login can fail with an unsupported-client response. See [the upstream report](https://github.com/google-gemini/gemini-cli/issues/29279). API-key authentication is documented upstream but is not yet wired into OneCap’s ACP login flow.
- Compatibility filtering covers known client limitations; remaining agents still require their own valid credentials, and real-account compatibility has not been verified for every entry. Existing unavailable installations remain visible for uninstall; their files and chats are not silently deleted.
- Agent authentication is invoked through ACP after session creation reports authentication required. Existing credentials are checked first. Protocol-driven agent login and request-scoped URL elicitation are supported; browser navigation is restricted to the active authentication request. First-class terminal login and legacy `terminal-auth` metadata open an embedded terminal; successful exit triggers an ACP reconnect. General agent tool terminals and form elicitation remain unsupported. Individual agent compatibility still needs verification with real accounts.
- Client-provided file and terminal capabilities are advertised as unsupported. Agents can still use their own native file and execution tools. The working folder is not an OS-level security boundary.
- The app sandbox is disabled to support downloaded executables and agent tools. Installed code runs with the user's account privileges, including npm setup scripts. Distribution should use Developer ID signing and notarization, with a deliberate runtime trust policy; this is not currently an App Store design.
- Direct chat supports text responses from compatible Chat Completions APIs; no streaming, Anthropic-native API, Responses API, images, or local HTTP endpoints yet.
- Editing an ACP message starts a fresh agent session with the earlier visible transcript as context. It does not undo tool actions or file changes from the replaced response.
- History restores the visible transcript and connection settings. ACP continuation starts a fresh session with the saved transcript as context; hidden reasoning, agent-owned session state, and tool state are not restored. No custom agent editor, per-agent secret mapping, automatic old-version cleanup, or MCP configuration UI yet.
- Stop cancels the current reply and preserves the transcript and draft. ACP cancellation keeps the session when acknowledged; an agent that does not acknowledge cancellation within 10 seconds is disconnected. New conversation saves the outgoing chat to history and opens an empty transcript. Package installations currently have no cancel control.

## Storage

`~/Library/Application Support/OneCap/` contains metadata (`state.json`), local chat history (`conversations.json`), saved project directories (`projects.json`), versioned agents, managed Node runtimes, npm cache, and per-conversation `ChatWorkspaces` folders used when no project is selected. Provider API keys live separately in Keychain. Agents may maintain their own credentials and session files outside this folder.

## Validation

```sh
xcodebuild -project OneCap.xcodeproj -scheme OneCap \
  -destination 'platform=macOS' -derivedDataPath /tmp/OneCap-build \
  CODE_SIGNING_ALLOWED=NO build
swift test --scratch-path /tmp/OneCap-swift-tests
# Optional: downloads and installs real packages in temporary folders, then removes them.
ONECAP_LIVE_INSTALL_TESTS=1 swift test --scratch-path /tmp/OneCap-swift-tests
```

Core tests cover registry decoding, package-name parsing, archive checksums, traversal and symlink rejection, provider URL validation, and ACP initialization/session/prompt/disconnect over a real subprocess using a local mock server. The mock requires `/usr/bin/python3` from the Xcode command line tools. Live providers need your own API key; they are not exercised by automated tests.

See [the Zed implementation research](docs/zed-acp-research.md) for the architecture and source links.

See [code organization and concurrency](docs/architecture.md) for the reusable components, actor boundaries, shared installation tasks, and process execution design.

Design tokens live in [DLS Package](Packages/DLS%20Package/README.md), linked as the `DLS` library. The app supports System, Light, and Dark appearance through Settings.

The Skills page includes **Add Caveman**, which installs the bundled [Caveman voice skill](https://github.com/juliusbrussee/caveman#say-less-the-caveman-voice) as an enabled global skill. Its instructions are shared with ACP agents and provider chat through the existing skill context. It is optional, works offline, and can be disabled or edited like other skills. Start a new chat after disabling it to clear instructions retained by the current session. Re-adding preserves local edits. Only the voice skill is included; the Caveman CLI, proxy, compression runtime, routing, and hooks are not installed. The pinned revision and upstream license notices ship beside its editable SKILL.md.

To add a skill from a public URL, click **+** on the Skills page, paste a GitHub Markdown file link or an HTTPS raw Markdown URL, and press **Fetch** or Return. Edit the fetched Markdown and skill name, then choose **Add skill** to save a local copy in the selected scope. Existing front matter is preserved. Downloads are limited to 256 KB; HTML pages and invalid UTF-8 are rejected.

The optional working-folder button sits inside the chat composer, on the left of its bottom row. Choosing a folder preserves the current draft. The first successfully installed agent becomes the default; subsequent installs and updates preserve the selection, which is restored on launch. Existing installations without a saved default use the first installed agent.

The top toolbar selects the installed ACP agent. The composer’s lower-right menu only shows that agent’s model, reasoning, and other advertised session choices (or saved provider models in provider chat); selection changes are confirmed over ACP before sending. Older ACP model/mode selectors are also supported. Agents that expose no model options keep their own defaults. Choices survive editing/resending within the live session; reconnecting or reopening a saved conversation uses the agent’s defaults. Provider chat uses the model IDs configured on the Providers page. New chat, connection type, and sign-in actions use the native SwiftUI toolbar. Selecting an agent, changing the optional project folder, or starting a new conversation prepares a session automatically. A Retry action is available if setup fails; there is no initial manual Connect step.

## Interactive agent sign-in

When an agent requests terminal authentication, OneCap opens a login sheet with a real VT100/Xterm terminal. Type and navigate normally, or complete a browser/device-code flow. Matching login links in terminal output can open in the default browser. The terminal transcript is not recorded to disk by OneCap. Sign-in is successful only after the login process exits with status zero and the reinitialized ACP agent creates a session. Cancel closes the login attempt without clearing the chat.

Modern terminal methods reuse the configured agent executable, base arguments, environment, and working directory, then append the advertised login arguments and environment overrides. Older Zed `_meta.terminal-auth` descriptors use their explicit program. Commands are passed as executable/argument arrays rather than interpreted by a shell.

Xcode may prompt you to trust **SwiftTermBuildInfoPlugin** on the first build. This plugin generates source-control build metadata for the pinned terminal library. The automated build check reviewed that plugin and used `-skipPackagePluginValidation` for that build invocation; no global trust setting was changed. Approve the plugin in Xcode for normal interactive builds.

Uninstall removes the agent’s managed directory, including retained versions, and its installation record. A failed settings write restores the staged directory. Saved chats, provider keys, shared Node runtimes/cache, external CLIs, and agent-owned sign-in files outside the installation directory remain. The next installed agent becomes the default when the selected agent is removed; removing the last agent clears the selection.


Grok Build’s npm entry can be a link to a bundled Mach-O executable. OneCap resolves links only within the managed installation and launches native entries directly; JavaScript entries continue to use managed Node.js. Removal paths still reject symbolic links.

Cursor is available in the ACP registry using its official CLI (`cursor-agent acp`), installed inside OneCap without running Cursor’s shell installer. The 2026.10.16-e3cb207 and 2026.10.19-6bbf2c4 Mac archives have SHA-256 pins in `KnownBinaryChecksums.swift` because the upstream registry omits checksums. New Cursor releases without registry checksums require refreshed pins before installation or update. An unverified update does not move an existing installed agent into Unavailable installations; its installed copy remains listed while the update is blocked. Cursor sign-in and account access are still required; OneCap does not install the Cursor editor.

Composer controls separate agent modes (such as Plan or Ask) beside the folder button from model/reasoning selection on the right. Composer choice lists open above their controls and scroll within a bounded height. The ACP agent selector remains in the top toolbar.

Project directories persist independently of their chats. Add a folder with the Projects heading’s plus button; select its name to return to its latest chat or use its plus button to start a separate chat in that directory. Each folder expands to its own history, while Recents includes project and standalone chats. Existing folder-associated chats automatically populate Projects on launch.

The composer plus button opens upward with Attach file and Attach folder options. Attach up to five files per message: UTF-8 text/code files up to 256 KB each, or images up to 10 MB each. Images can also be pasted, and files can be dropped onto the composer. Image previews and bytes are saved with local chat history. ACP image blocks are sent only to agents advertising image support; unsupported agents leave the draft intact. Provider chat sends image content to the configured model. PDF and other binary attachments are not supported.

The composer stays editable during a response. Sending a follow-up captures its text and attachments in a visible queue while the active run continues. Successful completion sends queued messages in order through the same session, with separate replies and file snapshots. Stop or failure pauses the queue. Queued messages can be removed, are saved with the conversation, and require an explicit Send queued messages action after reopening. Agent, model, and working-folder changes remain locked during a run.

The File changes review includes an Edit file action in the same review pane. Save (Command-S) writes the file, refreshes its diff/counts, and preserves the original undo baseline. Drafts survive switching files; closing with unsaved edits asks before discarding them. Saving refuses to overwrite a newer disk version and is unavailable while an agent is running. Reload reads the latest disk version, and Undo/Implement changes includes saved manual edits.


ACP authentication recovery recognizes the standard auth-required response and explicit OAuth-expiry errors returned as internal errors, including “OAuth session expired and could not be refreshed.” During an existing chat, OneCap preserves the transcript, draft, and attachments and shows Sign in again. It runs the agent-advertised browser/terminal method, reconnects as needed, and verifies the new credentials once before enabling chat. For Claude, the advertised subscription/Console login commands run in the existing login terminal; OneCap does not read, delete, or refresh Claude’s credential store itself. After sign-in, Retry last message retries the existing user turn with its attachments and prior visible context; requests are never replayed automatically. Cancellation and failed verification keep the chat and avoid repeated automatic login attempts.

Return sends the composer message; Shift-Return (or Option-Return) inserts a newline. Command-Return remains available. The always-visible authentication key is removed from the toolbar; Sign in again appears with authentication recovery notices. Transcript rows render from immutable message/timing snapshots, and native scroll anchoring and coalesced, deferred scroll updates replace per-chunk scroll commands during streaming. Login sheets use session identity and defer terminal process startup until after view creation.

Agent request failures are displayed inline rather than using the global application alert. Authentication recovery also recognizes structured ACP error details and streamed login-failure text paired with a rejected prompt; successful answers quoting such text do not trigger login. Return submission is deferred until native text-event dispatch finishes, with marked-text composition left to the input method.
