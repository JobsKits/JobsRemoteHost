//
//  QuickTunnelServiceTests.swift
//  JobsRemoteHostTests
//
//  Created by Jobs on 2026年7月1日，星期三.
//

import Darwin
import XCTest

@testable import JobsRemoteHost

final class QuickTunnelServiceTests: XCTestCase {
    func testForcedFailureShowsFailedConnectionState() {
        setenv("JOBS_REMOTE_HOST_FORCE_TUNNEL_FAILURE", "1", 1)
        defer {
            unsetenv("JOBS_REMOTE_HOST_FORCE_TUNNEL_FAILURE")
        }

        let service = QuickTunnelService()

        XCTAssertEqual(service.connectionState(), .failed)
        XCTAssertNil(service.publicBaseURL())
        XCTAssertTrue(service.status(inviteCode: "").contains("已模拟免安装公网通道失败"))
    }
}
