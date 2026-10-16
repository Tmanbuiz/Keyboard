import Foundation

/// Credentials and selected text may only be sent to the production writing endpoint.
enum ServiceOrigin {
    static let base = URL(string: "https://keyboard.atoyejet.workers.dev")!
    static func accepts(_ endpoint: String) -> Bool {
        guard let url = URLComponents(string: endpoint) else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == base.host &&
            (url.port == nil || url.port == 443) && url.user == nil && url.password == nil &&
            url.path == "/write" && url.query == nil && url.fragment == nil
    }
}
