//
//  HTTPRequest.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import Foundation
import Network

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
    let remoteAddress: String

    var hostHeader: String {
        headers["host"] ?? headers["Host"] ?? "unknown"
    }

    var jsonObject: [String: Any] {
        guard !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body),
              let dictionary = object as? [String: Any] else {
            return [:]
        };return dictionary
    }
}

enum HTTPParser {
    static func completeRequestLength(in data: Data) -> Int? {
        let marker = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: marker) else {
            return nil
        }
        let headerEnd = range.upperBound
        let headerData = data[..<range.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .dropFirst()
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0) }
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                    return nil
                };return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .first ?? 0
        let expectedLength = headerEnd + contentLength
        guard data.count >= expectedLength else {
            return nil
        };return expectedLength
    }

    static func parse(_ data: Data, remoteAddress: String) -> HTTPRequest? {
        let marker = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: marker),
              let headerText = String(data: data[..<range.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map { String($0) }
        guard requestParts.count >= 2 else {
            return nil
        }
        let target = requestParts[1]
        let pathAndQuery = target.split(separator: "?", maxSplits: 1).map { String($0) }
        let path = pathAndQuery.first ?? "/"
        let query = pathAndQuery.count > 1 ? parseQuery(pathAndQuery[1]) : [:]
        var headers = [String: String]()
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0) }
            guard parts.count == 2 else {
                continue
            }
            headers[parts[0].trimmingCharacters(in: .whitespacesAndNewlines)] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let bodyStart = range.upperBound
        let body = data[bodyStart...]
        return HTTPRequest(
            method: requestParts[0].uppercased(),
            path: path,
            query: query,
            headers: headers,
            body: Data(body),
            remoteAddress: remoteAddress
        )
    }

    private static func parseQuery(_ rawQuery: String) -> [String: String] {
        rawQuery
            .split(separator: "&")
            .reduce(into: [String: String]()) { result, pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map { String($0) }
                guard let rawKey = parts.first else {
                    return
                }
                let key = rawKey.removingPercentEncoding ?? rawKey
                let value = parts.count > 1 ? (parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? parts[1]) : ""
                result[key] = value
            }
    }
}

enum HTTPResponse {
    static func data(status: Int, headers: [String: String] = [:], body: Data = Data()) -> Data {
        var responseHeaders = headers
        responseHeaders["Content-Length"] = "\(body.count)"
        responseHeaders["Connection"] = "close"
        responseHeaders["Server"] = "JobsRemoteHost"
        let reason = reasonPhrase(for: status)
        let headerText = "HTTP/1.1 \(status) \(reason)\r\n" + responseHeaders
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\r\n") + "\r\n\r\n"
        var data = Data(headerText.utf8)
        data.append(body)
        return data
    }

    static func html(_ html: String, status: Int = 200) -> Data {
        data(
            status: status,
            headers: [
                "Content-Type": "text/html; charset=utf-8",
                "Cache-Control": "no-store"
            ],
            body: Data(html.utf8)
        )
    }

    static func json(_ dictionary: [String: Any], status: Int = 200) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: dictionary, options: [])) ?? Data("{}".utf8)
        return data(
            status: status,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "Cache-Control": "no-store"
            ],
            body: body
        )
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200:
            return "OK"
        case 202:
            return "Accepted"
        case 400:
            return "Bad Request"
        case 401:
            return "Unauthorized"
        case 403:
            return "Forbidden"
        case 404:
            return "Not Found"
        case 413:
            return "Payload Too Large"
        case 503:
            return "Service Unavailable"
        default:
            return "OK"
        }
    }
}

extension NWEndpoint {
    var readableAddress: String {
        switch self {
        case let .hostPort(host, port):
            return "\(host):\(port.rawValue)"
        default:
            return "\(self)"
        }
    }
}
