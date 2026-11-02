import DLS
import SwiftUI

struct RequestSettingsView: View {
    @Environment(\.dlsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.xxl) {
            Text("Changes save automatically and apply to the next request. Times are in seconds; 3,600 seconds is one hour.")
                .foregroundStyle(theme.colors.textSecondary)
            group("Waiting periods", limits: [
                (.connection, "Agent connection and options", "Time allowed for each connection, session setup, or model option request."),
                (.agentResponse, "Agent response", "Maximum time for a complete reply, including commands and permission waits."),
                (.providerResponse, "Provider response", "Maximum time for each provider request, including workspace tool rounds and chat titles."),
                (.authentication, "Agent sign-in", "Time allowed to complete an agent authentication request."),
                (.cancellation, "Stop acknowledgement", "Time to wait after Stop before disconnecting an unresponsive agent.")
            ])
            group("Downloads", limits: [
                (.download, "Agent and catalog downloads", "Time allowed for each network download attempt."),
                (.skillDownload, "Skill download", "Time allowed to wait for data when importing a Markdown skill.")
            ])
            group("Automatic retries", limits: [
                (.retryCount, "Additional attempts", "0 turns retries off. Applies to agent connections, downloads, and temporary provider rejections (HTTP 429 or 503)."),
                (.retryDelay, "Retry delay", "Wait between attempts. Each attempt gets its own waiting period.")
            ])
            Text("Agent messages and timed-out provider messages require manual retry to avoid duplicate commands or replies. Sign-in failures, invalid requests, and cancelled operations are not retried. External agents manage their own internal network and tool limits.")
                .dlsFont(.callout).foregroundStyle(theme.colors.textSecondary)
            Button("Reset to defaults") {
                for limit in RequestSettings.Limit.allCases {
                    UserDefaults.standard.removeObject(forKey: limit.key)
                }
            }
        }
    }

    private func group(_ title: String, limits: [(RequestSettings.Limit, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            Text(title).dlsFont(.heading)
            VStack(spacing: DLSSpacing.lg) {
                ForEach(limits, id: \.0) { limit, title, detail in
                    RequestLimitRow(limit: limit, title: title, detail: detail)
                    if limit != limits.last?.0 { Divider() }
                }
            }
            .cardSurface()
        }
    }
}

private struct RequestLimitRow: View {
    @Environment(\.dlsTheme) private var theme
    let limit: RequestSettings.Limit
    let title: String
    let detail: String
    @AppStorage private var value: Int

    init(limit: RequestSettings.Limit, title: String, detail: String) {
        self.limit = limit
        self.title = title
        self.detail = detail
        _value = AppStorage(wrappedValue: limit.defaultValue, limit.key)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DLSSpacing.lg) {
            VStack(alignment: .leading, spacing: DLSSpacing.xs) {
                Text(title)
                Text(detail).dlsFont(.callout).foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: DLSSpacing.xs) {
                TextField(title, value: Binding(
                    get: { value },
                    set: { value = min(max($0, limit.range.lowerBound), limit.range.upperBound) }
                ), format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .accessibilityLabel(title)
                .accessibilityIdentifier(limit.key)
                if limit != .retryCount { Text("s").foregroundStyle(theme.colors.textSecondary) }
                Stepper(title, value: $value, in: limit.range).labelsHidden()
                    .accessibilityLabel("Adjust \(title)")
            }
            .fixedSize()
        }
    }
}
