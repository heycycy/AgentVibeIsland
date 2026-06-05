import Foundation

struct Rule: Codable {
    let id: String
    let agent: String
    let action: String
    let scope: String
    var enabled: Bool
    let createdAt: Date
    let workspacePath: String
}
