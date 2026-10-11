import UIKit

struct KeyboardPalette {
    let background: UIColor
    let key: UIColor
    let function: UIColor
    let text: UIColor
    let accent: UIColor
    var borders = false

    static func make(_ theme: KeyboardTheme, dark: Bool = true, accent: KeyAccent = .theme, borders: Bool = false) -> KeyboardPalette {
        var palette = base(theme == .auto ? (dark ? .midnight : .light) : theme)
        if let rgb = accent.rgb {
            let color = UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            // Darken light-theme accents so suggestion text stays readable on a pale background.
            let readable = palette.background.isLight ? color.darker(by: 0.35) : color
            palette = KeyboardPalette(background: palette.background, key: palette.key, function: palette.function, text: palette.text, accent: readable)
        }
        palette.borders = borders
        return palette
    }

    private static func base(_ theme: KeyboardTheme) -> KeyboardPalette {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        switch theme {
        case .auto, .midnight: return KeyboardPalette(background: UIColor(white: 0.07, alpha: 1), key: UIColor(white: 0.22, alpha: 1), function: UIColor(white: 0.14, alpha: 1), text: .white, accent: rgb(0.63, 0.72, 1))
        case .ocean: return KeyboardPalette(background: rgb(0.06, 0.17, 0.20), key: rgb(0.15, 0.29, 0.32), function: rgb(0.10, 0.23, 0.26), text: .white, accent: rgb(0.38, 0.88, 0.75))
        case .light: return KeyboardPalette(background: UIColor(white: 0.84, alpha: 1), key: .white, function: UIColor(white: 0.70, alpha: 1), text: UIColor(white: 0.10, alpha: 1), accent: rgb(0.00, 0.40, 0.34))
        case .rose: return KeyboardPalette(background: rgb(0.22, 0.10, 0.16), key: rgb(0.37, 0.21, 0.29), function: rgb(0.29, 0.14, 0.21), text: .white, accent: rgb(1, 0.69, 0.77))
        case .forest: return KeyboardPalette(background: rgb(0.08, 0.15, 0.10), key: rgb(0.18, 0.28, 0.20), function: rgb(0.12, 0.21, 0.14), text: .white, accent: rgb(0.62, 0.86, 0.45))
        case .sunset: return KeyboardPalette(background: rgb(0.24, 0.11, 0.08), key: rgb(0.40, 0.21, 0.15), function: rgb(0.31, 0.15, 0.11), text: .white, accent: rgb(1, 0.72, 0.38))
        case .slate: return KeyboardPalette(background: rgb(0.13, 0.15, 0.19), key: rgb(0.25, 0.28, 0.34), function: rgb(0.19, 0.21, 0.26), text: .white, accent: rgb(0.55, 0.80, 1))
        }
    }
}

extension UIColor {
    var isLight: Bool {
        var white: CGFloat = 0
        if getWhite(&white, alpha: nil) { return white > 0.6 }
        return false
    }
    func darker(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: max(0, b - amount), alpha: a)
    }
}

/// The keyboard's root view. Adopting UIInputViewAudioFeedback lets the keyboard play the
/// standard key click, which follows the person's Keyboard Clicks setting and needs no Full Access.
final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyButton: UIButton {
    var onTap: (() -> Void)?
    var letter: Character?
    /// Characters offered when this key is held (accents, punctuation).
    var alternates: [String] = []
    var longPressConsumed = false
    private(set) var hintText: String?
    var normalColor: UIColor = .clear
    private let hint = UILabel()

    /// Key label size, scaled with the person's text size setting but capped so keys stay usable.
    static func fontSize(_ base: CGFloat) -> CGFloat {
        min(UIFontMetrics(forTextStyle: .body).scaledValue(for: base), base * 1.3)
    }

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
        if palette.borders {
            layer.borderWidth = 1
            layer.borderColor = palette.accent.withAlphaComponent(0.45).cgColor
        }
        setTitle(title, for: .normal)
        setTitleColor(palette.text, for: .normal)
        titleLabel?.font = .systemFont(ofSize: Self.fontSize(title.count > 3 ? 13 : 21))
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.7
        accessibilityLabel = title
        if let hint {
            hintText = hint
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
        guard !longPressConsumed else { longPressConsumed = false; return }
        onTap?()
    }
}

/// The enlarged letter shown above a key while it is pressed.
final class KeyPreview: UIView {
    private let label = UILabel()
    init(palette: KeyboardPalette) {
        super.init(frame: .zero)
        backgroundColor = palette.key
        layer.cornerRadius = 9; layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.3
        layer.shadowRadius = 4; layer.shadowOffset = CGSize(width: 0, height: 2)
        label.textColor = palette.text; label.textAlignment = .center
        label.font = .systemFont(ofSize: 32)
        label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.5
        addSubview(label)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func show(_ text: String, over keyFrame: CGRect, in area: CGRect) {
        let width = max(keyFrame.width * 1.5, 44), height: CGFloat = 54
        var x = keyFrame.midX - width / 2
        x = min(max(area.minX + 2, x), area.maxX - width - 2)
        frame = CGRect(x: x, y: max(area.minY, keyFrame.minY - height - 4), width: width, height: height)
        label.frame = CGRect(x: 4, y: 2, width: width - 8, height: height - 6)
        label.text = text
        isHidden = false
    }
}
