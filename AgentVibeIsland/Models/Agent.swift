import Foundation

struct Agent: Codable {
    let agent: String
    let agentLabel: String
    let pid: Int
}

struct StatusUpdate: Codable {
    let agent: String
    let taskDescription: String
    let taskProgress: Double
}

struct UnregisterRequest: Codable {
    let agent: String
    let pid: Int
}
