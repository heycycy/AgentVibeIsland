import XCTest
@testable import AgentVibeIsland

final class RulesStoreTests: XCTestCase {

    private var rulesStore: RulesStore!
    private var testDir: String!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "agentvibeisland-test-\(UUID().uuidString)"
        rulesStore = RulesStore(directory: testDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        super.tearDown()
    }

    // MARK: - Matching Rule Auto-Approves

    func testMatchingRuleAutoApproves() {
        let rule = Rule(
            id: "rule_abc",
            agent: "claude",
            action: "write_file",
            scope: "src/auth/**",
            enabled: true,
            createdAt: Date(),
            workspacePath: "/Users/name/projects/my-app"
        )
        rulesStore.addRule(rule)

        let request = PermissionRequest(
            event: "permission_request",
            agent: "claude",
            requestId: "req_abc",
            action: "write_file",
            actionLabel: "Write to file",
            scope: "src/auth/middleware.ts",
            taskDescription: "Refactoring auth module",
            taskProgress: 0.62,
            workspacePath: "/Users/name/projects/my-app"
        )

        let matched = rulesStore.matchingRule(for: request)
        XCTAssertNotNil(matched, "A matching rule should be found")
        XCTAssertEqual(matched?.id, "rule_abc")

        // When a rule matches, the request is never queued
        let queue = RequestQueue()
        XCTAssertEqual(queue.count, 0, "Queue should remain empty when rule auto-approves")
    }

    // MARK: - Non-Matching Cases

    func testNonMatchingWorkspace() {
        rulesStore.addRule(Rule(
            id: "rule_1", agent: "claude", action: "write_file",
            scope: "src/auth/**", enabled: true, createdAt: Date(),
            workspacePath: "/Users/name/projects/other-app"
        ))

        let request = PermissionRequest(
            event: "permission_request", agent: "claude", requestId: "req_1",
            action: "write_file", actionLabel: "Write to file",
            scope: "src/auth/middleware.ts", taskDescription: "Task",
            taskProgress: 0.5, workspacePath: "/Users/name/projects/my-app"
        )

        XCTAssertNil(rulesStore.matchingRule(for: request),
                     "Rule with different workspacePath must not match")
    }

    func testNonMatchingAgent() {
        rulesStore.addRule(Rule(
            id: "rule_2", agent: "cursor", action: "write_file",
            scope: "src/**", enabled: true, createdAt: Date(),
            workspacePath: "/Users/name/projects/my-app"
        ))

        let request = PermissionRequest(
            event: "permission_request", agent: "claude", requestId: "req_2",
            action: "write_file", actionLabel: "Write to file",
            scope: "src/main.ts", taskDescription: "Task",
            taskProgress: 0.5, workspacePath: "/Users/name/projects/my-app"
        )

        XCTAssertNil(rulesStore.matchingRule(for: request),
                     "Rule for different agent must not match")
    }

    func testDisabledRuleDoesNotMatch() {
        rulesStore.addRule(Rule(
            id: "rule_3", agent: "claude", action: "write_file",
            scope: "src/**", enabled: false, createdAt: Date(),
            workspacePath: "/Users/name/projects/my-app"
        ))

        let request = PermissionRequest(
            event: "permission_request", agent: "claude", requestId: "req_3",
            action: "write_file", actionLabel: "Write to file",
            scope: "src/main.ts", taskDescription: "Task",
            taskProgress: 0.5, workspacePath: "/Users/name/projects/my-app"
        )

        XCTAssertNil(rulesStore.matchingRule(for: request),
                     "Disabled rule must not match")
    }

    // MARK: - Glob Matching

    func testDoubleWildcardMatchesDeepPaths() {
        rulesStore.addRule(Rule(
            id: "rule_4", agent: "claude", action: "write_file",
            scope: "src/**", enabled: true, createdAt: Date(),
            workspacePath: "/Users/name/projects/my-app"
        ))

        let deep = PermissionRequest(
            event: "permission_request", agent: "claude", requestId: "req_4",
            action: "write_file", actionLabel: "Write",
            scope: "src/deeply/nested/file.ts", taskDescription: "Task",
            taskProgress: 0.5, workspacePath: "/Users/name/projects/my-app"
        )
        XCTAssertNotNil(rulesStore.matchingRule(for: deep),
                        "** should match deep paths")

        let outside = PermissionRequest(
            event: "permission_request", agent: "claude", requestId: "req_5",
            action: "write_file", actionLabel: "Write",
            scope: "other/file.ts", taskDescription: "Task",
            taskProgress: 0.5, workspacePath: "/Users/name/projects/my-app"
        )
        XCTAssertNil(rulesStore.matchingRule(for: outside),
                     "** should not match outside the prefix")
    }

    func testSingleWildcardDoesNotCrossDirectories() {
        rulesStore.addRule(Rule(
            id: "rule_5", agent: "claude", action: "write_file",
            scope: "src/*", enabled: true, createdAt: Date(),
            workspacePath: "/Users/name/projects/my-app"
        ))

        let shallow = PermissionRequest(
            event: "permission_request", agent: "claude", requestId: "req_6",
            action: "write_file", actionLabel: "Write",
            scope: "src/file.ts", taskDescription: "Task",
            taskProgress: 0.5, workspacePath: "/Users/name/projects/my-app"
        )
        XCTAssertNotNil(rulesStore.matchingRule(for: shallow),
                        "* should match files in the same directory")

        let deep = PermissionRequest(
            event: "permission_request", agent: "claude", requestId: "req_7",
            action: "write_file", actionLabel: "Write",
            scope: "src/nested/file.ts", taskDescription: "Task",
            taskProgress: 0.5, workspacePath: "/Users/name/projects/my-app"
        )
        XCTAssertNil(rulesStore.matchingRule(for: deep),
                     "* should not cross directory boundaries")
    }

    // MARK: - Persistence

    func testRulesPersistAcrossInstances() {
        rulesStore.addRule(Rule(
            id: "rule_persist", agent: "claude", action: "write_file",
            scope: "**", enabled: true, createdAt: Date(),
            workspacePath: "/Users/name/projects/my-app"
        ))

        let newStore = RulesStore(directory: testDir)
        XCTAssertEqual(newStore.allRules.count, 1)
        XCTAssertEqual(newStore.allRules.first?.id, "rule_persist")
    }

    func testRemoveRule() {
        rulesStore.addRule(Rule(
            id: "rule_rm", agent: "claude", action: "write_file",
            scope: "**", enabled: true, createdAt: Date(),
            workspacePath: "/Users/name/projects/my-app"
        ))
        XCTAssertEqual(rulesStore.allRules.count, 1)

        rulesStore.removeRule(id: "rule_rm")
        XCTAssertEqual(rulesStore.allRules.count, 0)
    }
}
