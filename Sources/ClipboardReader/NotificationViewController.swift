// Clipper-style notification capture. Based on Riley Testut's ClipboardReader,
// released under the Unlicense; see ThirdParty/Clipper/UNLICENSE.
#if PERSONAL_BACKGROUND_CLIPBOARD
import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let message = UILabel()
    private let symbol = UIImageView()
    private let retry = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        symbol.image = UIImage(systemName: "doc.on.clipboard")
        symbol.tintColor = .systemMint
        symbol.contentMode = .scaleAspectFit
        message.font = .preferredFont(forTextStyle: .body)
        message.textAlignment = .center
        message.numberOfLines = 0
        retry.setTitle("Try saving the current copy", for: .normal)
        retry.addTarget(self, action: #selector(saveCurrentCopy), for: .touchUpInside)
        retry.isHidden = true
        let stack = UIStackView(arrangedSubviews: [symbol, message, retry])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            symbol.heightAnchor.constraint(equalToConstant: 40),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
        preferredContentSize = CGSize(width: 320, height: 160)
    }

    func didReceive(_ notification: UNNotification) {
        guard notification.request.content.categoryIdentifier == PersonalClipboardNotifications.category else { return }
        saveCurrentCopy()
    }

    @objc private func saveCurrentCopy() {
        do {
            message.text = try PersonalClipboardCapture.saveCurrent()
            symbol.image = UIImage(systemName: "checkmark.circle")
            retry.isHidden = true
            // Save while the notification UI is visible, then dismiss.
            extensionContext?.dismissNotificationContentExtension()
        } catch {
            message.text = error.localizedDescription
            symbol.image = UIImage(systemName: "exclamationmark.circle")
            retry.isHidden = false
            preferredContentSize = CGSize(width: 320, height: 220)
        }
    }
}
#endif
