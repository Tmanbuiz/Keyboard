import Foundation

public struct GlidePoint: Equatable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public func distance(to other: GlidePoint) -> Double { hypot(x - other.x, y - other.y) }
}

public struct GlideCandidate: Equatable {
    public let word: String
    public let score: Double
}

public struct GlideDecoder {
    public init() {}

    public func decode(path: [GlidePoint], centers: [Character: GlidePoint], entries: [LexiconEntry],
                       language: KeyboardLanguage, keyWidth: Double, limit: Int = 3) -> [GlideCandidate] {
        guard path.count >= 3, keyWidth > 0, let first = path.first, let last = path.last,
              pathLength(path) > keyWidth * 0.75 else { return [] }
        let observed = resample(path, count: 32)
        var ranked: [GlideCandidate] = []
        for entry in entries where entry.language == language || (language == .pidgin && entry.language == .english) {
            let letters = Array(entry.word.lowercased())
            guard letters.count > 1, let start = letters.first.flatMap({ centers[$0] }),
                  let end = letters.last.flatMap({ centers[$0] }),
                  first.distance(to: start) < keyWidth * 1.1, last.distance(to: end) < keyWidth * 1.1 else { continue }
            var ideal: [GlidePoint] = []
            var complete = true
            for letter in letters {
                guard let point = centers[letter] else { complete = false; break }
                if point != ideal.last { ideal.append(point) }
            }
            guard complete, ideal.count > 1 else { continue }
            let sampled = resample(ideal, count: 32)
            let shape = zip(observed, sampled).map { $0.distance(to: $1) }.reduce(0, +) / 32 / keyWidth
            let lengthDifference = abs(pathLength(path) - pathLength(ideal)) / max(pathLength(ideal), keyWidth)
            guard shape < 1.6, lengthDifference < 1.5 else { continue }
            let score = shape + min(lengthDifference, 1) * 0.2
                + (first.distance(to: start) + last.distance(to: end)) / keyWidth * 0.25
                - log(Double(max(entry.frequency, 1)) + 1) * 0.035
            ranked.append(GlideCandidate(word: entry.word, score: score))
        }
        return Array(ranked.sorted { $0.score == $1.score ? $0.word < $1.word : $0.score < $1.score }.prefix(limit))
    }

    public func pathLength(_ points: [GlidePoint]) -> Double {
        zip(points, points.dropFirst()).map { $0.distance(to: $1) }.reduce(0, +)
    }

    public func resample(_ points: [GlidePoint], count: Int) -> [GlidePoint] {
        guard count > 0, let first = points.first else { return [] }
        let total = pathLength(points)
        guard total > 0, points.count > 1 else { return Array(repeating: first, count: count) }
        if count == 1 { return [first] }
        var cumulative = [0.0]
        for distance in zip(points, points.dropFirst()).map({ $0.distance(to: $1) }) { cumulative.append(cumulative.last! + distance) }
        var output: [GlidePoint] = []
        var segment = 1
        for i in 0..<count {
            let desired = total * Double(i) / Double(count - 1)
            while segment < points.count - 1 && cumulative[segment] < desired { segment += 1 }
            let distance = cumulative[segment] - cumulative[segment - 1]
            let fraction = distance == 0 ? 0 : (desired - cumulative[segment - 1]) / distance
            let a = points[segment - 1], b = points[segment]
            output.append(GlidePoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction))
        }
        return output
    }
}
