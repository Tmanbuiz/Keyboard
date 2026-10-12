import SwiftUI
import UIKit

struct AISettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var key = ""
    @State private var groqModel = GroqConfiguration.defaultModel
    @State private var endpoint = ""
    @State private var token = ""
    @State private var status = ""
    @State private var checking = false
    @State private var availableModels: [String] = []
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Choose your AI") {
                Picker("AI provider", selection: $model.preferences.writingProvider) {
                    ForEach(WritingProvider.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("ai-provider")
                Text("Groq uses your Groq account for rewriting, translation and Composer. Choosing Groq keeps Apple AI off for these tools.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your Groq account") {
                SecureField("Groq API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("groq-api-key")
                TextField("Groq model ID", text: $groqModel)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("groq-model")
                Menu("Choose a model") {
                    ForEach(modelChoices, id: \.self) { choice in Button(choice) { groqModel = choice } }
                }
                Button("Save Groq and use it") {
                    let configuration = GroqConfiguration(key: key, model: groqModel)
                    guard GroqVault.save(configuration) else { status = "Enter a valid Groq API key and model ID."; return }
                    model.preferences.writingProvider = .groq
                    status = "Groq saved. Copy the connection below and import it into your keyboard."
                }.accessibilityIdentifier("save-groq")
                Button(checking ? "Checking Groq…" : "Test Groq connection") { checkGroq() }
                    .disabled(checking || !GroqConfiguration(key: key, model: groqModel).valid)
                Link("Get a Groq API key", destination: URL(string: "https://console.groq.com/keys")!)
                Text("Your key stays in this device's Keychain. Only the text you ask AI to work on is sent to Groq. Internet access and your Groq account's usage limits apply.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Forget Groq key", role: .destructive) {
                    checkTask?.cancel()
                    if GroqVault.save(nil) { key = ""; availableModels = []; status = "Groq key removed from this app. Disconnect Groq in the keyboard to remove its copy too." }
                    else { status = "Could not remove the key. Try again." }
                }
            }
            Section("Use AI in your keyboard") {
                Button("Copy AI connection for keyboard") { copyConnection() }
                    .disabled(connection == nil).accessibilityIdentifier("copy-ai-connection")
                Text("1. Save your connection above.\n2. Tap Copy AI connection for keyboard.\n3. Open any message and switch to WianTribe.\n4. Tap ✦ → Groq/Auto → Import AI connection.\nEnable Allow Full Access in iPhone Keyboard settings for Groq.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("The copied connection contains your private key, is local to this iPhone and expires after two minutes. It is excluded from WianTribe clipboard history.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !status.isEmpty { Section { Text(status).font(.caption).accessibilityIdentifier("ai-setup-status") } }
            Section("Other options") {
                DisclosureGroup("Connect my own writing service") {
                    TextField("https://your-service.example/write", text: $endpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Access token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save writing service") {
                        let value = WritingConnection(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines), token: token.trimmingCharacters(in: .whitespacesAndNewlines))
                        if ConnectionVault.save(value) { model.preferences.writingProvider = .service; status = "Writing service saved. Copy its AI connection above." }
                        else { status = "Enter a valid HTTPS address and access token." }
                    }
                    Button("Disconnect writing service", role: .destructive) { ConnectionVault.save(nil); token = ""; status = "Writing service disconnected in this app." }
                }
                Text("Automatic tries Apple's local models and then your writing service. Apple uses only local models. Each explicit online choice uses only that provider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("AI setup")
        .onAppear {
            if let saved = GroqVault.load() { key = saved.key; groqModel = saved.model }
            if let saved = ConnectionVault.load() { endpoint = saved.endpoint; token = saved.token }
        }
        .onDisappear { checkTask?.cancel() }
    }

    private var modelChoices: [String] { Array(Set(GroqConfiguration.suggestedModels + availableModels)).sorted() }
    private var connection: WritingConnectionTransfer? {
        let provider = model.preferences.writingProvider
        let value = WritingConnectionTransfer(provider: provider, groq: provider == .groq ? GroqVault.load() : nil,
            service: provider == .service || provider == .automatic ? ConnectionVault.load() : nil)
        return value.valid ? value : nil
    }
    private func copyConnection() {
        guard let value = connection, let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.setItems([["public.utf8-plain-text": json, "org.nspasteboard.ConcealedType": Data()]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
        status = "Copied. In WianTribe's keyboard tap ✦ → \(model.preferences.writingProvider.shortTitle) → Import AI connection."
    }
    private func checkGroq() {
        let configuration = GroqConfiguration(key: key, model: groqModel)
        checking = true; status = ""; checkTask?.cancel()
        checkTask = Task { @MainActor in
            defer { checking = false }
            do {
                let models = try await GroqService.models(configuration: configuration)
                guard !Task.isCancelled else { return }
                availableModels = models
                status = models.contains(configuration.model)
                    ? "Groq accepted the key and listed your model. Save it, then import the connection into the keyboard."
                    : "Groq accepted the key, but did not list this model. Use Choose a model to select another."
            } catch { if !Task.isCancelled { status = error.localizedDescription } }
        }
    }
}
