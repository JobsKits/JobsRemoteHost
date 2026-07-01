//
//  Models.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import Foundation

enum RemoteAccessMode: String {
    case view
    case control

    var title: String {
        switch self {
        case .view:
            return "仅观看"
        case .control:
            return "观看并控制"
        }
    }
}

enum RemoteAuthorization: String {
    case pending
    case viewing
    case controlling
    case denied

    var allowsFrame: Bool {
        self == .viewing || self == .controlling
    }

    var allowsControl: Bool {
        self == .controlling
    }

    var title: String {
        switch self {
        case .pending:
            return "等待授权"
        case .viewing:
            return "已允许观看"
        case .controlling:
            return "已允许控制"
        case .denied:
            return "已拒绝"
        }
    }
}

enum QuickTunnelConnectionState: Equatable {
    case preparing
    case ready
    case failed
}

struct RemoteAccessRequest {
    let sessionID: String
    let displayName: String
    let requestedMode: RemoteAccessMode
    let remoteAddress: String
    let entryHost: String
    let createdAt: Date
}

struct ServerDisplayState {
    let isRunning: Bool
    let port: UInt16
    let inviteCode: String
    let localURLs: [String]
    let zeroTierURLs: [String]
    let zeroTierStatus: String
    let quickTunnelURL: String
    let quickTunnelStatus: String
    let quickTunnelConnectionState: QuickTunnelConnectionState
    let publicDirectURL: String
    let relayURL: String
    let permissionSummary: String
    let statusText: String
}

final class RemoteClientSession {
    let id: String
    let displayName: String
    let requestedMode: RemoteAccessMode
    let remoteAddress: String
    let entryHost: String
    let createdAt: Date
    var authorization: RemoteAuthorization
    var lastSeenAt: Date

    init(request: RemoteAccessRequest) {
        self.id = request.sessionID
        self.displayName = request.displayName
        self.requestedMode = request.requestedMode
        self.remoteAddress = request.remoteAddress
        self.entryHost = request.entryHost
        self.createdAt = request.createdAt
        self.authorization = .pending
        self.lastSeenAt = request.createdAt
    }
}
