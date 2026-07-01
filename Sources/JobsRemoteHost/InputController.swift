//
//  InputController.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import ApplicationServices
import Foundation

final class InputController {
    private let source = CGEventSource(stateID: .hidSystemState)

    func handle(json: [String: Any], captureRect: CGRect) -> Bool {
        guard AXIsProcessTrusted(),
              let type = json["type"] as? String else {
            return false
        }
        switch type {
        case "mouseMove":
            return postMouse(type: .mouseMoved, button: .left, json: json, rect: captureRect)
        case "mouseDown":
            let button = mouseButton(from: json)
            return postMouse(type: downType(for: button), button: button, json: json, rect: captureRect)
        case "mouseUp":
            let button = mouseButton(from: json)
            return postMouse(type: upType(for: button), button: button, json: json, rect: captureRect)
        case "wheel":
            return postWheel(json: json)
        case "keyDown":
            return postKey(json: json, isDown: true)
        case "keyUp":
            return postKey(json: json, isDown: false)
        default:
            return false
        }
    }

    private func point(from json: [String: Any], rect: CGRect) -> CGPoint? {
        guard let nx = json["nx"] as? Double,
              let ny = json["ny"] as? Double else {
            return nil
        };return CGPoint(
            x: rect.minX + rect.width * CGFloat(max(0, min(1, nx))),
            y: rect.minY + rect.height * CGFloat(max(0, min(1, ny)))
        )
    }

    private func postMouse(type: CGEventType, button: CGMouseButton, json: [String: Any], rect: CGRect) -> Bool {
        guard let point = point(from: json, rect: rect),
              let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func postWheel(json: [String: Any]) -> Bool {
        let deltaY = Int32(-((json["deltaY"] as? Double) ?? 0))
        let deltaX = Int32(-((json["deltaX"] as? Double) ?? 0))
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func postKey(json: [String: Any], isDown: Bool) -> Bool {
        guard let key = json["key"] as? String,
              let keyCode = keyCode(for: key),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else {
            return false
        }
        event.flags = flags(from: json)
        event.post(tap: .cghidEventTap)
        return true
    }

    private func mouseButton(from json: [String: Any]) -> CGMouseButton {
        let browserButton = (json["button"] as? Int) ?? 0
        switch browserButton {
        case 2:
            return .right
        case 1:
            return .center
        default:
            return .left
        }
    }

    private func downType(for button: CGMouseButton) -> CGEventType {
        switch button {
        case .right:
            return .rightMouseDown
        case .center:
            return .otherMouseDown
        default:
            return .leftMouseDown
        }
    }

    private func upType(for button: CGMouseButton) -> CGEventType {
        switch button {
        case .right:
            return .rightMouseUp
        case .center:
            return .otherMouseUp
        default:
            return .leftMouseUp
        }
    }

    private func flags(from json: [String: Any]) -> CGEventFlags {
        var flags = CGEventFlags()
        if (json["shift"] as? Bool) == true {
            flags.insert(.maskShift)
        }
        if (json["control"] as? Bool) == true {
            flags.insert(.maskControl)
        }
        if (json["option"] as? Bool) == true {
            flags.insert(.maskAlternate)
        }
        if (json["command"] as? Bool) == true {
            flags.insert(.maskCommand)
        };return flags
    }

    private func keyCode(for key: String) -> CGKeyCode? {
        let normalized = key.count == 1 ? key.lowercased() : key
        return [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "Enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
            ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "Tab": 48, " ": 49, "Space": 49, "`": 50,
            "Backspace": 51, "Escape": 53, "Meta": 55, "Shift": 56, "CapsLock": 57, "Alt": 58, "Control": 59,
            "ArrowLeft": 123, "ArrowRight": 124, "ArrowDown": 125, "ArrowUp": 126, "Delete": 117, "Home": 115, "End": 119, "PageUp": 116, "PageDown": 121
        ][normalized]
    }
}
