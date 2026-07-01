//
//  PermissionService.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import ApplicationServices
import CoreGraphics
import Foundation

enum PermissionService {
    static func summary() -> String {
        let screen = CGPreflightScreenCaptureAccess() ? "屏幕录制：已授权" : "屏幕录制：未授权"
        let accessibility = AXIsProcessTrusted() ? "辅助功能：已授权" : "辅助功能：未授权"
        return "\(screen)；\(accessibility)"
    }

    static func requestPermissions() {
        _ = CGRequestScreenCaptureAccess()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
