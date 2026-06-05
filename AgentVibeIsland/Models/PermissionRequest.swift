import Foundation

struct PermissionRequest: Codable {
    let event: String
    let agent: String
    let requestId: String
    let action: String
    let actionLabel: String
    let scope: String
    let taskDescription: String
    let taskProgress: Double
    let workspacePath: String
}

struct PermissionDecision: Codable {
    let requestId: String
    let decision: String
}
