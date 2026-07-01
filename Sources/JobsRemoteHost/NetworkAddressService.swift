//
//  NetworkAddressService.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import Darwin
import Foundation

final class NetworkAddressService {
    func localIPv4Addresses() -> [String] {
        var addresses = [String]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddress = ifaddr else {
            return []
        }
        defer {
            freeifaddrs(ifaddr)
        }
        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }
            let address = String(cString: hostname)
            guard !address.hasPrefix("169.254.") else {
                continue
            }
            addresses.append(address)
        };return Array(Set(addresses)).sorted()
    }

    func fetchPublicIPv4(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.ipify.org") else {
            completion(.failure(NetworkAddressError.invalidURL))
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data,
                  let address = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !address.isEmpty else {
                completion(.failure(NetworkAddressError.emptyResponse))
                return
            }
            completion(.success(address))
        }.resume()
    }
}

enum NetworkAddressError: Error {
    case invalidURL
    case emptyResponse
}
