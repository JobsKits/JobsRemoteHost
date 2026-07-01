//
//  ScreenCaptureService.swift
//  JobsRemoteHost
//
//  Created by Jobs on 2026年6月30日，星期二.
//

import AppKit
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

final class ScreenCaptureService {
    private let contentQueue = DispatchQueue(label: "com.jobs.remotehost.capture.content")

    func captureRect() -> CGRect {
        let screens = NSScreen.screens
        guard let first = screens.first?.frame else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        };return screens.dropFirst().reduce(first) { result, screen in
            result.union(screen.frame)
        }
    }

    func captureJPEG(maxPixelWidth: CGFloat = 1600, compression: CGFloat = 0.58) -> Data? {
        guard let display = primaryDisplay() else {
            return nil
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = true
        config.scalesToFit = true
        let semaphore = DispatchSemaphore(value: 0)
        var capturedImage: CGImage?
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
            capturedImage = image
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 3) == .success,
              let capturedImage else {
            return nil
        };return Self.jpegData(from: capturedImage, maxPixelWidth: maxPixelWidth, compression: compression)
    }

    private func primaryDisplay() -> SCDisplay? {
        let semaphore = DispatchSemaphore(value: 0)
        var primaryDisplay: SCDisplay?
        contentQueue.async {
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
                primaryDisplay = content?.displays.sorted { lhs, rhs in
                    if lhs.frame.origin == rhs.frame.origin {
                        return lhs.displayID < rhs.displayID
                    };return lhs.frame.minX < rhs.frame.minX
                }.first
                semaphore.signal()
            }
        }
        guard semaphore.wait(timeout: .now() + 3) == .success else {
            return nil
        };return primaryDisplay
    }

    private static func jpegData(from image: CGImage, maxPixelWidth: CGFloat, compression: CGFloat) -> Data? {
        let sourceWidth = CGFloat(image.width)
        let scale = min(maxPixelWidth / max(sourceWidth, 1), 1)
        let outputImage: CGImage
        if scale < 1 {
            guard let scaledImage = scaledImage(from: image, scale: scale) else {
                return nil
            }
            outputImage = scaledImage
        } else {
            outputImage = image
        };return encodeJPEG(from: outputImage, compression: compression)
    }

    private static func scaledImage(from image: CGImage, scale: CGFloat) -> CGImage? {
        let targetWidth = max(Int(CGFloat(image.width) * scale), 1)
        let targetHeight = max(Int(CGFloat(image.height) * scale), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    private static func encodeJPEG(from image: CGImage, compression: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties = [
            kCGImageDestinationLossyCompressionQuality: compression
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        };return data as Data
    }
}
