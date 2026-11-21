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
    /// For each screen, the most memory seen while it was shown, in megabytes: any new high the process
    /// reached on it (caught by iOS's own peak figure, even between checks) and the memory in use when it was left.
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

    /// Memory region tags from <mach/vm_statistics.h>, by name so the compiler checks every value.
    private static let heapTags: Set<Int32> = [
        VM_MEMORY_MALLOC, VM_MEMORY_MALLOC_SMALL, VM_MEMORY_MALLOC_LARGE, VM_MEMORY_MALLOC_HUGE, VM_MEMORY_REALLOC,
        VM_MEMORY_MALLOC_TINY, VM_MEMORY_MALLOC_LARGE_REUSABLE, VM_MEMORY_MALLOC_LARGE_REUSED, VM_MEMORY_MALLOC_NANO,
        VM_MEMORY_MALLOC_MEDIUM]
    private static let drawnTags: Set<Int32> = [
        VM_MEMORY_COREGRAPHICS, VM_MEMORY_LAYERKIT, VM_MEMORY_CGIMAGE, VM_MEMORY_COREGRAPHICS_DATA,
        VM_MEMORY_COREGRAPHICS_SHARED, VM_MEMORY_COREGRAPHICS_FRAMEBUFFERS, VM_MEMORY_COREGRAPHICS_BACKINGSTORES,
        VM_MEMORY_COREGRAPHICS_XALLOC, VM_MEMORY_COREIMAGE, VM_MEMORY_IMAGEIO, VM_MEMORY_COREUI,
        VM_MEMORY_COREUI_CACHED_IMAGE_DATA]
    private static let surfaceTags: Set<Int32> = [VM_MEMORY_IOSURFACE, VM_MEMORY_IOACCELERATOR]

    /// Splits the memory in use by kind, from iOS's own record of each memory region: heap (objects, word
    /// lists and text), graphics (keys, emoji and images drawn for the screen) and the rest (mostly system
    /// frameworks' own data, such as Apple's spell checker or text recognition). It lists the top-level
    /// regions only, about a millisecond's work, and runs only for the report and at a memory warning,
    /// never on a key press.
    static func kinds() -> (heap: UInt64, graphics: UInt64, other: UInt64) {
        guard let info = taskInfo() else { return (0, 0, 0) }
        let page = UInt64(getpagesize())
        var heap: UInt64 = 0, drawn: UInt64 = 0, surfaces: UInt64 = 0
        var address: vm_address_t = 0
        for _ in 0..<100_000 {
            var region = vm_region_submap_info_data_64_t()
            var count = mach_msg_type_number_t(MemoryLayout<vm_region_submap_info_data_64_t>.size / MemoryLayout<natural_t>.size)
            // Depth 0 lists the top level only. Heap and graphics memory is never inside a submap such as the
            // system's shared libraries, so there is no need to step into one.
            var size: vm_size_t = 0, depth: natural_t = 0
            let result = withUnsafeMutablePointer(to: &region) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                    vm_region_recurse_64(mach_task_self_, &address, &size, &depth, raw, &count)
                }
            }
            guard result == KERN_SUCCESS else { break }
            if region.is_submap == 0 {
                let tag = Int32(bitPattern: region.user_tag)
                // Pages marked reusable (freed, waiting to be reclaimed) don't count against the limit.
                let dirtied = UInt64(region.pages_dirtied) - min(UInt64(region.pages_reusable), UInt64(region.pages_dirtied))
                let dirty = (dirtied + UInt64(region.pages_swapped_out)) * page
                if heapTags.contains(tag) { heap += dirty }
                else if drawnTags.contains(tag) { drawn += dirty }
                else if surfaceTags.contains(tag) { surfaces += UInt64(region.pages_resident) * page }
            }
            let next = address.addingReportingOverflow(size)
            guard size > 0, !next.overflow else { break }
            address = next.partialValue
        }
        // iOS also charges IOSurfaces and GPU memory to the keyboard through a ledger, and memory the keyboard
        // draws into can appear in both records. The larger figure is used rather than the sum, so graphics
        // is never counted twice; it can read slightly low instead.
        let ledger = UInt64(max(info.ledger_tag_graphics_footprint, 0)) + UInt64(max(info.ledger_tag_graphics_footprint_compressed, 0))
        let total = info.phys_footprint
        let heapPart = min(heap, total)
        let graphics = min(max(drawn + surfaces, ledger), total - heapPart)
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

    /// Credits the screen shown since the last call with the memory it reached, then follows `screen`.
    /// Called the moment the screen changes, when the keyboard closes or the app leaves, and at a memory warning.
    static func noteScreen(_ screen: String) {
        let info = taskInfo()
        let current = info?.phys_footprint ?? 0
        let peak = max(UInt64(max(info?.ledger_phys_footprint_peak ?? 0, 0)), current)
        lock.lock(); defer { lock.unlock() }
        if let shown = shownScreen {
            // A new high for the process was reached while `shown` was on display; otherwise note memory now.
            let reached = peak > lastPeak ? peak : current
            screenPeaks[shown] = max(screenPeaks[shown] ?? 0, megabytes(Int64(reached)))
        }
        lastPeak = max(lastPeak, peak)
        shownScreen = screen
    }

    /// The highest memory this process reached on each screen, in megabytes.
    static var peaksByScreen: [String: Int] { lock.lock(); defer { lock.unlock() }; return screenPeaks }

    /// After "Reset health counter", highs from before the reset no longer count.
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
