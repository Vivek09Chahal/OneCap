import SwiftUI

struct ChatAuthenticationMenu: View {
    @Environment(AppStore.self) private var store
    
    var title = "Authenticate"

    var body: some View {
        Menu(title, systemImage: "key.horizontal") {
            ForEach(store.acp.authMethods) { method in
                Button(method.name) { Task { await store.authenticate(method) } }
                    .disabled(!method.isSupported)
                    .help(
                        method.isSupported
                        ? "Sign in with this method" : "This sign-in method is not supported")
            }
        }
        .disabled(store.acp.authMethods.isEmpty || store.sending || store.connecting)
        .help("Sign in to the connected agent")
    }
    
}
