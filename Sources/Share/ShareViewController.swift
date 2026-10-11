import UIKit
import UniformTypeIdentifiers

/// "Save to WianTribe" in the Share menu: saves shared text or links to the keyboard's clipboard.
/// It runs only when the person picks it, which is how App Store clipboard managers collect items
/// without background monitoring. With the App Group, the keyboard shows the item straight away.
final class ShareViewController: UIViewController {
    private let card = UIView()
    private let icon = UIImageView()
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 18; card.layer.cornerCurve = .continuous
        icon.image = UIImage(systemName: "doc.on.clipboard", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .medium))
        icon.tintColor = .systemMint; icon.contentMode = .scaleAspectFit
        label.text = NSLocalizedString("Saving…", comment: "")
        label.font = .preferredFont(forTextStyle: .headline); label.textAlignment = .center; label.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [icon, label]); stack.axis = .vertical; stack.spacing = 12
        for item in [card, stack] as [UIView] { item.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(card); card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor), card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 240),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
        Task { @MainActor in await save() }
    }

    private func save() async {
        let texts = await sharedTexts()
        let store = KeyboardStore()
        for text in texts where ClipboardHistory.shouldCapture(text) { store.capture(text) }
        let saved = texts.contains { ClipboardHistory.shouldCapture($0) }
        label.text = saved ? NSLocalizedString("Saved to your WianTribe clipboard", comment: "")
                           : NSLocalizedString("There's no text or link to save here", comment: "")
        icon.image = UIImage(systemName: saved ? "checkmark.circle.fill" : "exclamationmark.circle")
        try? await Task.sleep(nanoseconds: 900_000_000)
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Plain text and web links from whatever was shared, in order.
    private func sharedTexts() async -> [String] {
        var texts: [String] = []
        for item in (extensionContext?.inputItems as? [NSExtensionItem]) ?? [] {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) as? URL,
                   !url.isFileURL {
                    texts.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
                    if let text = value as? String { texts.append(text) }
                    else if let data = value as? Data, let text = String(data: data, encoding: .utf8) { texts.append(text) }
                }
            }
            if texts.isEmpty, let text = item.attributedContentText?.string, !text.isEmpty { texts.append(text) }
        }
        return texts
    }
}
