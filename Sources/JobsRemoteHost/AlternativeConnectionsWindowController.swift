//
//  AlternativeConnectionsWindowController.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年7月1日，星期三.
//

import AppKit

final class AlternativeConnectionsWindowController: NSWindowController {
    var onPrepareZeroTier: ((String) -> Void)?
    var onMapPort: (() -> Void)?
    var onCopied: ((String) -> Void)?

    private let zeroTierField = NSTextField(string: "")
    private let relayField = NSTextField(string: "")
    private let zeroTierURLField = AlternativeConnectionsWindowController.makeURLField()
    private let publicURLField = AlternativeConnectionsWindowController.makeURLField()
    private let relayURLField = AlternativeConnectionsWindowController.makeURLField()
    private let zeroTierButton = NSButton(title: "ZeroTier 一键准备", target: nil, action: nil)
    private let mapPortButton = NSButton(title: "尝试端口映射", target: nil, action: nil)
    private let closeButton = NSButton(title: "关闭", target: nil, action: nil)

    var zeroTierNetworkID: String {
        zeroTierField.stringValue
    }

    var relayBaseURL: String {
        relayField.stringValue
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 650),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "其他连接方式"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    func apply(state: ServerDisplayState) {
        zeroTierURLField.apply(
            displayText: state.zeroTierURLs.isEmpty ? state.zeroTierStatus : state.zeroTierURLs.joined(separator: "\n"),
            copyValue: state.zeroTierURLs.first ?? "",
            title: "ZeroTier 地址"
        )
        publicURLField.apply(
            displayText: state.publicDirectURL,
            copyValue: Self.firstURL(in: state.publicDirectURL),
            title: "外网直连地址"
        )
        relayURLField.apply(
            displayText: state.relayURL,
            copyValue: Self.firstURL(in: state.relayURL),
            title: "公网会话链接"
        )
        mapPortButton.isEnabled = state.isRunning
    }

    func present() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }
        zeroTierField.placeholderString = "填写 16 位 ZeroTier Network ID"
        zeroTierField.setAccessibilityLabel("ZeroTier Network ID")
        relayField.placeholderString = "例如：http://公网IP:8787 或 https://你的域名"
        relayField.setAccessibilityLabel("公网会话服务 Base URL")

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])

        let intro = Self.explanationLabel(
            "免安装公网通道当前不可用。下面三种方式任选一种即可，不需要全部配置；优先从 ZeroTier 开始。"
        )
        intro.font = .boldSystemFont(ofSize: 13)
        intro.textColor = .labelColor
        let zeroTierView = zeroTierBlock()
        let relayView = relayBlock()
        let directView = directBlock()
        rootStack.addArrangedSubview(intro)
        rootStack.addArrangedSubview(zeroTierView)
        rootStack.addArrangedSubview(relayView)
        rootStack.addArrangedSubview(directView)
        NSLayoutConstraint.activate([
            intro.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -36),
            zeroTierView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -36),
            relayView.widthAnchor.constraint(equalTo: zeroTierView.widthAnchor),
            directView.widthAnchor.constraint(equalTo: zeroTierView.widthAnchor)
        ])

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.addArrangedSubview(NSView())
        footer.addArrangedSubview(closeButton)
        rootStack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: zeroTierView.widthAnchor).isActive = true
        configureActions()
    }

    private func zeroTierBlock() -> NSView {
        let stack = methodStack(
            title: "1. ZeroTier 专网（优先备用）",
            lines: [
                "适合：双方可以安装 ZeroTier，希望获得稳定、固定的私有连接。",
                "需要：双方加入并授权到同一个 Network ID；不要求公网 IP，也不需要改路由器。",
                "操作：填写 Network ID → 点“一键准备” → 开启服务 → 复制下方 ZeroTier 地址。"
            ]
        )
        let controls = NSStackView(views: [zeroTierField, zeroTierButton])
        controls.orientation = .horizontal
        controls.spacing = 10
        zeroTierField.widthAnchor.constraint(equalToConstant: 470).isActive = true
        stack.addArrangedSubview(controls)
        stack.addArrangedSubview(zeroTierURLField)
        controls.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        zeroTierURLField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return boxed(stack)
    }

    private func relayBlock() -> NSView {
        let stack = methodStack(
            title: "2. 自建公网中继（有服务器时）",
            lines: [
                "适合：你已有公网服务器或域名，希望使用固定入口，不依赖临时公网链接。",
                "需要：先在公网机器启动项目内置 relay server；这里填的是中继地址，不是本机 8088。",
                "操作：填写 Base URL → 回主窗口重新开启服务 → 复制下方公网会话链接。"
            ]
        )
        stack.addArrangedSubview(relayField)
        stack.addArrangedSubview(relayURLField)
        relayField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        relayURLField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return boxed(stack)
    }

    private func directBlock() -> NSView {
        let stack = methodStack(
            title: "3. 路由器直连（实验性，最后再试）",
            lines: [
                "适合：确认有独立公网 IPv4，并且路由器支持 UPnP 或 NAT-PMP。",
                "限制：运营商共享公网 IP（CGNAT）通常无法使用；直连会把服务端口暴露到公网。",
                "操作：先开启服务 → 点“尝试端口映射” → 用手机流量验证下方外网直连地址。"
            ]
        )
        let controls = NSStackView(views: [mapPortButton, NSView()])
        controls.orientation = .horizontal
        controls.spacing = 10
        stack.addArrangedSubview(controls)
        stack.addArrangedSubview(publicURLField)
        controls.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        publicURLField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return boxed(stack)
    }

    private func methodStack(title: String, lines: [String]) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.alignment = .left
        stack.addArrangedSubview(titleLabel)
        titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        lines.forEach { line in
            let label = Self.explanationLabel(line)
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        };return stack
    }

    private func boxed(_ view: NSView) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        return container
    }

    private func configureActions() {
        zeroTierButton.target = self
        zeroTierButton.action = #selector(zeroTierTapped)
        mapPortButton.target = self
        mapPortButton.action = #selector(mapPortTapped)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        [zeroTierURLField, publicURLField, relayURLField].forEach { field in
            field.onCopied = { [weak self] title in
                self?.onCopied?(title)
            }
        }
    }

    @objc private func zeroTierTapped() {
        onPrepareZeroTier?(zeroTierField.stringValue)
    }

    @objc private func mapPortTapped() {
        onMapPort?()
    }

    @objc private func closeTapped() {
        close()
    }

    private static func explanationLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 12)
        label.maximumNumberOfLines = 0
        label.alignment = .left
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private static func makeURLField() -> CopyableURLField {
        CopyableURLField()
    }

    private static func firstURL(in text: String) -> String {
        let pattern = #"https?://[^\s　（()]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return text.hasPrefix("http://") || text.hasPrefix("https://") ? text : ""
        };return String(text[range])
    }
}
