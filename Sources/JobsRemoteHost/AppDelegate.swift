//
//  AppDelegate.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowController = MainWindowController()
    private let addressService = NetworkAddressService()
    private let relayService = RelaySessionService()
    private let captureService = ScreenCaptureService()
    private let inputController = InputController()
    private let portMapper = AutomaticPortMapper()
    private let zeroTierService = ZeroTierService()
    private let quickTunnelService = QuickTunnelService()
    private var server: RemoteHostServer?
    private var relayTunnelClient: RelayTunnelClient?
    private var quickTunnelTimer: DispatchSourceTimer?
    private var currentLocalAddress: String?
    private var currentZeroTierAddresses = [String]()
    private var currentState = ServerDisplayState(
        isRunning: false,
        port: 8088,
        inviteCode: "",
        localURLs: [],
        zeroTierURLs: [],
        zeroTierStatus: AppDelegate.zeroTierDefaultStatus,
        quickTunnelURL: "",
        quickTunnelStatus: AppDelegate.quickTunnelDefaultStatus,
        quickTunnelConnectionState: .preparing,
        publicDirectURL: "服务开启后生成",
        relayURL: "未配置公网会话服务：先启动 relay server，并在上方填写 http://公网IP:8787",
        permissionSummary: PermissionService.summary(),
        statusText: "服务未开启"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController.actionsDelegate = self
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        startQuickTunnelMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func updateState(_ transform: (ServerDisplayState) -> ServerDisplayState) {
        currentState = transform(currentState)
        windowController.apply(state: currentState)
    }

    private func startServer(port: UInt16, relayBaseURL: String, zeroTierNetworkID: String) {
        let inviteCode = Self.makeInviteCode()
        let localAddresses = addressService.localIPv4Addresses()
        let zeroTierAddresses = Array(Set(currentZeroTierAddresses + zeroTierService.detectedIPv4s())).sorted()
        currentLocalAddress = localAddresses.first
        currentZeroTierAddresses = zeroTierAddresses
        let localURLs = localAddresses.map { "http://\($0):\(port)/?invite=\(inviteCode)" }
        let zeroTierURLs = Self.urls(addresses: zeroTierAddresses, port: port, inviteCode: inviteCode)
        let server = RemoteHostServer(
            port: port,
            inviteCode: inviteCode,
            captureService: captureService,
            inputController: inputController
        )
        server.delegate = self
        do {
            try server.start()
            self.server = server
            let relayURL = relayService.sessionLink(baseURL: relayBaseURL, inviteCode: inviteCode)
            updateState { _ in
                ServerDisplayState(
                    isRunning: true,
                    port: port,
                    inviteCode: inviteCode,
                    localURLs: localURLs,
                    zeroTierURLs: zeroTierURLs,
                    zeroTierStatus: Self.zeroTierStatus(addresses: zeroTierAddresses, isRunning: true),
                    quickTunnelURL: self.quickTunnelService.publicURL(inviteCode: inviteCode),
                    quickTunnelStatus: self.quickTunnelService.status(inviteCode: inviteCode),
                    quickTunnelConnectionState: self.quickTunnelService.connectionState(),
                    publicDirectURL: "外网 IP 检测中...",
                    relayURL: relayURL,
                    permissionSummary: PermissionService.summary(),
                    statusText: "服务已开启，邀请码：\(inviteCode)"
                )
            }
            windowController.appendLog("服务已开启，端口 \(port)，邀请码 \(inviteCode)")
            startRelayTunnelIfNeeded(baseURL: relayBaseURL, inviteCode: inviteCode)
            prepareZeroTierIfNeeded(networkID: zeroTierNetworkID)
            refreshPublicAddress(port: port, inviteCode: inviteCode, relayBaseURL: relayBaseURL, localURLs: localURLs, localAddress: localAddresses.first)
        } catch {
            windowController.appendLog("服务启动失败：\(error)")
            showMessage(title: "启动失败", text: "\(error)")
        }
    }

    private func stopServer() {
        server?.stop()
        server = nil
        relayTunnelClient?.stop()
        relayTunnelClient = nil
        currentLocalAddress = nil
        updateState { state in
            ServerDisplayState(
                isRunning: false,
                port: state.port,
                inviteCode: "",
                localURLs: [],
                zeroTierURLs: [],
                zeroTierStatus: Self.zeroTierStatus(addresses: self.currentZeroTierAddresses, isRunning: false),
                quickTunnelURL: "",
                quickTunnelStatus: self.quickTunnelService.status(inviteCode: ""),
                quickTunnelConnectionState: self.quickTunnelService.connectionState(),
                publicDirectURL: "服务开启后生成",
                relayURL: "未配置公网会话服务：先启动 relay server，并在上方填写 http://公网IP:8787",
                permissionSummary: PermissionService.summary(),
                statusText: "服务未开启"
            )
        }
        windowController.appendLog("服务已停止")
    }

    private func refreshPublicAddress(port: UInt16, inviteCode: String, relayBaseURL: String, localURLs: [String], localAddress: String?) {
        addressService.fetchPublicIPv4 { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                let publicURL: String
                switch result {
                case let .success(ip):
                    let url = "http://\(ip):\(port)/?invite=\(inviteCode)"
                    let mapping = localAddress.map { "路由器需映射：TCP \(port) -> \($0):\(port)" } ?? "路由器需映射：TCP \(port) -> 本机内网 IP:\(port)"
                    publicURL = "\(url)\n这是外网直连地址，不走 relay；失败时请用下方公网会话链接。\n未确认外网可达，\(mapping)"
                case let .failure(error):
                    publicURL = "外网 IP 获取失败：\(error.localizedDescription)"
                }
                self.updateState { state in
                    ServerDisplayState(
                        isRunning: state.isRunning,
                        port: state.port,
                        inviteCode: state.inviteCode,
                        localURLs: state.localURLs,
                        zeroTierURLs: state.zeroTierURLs,
                        zeroTierStatus: state.zeroTierStatus,
                        quickTunnelURL: state.quickTunnelURL,
                        quickTunnelStatus: state.quickTunnelStatus,
                        quickTunnelConnectionState: state.quickTunnelConnectionState,
                        publicDirectURL: publicURL,
                        relayURL: state.relayURL,
                        permissionSummary: PermissionService.summary(),
                        statusText: state.statusText
                    )
                }
                self.registerRelayIfNeeded(baseURL: relayBaseURL, inviteCode: inviteCode, localURLs: localURLs, publicURL: publicURL)
            }
        }
    }

    private func registerRelayIfNeeded(baseURL: String, inviteCode: String, localURLs: [String], publicURL: String) {
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        relayService.registerHost(baseURL: baseURL, inviteCode: inviteCode, localURLs: localURLs, publicDirectURL: publicURL) { [weak self] relayURL in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.updateState { state in
                    ServerDisplayState(
                        isRunning: state.isRunning,
                        port: state.port,
                        inviteCode: state.inviteCode,
                        localURLs: state.localURLs,
                        zeroTierURLs: state.zeroTierURLs,
                        zeroTierStatus: state.zeroTierStatus,
                        quickTunnelURL: state.quickTunnelURL,
                        quickTunnelStatus: state.quickTunnelStatus,
                        quickTunnelConnectionState: state.quickTunnelConnectionState,
                        publicDirectURL: state.publicDirectURL,
                        relayURL: relayURL,
                        permissionSummary: PermissionService.summary(),
                        statusText: state.statusText
                    )
                }
            }
        }
    }

    private func startRelayTunnelIfNeeded(baseURL: String, inviteCode: String) {
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let client = RelayTunnelClient(
            baseURL: baseURL,
            inviteCode: inviteCode,
            captureService: captureService,
            inputController: inputController
        )
        client.delegate = self
        relayTunnelClient = client
        client.start()
    }

    private func mapPortAutomatically() {
        guard currentState.isRunning else {
            windowController.appendLog("端口映射失败：服务未开启")
            return
        }
        let port = currentState.port
        let localAddress = currentLocalAddress ?? addressService.localIPv4Addresses().first
        windowController.appendLog("开始尝试自动端口映射：TCP \(port)")
        updateState { state in
            ServerDisplayState(
                isRunning: state.isRunning,
                port: state.port,
                inviteCode: state.inviteCode,
                localURLs: state.localURLs,
                zeroTierURLs: state.zeroTierURLs,
                zeroTierStatus: state.zeroTierStatus,
                quickTunnelURL: state.quickTunnelURL,
                quickTunnelStatus: state.quickTunnelStatus,
                quickTunnelConnectionState: state.quickTunnelConnectionState,
                publicDirectURL: "\(Self.firstLineURL(from: state.publicDirectURL))\n正在尝试自动端口映射：NAT-PMP / UPnP",
                relayURL: state.relayURL,
                permissionSummary: PermissionService.summary(),
                statusText: state.statusText
            )
        }
        portMapper.mapTCP(port: port, localAddress: localAddress) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                switch result {
                case let .success(mapping):
                    self.windowController.appendLog("\(mapping.method) \(mapping.message)")
                    self.updateState { state in
                        ServerDisplayState(
                            isRunning: state.isRunning,
                            port: state.port,
                            inviteCode: state.inviteCode,
                            localURLs: state.localURLs,
                            zeroTierURLs: state.zeroTierURLs,
                            zeroTierStatus: state.zeroTierStatus,
                            quickTunnelURL: state.quickTunnelURL,
                            quickTunnelStatus: state.quickTunnelStatus,
                            quickTunnelConnectionState: state.quickTunnelConnectionState,
                            publicDirectURL: "\(Self.firstLineURL(from: state.publicDirectURL))\n\(mapping.message)",
                            relayURL: state.relayURL,
                            permissionSummary: PermissionService.summary(),
                            statusText: state.statusText
                        )
                    }
                case let .failure(error):
                    self.windowController.appendLog("自动端口映射失败：\(error.localizedDescription)")
                    self.windowController.appendLog("如果路由器关闭 UPnP/NAT-PMP，或当前网络是运营商 CGNAT，软件无法自动打通外网直连。")
                    self.updateState { state in
                        ServerDisplayState(
                            isRunning: state.isRunning,
                            port: state.port,
                            inviteCode: state.inviteCode,
                            localURLs: state.localURLs,
                            zeroTierURLs: state.zeroTierURLs,
                            zeroTierStatus: state.zeroTierStatus,
                            quickTunnelURL: state.quickTunnelURL,
                            quickTunnelStatus: state.quickTunnelStatus,
                            quickTunnelConnectionState: state.quickTunnelConnectionState,
                            publicDirectURL: "\(Self.firstLineURL(from: state.publicDirectURL))\n自动映射失败：\(error.localizedDescription)",
                            relayURL: state.relayURL,
                            permissionSummary: PermissionService.summary(),
                            statusText: state.statusText
                        )
                    }
                }
            }
        }
    }

    private func prepareZeroTierIfNeeded(networkID: String) {
        let trimmed = networkID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            refreshZeroTierAddresses(messagePrefix: nil)
            return
        }
        windowController.appendLog("ZeroTier 一键准备：\(trimmed)")
        updateState { state in
            ServerDisplayState(
                isRunning: state.isRunning,
                port: state.port,
                inviteCode: state.inviteCode,
                localURLs: state.localURLs,
                zeroTierURLs: state.zeroTierURLs,
                zeroTierStatus: "ZeroTier 准备中：正在加入/刷新网络 \(trimmed)",
                quickTunnelURL: state.quickTunnelURL,
                quickTunnelStatus: state.quickTunnelStatus,
                quickTunnelConnectionState: state.quickTunnelConnectionState,
                publicDirectURL: state.publicDirectURL,
                relayURL: state.relayURL,
                permissionSummary: PermissionService.summary(),
                statusText: state.statusText
            )
        }
        zeroTierService.prepare(networkID: trimmed) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleZeroTierResult(result)
            }
        }
    }

    private func refreshZeroTierAddresses(messagePrefix: String?) {
        let addresses = zeroTierService.detectedIPv4s()
        currentZeroTierAddresses = addresses
        let urls = Self.urls(addresses: addresses, port: currentState.port, inviteCode: currentState.inviteCode)
        let status = messagePrefix.map { "\($0)\n\(Self.zeroTierStatus(addresses: addresses, isRunning: currentState.isRunning))" } ?? Self.zeroTierStatus(addresses: addresses, isRunning: currentState.isRunning)
        updateState { state in
            ServerDisplayState(
                isRunning: state.isRunning,
                port: state.port,
                inviteCode: state.inviteCode,
                localURLs: state.localURLs,
                zeroTierURLs: urls,
                zeroTierStatus: status,
                quickTunnelURL: state.quickTunnelURL,
                quickTunnelStatus: state.quickTunnelStatus,
                quickTunnelConnectionState: state.quickTunnelConnectionState,
                publicDirectURL: state.publicDirectURL,
                relayURL: state.relayURL,
                permissionSummary: PermissionService.summary(),
                statusText: state.statusText
            )
        }
    }

    private func handleZeroTierResult(_ result: Result<ZeroTierPreparationResult, Error>) {
        switch result {
        case let .success(preparation):
            let addresses = Array(Set(preparation.networks.flatMap(\.assignedIPv4s))).sorted()
            currentZeroTierAddresses = addresses
            windowController.appendLog(preparation.message)
            let urls = Self.urls(addresses: addresses, port: currentState.port, inviteCode: currentState.inviteCode)
            updateState { state in
                ServerDisplayState(
                    isRunning: state.isRunning,
                    port: state.port,
                    inviteCode: state.inviteCode,
                    localURLs: state.localURLs,
                    zeroTierURLs: urls,
                    zeroTierStatus: urls.isEmpty ? "\(preparation.message)\n服务开启后会在这里生成 ZeroTier 地址。" : preparation.message,
                    quickTunnelURL: state.quickTunnelURL,
                    quickTunnelStatus: state.quickTunnelStatus,
                    quickTunnelConnectionState: state.quickTunnelConnectionState,
                    publicDirectURL: state.publicDirectURL,
                    relayURL: state.relayURL,
                    permissionSummary: PermissionService.summary(),
                    statusText: state.statusText
                )
            }
        case let .failure(error):
            windowController.appendLog("ZeroTier 准备失败：\(error.localizedDescription)")
            updateState { state in
                ServerDisplayState(
                    isRunning: state.isRunning,
                    port: state.port,
                    inviteCode: state.inviteCode,
                    localURLs: state.localURLs,
                    zeroTierURLs: state.zeroTierURLs,
                    zeroTierStatus: "ZeroTier 准备失败：\(error.localizedDescription)",
                    quickTunnelURL: state.quickTunnelURL,
                    quickTunnelStatus: state.quickTunnelStatus,
                    quickTunnelConnectionState: state.quickTunnelConnectionState,
                    publicDirectURL: state.publicDirectURL,
                    relayURL: state.relayURL,
                    permissionSummary: PermissionService.summary(),
                    statusText: state.statusText
                )
            }
        }
    }

    private func startQuickTunnelMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            self?.refreshQuickTunnelState()
        }
        quickTunnelTimer = timer
        timer.resume()
    }

    private func refreshQuickTunnelState() {
        let quickTunnelURL = quickTunnelService.publicURL(inviteCode: currentState.inviteCode)
        let quickTunnelStatus = quickTunnelService.status(inviteCode: currentState.inviteCode)
        let quickTunnelConnectionState = quickTunnelService.connectionState()
        guard quickTunnelURL != currentState.quickTunnelURL
                || quickTunnelStatus != currentState.quickTunnelStatus
                || quickTunnelConnectionState != currentState.quickTunnelConnectionState else {
            return
        }
        updateState { state in
            ServerDisplayState(
                isRunning: state.isRunning,
                port: state.port,
                inviteCode: state.inviteCode,
                localURLs: state.localURLs,
                zeroTierURLs: state.zeroTierURLs,
                zeroTierStatus: state.zeroTierStatus,
                quickTunnelURL: quickTunnelURL,
                quickTunnelStatus: quickTunnelStatus,
                quickTunnelConnectionState: quickTunnelConnectionState,
                publicDirectURL: state.publicDirectURL,
                relayURL: state.relayURL,
                permissionSummary: PermissionService.summary(),
                statusText: state.statusText
            )
        }
    }

    private func showAuthorizationAlert(for request: RemoteAccessRequest) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "远程访问请求"
        alert.informativeText = """
        名称：\(request.displayName)
        请求：\(request.requestedMode.title)
        来源：\(request.remoteAddress)
        入口：\(request.entryHost)
        """
        alert.addButton(withTitle: "允许控制")
        alert.addButton(withTitle: "仅允许观看")
        alert.addButton(withTitle: "拒绝")
        let result = alert.runModal()
        let authorization: RemoteAuthorization
        switch result {
        case .alertFirstButtonReturn:
            authorization = .controlling
        case .alertSecondButtonReturn:
            authorization = .viewing
        default:
            authorization = .denied
        };server?.resolve(sessionID: request.sessionID, authorization: authorization)
    }

    private func requestAuthorization(for request: RemoteAccessRequest, completion: @escaping (RemoteAuthorization) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "公网远程访问请求"
        alert.informativeText = """
        名称：\(request.displayName)
        请求：\(request.requestedMode.title)
        来源：\(request.remoteAddress)
        入口：\(request.entryHost)
        """
        alert.addButton(withTitle: "允许控制")
        alert.addButton(withTitle: "仅允许观看")
        alert.addButton(withTitle: "拒绝")
        let result = alert.runModal()
        switch result {
        case .alertFirstButtonReturn:
            completion(.controlling)
        case .alertSecondButtonReturn:
            completion(.viewing)
        default:
            completion(.denied)
        }
    }

    private func showMessage(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    private static func makeInviteCode() -> String {
        let source = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in source.randomElement() })
    }

    private static func firstLineURL(from text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        return firstLine.hasPrefix("http://") || firstLine.hasPrefix("https://") ? firstLine : text
    }

    private static let zeroTierDefaultStatus = "高级备用：双方加入同一 ZeroTier 网络后，用这里的虚拟 IP 链接访问。"
    private static let quickTunnelDefaultStatus = "免安装公网通道准备中：首次运行需要下载 cloudflared，生成后这里显示公网链接。"

    private static func urls(addresses: [String], port: UInt16, inviteCode: String) -> [String] {
        guard !inviteCode.isEmpty else {
            return []
        };return addresses.map { "http://\($0):\(port)/?invite=\(inviteCode)" }
    }

    private static func zeroTierStatus(addresses: [String], isRunning: Bool) -> String {
        guard !addresses.isEmpty else {
            return zeroTierDefaultStatus
        }
        let suffix = isRunning ? "可复制下方 ZeroTier 地址给同网络朋友。" : "开启服务后会生成 ZeroTier 地址。"
        return "ZeroTier 已发现虚拟 IP：\(addresses.joined(separator: ", "))；\(suffix)"
    }
}

extension AppDelegate: MainWindowControllerDelegate {
    func mainWindowControllerDidTapStart(_ controller: MainWindowController, port: UInt16, relayBaseURL: String, zeroTierNetworkID: String) {
        startServer(port: port, relayBaseURL: relayBaseURL, zeroTierNetworkID: zeroTierNetworkID)
    }

    func mainWindowControllerDidTapStop(_ controller: MainWindowController) {
        stopServer()
    }

    func mainWindowControllerDidTapMapPort(_ controller: MainWindowController) {
        mapPortAutomatically()
    }

    func mainWindowControllerDidTapPrepareZeroTier(_ controller: MainWindowController, networkID: String) {
        prepareZeroTierIfNeeded(networkID: networkID)
    }

    func mainWindowControllerDidTapRequestPermissions(_ controller: MainWindowController) {
        PermissionService.requestPermissions()
        updateState { state in
            ServerDisplayState(
                isRunning: state.isRunning,
                port: state.port,
                inviteCode: state.inviteCode,
                localURLs: state.localURLs,
                zeroTierURLs: state.zeroTierURLs,
                zeroTierStatus: state.zeroTierStatus,
                quickTunnelURL: state.quickTunnelURL,
                quickTunnelStatus: state.quickTunnelStatus,
                quickTunnelConnectionState: state.quickTunnelConnectionState,
                publicDirectURL: state.publicDirectURL,
                relayURL: state.relayURL,
                permissionSummary: PermissionService.summary(),
                statusText: state.statusText
            )
        }
        windowController.appendLog("已请求系统权限，请在系统设置里允许屏幕录制和辅助功能")
    }
}

extension AppDelegate: RemoteHostServerDelegate {
    func remoteHostServer(_ server: RemoteHostServer, didReceive request: RemoteAccessRequest) {
        windowController.appendLog("收到授权请求：\(request.displayName)，\(request.requestedMode.title)，来自 \(request.remoteAddress)")
        showAuthorizationAlert(for: request)
    }

    func remoteHostServer(_ server: RemoteHostServer, didLog message: String) {
        windowController.appendLog(message)
    }
}

extension AppDelegate: RelayTunnelClientDelegate {
    func relayTunnelClient(_ client: RelayTunnelClient, didReceive request: RemoteAccessRequest, completion: @escaping (RemoteAuthorization) -> Void) {
        windowController.appendLog("收到公网授权请求：\(request.displayName)，\(request.requestedMode.title)，来自 \(request.remoteAddress)")
        requestAuthorization(for: request, completion: completion)
    }

    func relayTunnelClient(_ client: RelayTunnelClient, didLog message: String) {
        windowController.appendLog(message)
    }
}
