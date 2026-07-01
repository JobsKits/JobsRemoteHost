//
//  MainWindowControllerLayoutTests.swift
//  JobsRemoteHostTests
//
//  Created by Jobs on 2026年7月1日，星期三.
//

import AppKit
import XCTest

@testable import JobsRemoteHost

final class MainWindowControllerLayoutTests: XCTestCase {
    func testMainPanelsUseResponsiveLayout() throws {
        let controller = MainWindowController()
        let contentView = try XCTUnwrap(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()

        let rootStack = try XCTUnwrap(contentView.subviews.compactMap { $0 as? NSStackView }.first)
        let panels = Array(rootStack.arrangedSubviews.dropFirst())
        XCTAssertEqual(panels.count, 3)
        XCTAssertEqual(panels[0].frame.width, panels[1].frame.width, accuracy: 0.5)
        XCTAssertEqual(panels[1].frame.width, panels[2].frame.width, accuracy: 0.5)

        let controlStack = try XCTUnwrap(panels[0].subviews.compactMap { $0 as? NSStackView }.first)
        XCTAssertEqual(controlStack.orientation, .horizontal)

        let urlStack = try XCTUnwrap(panels[1].subviews.compactMap { $0 as? NSStackView }.first)
        XCTAssertEqual(urlStack.arrangedSubviews.count, 3)
        XCTAssertGreaterThan(panels[2].frame.height, panels[1].frame.height)
    }
}
