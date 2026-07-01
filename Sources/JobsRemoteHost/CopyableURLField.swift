//
//  CopyableURLField.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import AppKit

final class CopyableURLField: NSTextField {
    var copyValue: String = ""
    var copyTitle: String = "地址"
    var onCopied: ((String) -> Void)?

    convenience init() {
        self.init(labelWithString: "")
        setup()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        copyCurrentValue()
    }

    func apply(displayText: String, copyValue: String, title: String) {
        self.stringValue = displayText
        self.copyValue = copyValue
        self.copyTitle = title
        self.textColor = copyValue.isEmpty ? .secondaryLabelColor : .controlTextColor
        self.toolTip = copyValue.isEmpty ? "暂无可复制地址" : "点击复制\(title)"
    }

    private func setup() {
        isSelectable = false
        maximumNumberOfLines = 3
        lineBreakMode = .byTruncatingMiddle
        alignment = .left
        font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textColor = .controlTextColor
        wantsLayer = true
    }

    private func copyCurrentValue() {
        let value = normalizedCopyValue()
        guard !value.isEmpty else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        onCopied?(copyTitle)
    }

    private func normalizedCopyValue() -> String {
        let value = copyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("http://") || value.hasPrefix("https://") else {
            return ""
        };return value
    }
}
