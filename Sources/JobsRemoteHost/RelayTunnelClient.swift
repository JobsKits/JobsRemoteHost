//
//  RelayTunnelClient.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import Foundation

protocol RelayTunnelClientDelegate: AnyObject {
    func relayTunnelClient(_ client: RelayTunnelClient, didReceive request: RemoteAccessRequest, completion: @escaping (RemoteAuthorization) -> Void)
    func relayTunnelClient(_ client: RelayTunnelClient, didLog message: String)
}

final class RelayTunnelClient {
    weak var delegate: RelayTunnelClientDelegate?

    private let baseURL: String
    private let inviteCode: String
    private let captureService: ScreenCaptureService
    private let inputController: InputController
    private let queue = DispatchQueue(label: "com.jobs.remotehost.relay")
    private var webSocketTask: URLSessionWebSocketTask?
    private var frameTimer: DispatchSourceTimer?
    private var authorizations = [String: RemoteAuthorization]()
    private var isRunning = false

    init(baseURL: String, inviteCode: String, captureService: ScreenCaptureService, inputController: InputController) {
        self.baseURL = baseURL
        self.inviteCode = inviteCode
        self.captureService = captureService
        self.inputController = inputController
    }

    func start() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard self.webSocketTask == nil else {
                return
            }
            guard let url = self.webSocketURL() else {
                self.log("公网会话连接失败：Base URL 无效")
                return
            }
            let task = URLSession.shared.webSocketTask(with: url)
            self.webSocketTask = task
            self.isRunning = true
            task.resume()
            self.log("公网会话通道连接中：\(url.absoluteString)")
            self.sendJSON([
                "type": "host:hello",
                "session": self.inviteCode,
                "capabilities": ["view", "control", "jpegRelay"]
            ])
            self.receiveLoop()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.isRunning = false
            self.frameTimer?.cancel()
            self.frameTimer = nil
            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.webSocketTask = nil
            self.authorizations.removeAll()
            self.log("公网会话通道已停止")
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else {
                return
            }
            self.queue.async {
                guard self.isRunning else {
                    return
                }
                switch result {
                case let .success(message):
                    self.handle(message: message)
                    self.receiveLoop()
                case let .failure(error):
                    self.log("公网会话通道断开：\(error.localizedDescription)")
                    self.webSocketTask = nil
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let text: String?
        switch message {
        case let .string(value):
            text = value
        case let .data(data):
            text = String(data: data, encoding: .utf8)
        @unknown default:
            text = nil
        }
        guard let text,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        switch type {
        case "relay:ready":
            log("公网会话通道已连接")
        case "viewer:request":
            handleViewerRequest(json)
        case "viewer:disconnect":
            handleViewerDisconnect(json)
        case "control":
            handleControl(json)
        default:
            break
        }
    }

    private func handleViewerRequest(_ json: [String: Any]) {
        guard let viewerID = json["viewerID"] as? String else {
            return
        }
        let mode = RemoteAccessMode(rawValue: (json["mode"] as? String) ?? "") ?? .view
        let displayName = ((json["displayName"] as? String) ?? "公网访客").trimmingCharacters(in: .whitespacesAndNewlines)
        let request = RemoteAccessRequest(
            sessionID: viewerID,
            displayName: displayName.isEmpty ? "公网访客" : displayName,
            requestedMode: mode,
            remoteAddress: (json["remoteAddress"] as? String) ?? "relay",
            entryHost: (json["entryHost"] as? String) ?? RelaySessionService().sessionLink(baseURL: baseURL, inviteCode: inviteCode),
            createdAt: Date()
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.relayTunnelClient(self, didReceive: request) { [weak self] authorization in
                self?.queue.async {
                    self?.resolve(viewerID: viewerID, authorization: authorization)
                }
            }
        }
    }

    private func resolve(viewerID: String, authorization: RemoteAuthorization) {
        authorizations[viewerID] = authorization
        sendJSON([
            "type": "auth",
            "viewerID": viewerID,
            "authorization": authorization.rawValue,
            "title": authorization.title
        ])
        log("公网访客 \(viewerID) 已更新为：\(authorization.title)")
        if authorization.allowsFrame {
            startFrameTimerIfNeeded()
        }
    }

    private func handleViewerDisconnect(_ json: [String: Any]) {
        guard let viewerID = json["viewerID"] as? String else {
            return
        }
        authorizations.removeValue(forKey: viewerID)
        stopFrameTimerIfIdle()
        log("公网访客已断开：\(viewerID)")
    }

    private func handleControl(_ json: [String: Any]) {
        guard let viewerID = json["viewerID"] as? String,
              authorizations[viewerID]?.allowsControl == true,
              let payload = json["payload"] as? [String: Any] else {
            return
        }
        _ = inputController.handle(json: payload, captureRect: captureService.captureRect())
    }

    private func startFrameTimerIfNeeded() {
        guard frameTimer == nil else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(260), leeway: .milliseconds(80))
        timer.setEventHandler { [weak self] in
            self?.sendFrameIfNeeded()
        }
        frameTimer = timer
        timer.resume()
    }

    private func stopFrameTimerIfIdle() {
        guard !authorizations.values.contains(where: { $0.allowsFrame }) else {
            return
        }
        frameTimer?.cancel()
        frameTimer = nil
    }

    private func sendFrameIfNeeded() {
        guard authorizations.values.contains(where: { $0.allowsFrame }),
              let jpeg = captureService.captureJPEG(maxPixelWidth: 1400, compression: 0.46) else {
            stopFrameTimerIfIdle()
            return
        }
        sendJSON([
            "type": "frame",
            "mime": "image/jpeg",
            "data": jpeg.base64EncodedString()
        ])
    }

    private func sendJSON(_ json: [String: Any]) {
        guard let webSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: json, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        webSocketTask.send(.string(text)) { [weak self] error in
            guard let error else {
                return
            }
            self?.log("公网会话发送失败：\(error.localizedDescription)")
        }
    }

    private func webSocketURL() -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              let base = URL(string: trimmed),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = (components.scheme == "https") ? "wss" : "ws"
        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = (prefix.isEmpty ? "" : "/\(prefix)") + "/ws"
        components.queryItems = [
            URLQueryItem(name: "role", value: "host"),
            URLQueryItem(name: "session", value: inviteCode)
        ]
        return components.url
    }

    private func log(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.relayTunnelClient(self, didLog: message)
        }
    }
}
