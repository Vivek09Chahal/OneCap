# OneCap Plugin API v1

OneCap runs independently of installed extensions. It discovers packages at startup in
`~/Library/Application Support/OneCap/Plugins/<package>/plugin.json`.
Use **Plugins → Install plugin…** to copy a plugin folder into this directory.
Use **Reload** after adding or changing files while the app is running.

Packages declare commands and agent tools in `plugin.json`. OneCap registers enabled
commands in its macOS **Plugins** menu and the Installed extensions section. Tools
are registered with provider chats at the next message, using the existing approval
flow. No per-plugin Swift code or rebuild is needed. Current ACP agent harnesses
continue to use separately configured MCP connections; package tools are available
in provider chats. Plugin packages and account integrations are separate concepts:
installing a Gmail package alone does not grant access to a Google account.

## Package format

See [the runnable Text Utilities example](../Examples/Plugins/text-utilities/plugin.json).
A package contains a manifest and its own executable code. Required manifest fields:

- `apiVersion`: `1` (unsupported versions are rejected).
- `id`: unique lowercase identifier with letters, digits, periods, and hyphens.
- `name`, `version`, `summary`: package metadata.
- `entrypoint`: relative file path inside the package.
- `interpreter`: optional `/usr/bin/python3`, `/bin/sh`, or `/usr/bin/osascript`.
  Omit for a directly executable package entrypoint.
- `commands`, `tools`: arrays of features, each with `id`, `title`, `description`,
  and an object JSON Schema in `inputSchema`. Use empty arrays for unused hooks.

## Execution bridge

Each invocation launches a separate process with its working directory set to the
package folder. It receives one UTF-8 JSON document on standard input:

```json
{"apiVersion":1,"method":"tools/call","name":"count-words","arguments":{"text":"hello world"},"context":{"workspace":null}}
```

For a menu command, `method` is `commands/execute`. `workspace` is the selected
folder’s path, or `null`. Standard output must contain exactly one response:

```json
{"apiVersion":1,"result":{"words":2,"characters":11}}
```

Return `{"apiVersion":1,"error":{"message":"Failure"}}` for failure. OneCap reports
a generic failure; diagnostics belong on standard error. Standard error is discarded.
Processes exit after each action; persistent services should use MCP connections.
Plugin authors must validate arguments against their declared schemas. OneCap checks
that arguments are objects; it does not implement a full JSON Schema validator.

## Lifecycle and trust

Discovery parses manifests and hashes package files without running code. Installation
copies a package into the managed directory; it starts disabled. Enabling requires a
trust confirmation. Changing any package file invalidates its approval. Disable or
remove unregisters commands and prevents future tool calls, including calls prepared
before the change. Actions already executing may finish. The original source folder
is preserved when an installed package is removed.

A separate process is **not a sandbox**: trusted plugins have the current macOS user’s
file and network permissions. The host exposes no arbitrary callbacks into its own
objects and does not pass provider credentials or inherited secret environment
variables. This is not protection against a malicious plugin reading user files.
OAuth connections and token storage must be implemented separately by the integration.

Packages are limited to 10 MB, 500 files and 64 declared features. Symlinks and escaping
entrypoint paths are rejected. Each action has a 30-second timeout, 64 KB input limit,
and 1 MB output limit. There are no install scripts. One malformed package is reported
without preventing other packages or the host from loading.

## Try it

1. Install the `Examples/Plugins/text-utilities` folder from the Plugins page.
2. Select **Show files** to review its code, then enable it.
3. Choose **Plugins → Text Utilities → About Text Utilities** from the menu.
4. In a provider chat, ask to count words using Text Utilities and approve the call.
5. Disable or remove the package to unregister its features.
