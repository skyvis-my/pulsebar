import Darwin
import Foundation

/// Reads 64-bit interface byte counters via sysctl(NET_RT_IFLIST2) and turns them into bytes/second.
final class NetworkSampler {
    private var last: (rx: UInt64, tx: UInt64, at: TimeInterval)?

    /// Physical interfaces only. Counting utun/ipsec too would double-count VPN traffic.
    private static func counts(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    func sample() -> (up: Double, down: Double)? {
        guard let totals = Self.readTotals() else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        defer { last = (totals.rx, totals.tx, now) }
        guard let prev = last, now > prev.at else { return nil }
        let dt = now - prev.at
        // Counters reset when an interface goes away; treat a backwards step as zero.
        let rx = totals.rx >= prev.rx ? Double(totals.rx - prev.rx) : 0
        let tx = totals.tx >= prev.tx ? Double(totals.tx - prev.tx) : 0
        return (tx / dt, rx / dt)
    }

    private static func readTotals() -> (rx: UInt64, tx: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return nil }

        var rx: UInt64 = 0, tx: UInt64 = 0
        var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.load(fromByteOffset: offset, as: if_msghdr.self)
                let msgLen = Int(hdr.ifm_msglen)
                guard msgLen > 0 else { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2 {
                    let m2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if if_indextoname(UInt32(m2.ifm_index), &nameBuf) != nil,
                       counts(String(cString: nameBuf)) {
                        rx &+= m2.ifm_data.ifi_ibytes
                        tx &+= m2.ifm_data.ifi_obytes
                    }
                }
                offset += msgLen
            }
        }
        return (rx, tx)
    }
}
