//
//  ZeroTierService.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import Foundation

struct ZeroTierNetworkInfo {
    let id: String
    let name: String
    let status: String
    let assignedIPv4s: [String]
}

struct ZeroTierPreparationResult {
    let message: String
    let networks: [ZeroTierNetworkInfo]
}

final class ZeroTierService {
    func prepare(networkID: String, completion: @escaping (Result<ZeroTierPreparationResult, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            let trimmedNetworkID = networkID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let cliPath = self.findCLIPath() else {
                completion(.failure(ZeroTierServiceError.cliNotFound))
                return
            }
            if !trimmedNetworkID.isEmpty {
                let validation = self.validate(networkID: trimmedNetworkID)
                guard validation else {
                    completion(.failure(ZeroTierServiceError.invalidNetworkID))
                    return
                }
                _ = self.runCLI(cliPath: cliPath, arguments: ["join", trimmedNetworkID])
            }
            let listResult = self.runCLI(cliPath: cliPath, arguments: ["-j", "listnetworks"])
            guard listResult.exitCode == 0 else {
                completion(.failure(ZeroTierServiceError.commandFailed(listResult.stderr.isEmpty ? listResult.stdout : listResult.stderr)))
                return
            }
            let networks = self.parseNetworks(from: listResult.stdout)
            let filtered = trimmedNetworkID.isEmpty ? networks : networks.filter { $0.id.lowercased() == trimmedNetworkID.lowercased() }
            let message = self.message(for: filtered, requestedNetworkID: trimmedNetworkID)
            completion(.success(ZeroTierPreparationResult(message: message, networks: filtered)))
        }
    }

    func detectedIPv4s() -> [String] {
        let trimmedNetworks = listNetworksFromCLI()
        let cliAddresses = trimmedNetworks.flatMap(\.assignedIPv4s)
        return Array(Set(cliAddresses)).sorted()
    }

    private func listNetworksFromCLI() -> [ZeroTierNetworkInfo] {
        guard let cliPath = findCLIPath() else {
            return []
        }
        let result = runCLI(cliPath: cliPath, arguments: ["-j", "listnetworks"])
        guard result.exitCode == 0 else {
            return []
        };return parseNetworks(from: result.stdout)
    }

    private func findCLIPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/zerotier-cli",
            "/usr/local/bin/zerotier-cli",
            "/Library/Application Support/ZeroTier/One/zerotier-cli"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        let result = runCommand(path: "/usr/bin/env", arguments: ["which", "zerotier-cli"])
        let commandPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0,
              !commandPath.isEmpty,
              FileManager.default.isExecutableFile(atPath: commandPath) else {
            return nil
        };return commandPath
    }

    private func validate(networkID: String) -> Bool {
        let pattern = #"^[A-Fa-f0-9]{16}$"#
        return networkID.range(of: pattern, options: .regularExpression) != nil
    }

    private func runCLI(cliPath: String, arguments: [String]) -> ProcessResult {
        runCommand(path: cliPath, arguments: arguments)
    }

    private func runCommand(path: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return ProcessResult(exitCode: process.terminationStatus, stdout: output, stderr: error)
        } catch {
            return ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
    }

    private func parseNetworks(from json: String) -> [ZeroTierNetworkInfo] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let array = object as? [[String: Any]] else {
            return []
        };return array.map { item in
            let addresses = (item["assignedAddresses"] as? [String] ?? [])
                .compactMap { value -> String? in
                    let address = value.components(separatedBy: "/").first ?? value
                    guard address.contains(".") else {
                        return nil
                    };return address
                };return ZeroTierNetworkInfo(
                id: (item["nwid"] as? String) ?? (item["id"] as? String) ?? "",
                name: (item["name"] as? String) ?? "ZeroTier 网络",
                status: (item["status"] as? String) ?? "UNKNOWN",
                assignedIPv4s: addresses
            )
        }
    }

    private func message(for networks: [ZeroTierNetworkInfo], requestedNetworkID: String) -> String {
        if !requestedNetworkID.isEmpty, networks.isEmpty {
            return "已尝试加入 ZeroTier 网络 \(requestedNetworkID)。如果还没有虚拟 IP，请到 ZeroTier Central 授权这台 Mac 后再刷新。"
        }
        guard !networks.isEmpty else {
            return "未发现 ZeroTier 网络。请填写 Network ID 后点击 ZeroTier 一键准备。"
        }
        let addresses = networks.flatMap(\.assignedIPv4s)
        guard !addresses.isEmpty else {
            return "已发现 ZeroTier 网络，但还没有分配 IPv4。请确认本机已在 ZeroTier Central 被授权。"
        };return "ZeroTier 已就绪：\(addresses.joined(separator: ", "))"
    }
}

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ZeroTierServiceError: LocalizedError {
    case cliNotFound
    case invalidNetworkID
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "未检测到 zerotier-cli。请先安装 ZeroTier One，然后重新打开本软件。"
        case .invalidNetworkID:
            return "ZeroTier Network ID 应该是 16 位十六进制字符。"
        case let .commandFailed(message):
            return "ZeroTier 命令执行失败：\(message)"
        }
    }
}
