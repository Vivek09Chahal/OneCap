import AppKit
import DLS
@preconcurrency import SwiftTerm
import SwiftUI

struct TerminalLoginView: View {
    @Environment(\.dlsTheme) private var theme
    let session: TerminalLoginSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            Label("Sign in to \(session.command.agentName)", systemImage: "terminal")
                .font(DLSTypography.sectionTitle)
            Text(session.command.label).font(DLSTypography.body)
            Text("Complete the agent’s login below. Return to chat after sign-in. If a reply failed, use Retry last message to continue.")
                .font(DLSTypography.caption).foregroundStyle(theme.colors.textSecondary)
            LoginTerminal(session: session)
                .frame(minHeight: 380)
                .clipShape(RoundedRectangle(cornerRadius: DLSRadius.small))
            HStack {
                if let url = session.loginURL {
                    Button("Open \(url.host ?? "login page")", systemImage: "arrow.up.right.square") {
                        session.openLink(url)
                    }
                }
                Spacer()
                Button("Cancel sign-in", role: .cancel) { session.cancel() }
            }
        }
        .padding(DLSSpacing.xxl)
        .frame(width: 760, height: 560)
        .interactiveDismissDisabled()
    }
}

private struct LoginTerminal: NSViewRepresentable {
    @Environment(\.dlsTheme) private var theme
    let session: TerminalLoginSession
    
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    
    func makeNSView(context: Context) -> LoginProcessTerminalView {
        let terminal = LoginProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 712, height: 380))
        terminal.loginSession = session
        terminal.processDelegate = context.coordinator
        terminal.nativeBackgroundColor = NSColor(theme.colors.surface)
        terminal.nativeForegroundColor = NSColor(theme.colors.textPrimary)
        terminal.font = NSFont.monospacedSystemFont(
            ofSize: DLSTypography.terminalPointSize, weight: .regular)
        terminal.setHostLogging(directory: nil)
        session.terminateProcess = { [weak terminal] in terminal?.terminate() }
        let command = session.command
        // Starting or failing a login can change sheet state. Defer it until after
        // NSView creation so authentication never removes its own view mid-update.
        DispatchQueue.main.async { [weak terminal, weak session] in
            guard let terminal, let session, !session.finished else { return }
            terminal.startProcess(
                executable: command.executable, args: command.arguments,
                environment: command.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" },
                currentDirectory: command.directory.path)
            if !terminal.process.running { session.complete(exitCode: nil) }
            terminal.window?.makeFirstResponder(terminal)
        }
        return terminal
    }
    
    func updateNSView(_ terminal: LoginProcessTerminalView, context: Context) {
        let background = NSColor(theme.colors.surface)
        let foreground = NSColor(theme.colors.textPrimary)
        if terminal.nativeBackgroundColor != background { terminal.nativeBackgroundColor = background }
        if terminal.nativeForegroundColor != foreground { terminal.nativeForegroundColor = foreground }
    }
    
    static func dismantleNSView(_ terminal: LoginProcessTerminalView, coordinator: Coordinator) {
        if !coordinator.session.finished { coordinator.session.cancel() }
        terminal.processDelegate = nil
        if terminal.process.running { terminal.terminate() }
    }
    
    @MainActor final class Coordinator: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        let session: TerminalLoginSession
        init(session: TerminalLoginSession) { self.session = session }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
            Task { @MainActor [weak session] in
                session?.complete(exitCode: exitCode)
            }
        }
    }
}

private final class LoginProcessTerminalView: LocalProcessTerminalView {
    weak var loginSession: TerminalLoginSession?
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        let data = Data(slice)
        Task { @MainActor [weak self] in self?.loginSession?.consumeOutput(data) }
    }
    override func requestOpenLink(
        source: SwiftTerm.TerminalView, link: String, params: [String: String]
    ) {
        guard let url = LoginURL.validated(link) else { return }
        loginSession?.openLink(url)
    }
}
