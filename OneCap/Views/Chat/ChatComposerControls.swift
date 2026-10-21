import DLS
import SwiftUI

/// Keep controls readable when an inspector makes the chat column narrow.
struct ChatComposerControls<Leading: View, Trailing: View>: View {
    let sending: Bool
    let stopping: Bool
    let canSubmit: Bool
    let importingFiles: Bool
    let send: () -> Void
    let stop: () -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DLSSpacing.sm) {
                leading().fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: DLSSpacing.sm)
                actions.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: DLSSpacing.sm) {
                ComposerControlsFlow(spacing: DLSSpacing.sm) { leading() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: DLSSpacing.sm) {
                    Spacer(minLength: DLSSpacing.none)
                    actions
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: DLSSpacing.sm) {
            trailing()
            if importingFiles { ProgressView().controlSize(.mini) }
            ComposerSendButton(
                sending: sending, stopping: stopping, enabled: canSubmit, send: send, stop: stop)
        }
    }
}
