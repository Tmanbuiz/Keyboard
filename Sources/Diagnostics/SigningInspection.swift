import Foundation
import CryptoKit

/// Reads public signing metadata and checks executable page hashes. It cannot
/// verify certificate trust or reproduce the kernel's signature acceptance.
enum SigningInspection {
    enum InspectionError: Error { case malformed }
    static func inspect(_ bundle: Bundle) -> String {
        guard let executable = bundle.executableURL else { return "Executable missing" }
        do {
            let data = try Data(contentsOf: executable)
            var report = try inspectExecutable(data)
            let profileURL = bundle.bundleURL.appendingPathComponent("embedded.mobileprovision")
            if let raw = try? Data(contentsOf: profileURL),
               let start = raw.range(of: Data("<plist".utf8)),
               let end = raw.range(of: Data("</plist>".utf8), in: start.lowerBound..<raw.endIndex),
               let profile = (try? PropertyListSerialization.propertyList(from: raw.subdata(in: start.lowerBound..<end.upperBound), format: nil)) as? [String: Any] {
                let claims = profile["Entitlements"] as? [String: Any] ?? [:]
                report += "\nProfile application identifier: \(claims["application-identifier"] as? String ?? "absent")"
                report += "\nProfile team identifier: \(claims["com.apple.developer.team-identifier"] as? String ?? "absent")"
                report += "\nProfile app groups: \((claims["com.apple.security.application-groups"] as? [String] ?? []).joined(separator: ", "))"
                if let expiry = profile["ExpirationDate"] as? Date {
                    report += "\nProfile expires: \(ISO8601DateFormatter().string(from: expiry)); expired: \(expiry < Date())"
                }
                report += "\nProfile metadata read; profile signature trust is not verified."
            } else { report += "\nProvisioning profile absent or unreadable" }
            return report
        } catch { return "Signing inspection unavailable: \(error)" }
    }

    static func inspectExecutable(_ data: Data) throws -> String {
        func number(_ offset: Int, _ count: Int = 4, big: Bool = false) throws -> Int {
            guard offset >= 0, count > 0, offset <= data.count - count else { throw InspectionError.malformed }
            var value: UInt64 = 0
            for i in 0..<count {
                let shift = (big ? count - i - 1 : i) * 8
                value |= UInt64(data[offset + i]) << shift
            }
            guard value <= UInt64(Int.max) else { throw InspectionError.malformed }
            return Int(value)
        }
        guard try number(0) == 0xfeedfacf else { return "Unsupported executable format (expected thin Mach-O 64)" }
        let commands = try number(16)
        let commandBytes = try number(20)
        guard commands <= commandBytes / 8, commandBytes <= data.count - 32 else { throw InspectionError.malformed }
        var cursor = 32
        var signature: (Int, Int)?
        for _ in 0..<commands {
            let command = try number(cursor)
            let size = try number(cursor + 4)
            guard size >= 8, size <= 32 + commandBytes - cursor else { throw InspectionError.malformed }
            if command == 0x1d {
                guard size >= 16 else { throw InspectionError.malformed }
                signature = (try number(cursor + 8), try number(cursor + 12))
            }
            cursor += size
        }
        guard let (start, size) = signature else { return "No embedded code signature" }
        guard size >= 12, start <= data.count - size,
              try number(start, big: true) == 0xfade0cc0 else { throw InspectionError.malformed }
        let length = try number(start + 4, big: true)
        let count = try number(start + 8, big: true)
        guard length >= 12, length <= size, count <= (length - 12) / 8 else { throw InspectionError.malformed }
        var directories: [Int] = []
        var cms = false
        var entitlements: [String: Any] = [:]
        for i in 0..<count {
            let kind = try number(start + 12 + i * 8, big: true)
            let relative = try number(start + 16 + i * 8, big: true)
            guard relative >= 12 + count * 8, relative <= length - 8 else { throw InspectionError.malformed }
            let offset = start + relative
            let blobLength = try number(offset + 4, big: true)
            guard blobLength >= 8, blobLength <= length - relative else { throw InspectionError.malformed }
            if try number(offset, big: true) == 0xfade0c02 { directories.append(offset) }
            if kind == 0x10000 { cms = blobLength > 8 }
            if kind == 5 {
                let xml = data.subdata(in: offset + 8..<offset + blobLength)
                entitlements = (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any] ?? [:]
            }
        }
        var lines = ["CMS signature present: \(cms)", "Code directories: \(directories.count)"]
        guard !directories.isEmpty else { return lines.joined(separator: "\n") + "\nNo code directory" }
        for directory in directories {
            let directoryLength = try number(directory + 4, big: true)
            guard directoryLength >= 44 else { throw InspectionError.malformed }
            let version = try number(directory + 8, big: true)
            let flags = try number(directory + 12, big: true)
            let hashes = try number(directory + 16, big: true)
            let slots = try number(directory + 28, big: true)
            var limit = try number(directory + 32, big: true)
            let hashSize = try number(directory + 36, 1)
            let hashType = try number(directory + 37, 1)
            let pagePower = try number(directory + 39, 1)
            guard hashSize > 0, pagePower <= 30, hashes <= directoryLength,
                  slots <= (directoryLength - hashes) / hashSize else { throw InspectionError.malformed }
            if version >= 0x20100 {
                guard directoryLength >= 48 else { throw InspectionError.malformed }
                if try number(directory + 44, big: true) != 0 {
                    lines.append("Scatter code directory: page verification unsupported")
                    continue
                }
            }
            if version >= 0x20300 {
                guard directoryLength >= 64 else { throw InspectionError.malformed }
                let wideLimit = try number(directory + 56, 8, big: true)
                if wideLimit > 0 { limit = wideLimit }
            }
            let pageSize = pagePower == 0 ? max(limit, 1) : 1 << pagePower
            guard limit <= start, slots == (limit + pageSize - 1) / pageSize else { throw InspectionError.malformed }
            var mismatches: [Int] = []
            for slot in 0..<slots {
                let lower = slot * pageSize
                let bytes = data.subdata(in: lower..<min(lower + pageSize, limit))
                let digest: Data
                switch hashType {
                case 1: digest = Data(Insecure.SHA1.hash(data: bytes))
                case 2, 3: digest = Data(SHA256.hash(data: bytes))
                case 4: digest = Data(SHA384.hash(data: bytes))
                default: return "Unsupported code hash type: \(hashType)"
                }
                guard hashSize <= digest.count else { throw InspectionError.malformed }
                let hashStart = directory + hashes + slot * hashSize
                if data.subdata(in: hashStart..<hashStart + hashSize) != digest.prefix(hashSize) { mismatches.append(slot) }
            }
            lines.append("Ad-hoc signature: \(flags & 2 != 0); hash type: \(hashType)")
            lines.append("Executable pages checked: \(slots); mismatches: \(mismatches.count)")
            if !mismatches.isEmpty { lines.append("Mismatched page indexes: \(mismatches.prefix(20).map(String.init).joined(separator: ", "))") }
        }
        lines.append("Signed application identifier: \(entitlements["application-identifier"] as? String ?? "absent")")
        lines.append("Signed team identifier: \(entitlements["com.apple.developer.team-identifier"] as? String ?? "absent")")
        lines.append("Signed app groups: \((entitlements["com.apple.security.application-groups"] as? [String] ?? []).joined(separator: ", "))")
        lines.append("Page checks do not validate certificate trust, provisioning or iOS acceptance.")
        return lines.joined(separator: "\n")
    }
}
