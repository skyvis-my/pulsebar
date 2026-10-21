import Darwin
import Foundation

/// Unprivileged ICMP echo using a SOCK_DGRAM/IPPROTO_ICMP socket (no root, no /sbin/ping process).
final class Pinger {
    private let queue = DispatchQueue(label: "pulsebar.ping")
    private let ident = UInt16(truncatingIfNeeded: getpid())
    private var seq: UInt16 = 0
    private var inFlight = false
    private var cachedHost: (name: String, addr: sockaddr_in)?

    /// Calls back on the main queue with round-trip milliseconds, or nil on timeout/failure.
    func ping(_ host: String, timeout: TimeInterval = 0.9, completion: @escaping (Double?) -> Void) {
        queue.async { [self] in
            guard !inFlight else { return }
            inFlight = true
            let ms = send(to: host, timeout: timeout)
            inFlight = false
            DispatchQueue.main.async { completion(ms) }
        }
    }

    private func resolve(_ host: String) -> sockaddr_in? {
        if let c = cachedHost, c.name == host { return c.addr }
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_DGRAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let info = res, let sa = info.pointee.ai_addr else {
            return nil
        }
        defer { freeaddrinfo(res) }
        let addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        cachedHost = (host, addr)
        return addr
    }

    private func send(to host: String, timeout: TimeInterval) -> Double? {
        guard var addr = resolve(host) else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        seq &+= 1
        let mySeq = seq
        var packet = [UInt8](repeating: 0, count: 16)
        packet[0] = 8 // echo request
        packet[4] = UInt8(ident >> 8); packet[5] = UInt8(ident & 0xff)
        packet[6] = UInt8(mySeq >> 8); packet[7] = UInt8(mySeq & 0xff)
        let sum = Self.checksum(packet)
        packet[2] = UInt8(sum >> 8); packet[3] = UInt8(sum & 0xff)

        let start = DispatchTime.now().uptimeNanoseconds
        let sent = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == packet.count else { if Self.isNetworkDown(errno) { cachedHost = nil }; return nil }

        let deadline = start + UInt64(timeout * 1e9)
        var buf = [UInt8](repeating: 0, count: 256)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return nil }
            var tv = timeval(tv_sec: 0, tv_usec: Int32((deadline - now) / 1000))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let n = recv(fd, &buf, buf.count, 0)
            guard n > 0 else { return nil }
            // macOS delivers the IPv4 header on ICMP datagram sockets; skip it.
            var off = 0
            if buf[0] >> 4 == 4 { off = Int(buf[0] & 0x0f) * 4 }
            guard n >= off + 8, buf[off] == 0 else { continue }
            let rid = UInt16(buf[off + 4]) << 8 | UInt16(buf[off + 5])
            let rseq = UInt16(buf[off + 6]) << 8 | UInt16(buf[off + 7])
            if rid == ident && rseq == mySeq {
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            }
        }
    }

    private static func isNetworkDown(_ err: Int32) -> Bool {
        err == ENETUNREACH || err == EHOSTUNREACH || err == ENETDOWN
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count { sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]); i += 2 }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum)
    }
}
