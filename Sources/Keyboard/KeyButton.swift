import UIKit

struct KeyboardPalette {
    let background: UIColor
    let key: UIColor
    let function: UIColor
    let text: UIColor
    let accent: UIColor
    static func make(_ theme: KeyboardTheme) -> KeyboardPalette {
        switch theme {
        case .ocean: return KeyboardPalette(background: UIColor(red: 0.06, green: 0.17, blue: 0.20, alpha: 1), key: UIColor(red: 0.15, green: 0.29, blue: 0.32, alpha: 1), function: UIColor(red: 0.10, green: 0.23, blue: 0.26, alpha: 1), text: .white, accent: UIColor(red: 0.38, green: 0.88, blue: 0.75, alpha: 1))
        case .midnight: return KeyboardPalette(background: UIColor(white: 0.07, alpha: 1), key: UIColor(white: 0.22, alpha: 1), function: UIColor(white: 0.14, alpha: 1), text: .white, accent: UIColor(red: 0.63, green: 0.72, blue: 1, alpha: 1))
        case .light: return KeyboardPalette(background: UIColor(white: 0.87, alpha: 1), key: .white, function: UIColor(white: 0.76, alpha: 1), text: UIColor(white: 0.12, alpha: 1), accent: UIColor(red: 0.00, green: 0.40, blue: 0.34, alpha: 1))
        case .rose: return KeyboardPalette(background: UIColor(red: 0.22, green: 0.10, blue: 0.16, alpha: 1), key: UIColor(red: 0.37, green: 0.21, blue: 0.29, alpha: 1), function: UIColor(red: 0.29, green: 0.14, blue: 0.21, alpha: 1), text: .white, accent: UIColor(red: 1, green: 0.69, blue: 0.77, alpha: 1))
        }
    }
}

final class KeyButton: UIButton {
    var onTap: (() -> Void)?
    var letter: Character?
    var held = false
    var normalColor: UIColor = .clear
    private let hint = UILabel()

    init(title: String, hint: String? = nil, palette: KeyboardPalette, function: Bool = false) {
        super.init(frame: .zero)
        normalColor = function ? palette.function : palette.key
        backgroundColor = normalColor
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.13
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        setTitle(title, for: .normal)
        setTitleColor(palette.text, for: .normal)
        titleLabel?.font = .systemFont(ofSize: title.count > 3 ? 13 : 21)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.7
        accessibilityLabel = title
        if let hint {
            self.hint.text = hint
            self.hint.font = .systemFont(ofSize: 9)
            self.hint.textColor = palette.text.withAlphaComponent(0.6)
            self.hint.translatesAutoresizingMaskIntoConstraints = false
            addSubview(self.hint)
            NSLayoutConstraint.activate([self.hint.topAnchor.constraint(equalTo: topAnchor, constant: 2), self.hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)])
            accessibilityHint = "Hold for \(hint) and more characters"
        }
        addTarget(self, action: #selector(tap), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? normalColor.withAlphaComponent(0.55) : normalColor }
    }
    @objc private func tap() {
        guard !held else { held = false; return }
        onTap?()
    }
}
