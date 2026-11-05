# Managed account connections

Catalog apps now use **Connect account → browser sign-in → permission approval → connection verification**.
This flow is shared by every catalog entry, including Gmail, Google Calendar, Figma, Drive, GitHub, and Notion.
Manual endpoint/token fields appear only in **Custom MCP connection** and existing custom connections.
An app becomes connectable when its connector is configured on the backend. A catalog listing alone does not
mean its service is integrated. Local desktop capabilities and proprietary databases may need a different connector.

## Deploy the connection service

The bridge uses Python 3.11+ and SQLite, with no third-party Python dependencies.
Deploy `Backend/managed-integrations/server.py` behind an HTTPS reverse proxy, with a persistent database volume.
Set a request size limit, connection limits, and a 75-second upstream timeout at the proxy. The default bind address is loopback.
Do not expose the Python development HTTP server directly on the internet.

1. Create a Composio project and API key with connected-account and tool execution permissions.
2. Create an auth configuration for each service you offer. Choose OAuth where supported, including Figma.
   Choose the scopes your app needs; Composio handles consent and token refresh.
   API-key-based services use the provider's hosted credential collection screen rather than an MCP form.
3. Copy `Backend/managed-integrations/connectors.example.json` outside the repository. Replace auth configuration
   placeholders and remove entries you have not configured. Each key is a OneCap catalog ID. The toolkit slug
   can differ: `google-calendar` maps to `googlecalendar`, and `google-drive` to `googledrive`.
   Add other supported catalog services to this JSON without changing Swift code.
4. Provision a random device bearer token per user/device (at least 32 random bytes). Set
   `ONECAP_USER_TOKEN_HASHES` to a JSON object mapping each token's SHA-256 hex digest to a stable, unique user ID.
   The server derives the Composio user from this mapping, never from client input. Multiple devices for one
   person can map to the same user ID. Rotate credentials by replacing entries and reprovisioning devices.
5. Inject secrets through the deployment secret store:

   ```sh
   export COMPOSIO_API_KEY='<server-only project key>'
   export ONECAP_USER_TOKEN_HASHES='<JSON token digest to user ID mapping>'
   export ONECAP_CONNECTORS="$(cat /secure/path/connectors.json)"
   export ONECAP_DATABASE='/persistent/onecap/connections.sqlite3'
   python3 Backend/managed-integrations/server.py
   ```

Never bundle the Composio project key in the desktop application. The example connector file is a configuration
template, not evidence that all listed services are live. Add only services with valid auth configurations.

## Provision the desktop app

For development, add `ONECAP_INTEGRATION_URL` and `ONECAP_INTEGRATION_TOKEN` to the Xcode Run scheme's
environment variables. The URL is the service root, e.g. `http://127.0.0.1:8787` for local development or your
production HTTPS domain. The token is the device bearer token whose hash was registered on the server.
The app copies the token into macOS Keychain on first use; remove it from the scheme after provisioning.

For a distributed deployment, set `OneCapIntegrationURL` in the app's Info.plist or provision the
`managedIntegrationURL` user default. Provision the device token through your enrollment process into a generic
password Keychain item with service `dev.onecap.provider-keys` and account
`31F995CD-850D-46D7-B9D0-567A22D48BD0`. There is no public enrollment or OneCap user-login server in this checkout;
credential enrollment must be supplied before a public rollout. Never ship one shared device credential to all users.

## Behavior and boundaries

- Backend capability discovery controls which app's Connect button can proceed. Unconfigured services explain
  that account linking is unavailable instead of opening a technical form.
- Browser links are restricted to HTTPS on `connect.composio.dev`. The backend and client refuse redirects
  on credentialed API requests. Composio performs the provider's OAuth state/callback processing.
- Sign-in waits up to five minutes, supports cancellation, and removes the pending account on failure/cancel
  after its connection ID has been received. If the app exits before cleanup, an administrator can remove
  abandoned accounts from Composio; this service does not yet run an orphan cleanup job.
- OneCap saves a connection only after the account is ACTIVE and its MCP tools can be loaded.
- The backend validates owner, toolkit, auth configuration, and account status before listing or executing tools.
  Execution takes only tool arguments from the client; account ID, user ID, and tool version come from the server.
  It exposes up to 100 featured tools per app. Existing provider-chat tool count limits still apply.
- Both provider chats and compatible ACP harnesses use the same authenticated HTTP MCP bridge. Existing
  per-action provider-chat approvals and agent-specific permission handling remain in place.
- Disconnect deletes the connected account on Composio before removing local state and its Keychain credential.
  MCP session teardown does not disconnect the account. Revoking the OAuth grant at Google/Figma is a separate
  action in that service's account settings. Expired accounts must be disconnected and linked again.
- No live provider sign-in can be verified without a configured backend, project key, and service auth configs.

## Validation

```sh
cd Backend/managed-integrations
python3 -m unittest -v
```

Swift tests in `ManagedPluginTests.swift` cover service discovery, multiple service links, unsafe redirect rejection,
expired/declined sign-in, timeout/cancellation, endpoint validation, and old saved connections.

Official API contracts: [Connect links](https://docs.composio.dev/reference/api-reference/connected-accounts/postConnectedAccountsLink),
[account details](https://docs.composio.dev/reference/api-reference/connected-accounts/getConnectedAccountsByNanoid),
[tools](https://docs.composio.dev/reference/api-reference/tools/getTools), and
[execution](https://docs.composio.dev/reference/api-reference/tools/postToolsExecuteByToolSlug).
