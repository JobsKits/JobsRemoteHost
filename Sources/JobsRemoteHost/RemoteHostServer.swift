//
//  RemoteHostServer.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import Foundation
import Network

protocol RemoteHostServerDelegate: AnyObject {
    func remoteHostServer(_ server: RemoteHostServer, didReceive request: RemoteAccessRequest)
    func remoteHostServer(_ server: RemoteHostServer, didLog message: String)
}

final class RemoteHostServer {
    weak var delegate: RemoteHostServerDelegate?

    let port: UInt16
    let inviteCode: String

    private let captureService: ScreenCaptureService
    private let inputController: InputController
    private let queue = DispatchQueue(label: "com.jobs.remotehost.http")
    private var listener: NWListener?
    private var sessions = [String: RemoteClientSession]()

    init(port: UInt16, inviteCode: String, captureService: ScreenCaptureService, inputController: InputController) {
        self.port = port
        self.inviteCode = inviteCode
        self.captureService = captureService
        self.inputController = inputController
    }

    func start() throws {
        guard listener == nil else {
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw RemoteHostServerError.invalidPort
        }
        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.log("HTTP 服务状态：\(state)")
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [weak self] in
            self?.sessions.removeAll()
        }
    }

    func resolve(sessionID: String, authorization: RemoteAuthorization) {
        queue.async { [weak self] in
            guard let self,
                  let session = self.sessions[sessionID] else {
                return
            }
            session.authorization = authorization
            session.lastSeenAt = Date()
            self.log("会话 \(session.displayName) 已更新为：\(authorization.title)")
        }
    }

    func activeSessionsSnapshot(completion: @escaping ([RemoteClientSession]) -> Void) {
        queue.async { [weak self] in
            completion(self?.sessions.values.sorted(by: { $0.createdAt < $1.createdAt }) ?? [])
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }
            if nextBuffer.count > 1024 * 1024 {
                self.send(HTTPResponse.json(["ok": false, "message": "请求过大"], status: 413), on: connection)
                return
            }
            if let length = HTTPParser.completeRequestLength(in: nextBuffer) {
                let requestData = nextBuffer.prefix(length)
                guard let request = HTTPParser.parse(Data(requestData), remoteAddress: connection.endpoint.readableAddress) else {
                    self.send(HTTPResponse.json(["ok": false, "message": "请求无法解析"], status: 400), on: connection)
                    return
                }
                self.route(request, on: connection)
                return
            }
            guard error == nil, !isComplete else {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        switch (request.method, request.path) {
        case ("GET", "/"):
            send(HTTPResponse.html(ViewerPage.html(inviteCode: inviteCode)), on: connection)
        case ("GET", "/api/info"):
            sendInfo(on: connection)
        case ("POST", "/api/request"):
            handleAccessRequest(request, on: connection)
        case ("GET", "/api/status"):
            handleStatus(request, on: connection)
        case ("GET", "/api/frame"):
            handleFrame(request, on: connection)
        case ("POST", "/api/control"):
            handleControl(request, on: connection)
        default:
            send(HTTPResponse.json(["ok": false, "message": "没有这个接口"], status: 404), on: connection)
        }
    }

    private func sendInfo(on connection: NWConnection) {
        send(
            HTTPResponse.json([
                "ok": true,
                "service": "JobsRemoteHost",
                "inviteCode": inviteCode,
                "permissions": PermissionService.summary()
            ]),
            on: connection
        )
    }

    private func handleAccessRequest(_ request: HTTPRequest, on connection: NWConnection) {
        let json = request.jsonObject
        guard (json["invite"] as? String) == inviteCode else {
            send(HTTPResponse.json(["ok": false, "message": "验证码不正确"], status: 403), on: connection)
            return
        }
        let requestedMode = RemoteAccessMode(rawValue: (json["mode"] as? String) ?? "") ?? .view
        let displayName = ((json["displayName"] as? String) ?? "浏览器访客").trimmingCharacters(in: .whitespacesAndNewlines)
        let entryHost = ((json["entryHost"] as? String) ?? request.hostHeader).trimmingCharacters(in: .whitespacesAndNewlines)
        let accessRequest = RemoteAccessRequest(
            sessionID: UUID().uuidString,
            displayName: displayName.isEmpty ? "浏览器访客" : displayName,
            requestedMode: requestedMode,
            remoteAddress: request.remoteAddress,
            entryHost: entryHost,
            createdAt: Date()
        )
        sessions[accessRequest.sessionID] = RemoteClientSession(request: accessRequest)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.remoteHostServer(self, didReceive: accessRequest)
        }
        log("收到访问请求：\(accessRequest.displayName)，\(accessRequest.requestedMode.title)，来自 \(accessRequest.remoteAddress)")
        send(
            HTTPResponse.json([
                "ok": true,
                "sessionID": accessRequest.sessionID,
                "authorization": RemoteAuthorization.pending.rawValue
            ], status: 202),
            on: connection
        )
    }

    private func handleStatus(_ request: HTTPRequest, on connection: NWConnection) {
        guard let sessionID = request.query["session"],
              let session = sessions[sessionID] else {
            send(HTTPResponse.json(["ok": false, "authorization": RemoteAuthorization.denied.rawValue], status: 404), on: connection)
            return
        }
        session.lastSeenAt = Date()
        send(
            HTTPResponse.json([
                "ok": true,
                "authorization": session.authorization.rawValue,
                "title": session.authorization.title
            ]),
            on: connection
        )
    }

    private func handleFrame(_ request: HTTPRequest, on connection: NWConnection) {
        guard let sessionID = request.query["session"],
              let session = sessions[sessionID],
              session.authorization.allowsFrame else {
            send(HTTPResponse.json(["ok": false, "message": "未授权观看"], status: 403), on: connection)
            return
        }
        session.lastSeenAt = Date()
        guard let jpeg = captureService.captureJPEG() else {
            send(HTTPResponse.json(["ok": false, "message": "屏幕采集失败，请检查屏幕录制权限"], status: 503), on: connection)
            return
        }
        send(
            HTTPResponse.data(
                status: 200,
                headers: [
                    "Content-Type": "image/jpeg",
                    "Cache-Control": "no-store"
                ],
                body: jpeg
            ),
            on: connection
        )
    }

    private func handleControl(_ request: HTTPRequest, on connection: NWConnection) {
        let json = request.jsonObject
        guard let sessionID = json["session"] as? String,
              let session = sessions[sessionID],
              session.authorization.allowsControl else {
            send(HTTPResponse.json(["ok": false, "message": "未授权控制"], status: 403), on: connection)
            return
        }
        session.lastSeenAt = Date()
        let handled = inputController.handle(json: json, captureRect: captureService.captureRect())
        send(HTTPResponse.json(["ok": handled]), on: connection)
    }

    private func send(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func log(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.remoteHostServer(self, didLog: message)
        }
    }
}

enum RemoteHostServerError: Error {
    case invalidPort
}
