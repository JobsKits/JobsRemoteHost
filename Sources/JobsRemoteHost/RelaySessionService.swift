//
//  RelaySessionService.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import Foundation

final class RelaySessionService {
    func sessionLink(baseURL: String, inviteCode: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else {
            return "未配置公网会话服务：先启动 relay server，并在上方填写 http://公网IP:8787"
        };return "\(trimmed)/s/\(inviteCode)"
    }

    func registerHost(baseURL: String, inviteCode: String, localURLs: [String], publicDirectURL: String, completion: @escaping (String) -> Void) {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/api/hosts/register") else {
            completion(sessionLink(baseURL: baseURL, inviteCode: inviteCode))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        let payload: [String: Any] = [
            "inviteCode": inviteCode,
            "localURLs": localURLs,
            "publicDirectURL": publicDirectURL,
            "capabilities": ["view", "control", "hostAuthorization"]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any],
                  let link = dictionary["sessionURL"] as? String,
                  !link.isEmpty else {
                completion(self.sessionLink(baseURL: baseURL, inviteCode: inviteCode))
                return
            }
            completion(link)
        }.resume()
    }
}
