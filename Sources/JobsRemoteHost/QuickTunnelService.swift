//
//  QuickTunnelService.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import Foundation
import Darwin

final class QuickTunnelService {
    private let fileManager = FileManager.default

    func publicBaseURL() -> String? {
        guard !isForcedFailure else {
            return nil
        }
        guard tunnelProcessState() == .running else {
            return nil
        };return publicBaseURLFromRuntimeFile() ?? publicBaseURLFromLog()
    }

    func publicURL(inviteCode: String) -> String {
        let trimmedInviteCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInviteCode.isEmpty,
              let baseURL = publicBaseURL() else {
            return ""
        }
        let encodedInviteCode = trimmedInviteCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedInviteCode
        return "\(baseURL)/?invite=\(encodedInviteCode)"
    }

    func status(inviteCode: String) -> String {
        if isForcedFailure {
            return "测试模式：已模拟免安装公网通道失败，可检查“其他连接方式…”是否出现。"
        }
        let processState = tunnelProcessState()
        if processState == .stopped {
            return "免安装公网通道已断开：旧公网链接已失效，请重新启动应用生成新链接。"
        }
        guard let baseURL = publicBaseURL() else {
            if let status = publicStatus(), !status.isEmpty {
                if status.contains("已就绪") {
                    return "免安装公网通道正在刷新链接：请稍等几秒；如果一直不出现，请重新启动应用。"
                };return status
            };return "免安装公网通道准备中：Python 打包版会自动准备公网链接；Swift 源码版请手动提供通道状态。"
        }
        guard !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "免安装公网通道已就绪：\(baseURL)。开启服务后会自动拼接邀请码。"
        };return "免安装公网通道已就绪：朋友无需安装客户端，直接打开下方链接。"
    }

    func connectionState() -> QuickTunnelConnectionState {
        if isForcedFailure {
            return .failed
        }
        if publicBaseURL() != nil {
            return .ready
        }
        if tunnelProcessState() == .stopped {
            return .failed
        }
        if let status = publicStatus(), Self.isFailureStatus(status) {
            return .failed
        };return .preparing
    }

    private func publicBaseURLFromRuntimeFile() -> String? {
        let path = runtimeFilePath()
        guard fileManager.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        };return firstPublicTunnelURL(in: content)
    }

    private func runtimeFilePath() -> String {
        let projectDir = ProcessInfo.processInfo.environment["JOBS_REMOTE_HOST_PROJECT_DIR"] ?? fileManager.currentDirectoryPath
        return "\(projectDir)/.runtime/jobs-remote-host-tunnel-url.txt"
    }

    private func publicBaseURLFromLog() -> String? {
        let path = runtimeLogFilePath()
        guard fileManager.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        };return firstPublicTunnelURL(in: content)
    }

    private func firstPublicTunnelURL(in text: String) -> String? {
        let pattern = #"https://[-A-Za-z0-9.]+\.trycloudflare\.com"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range, in: text) else {
            return nil
        };return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func publicStatus() -> String? {
        let path = runtimeStatusFilePath()
        guard fileManager.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        };return trimmed
    }

    private func runtimeStatusFilePath() -> String {
        let projectDir = ProcessInfo.processInfo.environment["JOBS_REMOTE_HOST_PROJECT_DIR"] ?? fileManager.currentDirectoryPath
        return "\(projectDir)/.runtime/jobs-remote-host-tunnel-status.txt"
    }

    private func runtimePIDFilePath() -> String {
        let projectDir = ProcessInfo.processInfo.environment["JOBS_REMOTE_HOST_PROJECT_DIR"] ?? fileManager.currentDirectoryPath
        return "\(projectDir)/.runtime/jobs-remote-host-tunnel.pid"
    }

    private func runtimeLogFilePath() -> String {
        let projectDir = ProcessInfo.processInfo.environment["JOBS_REMOTE_HOST_PROJECT_DIR"] ?? fileManager.currentDirectoryPath
        return "\(projectDir)/.runtime/jobs-remote-host-tunnel-cloudflared.log"
    }

    private enum TunnelProcessState: Equatable {
        case unknown
        case running
        case stopped
    }

    private func tunnelProcessState() -> TunnelProcessState {
        let path = runtimePIDFilePath()
        guard fileManager.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .unknown
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(trimmed), pid > 0 else {
            return .stopped
        }
        guard kill(pid, 0) == 0 || errno == EPERM else {
            return .stopped
        }
        if processLooksLikeCloudflared(pid: pid) {
            return .running
        };return .stopped
    }

    private func processLooksLikeCloudflared(pid: Int32) -> Bool {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let length: Int32 = pathBuffer.withUnsafeMutableBufferPointer { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else {
                return 0
            };return proc_pidpath(pid, baseAddress, UInt32(bufferPointer.count))
        }
        guard length > 0 else {
            return false
        }
        let executablePath = String(cString: pathBuffer).lowercased()
        return executablePath.contains("cloudflared")
    }

    private var isForcedFailure: Bool {
        let value = ProcessInfo.processInfo.environment["JOBS_REMOTE_HOST_FORCE_TUNNEL_FAILURE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["1", "true", "yes"].contains(value)
    }

    private static func isFailureStatus(_ status: String) -> Bool {
        ["失败", "已断开", "已退出", "立即断开", "不可用"].contains { status.contains($0) }
    }
}
