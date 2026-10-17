import SwiftUI
import AuthenticationServices
import UIKit

fileprivate enum AccountAPI {
    static let base = ServiceOrigin.base
    struct Challenge: Decodable { let id: String; let nonce: String }
    struct Session: Decodable { let token: String; let expiresAtSeconds: Double; let dailyLimit: Int }
    struct Usage: Decodable { let dailyLimit: Int; let used: Int; let resetsAt: String }
    struct Acknowledgement: Decodable { let signedOut: Bool?; let deleted: Bool? }
    static func call<T: Decodable>(_ path: String, body: [String: String]? = nil, token: String? = nil, method: String = "POST") async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method; request.timeoutInterval = 30
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body) }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await BoundedHTTP.load(request, maximum: 100_000)
        switch response.statusCode {
        case 200...299: return try JSONDecoder().decode(T.self, from: data)
        case 401:
            if path.hasPrefix("auth/"), let body = try? JSONDecoder().decode([String: String].self, from: data), let message = body["error"] {
                throw NSError(domain: "AIAccount", code: 401, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw WritingError.unauthorized
        case 429: throw WritingError.rateLimited
        case 403: throw NSError(domain: "AIAccount", code: 403, userInfo: [NSLocalizedDescriptionKey: "This AI account is disabled. Contact WianTribe support."])
        default: throw NSError(domain: "AIAccount", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "AI account setup is temporarily unavailable. Check your connection and try again."])
        }
    }
}

@MainActor
final class AIAccountModel: ObservableObject {
    static let shared = AIAccountModel()
    @Published private(set) var signedIn = ConnectionVault.load()?.appleUserID != nil
    @Published private(set) var busy = false
    @Published fileprivate var challenge: AccountAPI.Challenge?
    @Published private(set) var status = ""
    @Published private(set) var used: Int?
    @Published private(set) var dailyLimit: Int?
    @Published private(set) var deleted = false
    @Published private(set) var trace: [String] = []
    private func note(_ text: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        trace.append("\(f.string(from: Date())) \(text)"); if trace.count > 14 { trace.removeFirst() }
    }

    func reload() async {
        guard !busy else { return }
        signedIn = ConnectionVault.load()?.appleUserID != nil
        note("reload: stored session \(signedIn ? "found" : "none")")
        guard let user = ConnectionVault.load()?.appleUserID else { return }
        let state: ASAuthorizationAppleIDProvider.CredentialState? = await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: user) { state, error in
                continuation.resume(returning: error == nil ? state : nil)
            }
        }
        note("apple state: \(state.map { String($0.rawValue) } ?? "unknown") (0 revoked,1 authorized,2 notFound)")
        if let state, state == .revoked {
            await signOut(); status = "Apple access was revoked. Sign in again to use AI."
        }
    }
    func prepare() async {
        await reload()
        if signedIn { await refreshUsage(); if signedIn { return } }
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { challenge = try await AccountAPI.call("auth/challenge"); if !signedIn && status.isEmpty == false && !status.hasPrefix("Your AI session") { status = "" } }
        catch { challenge = nil; status = error.localizedDescription }
    }
    func finish(_ result: Result<ASAuthorization, Error>) {
        guard !busy else { return }
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { status = "Apple sign-in could not finish. Please try again." }
            Task { await prepare() }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8),
                  let challenge else { status = "Apple did not return a sign-in token. Please try again."; Task { await prepare() }; return }
            busy = true; note("apple returned token; contacting server")
            Task {
                defer { busy = false }
                do {
                    guard ConnectionVault.hasSharedStorage else {
                        throw NSError(domain: "AIAccount", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sharing with the keyboard isn't available in this build. Please install the latest version of WianTribe and try again."])
                    }
                    let session: AccountAPI.Session = try await AccountAPI.call("auth/apple", body: ["identityToken": token, "challengeID": challenge.id])
                    note("server accepted sign-in")
                    let connection = WritingConnection(endpoint: AccountAPI.base.appendingPathComponent("write").absoluteString,
                        token: session.token, expiresAt: Date(timeIntervalSince1970: session.expiresAtSeconds), appleUserID: credential.user)
                    guard ConnectionVault.save(connection), ConnectionVault.load()?.appleUserID == credential.user else {
                        let _: AccountAPI.Acknowledgement? = try? await AccountAPI.call("auth/logout", token: session.token)
                        throw NSError(domain: "AIAccount", code: 2, userInfo: [NSLocalizedDescriptionKey: "Your sign-in could not be saved on this iPhone. Please update WianTribe and try again."])
                    }
                    note("saved and read back OK")
                    let store = KeyboardStore(); var preferences = store.preferences
                    preferences.aiEngine = .service; store.preferences = preferences
                    signedIn = true; deleted = false; self.challenge = nil; dailyLimit = session.dailyLimit; used = nil
                    status = "Signed in. Your keyboard is connected automatically. Enable Allow Full Access to use online AI."
                } catch { self.challenge = nil; status = error.localizedDescription; note("sign-in failed: \(error.localizedDescription)") }
            }
        }
    }
    func refreshUsage() async {
        guard let connection = ConnectionVault.load(), !busy else { return }
        busy = true; defer { busy = false }
        do {
            let usage: AccountAPI.Usage = try await AccountAPI.call("me", token: connection.token, method: "GET")
            used = usage.used; dailyLimit = usage.dailyLimit; note("usage check OK")
        } catch WritingError.unauthorized { note("usage check: server said 401 (session unknown)"); ConnectionVault.save(nil); signedIn = false; status = WritingError.unauthorized.localizedDescription }
        catch { status = "Signed in. Usage information is unavailable right now." }
    }
    func signOut() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        note("signing out")
        let token = ConnectionVault.load()?.token
        ConnectionVault.save(nil); signedIn = false; challenge = nil; used = nil; dailyLimit = nil
        if let token { let _: AccountAPI.Acknowledgement? = try? await AccountAPI.call("auth/logout", token: token) }
        status = "Signed out on this device."
    }
    func deleteAccount(authorizationCode: String?) async {
        guard let token = ConnectionVault.load()?.token, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let reply: AccountAPI.Acknowledgement = try await AccountAPI.call("account/delete", body: authorizationCode.map { ["authorizationCode": $0] } ?? [:], token: token)
            guard reply.deleted == true else { throw WritingError.invalidResponse }
            ConnectionVault.save(nil); signedIn = false; challenge = nil; used = nil; dailyLimit = nil; deleted = true
            status = "Your WianTribe AI account was deleted. You can also remove WianTribe from Sign in with Apple in your Apple Account settings."
        } catch { status = error.localizedDescription }
    }
}

struct AIAccountView: View {
    @StateObject private var model = AIAccountModel.shared
    @State private var confirmDeletion = false
    @State private var confirmWithApple = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            Section {
                Label(model.signedIn ? "AI account connected" : "Connect your AI account", systemImage: "sparkles")
                    .font(.headline)
                Text("Sign in once to use rewriting and translation in the app and keyboard. Your connection is shared securely on this device.")
                if !model.status.isEmpty { Text(model.status).font(.callout).foregroundStyle(model.signedIn ? Color.secondary : Color.orange) }
            }
            if model.signedIn {
                Section("Daily allowance") {
                    if let limit = model.dailyLimit {
                        LabeledContent("Requests", value: model.used.map { "\($0) of \(limit) used" } ?? "\(limit) per day")
                    }
                    Text("Resets at midnight UTC. Connection tests and unsuccessful requests may count toward your allowance.").font(.caption)
                    Button("Refresh usage") { Task { await model.refreshUsage() } }.disabled(model.busy)
                }
                Section {
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }.disabled(model.busy)
                    Button("Delete AI account", role: .destructive) { confirmDeletion = true }.disabled(model.busy)
                }
                if confirmWithApple {
                    Section {
                        Text("Confirm with Apple to finish deleting your account. This also removes WianTribe from your Sign in with Apple list.").font(.callout)
                        SignInWithAppleButton(.continue) { $0.requestedScopes = [] } onCompletion: { result in
                            confirmWithApple = false
                            switch result {
                            case .success(let authorization):
                                let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                                Task { await model.deleteAccount(authorizationCode: code) }
                            case .failure: break
                            }
                        }.signInWithAppleButtonStyle(.white).frame(height: 48)
                        Button("Cancel") { confirmWithApple = false }
                    }
                }
            } else {
                Section {
                    if model.challenge != nil {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = []; request.nonce = model.challenge?.nonce
                        } onCompletion: { model.finish($0) }
                        .signInWithAppleButtonStyle(.white).frame(height: 48).disabled(model.busy)
                    }
                    Button(model.challenge == nil ? "Prepare sign-in" : "Refresh sign-in") { Task { await model.prepare() } }.disabled(model.busy)
                    Text("Apple verifies your identity. WianTribe does not request your name or email address. No API key or connection import is needed.").font(.caption)
                }
            }
            if model.busy { Section { ProgressView("Please wait…") } }
            Section("Keyboard access") {
                Text("On your iPhone: Settings → General → Keyboard → Keyboards → WianTribe → Allow Full Access. Basic typing remains available without it.")
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Section("Privacy") {
                Text("Text is sent to WianTribe's AI service only when you request an online writing action. The service keeps account/session identifiers and usage counts; it does not save your submitted text or AI results.")
                Text("Deleting your account removes its access and sign-in records. App-specific pseudonymous usage buckets remain for up to 30 days to enforce usage limits. Clipboard entries and locally learned words can be cleared separately in Settings.").font(.caption)
                Link("Manage Sign in with Apple", destination: URL(string: "https://support.apple.com/102571")!)
            }
        }.navigationTitle("AI account")
            .task { await model.prepare() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.reload() } } }
            .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in Task { await model.signOut() } }
            .confirmationDialog("Delete your WianTribe AI account? All its connections will stop working.", isPresented: $confirmDeletion) {
                Button("Delete AI account", role: .destructive) { confirmWithApple = true }
            }
    }
}
