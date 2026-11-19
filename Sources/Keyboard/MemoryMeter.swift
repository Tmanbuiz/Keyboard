import Foundation

/// Measures where the keyboard's memory goes, for the diagnostic report in ⚙︎. It records megabytes
/// only, never anything typed. Each part is measured as the change in memory while that part did its
/// work, so the figures are close estimates rather than exact sizes.
enum MemoryMeter {
    enum Part { case dictionaries, emoji, spellChecker, handwriting }

    private static let lock = NSLock()
    private static var growth: [Part: Int64] = [:]
    /// Memory given back by keyboard copies that went off screen and freed their keys and panels.
    private static var freedByHiding: Int64 = 0
    /// Memory in use when the first keyboard screen loaded in this process.
    private static var startBytes: UInt64?

    /// Memory iOS counts against this keyboard's limit, in bytes.
    static var footprint: UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static func markStart() {
        lock.lock(); defer { lock.unlock() }
        if startBytes == nil { startBytes = footprint }
    }

    /// Runs `work` and adds the memory it kept (or freed) to `part`.
    @discardableResult
    static func measure<T>(_ part: Part, _ work: () -> T) -> T {
        let before = footprint
        let result = work()
        let change = Int64(footprint) - Int64(before)
        lock.lock(); growth[part, default: 0] += change; lock.unlock()
        return result
    }

    private static func megabytes(_ bytes: Int64) -> Int { Int(max(bytes, 0) / 1_048_576) }

    /// Adds the memory a hidden keyboard copy gave back since `before`.
    static func noteFreed(since before: UInt64) {
        let freed = Int64(before) - Int64(footprint)
        lock.lock(); freedByHiding += max(freed, 0); lock.unlock()
    }

    /// For example "used 182 MB (31 MB at start) · keyboard copies 3 (1 with keys) · hidden copies freed 20 MB ·
    /// dictionaries 4 MB · emoji 9 MB · spell checker 41 MB · handwriting 0 MB".
    static func report(copies: Int, withKeys: Int) -> String {
        lock.lock(); let parts = growth, start = startBytes, freed = freedByHiding; lock.unlock()
        var text = "used \(megabytes(Int64(footprint))) MB"
        if let start { text += " (\(megabytes(Int64(start))) MB at start)" }
        text += " · keyboard copies \(copies) (\(withKeys) with keys)"
        text += " · hidden copies freed \(megabytes(freed)) MB"
        text += " · dictionaries \(megabytes(parts[.dictionaries] ?? 0)) MB"
        text += " · emoji \(megabytes(parts[.emoji] ?? 0)) MB"
        text += " · spell checker \(megabytes(parts[.spellChecker] ?? 0)) MB"
        text += " · handwriting \(megabytes(parts[.handwriting] ?? 0)) MB"
        return text
    }
}

/// Counts keyboard screens alive in memory. iOS normally keeps one; a higher number means old
/// keyboards were never freed, and each one holds its own keys and suggestions.
final class KeyboardInstanceCounter {
    private static let lock = NSLock()
    private static var live = 0
    static var count: Int { lock.lock(); defer { lock.unlock() }; return live }
    init() { Self.lock.lock(); Self.live += 1; Self.lock.unlock() }
    deinit { Self.lock.lock(); Self.live -= 1; Self.lock.unlock() }
}
