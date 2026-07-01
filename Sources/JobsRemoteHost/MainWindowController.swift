//
//  MainWindowController.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import AppKit

protocol MainWindowControllerDelegate: AnyObject {
    func mainWindowControllerDidTapStart(_ controller: MainWindowController, port: UInt16, relayBaseURL: String, zeroTierNetworkID: String)
    func mainWindowControllerDidTapStop(_ controller: MainWindowController)
    func mainWindowControllerDidTapRequestPermissions(_ controller: MainWindowController)
    func mainWindowControllerDidTapMapPort(_ controller: MainWindowController)
    func mainWindowControllerDidTapPrepareZeroTier(_ controller: MainWindowController, networkID: String)
}

final class MainWindowController: NSWindowController {
    weak var actionsDelegate: MainWindowControllerDelegate?

    private let statusLabel = NSTextField(labelWithString: "服务未开启")
    private let permissionLabel = NSTextField(labelWithString: PermissionService.summary())
    private let portField = NSTextField(string: "8088")
    private let localURLField = MainWindowController.makeURLField()
    private let quickTunnelURLField = MainWindowController.makeURLField()
    private let copyTipContainer = NSView()
    private let copyTipLabel = NSTextField(labelWithString: "复制成功")
    private let logView = NSTextView()
    private let startButton = NSButton(title: "开启服务", target: nil, action: nil)
    private let stopButton = NSButton(title: "停止服务", target: nil, action: nil)
    private let alternativeConnectionsButton = NSButton(title: "其他连接方式…", target: nil, action: nil)
    private let permissionButton = NSButton(title: "请求系统权限", target: nil, action: nil)
    private lazy var alternativeConnectionsWindowController: AlternativeConnectionsWindowController = {
        let controller = AlternativeConnectionsWindowController()
        controller.onPrepareZeroTier = { [weak self] networkID in
            guard let self else {
                return
            }
            self.actionsDelegate?.mainWindowControllerDidTapPrepareZeroTier(self, networkID: networkID)
        }
        controller.onMapPort = { [weak self] in
            guard let self else {
                return
            }
            self.actionsDelegate?.mainWindowControllerDidTapMapPort(self)
        }
        controller.onCopied = { [weak self] title in
            self?.showCopyTip("\(title)已复制")
        };return controller
    }()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "JobsRemoteHost"
        window.center()
        self.init(window: window)
        setupUI()
    }

    func apply(state: ServerDisplayState) {
        statusLabel.stringValue = state.statusText
        permissionLabel.stringValue = state.permissionSummary
        localURLField.apply(
            displayText: state.localURLs.isEmpty ? "未发现内网 IPv4 地址" : state.localURLs.joined(separator: "\n"),
            copyValue: state.localURLs.first ?? "",
            title: "内网地址"
        )
        quickTunnelURLField.apply(
            displayText: state.quickTunnelURL.isEmpty ? state.quickTunnelStatus : state.quickTunnelURL,
            copyValue: state.quickTunnelURL,
            title: "免安装公网链接"
        )
        alternativeConnectionsButton.isHidden = state.quickTunnelConnectionState != .failed
        alternativeConnectionsWindowController.apply(state: state)
        if state.quickTunnelConnectionState != .failed {
            alternativeConnectionsWindowController.close()
        }
        portField.stringValue = "\(state.port)"
        startButton.isEnabled = !state.isRunning
        stopButton.isEnabled = state.isRunning
    }

    func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        logView.string.append(line)
        logView.scrollToEndOfDocument(nil)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }
        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.distribution = .fill
        rootStack.spacing = 14
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])
        setupCopyTip(in: contentView)

        let controlPanel = controlBlock()
        let urlPanel = urlBlock()
        let logPanel = logBlock()
        rootStack.addArrangedSubview(titleBlock())
        rootStack.addArrangedSubview(controlPanel)
        rootStack.addArrangedSubview(urlPanel)
        rootStack.addArrangedSubview(logPanel)
        NSLayoutConstraint.activate([
            controlPanel.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            urlPanel.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            logPanel.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
        configureActions()
        apply(
            state: ServerDisplayState(
                isRunning: false,
                port: 8088,
                inviteCode: "",
                localURLs: [],
                zeroTierURLs: [],
                zeroTierStatus: "高级备用：双方加入同一 ZeroTier 网络后，用这里的虚拟 IP 链接访问。",
                quickTunnelURL: "",
                quickTunnelStatus: "免安装公网通道准备中：首次运行需要下载 cloudflared，生成后这里显示公网链接。",
                quickTunnelConnectionState: .preparing,
                publicDirectURL: "服务开启后生成",
                relayURL: "未配置公网会话服务：先启动 relay server，并在上方填写 http://公网IP:8787",
                permissionSummary: PermissionService.summary(),
                statusText: "服务未开启"
            )
        )
    }

    private func titleBlock() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        let title = NSTextField(labelWithString: "JobsRemoteHost")
        title.font = .boldSystemFont(ofSize: 28)
        let desc = NSTextField(labelWithString: "推荐用免安装公网链接：朋友只用浏览器访问，本机先弹授权窗口。")
        desc.textColor = .secondaryLabelColor
        desc.maximumNumberOfLines = 2
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(desc)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(permissionLabel)
        return stack
    }

    private func controlBlock() -> NSView {
        let portLabel = NSTextField(labelWithString: "监听端口")
        portLabel.setContentHuggingPriority(.required, for: .horizontal)
        portField.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let buttons = NSStackView(views: [startButton, stopButton, permissionButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            startButton.widthAnchor.constraint(equalTo: permissionButton.widthAnchor),
            stopButton.widthAnchor.constraint(equalTo: permissionButton.widthAnchor)
        ])
        stopButton.isEnabled = false
        let stack = NSStackView(views: [portLabel, portField, NSView(), buttons])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return boxed(stack, hugsHeight: true)
    }

    private func urlBlock() -> NSView {
        let localTitle = NSTextField(labelWithString: "内网地址")
        let quickTunnelTitle = NSTextField(labelWithString: "免安装公网链接（推荐）")
        [localTitle, quickTunnelTitle].forEach { label in
            label.alignment = .right
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        [localURLField, quickTunnelURLField].forEach { field in
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let localRow = NSStackView(views: [localTitle, localURLField])
        localRow.orientation = .horizontal
        localRow.alignment = .firstBaseline
        localRow.spacing = 12
        let quickTunnelRow = NSStackView(views: [quickTunnelTitle, quickTunnelURLField])
        quickTunnelRow.orientation = .horizontal
        quickTunnelRow.alignment = .firstBaseline
        quickTunnelRow.spacing = 12
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.addArrangedSubview(localRow)
        stack.addArrangedSubview(quickTunnelRow)
        let alternatives = NSStackView(views: [alternativeConnectionsButton, NSView()])
        alternatives.orientation = .horizontal
        alternatives.spacing = 8
        alternativeConnectionsButton.isHidden = true
        alternativeConnectionsButton.toolTip = "免安装公网通道失败后，查看 ZeroTier、自建中继和路由器直连。"
        stack.addArrangedSubview(alternatives)
        NSLayoutConstraint.activate([
            localTitle.widthAnchor.constraint(equalTo: quickTunnelTitle.widthAnchor),
            localRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            quickTunnelRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            alternatives.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return boxed(stack, hugsHeight: true)
    }

    private func logBlock() -> NSView {
        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let menu = NSMenu()
        menu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let clearItem = NSMenuItem(title: "清除日志", action: #selector(clearLog), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        logView.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = logView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return scroll
    }

    private func boxed(_ view: NSView, hugsHeight: Bool = false) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        if hugsHeight {
            container.setContentHuggingPriority(.required, for: .vertical)
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
    }

    private func configureActions() {
        startButton.target = self
        startButton.action = #selector(startTapped)
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        alternativeConnectionsButton.target = self
        alternativeConnectionsButton.action = #selector(alternativeConnectionsTapped)
        permissionButton.target = self
        permissionButton.action = #selector(permissionTapped)
        [localURLField, quickTunnelURLField].forEach { field in
            field.onCopied = { [weak self] title in
                self?.showCopyTip("\(title)已复制")
            }
        }
    }

    @objc private func startTapped() {
        let port = UInt16(portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8088
        actionsDelegate?.mainWindowControllerDidTapStart(
            self,
            port: port,
            relayBaseURL: alternativeConnectionsWindowController.relayBaseURL,
            zeroTierNetworkID: alternativeConnectionsWindowController.zeroTierNetworkID
        )
    }

    @objc private func stopTapped() {
        actionsDelegate?.mainWindowControllerDidTapStop(self)
    }

    @objc private func alternativeConnectionsTapped() {
        alternativeConnectionsWindowController.present()
    }

    @objc private func permissionTapped() {
        actionsDelegate?.mainWindowControllerDidTapRequestPermissions(self)
    }

    @objc private func clearLog() {
        logView.string = ""
    }

    private func setupCopyTip(in contentView: NSView) {
        copyTipContainer.isHidden = true
        copyTipContainer.wantsLayer = true
        copyTipContainer.layer?.cornerRadius = 8
        copyTipContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        copyTipContainer.layer?.zPosition = 1000
        copyTipContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(copyTipContainer)

        copyTipLabel.alignment = .center
        copyTipLabel.textColor = .white
        copyTipLabel.font = .boldSystemFont(ofSize: 13)
        copyTipLabel.translatesAutoresizingMaskIntoConstraints = false
        copyTipContainer.addSubview(copyTipLabel)
        NSLayoutConstraint.activate([
            copyTipContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            copyTipContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            copyTipContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            copyTipContainer.heightAnchor.constraint(equalToConstant: 44),
            copyTipLabel.leadingAnchor.constraint(equalTo: copyTipContainer.leadingAnchor, constant: 20),
            copyTipLabel.trailingAnchor.constraint(equalTo: copyTipContainer.trailingAnchor, constant: -20),
            copyTipLabel.centerYAnchor.constraint(equalTo: copyTipContainer.centerYAnchor)
        ])
    }

    private func showCopyTip(_ message: String) {
        copyTipLabel.stringValue = message
        copyTipContainer.alphaValue = 1
        copyTipContainer.isHidden = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideCopyTip), object: nil)
        perform(#selector(hideCopyTip), with: nil, afterDelay: 1.2)
    }

    @objc private func hideCopyTip() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            copyTipContainer.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.copyTipContainer.isHidden = true
        }
    }

    private static func makeURLField() -> CopyableURLField {
        CopyableURLField()
    }

}
