# Code organization and concurrency

## UI composition

`ContentView` owns navigation, startup, and global presentation. A fixed icon rail sits beside `WorkspaceSplitView`, which uses a stable native HSplitView inside a NavigationStack for the resizable history sidebar and selected feature. The native toolbar includes a history visibility toggle. `Views/History` separates history navigation, grouped lists, conversation rows, and native context menus. Renamed titles, pin state, and archive state are optional transcript metadata for compatibility with earlier saved histories. `Views/Components` contains shared presentation such as the sidebar, section headings, card styling, and permission sheet. Feature-specific components live under `Views/Registry`, `Views/Providers`, and `Views/Chat`. Registry and provider management share page/section headers. The registry combines supported native binary and managed CLI installation routes in one catalog, with native toolbar search and refresh. `AgentCompatibility` shares install eligibility and known integration exclusions between browsing, the installer, default selection, and connection startup. Existing unavailable installations remain removable. Registry sections distinguish installed and available agents; provider cards separate identity, endpoint/model details, and actions. The add-provider sheet composes reusable labeled fields around the existing Keychain-backed save operation.

Registry cards, provider cards, messages, the transcript, and the composer accept values, bindings, and actions rather than requiring the whole app store. Feature containers connect those components to application state. `ChatLayout` shares the centered column dimensions between the transcript and composer; DLS supplies the semantic sidebar/composer colors and font tokens for both themes. `AppStore` stays on the main actor; its catalog, provider, and conversation operations are grouped in separate extensions.

## Services

- `HTTPDownloader` implements the injectable, Sendable `Downloading` protocol.
- `AgentInstaller` coordinates installations and uninstall transactions. Uninstall derives the owned directory from the validated agent ID, stages it before removing metadata, and restores files if that write fails. Per-agent guards prevent installation/removal overlap; shared runtimes and unrelated files are preserved. `BinaryAgentInstaller` and `NpmAgentInstaller` handle distribution-specific details.
- `PackageValidation` owns identifier, path, and SHA-256 checks. `ArchiveExtractor` owns extraction and link validation.
- `NodeRuntime` manages the shared runtime. Registry and package response models have separate types.
- `ConversationRepository` saves local transcript snapshots in a separate file. `AppStore+History` preserves connection settings and drafts, orders snapshot writes, and rebuilds visible ACP context once on continuation. Partial-response snapshots freeze their timers; historical agent runtime and tool state are not restored.
- `AppRepository` owns persisted settings and Keychain operations. Each mutation is a serialized read-modify-write transaction.
- `ProcessRunner` handles command execution and cancellation. `WorkspaceFolderPicker` keeps AppKit interaction on the main actor and presents asynchronously.

## Protocol contracts

`OneCap/Protocols` contains the shared service contracts. Callers accept protocols through their initializers; implementations remain responsible for their actor isolation and execution behavior.

- `SnapshotRepository<Value>` supplies typed load/save operations. `JSONFileRepository` implements atomic JSON persistence once; `ConversationRepository` and `ProjectRepository` specialize it while retaining their existing filenames and JSON formats. AppStore accepts injected repositories, including in-memory implementations.
- `AgentInstalling` separates AppStore from registry/install/uninstall coordination. `AgentDistributionInstalling` gives binary and npm strategies a common command-preparation operation, followed by the coordinator's existing atomic publish step.
- `Downloading`, `ArchiveExtracting`, `NodeRuntimeProviding`, and `ProcessRunning` isolate package dependencies. Installation strategies can use substitute downloaders, extractors, runtimes, and process runners without performing real downloads or launching processes in tests.
- `ProviderResponding` lets AppStore request provider replies through an injected client.

The transactional settings/Keychain repository and observable ACP connection retain their specialized behavior. Snapshot protocols do not replace settings transactions or ACP lifecycle state.

## Execution rules

UI state is main-actor isolated. Network clients explicitly use `@concurrent`, so encoding and decoding do not inherit a UI caller's executor. Installer and repository actors protect their own mutable state and perform filesystem work outside the main actor.

Independent startup tasks and Node archive/checksum downloads use `async let`. Repeated concurrent requests for an agent version share one installation task; concurrent npm installs share one runtime setup task. These shared setup tasks complete for their waiters rather than being cancelled by one caller alone.

Blocking pipe reads and process waits use utility Dispatch threads through checked continuations, rather than blocking Swift's cooperative thread pool. Cancelling a direct `ProcessRunner` task terminates its process and reports `CancellationError`; this does not provide process-tree cancellation. Package installation still has no UI cancel control.

The ACP connection remains main-actor isolated with its observable connection state and protocol lifecycle. It uses asynchronous file-handle callbacks for incoming process data. Additional actors are not introduced for small UI/protocol transitions that require ordered state changes.

## Verification

The macOS build and core suite pass after the protocol refactor. Tests cover protocol-backed dependency injection, JSON format compatibility, distribution strategy substitution, concurrent installation deduplication, shared runtime failure/retry, concurrent repository writes and disk reload, parallel command output, process failure and cancellation, existing protocol and validation behavior, and real binary/npm installations in temporary folders.

## Design tokens

`Packages/DLS Package` is a separate local Swift package exposing the `DLS` module. It supplies spacing, radius, size, typography, and semantic light/dark color tokens. Presentation roots apply `.dlsAppearance(...)`; components consume `@Environment(\.dlsTheme)`. The app persists the System/Light/Dark setting with AppStorage.

The sidebar uses a native `MazeMark` Shape. The same vector geometry generates all macOS app icon sizes. Regenerate assets from the repository root with:

```sh
xcrun swiftc -parse-as-library Scripts/GenerateAppIcon.swift OneCap/Views/Components/MazeMark.swift \
  "Packages/DLS Package/Sources/DLS/ColorTokens.swift" -o /tmp/OneCap-generate-icon
/tmp/OneCap-generate-icon
```

`ChatWorkspaceDirectory` resolves an explicitly selected project folder or creates an app-managed directory for the current conversation. ACP receives a valid working directory even when the user does not attach a project. Project selection remains optional and stays beside the composer.

## Terminal login

`TerminalLoginCommand` resolves modern and legacy descriptors into an executable, literal arguments, environment, and cwd. `TerminalLoginCoordinator` presents one in-memory login session and propagates success, failure, and cancellation. The SwiftUI authentication sheet embeds SwiftTerm's AppKit terminal. ACP reconnects after successful login because credentials changed in a separate process. Selecting another agent, stopping setup, closing the sheet, or quitting cancels the active login. SwiftTerm is pinned in the app project; the core test target also links it to exercise actual PTY behavior.


## Expired authentication

`ACPAuthenticationFailure` classifies the standard ACP auth-required error and narrowly recognized credential-expiry messages, including adapters that use an internal-error code. The connection invalidates its session readiness when these responses arrive. Initial session preparation can authenticate once; explicit reauthentication verifies the replacement session without starting another automatic login. Prompt failures surface a recovery action rather than a generic modal error. AppStore preserves the current conversation and requires an explicit Retry last message after successful login, using the existing edit/resend path to retain the user message ID and attachments. Quota, model-access, and network errors remain ordinary failures.


## Chat rendering and input

`ChatTranscriptEntry` pairs each visible message with its reply timing using one immutable snapshot. Lazy rows do not retain indexes into AppStore’s mutable transcript during edits or auth recovery. Streaming scroll requests are coalesced and deferred outside the render pass, alongside native size-change anchoring. Login sheets bind to their session item, and terminal startup/completion callbacks avoid mutating sheet state during representable creation. The composer handles Return as send and leaves Shift/Option-Return available for multiline input; blank or unavailable submissions retain their draft. Authentication actions appear in recovery notices rather than as an always-visible toolbar key.


`Scripts/VerifyChatRecoveryLayout.swift` runs a local mock ACP agent against the built Debug app module in an isolated hidden window. It exercises repeated streamed OAuth errors, checks the inline recovery state, and verifies rendered pixels for both the history header and composer. The native NavigationSplitView previously yielded empty column captures in this check; WorkspaceSplitView retains them. The script uses temporary storage and never contacts a real provider or signs in to an account.

## macOS workspace behavior

Each window owns an `AppStore` selection and draft. `AppLibrary` shares history, provider and agent catalogs, repositories, and ordered persistence queues. Window routing focuses an existing owner when a chat is already open; opening the current chat in a new window transfers it. Archive, delete, and project removal reset affected windows before saving so stale drafts cannot restore removed records.

History retains pinned and project sections and groups standalone chats by calendar day. Rename edits directly in a row: Return commits, Escape cancels, and leaving the field commits a nonempty title. Archive supports Undo and Redo; permanent deletion still requires confirmation. Sidebar search uses `NSSearchField` and Command-F reveals and focuses it.

The menu bar exposes New Chat (Command-N), New Window (Command-Shift-N), page navigation (Command-1 through Command-6), Settings (Command-comma), and Toggle History (Control-Command-S). The chat toolbar supports native customization with persistent item identifiers. A status strip shows connection and response state plus the current model; long drafts show a character count.

`Scripts/VerifyMacWorkspace.swift` renders isolated light and dark fixtures at standard and minimum window sizes, checks toolbar customization and palette items, and verifies native search focus. `MacWorkspaceTests` covers calendar boundaries across daylight saving, independent drafts with shared history writes, and cross-window archive/delete behavior.
