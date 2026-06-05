import Foundation

final class RulesStore {
    private var rules: [Rule] = []
    private let filePath: URL
    private let lock = NSLock()

    init(directory: String? = nil) {
        let dir: URL
        if let customDir = directory {
            dir = URL(fileURLWithPath: customDir)
        } else {
            dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".agentvibeisland")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        filePath = dir.appendingPathComponent("rules.json")
        loadRules()
    }

    // MARK: - Persistence

    func loadRules() {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: filePath.path) else { return }
        guard let data = try? Data(contentsOf: filePath) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        rules = (try? decoder.decode([Rule].self, from: data)) ?? []
    }

    func saveRules() {
        lock.lock()
        let snapshot = rules
        lock.unlock()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: filePath, options: .atomic)
    }

    // MARK: - CRUD

    func addRule(_ rule: Rule) {
        lock.lock()
        rules.append(rule)
        lock.unlock()
        saveRules()
    }

    func removeRule(id: String) {
        lock.lock()
        rules.removeAll { $0.id == id }
        lock.unlock()
        saveRules()
    }

    func updateEnabled(id: String, enabled: Bool) {
        lock.lock()
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].enabled = enabled
        }
        lock.unlock()
        saveRules()
    }

    func removeDisabled() {
        lock.lock()
        rules.removeAll { !$0.enabled }
        lock.unlock()
        saveRules()
    }

    var allRules: [Rule] {
        lock.lock()
        defer { lock.unlock() }
        return rules
    }

    // MARK: - Matching

    func matchingRule(for request: PermissionRequest) -> Rule? {
        lock.lock()
        defer { lock.unlock() }

        return rules.first { rule in
            guard rule.enabled else { return false }
            guard rule.agent == request.agent else { return false }
            guard rule.action == request.action else { return false }
            guard rule.workspacePath == request.workspacePath else { return false }
            return globMatch(pattern: rule.scope, path: request.scope)
        }
    }

    // MARK: - Glob Matching

    private func globMatch(pattern: String, path: String) -> Bool {
        let regexPattern = convertGlobToRegex(pattern)
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return false }
        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    private func convertGlobToRegex(_ glob: String) -> String {
        var regex = "^"
        var i = glob.startIndex

        while i < glob.endIndex {
            let c = glob[i]
            let next = glob.index(after: i)

            switch c {
            case "*":
                if next < glob.endIndex && glob[next] == "*" {
                    let afterStars = glob.index(after: next)
                    if afterStars < glob.endIndex && glob[afterStars] == "/" {
                        // **/ matches zero or more directories
                        regex += "(?:.+/)?"
                        i = glob.index(after: afterStars)
                        continue
                    } else {
                        // ** at end matches everything
                        regex += ".*"
                        i = glob.index(after: next)
                        continue
                    }
                } else {
                    // * matches any characters except /
                    regex += "[^/]*"
                }
            case "?":
                regex += "[^/]"
            case ".":
                regex += "\\."
            case "(", ")", "{", "}", "+", "^", "$", "|", "\\":
                regex += "\\\(c)"
            default:
                regex += String(c)
            }

            i = next
        }

        regex += "$"
        return regex
    }
}
