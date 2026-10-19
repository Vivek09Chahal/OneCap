import DLS
import SwiftUI

struct ProviderConnectionFields: View {
    @Binding var name: String
    @Binding var baseURL: String
    @Binding var model: String
    @Binding var key: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DLSSpacing.lg) {
            HStack(alignment: .top, spacing: DLSSpacing.lg) {
                ProviderFormField("Name") {
                    TextField("Provider name", text: $name).accessibilityLabel("Provider name")
                }
                ProviderFormField("Model ID") {
                    TextField("Model identifier", text: $model).accessibilityLabel("Model ID")
                        .autocorrectionDisabled()
                }
            }
            ProviderFormField(
                "API base URL",
                hint: "Include /v1 if required. OneCap adds /chat/completions automatically."
            ) {
                TextField("https://api.example.com/v1", text: $baseURL).accessibilityLabel("API base URL")
                    .autocorrectionDisabled()
            }
            ProviderFormField("API key", hint: "Stored securely in macOS Keychain.") {
                SecureField("Enter your API key", text: $key).accessibilityLabel("API key")
                    .privacySensitive()
            }
        }
    }
}
