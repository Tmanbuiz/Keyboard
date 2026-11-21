import Foundation

/// Measures where the keyboard's memory goes, for the diagnostic report in ⚙︎. It records megabytes and
/// screen names only, never anything typed. Each part is measured as the change in memory while that part
/// did its work, so the figures are close estimates rather than exact sizes.
enum MemoryMeter {
    enum Part { case dictionaries, emoji, spellChecker, handwriting }

    private static let lock = NSLock()
    private static var growth: [Part: Int64] = [:]
    /// Memory given back by keyboard copies that went off screen and freed their keys and panels.
    private static var freedByHiding: Int64 = 0
    /// Memory in use when the first keyboard screen loaded in this process.
    private static var startBytes: UInt64?
    /// The screen shown since the last noteScreen call, and this process's highest memory at that call.
    private static var shownScreen: String?
    private static var lastPeak: UInt64 = 0
    /// For each screen, the highest memory this process reached while it was shown, in megabytes. A screen
    /// is credited only when it set a new high for the process: that is the screen that pushed memory up.
    private static var screenPeaks: [String: Int] = [:]

    /// iOS's memory accounting for this keyboard process.
    private static func taskInfo() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    /// Memory iOS counts against this keyboard's limit, in bytes.
    static var footprint: UInt64 { taskInfo()?.phys_footprint ?? 0 }

    /// The most memory this process has used since it started, in bytes. iOS keeps this figure itself,
    /// so a short spike between two checks is still caught.
    static var peakFootprint: UInt64 {
        guard let info = taskInfo() else { return 0 }
        return max(UInt64(max(info.ledger_phys_footprint_peak, 0)), info.phys_footprint)
    }

    /// Splits the memory in use by kind, from iOS's own record of each memory region: heap (objects, word
    /// lists and text), graphics (keys, emoji and images drawn for the screen) and the rest (mostly system
    /// frameworks' own data, such as Apple's spell checker or text recognition). Takes a few milliseconds,
    /// so it runs only for the report and at a memory warning, never on a key press.
    static func kinds() -> (heap: UInt64, graphics: UInt64, other: UInt64) {
        guard let info = taskInfo() else { return (0, 0, 0) }
        let page = UInt64(getpagesize())
        var heap: UInt64 = 0, drawn: UInt64 = 0, surfaces: UInt64 = 0
        var address: vm_address_t = 0, depth: natural_t = 0
        for _ in 0..<200_000 {
            var region = vm_region_submap_info_data_64_t()
            var count = mach_msg_type_number_t(MemoryLayout<vm_region_submap_info_data_64_t>.size / MemoryLayout<natural_t>.size)
            var size: vm_size_t = 0
            let result = withUnsafeMutablePointer(to: &region) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                    vm_region_recurse_64(mach_task_self_, &address, &size, &depth, raw, &count)
                }
            }
            guard result == KERN_SUCCESS else { break }
            if region.is_submap != 0 { depth += 1; continue }
            let dirty = (UInt64(region.pages_dirtied) + UInt64(region.pages_swapped_out)) * page
            // Region tags from <mach/vm_statistics.h>.
            switch region.user_tag {
            case 1...13: heap += dirty                                  // malloc
            case 42, 51, 52, 54...58, 68, 70, 76, 103: drawn += dirty   // CoreGraphics, CoreAnimation, CGImage, CoreImage, ImageIO, CoreUI
            case 88, 100: surfaces += UInt64(region.pages_resident) * page // IOSurface, GPU
            default: break
            }
            let next = address.addingReportingOverflow(size)
            guard size > 0, !next.overflow else { break }
            address = next.partialValue
        }
        // iOS also charges IOSurfaces and GPU memory to the keyboard through a ledger. Surfaces that are
        // mapped show up both ways, so the larger figure is used rather than the sum.
        let ledger = UInt64(max(info.ledger_tag_graphics_footprint, 0)) + UInt64(max(info.ledger_tag_graphics_footprint_compressed, 0))
        let total = info.phys_footprint
        let heapPart = min(heap, total)
        let graphics = min(drawn + max(ledger, surfaces), total - heapPart)
        return (heapPart, graphics, total - heapPart - graphics)
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

    /// Credits any new high in this process's memory to the screen shown since the last call, then follows
    /// `screen`. Called whenever the screen changes, when the keyboard closes and at a memory warning.
    static func noteScreen(_ screen: String) {
        let peak = peakFootprint
        lock.lock(); defer { lock.unlock() }
        if let shown = shownScreen, peak > lastPeak {
            screenPeaks[shown] = max(screenPeaks[shown] ?? 0, megabytes(Int64(peak)))
        }
        lastPeak = max(lastPeak, peak)
        shownScreen = screen
    }

    /// The highest memory this process reached on each screen, in megabytes.
    static var peaksByScreen: [String: Int] { lock.lock(); defer { lock.unlock() }; return screenPeaks }

    /// After "Reset health counter", only new highs count.
    static func resetScreenPeaks() {
        let peak = peakFootprint
        lock.lock(); screenPeaks = [:]; lastPeak = peak; lock.unlock()
    }

    /// For example "used 182 MB (31 MB at start, highest 190 MB) · heap 60 MB · graphics 90 MB · other 32 MB ·
    /// keyboard copies 3 (1 with keys) · hidden copies freed 20 MB · dictionaries 4 MB · emoji 9 MB ·
    /// spell checker 41 MB · handwriting 0 MB".
    static func report(copies: Int, withKeys: Int) -> String {
        lock.lock(); let parts = growth, start = startBytes, freed = freedByHiding; lock.unlock()
        let split = kinds()
        var text = "used \(megabytes(Int64(footprint))) MB ("
        if let start { text += "\(megabytes(Int64(start))) MB at start, " }
        text += "highest \(megabytes(Int64(peakFootprint))) MB)"
        text += " · heap \(megabytes(Int64(split.heap))) MB · graphics \(megabytes(Int64(split.graphics))) MB · other \(megabytes(Int64(split.other))) MB"
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
