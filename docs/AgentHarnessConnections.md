# Agent harness connections

The Agent Harnesses page retains the ACP registry as its catalog source. Changing the page name does not remove registry entries or change saved agent IDs. Existing compatibility exclusions still apply.

| Harness | OneCap connection |
| --- | --- |
| Codex (`codex-acp` or `codex`) | Official `codex app-server` over stdio JSON-RPC, without the ACP adapter |
| All other registry entries | Existing ACP connection and advertised distribution |

Several upstream harnesses, including Cursor, Copilot, and Antigravity, expose ACP directly. ACP is their interface, not necessarily a separate adapter process. Adapter-based entries, including Claude, remain supported through their existing distributions; additional native interfaces need their own implementation and compatibility tests before changing their routes. OneCap does not silently drop these agents or substitute a provider-only model call for their harness.

## Codex

`OfficialCodex` replaces the registry's adapter distribution with the official pinned `@openai/codex@0.160.1` npm package and `app-server` arguments. The existing `codex-acp` ID remains unchanged for saved chats, agent selection, and uninstall ownership.

Managed npm installations of the old adapter already contain `@openai/codex`. On settings load, OneCap verifies that package's manifest and rewrites launch metadata to its `bin/codex.js app-server` entry. The adapter's JavaScript is no longer launched. Existing files are retained until the user updates or uninstalls the agent. Older standalone adapter binaries without a reusable official package require an update from Agent Harnesses; they do not silently fall back to the adapter.

`ACPConnection` retains the shared process/pipe lifecycle and existing observable UI state. It selects `CodexAppServer` behavior for Codex IDs and ACP behavior for every other agent. The Codex wire omits ACP initialization, `session/*`, authentication RPCs, and the `jsonrpc` header. The internal class name is retained for compatibility with existing callers and tests.

The native route handles initialization, account checks and browser sign-in completion, paginated model catalogs, workspace-write threads with user-reviewed approvals, model/reasoning overrides on each turn, message and tool events, and turn completion/interruption. A turn/start acknowledgment is not treated as a completed reply. Unsupported server requests return an explicit capability error. Existing visible-history replay and edit/restart behavior are retained; native thread IDs are not yet persisted with saved chats.

Tests use a local mock app-server for login success/failure, event races, streaming deduplication, stale threads, model changes, approvals, cancellation, server errors, and migration. A real installed Codex handshake also verifies account detection and model listing without running inference. This does not establish live-account compatibility for every catalog entry.

Official protocol: https://learn.chatgpt.com/docs/app-server
