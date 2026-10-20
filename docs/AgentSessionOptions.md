# Agent settings in the composer

The model selector shows only model options. Every other advertised session option
gets its own composer control, in agent order: modes such as Plan/Ask, reasoning,
fast mode, workspace access, permissions, and custom settings. Controls wrap when
the chat column narrows. Unsupported or unadvertised features are not invented;
OneCap relies on the agent to enforce a selected workspace or permission policy.

Select controls display only the selected value, such as Medium or Ultra; their
names and descriptions remain available through hover and accessibility labels.
Boolean and two-choice On/Off settings use labeled switches. Controls preserve the
agent's exact IDs, groups, descriptions, and current value. The client advertises
`clientCapabilities.session.configOptions.boolean` and sends an actual JSON
boolean with `type: "boolean"` when updating those options. Other select values
remain strings. Configuration is updated only from the agent's confirmed reply or
current-session notification. Existing legacy model/mode RPCs remain supported.

Composer popovers anchor with their arrow at the bottom. Lists scroll and cap their
height to the space above the triggering control, keeping expansion above the
text field. Escape closes the list. Changing an option closes its list and disables
the other controls until the agent confirms the new configuration.

Offline tests exercise a mock ACP process with independent model, reasoning, mode,
boolean fast-mode, and workspace-access options, including boolean wire types,
invalid values, and session restart. Hidden fixture renders check wide/narrow
composer layouts in both themes; no live provider sign-ins are used for validation.

Protocol: [ACP session config options](https://agentclientprotocol.com/protocol/v1/session-config-options).
