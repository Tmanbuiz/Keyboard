import UIKit
import Vision

/// A finger-writing surface. After a short pause the ink is read with Apple's on-device
/// Vision text recognition; nothing leaves the phone.
final class HandwritingCanvas: UIView {
    var onPause: ((UIImage) -> Void)?
    private var strokes: [UIBezierPath] = []
    private var current: UIBezierPath?
    private var pauseTimer: Timer?
    private let ink: UIColor
    private let hint = UILabel()

    init(palette: KeyboardPalette) {
        ink = palette.text
        super.init(frame: .zero)
        backgroundColor = palette.key
        layer.cornerRadius = 10; layer.cornerCurve = .continuous
        isMultipleTouchEnabled = false
        hint.text = "Write a word here"; hint.textColor = palette.text.withAlphaComponent(0.35)
        hint.font = .systemFont(ofSize: 15); hint.textAlignment = .center
        addSubview(hint)
        isAccessibilityElement = true
        accessibilityLabel = "Handwriting area"
        accessibilityHint = "Write a word with your finger. It is typed after a short pause."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layoutSubviews() { super.layoutSubviews(); hint.frame = bounds }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        pauseTimer?.invalidate(); hint.isHidden = true
        let path = UIBezierPath(); path.lineWidth = 4; path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.move(to: point); path.addLine(to: point)
        current = path; strokes.append(path); setNeedsDisplay()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] { current?.addLine(to: sample.location(in: self)) }
        setNeedsDisplay()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finishStroke() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finishStroke() }

    private func finishStroke() {
        current = nil
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { [weak self] _ in
            guard let self, let image = self.snapshot() else { return }
            self.clear()
            self.onPause?(image)
        }
    }

    override func draw(_ rect: CGRect) {
        ink.setStroke()
        for stroke in strokes { stroke.stroke() }
    }

    func clear() { strokes = []; current = nil; hint.isHidden = false; setNeedsDisplay() }
    func stop() { pauseTimer?.invalidate(); pauseTimer = nil }

    /// Black ink on white, cropped to the writing, which is what text recognition reads best.
    private func snapshot() -> UIImage? {
        guard !strokes.isEmpty else { return nil }
        let bounds = strokes.reduce(CGRect.null) { $0.union($1.bounds) }.insetBy(dx: -16, dy: -16)
        guard bounds.width > 8, bounds.height > 8 else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: bounds.size))
            context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            UIColor.black.setStroke()
            for stroke in strokes { let copy = stroke.copy() as! UIBezierPath; copy.lineWidth = 5; copy.stroke() }
        }
    }
}

final class HandwritingSupport {
    let canvas: HandwritingCanvas
    private let queue = DispatchQueue(label: "com.wiantribe.keyboard.handwriting", qos: .userInitiated)

    init(palette: KeyboardPalette) { canvas = HandwritingCanvas(palette: palette) }
    func stop() { canvas.stop() }

    /// Up to three readings of the handwriting, best first.
    func recognize(_ image: UIImage, language: String, completion: @escaping ([String]) -> Void) {
        guard let cgImage = image.cgImage else { completion([]); return }
        queue.async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let supported = try? request.supportedRecognitionLanguages(),
               let match = supported.first(where: { $0 == language || $0.hasPrefix(language + "-") }) {
                request.recognitionLanguages = [match]
            }
            var results: [String] = []
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                let observations = request.results ?? []
                // Join the lines for each candidate rank so a word written in two parts still reads as one.
                for rank in 0..<3 {
                    let words = observations.compactMap { $0.topCandidates(3).dropFirst(rank).first?.string }
                    let text = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty && !results.contains(text) { results.append(text) }
                }
            } catch { results = [] }
            DispatchQueue.main.async { completion(results) }
        }
    }
}

extension KeyboardViewController {
    func buildHandwritingPanel() {
        let support = HandwritingSupport(palette: palette)
        handwriting = support
        let side = UIStackView(); side.axis = .vertical; side.spacing = 5; side.distribution = .fillEqually
        let space = button("space", function: true) { [weak self] in self?.textDocumentProxy.insertText(" ") }
        let delete = button("⌫", function: true) { [weak self] in self?.textDocumentProxy.deleteBackward() }
        delete.accessibilityLabel = "Delete"
        let enter = button("↵", function: true) { [weak self] in self?.textDocumentProxy.insertText("\n") }
        enter.accessibilityLabel = "Return"
        let done = button("ABC", function: true) { [weak self] in self?.showPanel(nil) }
        for key in [space, delete, enter, done] { side.addArrangedSubview(key) }
        side.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let body = UIStackView(arrangedSubviews: [support.canvas, side]); body.spacing = 5
        layoutPanel(header: nil, body: body)
        let language = pack.primaryLanguage
        setStatus("Write a word, then pause. Alternatives appear here")
        support.canvas.onPause = { [weak self, weak support] image in
            guard let self, let support else { return }
            self.setStatus("Reading…")
            support.recognize(image, language: language) { [weak self] candidates in
                guard let self, self.panel == "handwriting" else { return }
                guard let best = candidates.first else { self.setStatus("Couldn't read that. Try writing a little larger"); return }
                let needsSpace = !(self.before.isEmpty || self.before.last?.isWhitespace == true)
                let inserted = (needsSpace ? " " : "") + best
                self.textDocumentProxy.insertText(inserted)
                self.showHandwritingChoices(candidates, inserted: inserted)
            }
        }
    }

    /// Lets the person swap the typed word for another reading.
    private func showHandwritingChoices(_ candidates: [String], inserted: String) {
        let prefix = inserted.hasPrefix(" ") ? " " : ""
        showSuggestions(candidates.map { candidate in (candidate, { [weak self] in
            guard let self, self.before.hasSuffix(inserted) else { return }
            for _ in inserted { self.textDocumentProxy.deleteBackward() }
            self.textDocumentProxy.insertText(prefix + candidate)
            self.setStatus("Write the next word")
        }) })
    }
}
