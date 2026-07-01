//
//  AutomaticPortMapper.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import Darwin
import Foundation

struct PortMappingResult {
    let method: String
    let message: String
}

final class AutomaticPortMapper {
    private let queue = DispatchQueue(label: "com.jobs.remotehost.portmapper")

    func mapTCP(port: UInt16, localAddress: String?, completion: @escaping (Result<PortMappingResult, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            do {
                if let gateway = try self.defaultGatewayIPv4() {
                    do {
                        let result = try self.mapWithNATPMP(gateway: gateway, port: port)
                        completion(.success(result))
                        return
                    } catch {
                        // NAT-PMP is optional; continue with UPnP.
                    }
                }
                guard let localAddress else {
                    throw PortMappingError.missingLocalAddress
                }
                let result = try self.mapWithUPnP(localAddress: localAddress, port: port)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func defaultGatewayIPv4() throws -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        };return output
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count == 2, parts[0] == "gateway" else {
                    return nil
                };return parts[1]
            }
            .first
    }

    private func mapWithNATPMP(gateway: String, port: UInt16) throws -> PortMappingResult {
        let socketFileDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFileDescriptor >= 0 else {
            throw PortMappingError.socketFailed
        }
        defer {
            close(socketFileDescriptor)
        }
        setReceiveTimeout(on: socketFileDescriptor, seconds: 3)
        var request = [UInt8]()
        request.append(0) // NAT-PMP version.
        request.append(2) // Map TCP.
        request.appendUInt16(0)
        request.appendUInt16(port)
        request.appendUInt16(port)
        request.appendUInt32(3600)
        try sendUDP(request, to: gateway, port: 5351, socketFileDescriptor: socketFileDescriptor)
        let response = try receiveUDP(socketFileDescriptor: socketFileDescriptor, maxLength: 32)
        guard response.count >= 16,
              response[0] == 0,
              response[1] == 130 else {
            throw PortMappingError.invalidNATPMPResponse
        }
        let resultCode = response.uint16(at: 2)
        guard resultCode == 0 else {
            throw PortMappingError.natPMPRejected(code: resultCode)
        }
        let externalPort = response.uint16(at: 10)
        return PortMappingResult(
            method: "NAT-PMP",
            message: "自动映射成功：TCP \(externalPort) -> 本机 TCP \(port)，有效期 3600 秒"
        )
    }

    private func mapWithUPnP(localAddress: String, port: UInt16) throws -> PortMappingResult {
        let location = try discoverUPnPLocation()
        let description = try fetchText(from: location)
        let service = try parseWANService(from: description, baseURL: location)
        try addUPnPPortMapping(service: service, localAddress: localAddress, port: port)
        return PortMappingResult(
            method: "UPnP",
            message: "自动映射成功：TCP \(port) -> \(localAddress):\(port)"
        )
    }

    private func discoverUPnPLocation() throws -> URL {
        let socketFileDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFileDescriptor >= 0 else {
            throw PortMappingError.socketFailed
        }
        defer {
            close(socketFileDescriptor)
        }
        setReceiveTimeout(on: socketFileDescriptor, seconds: 3)
        let searchTargets = [
            "urn:schemas-upnp-org:service:WANIPConnection:1",
            "urn:schemas-upnp-org:service:WANPPPConnection:1",
            "urn:schemas-upnp-org:device:InternetGatewayDevice:1",
            "ssdp:all"
        ]
        for target in searchTargets {
            let request = """
            M-SEARCH * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            MAN: "ssdp:discover"\r
            MX: 2\r
            ST: \(target)\r
            \r

            """
            try sendUDP(Array(request.utf8), to: "239.255.255.250", port: 1900, socketFileDescriptor: socketFileDescriptor)
        }
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            guard let text = try? String(bytes: receiveUDP(socketFileDescriptor: socketFileDescriptor, maxLength: 8192), encoding: .utf8),
                  let location = Self.locationHeader(in: text),
                  let url = URL(string: location) else {
                continue
            };return url
        }
        throw PortMappingError.upnpNotFound
    }

    private func fetchText(from url: URL) throws -> String {
        var text: String?
        var requestError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: url) { data, _, error in
            requestError = error
            if let data {
                text = String(data: data, encoding: .utf8)
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 6)
        if let requestError {
            throw requestError
        }
        guard let text else {
            throw PortMappingError.invalidUPnPDescription
        };return text
    }

    private func parseWANService(from description: String, baseURL: URL) throws -> UPnPService {
        let pattern = #"(?is)<service>\s*.*?<serviceType>\s*([^<]+)\s*</serviceType>\s*.*?<controlURL>\s*([^<]+)\s*</controlURL>\s*.*?</service>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let range = NSRange(description.startIndex..., in: description)
        for match in regex.matches(in: description, range: range) {
            guard let typeRange = Range(match.range(at: 1), in: description),
                  let controlRange = Range(match.range(at: 2), in: description) else {
                continue
            }
            let serviceType = String(description[typeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard serviceType.contains("WANIPConnection") || serviceType.contains("WANPPPConnection") else {
                continue
            }
            let controlPath = String(description[controlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let controlURL = absoluteURL(for: controlPath, baseURL: baseURL) else {
                continue
            };return UPnPService(serviceType: serviceType, controlURL: controlURL)
        }
        throw PortMappingError.wanServiceNotFound
    }

    private func addUPnPPortMapping(service: UPnPService, localAddress: String, port: UInt16) throws {
        let body = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:AddPortMapping xmlns:u="\(service.serviceType)">
              <NewRemoteHost></NewRemoteHost>
              <NewExternalPort>\(port)</NewExternalPort>
              <NewProtocol>TCP</NewProtocol>
              <NewInternalPort>\(port)</NewInternalPort>
              <NewInternalClient>\(localAddress)</NewInternalClient>
              <NewEnabled>1</NewEnabled>
              <NewPortMappingDescription>JobsRemoteHost</NewPortMappingDescription>
              <NewLeaseDuration>3600</NewLeaseDuration>
            </u:AddPortMapping>
          </s:Body>
        </s:Envelope>
        """
        var request = URLRequest(url: service.controlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.serviceType)#AddPortMapping\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)
        var statusCode = 0
        var responseText = ""
        var requestError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            requestError = error
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data {
                responseText = String(data: data, encoding: .utf8) ?? ""
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        if let requestError {
            throw requestError
        }
        guard (200..<300).contains(statusCode), !responseText.localizedCaseInsensitiveContains("errorCode") else {
            throw PortMappingError.upnpRejected(status: statusCode, body: responseText)
        }
    }

    private func absoluteURL(for controlPath: String, baseURL: URL) -> URL? {
        if controlPath.hasPrefix("http://") || controlPath.hasPrefix("https://") {
            return URL(string: controlPath)
        }
        if controlPath.hasPrefix("/") {
            var components = URLComponents()
            components.scheme = baseURL.scheme
            components.host = baseURL.host
            components.port = baseURL.port
            components.path = controlPath
            return components.url
        };return URL(string: controlPath, relativeTo: baseURL)?.absoluteURL
    }

    private func sendUDP(_ bytes: [UInt8], to host: String, port: UInt16, socketFileDescriptor: Int32) throws {
        var address = try sockaddrIn(host: host, port: port)
        let sent = bytes.withUnsafeBytes { bytesPointer in
            withUnsafePointer(to: &address) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(socketFileDescriptor, bytesPointer.baseAddress, bytes.count, 0, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.stride))
                }
            }
        }
        guard sent == bytes.count else {
            throw PortMappingError.sendFailed
        }
    }

    private func receiveUDP(socketFileDescriptor: Int32, maxLength: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: maxLength)
        let count = recvfrom(socketFileDescriptor, &buffer, maxLength, 0, nil, nil)
        guard count > 0 else {
            throw PortMappingError.receiveTimeout
        };return Array(buffer.prefix(count))
    }

    private func sockaddrIn(host: String, port: UInt16) throws -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw PortMappingError.invalidAddress(host)
        };return address
    }

    private func setReceiveTimeout(on socketFileDescriptor: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(socketFileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.stride))
    }

    private static func locationHeader(in response: String) -> String? {
        response
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count == 2, parts[0].lowercased() == "location" else {
                    return nil
                };return parts[1]
            }
            .first
    }
}

private struct UPnPService {
    let serviceType: String
    let controlURL: URL
}

enum PortMappingError: LocalizedError {
    case socketFailed
    case sendFailed
    case receiveTimeout
    case invalidAddress(String)
    case invalidNATPMPResponse
    case natPMPRejected(code: UInt16)
    case missingLocalAddress
    case upnpNotFound
    case invalidUPnPDescription
    case wanServiceNotFound
    case upnpRejected(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .socketFailed:
            return "创建网络套接字失败"
        case .sendFailed:
            return "发送端口映射请求失败"
        case .receiveTimeout:
            return "等待路由器响应超时"
        case let .invalidAddress(address):
            return "无效地址：\(address)"
        case .invalidNATPMPResponse:
            return "NAT-PMP 响应格式不正确"
        case let .natPMPRejected(code):
            return "路由器拒绝 NAT-PMP 映射，错误码：\(code)"
        case .missingLocalAddress:
            return "未找到本机内网 IP"
        case .upnpNotFound:
            return "未发现支持 UPnP 的网关"
        case .invalidUPnPDescription:
            return "UPnP 网关描述无法解析"
        case .wanServiceNotFound:
            return "UPnP 网关没有暴露 WANIPConnection 服务"
        case let .upnpRejected(status, body):
            let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "路由器拒绝 UPnP 映射，HTTP \(status)\(message.isEmpty ? "" : "，\(message)")"
        }
    }
}

private extension Array where Element == UInt8 {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    func uint16(at index: Int) -> UInt16 {
        (UInt16(self[index]) << 8) | UInt16(self[index + 1])
    }
}
