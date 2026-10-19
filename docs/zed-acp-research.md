# How Zed installs ACP agents

Inspected public upstream `main` on 2026-10-18. These links track upstream and may change. OneCap is a new Swift implementation of the documented protocol and registry format; it does not copy Zed's Rust/GPUI UI implementation.

## The distinction that drives the architecture

An ACP agent is an executable harness or adapter. A model provider is a remote inference API. OpenCode, Kimi CLI, and Amp are agent integrations; DeepSeek can be used as a provider where supported. Installing an agent does not install all of its models or supply its credentials. The user's “kiwi” is interpreted provisionally as Kimi CLI, which appears in the registry.

Zed also keeps external agent configuration separate from its own LLM provider settings: [external agents](https://zed.dev/docs/ai/external-agents) and [agent settings](https://zed.dev/docs/ai/agent-settings).

## Source map

| Responsibility | Upstream code | What it does |
| --- | --- | --- |
| Discovery | [agent_registry_store.rs](https://github.com/zed-industries/zed/blob/main/crates/project/src/agent_registry_store.rs) | Fetches the public registry, parses distribution metadata, determines platform support, prefers a matching binary and falls back to npm. |
| Installation and command construction | [agent_server_store.rs](https://github.com/zed-industries/zed/blob/main/crates/project/src/agent_server_store.rs) | Downloads versioned archives/raw binaries, verifies checksums (with GitHub release digest fallback), resolves commands and environment, installs npm packages through a managed Node runtime, and reads package executables. |
| Runtime management | [node_runtime crate](https://github.com/zed-industries/zed/tree/main/crates/node_runtime) | Provides Node/npm binaries and environment to integrations. |
| Registry UI | [agent_registry_ui.rs](https://github.com/zed-industries/zed/blob/main/crates/agent_ui/src/agent_registry_ui.rs) | Presents installable agents and installation state. |
| Agent lifecycle | [acp.rs](https://github.com/zed-industries/zed/blob/main/crates/agent_servers/src/acp.rs) | Connects external agents to the editor's session and client capabilities. |
| Process transport | [transport.rs](https://github.com/zed-industries/zed/blob/main/crates/agent_servers/src/acp/transport.rs) | Spawns a child with piped stdin/stdout/stderr, sends newline-delimited JSON, reads responses, and owns cleanup. |

Registry index: [registry.json](https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json). The index declares agents and their versions; each entry can have `binary`, `npx`, and/or `uvx` distributions. Platform identifiers include `darwin-aarch64` and `darwin-x86_64`. Binaries specify archive URL, command, arguments, environment, and optional SHA-256. See the [registry format](https://github.com/agentclientprotocol/registry/blob/main/FORMAT.md).

Zed's inspected registry selection code handles binary/npm distributions. A distribution type existing in the registry specification does not guarantee every client supports it.

## The process behind “Install”

1. Fetch metadata from the ACP registry.
2. Pick a distribution for the current platform.
3. Download/cache the binary or install the package using a managed runtime.
4. Construct executable, arguments, environment, and working directory.
5. Launch the process with pipes.
6. Send ACP `initialize`, negotiate capabilities, and offer returned authentication methods.
7. Create a session with `session/new`, then send `session/prompt` and consume `session/update` events.
8. Handle agent-to-client requests, including permissions, files, and terminal capabilities that the client advertises.

Protocol references: [initialization](https://agentclientprotocol.com/protocol/v1/initialization), [session setup](https://agentclientprotocol.com/protocol/v1/session-setup), and [prompt turns](https://agentclientprotocol.com/protocol/v1/prompt-turn).

## Why installing every registry entry is not sufficient

The [Amp adapter README](https://github.com/tao12345666333/amp-acp#prerequisites) explicitly requires a separate Amp CLI and authentication. Downloading the adapter binary does not satisfy that dependency. A complete no-terminal product needs a tested dependency recipe for such agents, not just generic registry parsing.

Provider API keys also are not interchangeable with agent credentials. OneCap's first direct chat client accepts compatible HTTPS Chat Completions endpoints; [DeepSeek's API documentation](https://api-docs.deepseek.com/) documents that compatibility. Mapping a saved provider to an agent must use that agent's supported configuration, with explicit credential scope.

## OneCap implementation and next milestones

The initial app implements registry discovery, binary/npm installation, a shared managed Node LTS runtime, Keychain provider keys, direct provider chat, and a minimal ACP v1 text client. SwiftUI owns the interface; AppKit supplies the folder picker. UIKit is not the native macOS framework.

Next milestones: dependency recipes (starting with Amp), managed uv/Python, per-agent key configuration and richer auth flows, client file/terminal tools with review UI, agent model/config selectors, durable conversations, session resume, install cancellation, uninstall/cleanup, and signed/notarized distribution. Live agent compatibility and UI visual QA remain necessary; successful compilation is not proof of those integrations.

## Verification of this implementation

The macOS Debug target builds successfully with Xcode 27.1, with code signing disabled for the build check. Eight Swift Testing checks passed, including live installation of the current registry's OpenCode Mac binary and Codex ACP npm package using a newly downloaded managed Node.js runtime. Both live installs used temporary directories, removed after the checks. No real agent prompts, account authentication, or billable provider requests were used. UI visual inspection was interrupted and remains unverified.


## Automatic connection and browser login

The inspected Zed ACP v1 implementation advertises URL elicitation and forwards agent-managed authentication through `authenticate`: [v1.rs](https://github.com/zed-industries/zed/blob/main/crates/agent_servers/src/acp/v1.rs). The [ACP authentication specification](https://agentclientprotocol.com/protocol/v1/authentication) distinguishes agent-managed login from terminal login, and [URL elicitation](https://agentclientprotocol.com/protocol/v1/elicitation) defines agent-provided browser interactions.

OneCap now uses a SwiftUI task keyed by agent, conversation, and project folder to connect automatically. It attempts `session/new` first, handles the typed authentication-required error, invokes an advertised agent-managed authentication method, and retries session creation once after successful login. It does not retry a submitted prompt automatically. Active authentication URL requests can launch the default browser; unrelated requests, non-web URLs, and remote plain-HTTP URLs cannot. Browser navigation alone does not mark a session ready.

Connection cancellation uses generation checks so a previous agent cannot overwrite a newer selection. Mock-agent tests cover saved login reuse, browser login, failed authentication, unrelated URL requests, and switching during connection. Real provider accounts were not used. Terminal login and legacy terminal-auth metadata are implemented in the subsequent terminal integration below.


## Terminal authentication integration

OneCap now advertises terminal authentication only when a terminal runner is attached. It follows the [ACP terminal authentication flow](https://agentclientprotocol.com/protocol/v1/authentication): run a separate interactive process with the configured agent invocation plus the descriptor arguments/environment; consider only zero exit successful; reconnect and initialize ACP afterward. It never calls `authenticate` for a terminal method.

The [Zed legacy metadata handler](https://github.com/zed-industries/zed/blob/main/crates/agent_servers/src/acp/v1.rs) also accepts `_meta.terminal-auth` with command, args, and environment. OneCap supports that descriptor as a compatibility path, resolving commands through the configured environment and managed npm binaries.

The interactive frontend embeds [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm/tree/v1.20.0) 1.20.0 in a SwiftUI sheet using its AppKit local-process terminal. This provides a real pseudo-terminal and escape-sequence rendering rather than a plain output log. The core coordinator and command builder do not depend on the terminal UI. Tests cover descriptor semantics, cancellation/failure, login URL detection, ACP reconnection, and a real PTY process reading interactive input. Actual provider account sign-in remains to be exercised manually.
