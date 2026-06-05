import Foundation

final class IPCServer {

    // MARK: - Properties

    private let socketPath: String
    private var serverFD: Int32 = -1
    private var isRunning = false
    private let acceptQueue = DispatchQueue(label: "com.agentvibeisland.ipc.accept", qos: .utility)

    let requestQueue: RequestQueue
    let rulesStore: RulesStore
    let agentRegistry: AgentRegistry

    /// Called on the IPC thread when a new permission request is enqueued (not auto-approved).
    var onNewRequest: (() -> Void)?

    // MARK: - Types

    private struct HTTPRequest {
        let method: String
        let path: String
        let body: Data
    }

    // MARK: - Init

    init(requestQueue: RequestQueue, rulesStore: RulesStore, agentRegistry: AgentRegistry) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentvibeisland").path
        self.socketPath = (dir as NSString).appendingPathComponent("ipc.sock")
        self.requestQueue = requestQueue
        self.rulesStore = rulesStore
        self.agentRegistry = agentRegistry
    }

    // MARK: - Lifecycle

    func start() {
        // Prevent SIGPIPE crashes when writing to closed connections
        signal(SIGPIPE, SIG_IGN)

        // Ensure directory exists
        let dir = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Remove stale socket file
        unlink(socketPath)

        // Create Unix domain socket
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            NSLog("AgentVibeIsland: Failed to create socket")
            return
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathMaxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard socketPath.utf8.count < pathMaxLen else {
            NSLog("AgentVibeIsland: Socket path too long")
            Darwin.close(serverFD)
            serverFD = -1
            return
        }

        socketPath.withCString { cstr in
            _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
                strncpy(ptr, cstr, pathMaxLen - 1)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            NSLog("AgentVibeIsland: Failed to bind: %s", String(cString: strerror(errno)))
            Darwin.close(serverFD)
            serverFD = -1
            return
        }

        guard listen(serverFD, 5) == 0 else {
            NSLog("AgentVibeIsland: Failed to listen: %s", String(cString: strerror(errno)))
            Darwin.close(serverFD)
            serverFD = -1
            return
        }

        isRunning = true
        NSLog("AgentVibeIsland: IPC server listening at %@", socketPath)

        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        if serverFD >= 0 {
            Darwin.close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
        NSLog("AgentVibeIsland: IPC server stopped")
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverFD, sockPtr, &clientAddrLen)
                }
            }

            guard clientFD >= 0 else {
                if !isRunning { break }
                continue
            }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleConnection(clientFD)
            }
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ fd: Int32) {
        defer { Darwin.close(fd) }

        guard let request = readHTTPRequest(fd: fd) else {
            sendHTTPResponse(fd: fd, statusCode: 400,
                             body: Data("{\"error\":\"bad request\"}".utf8))
            return
        }

        switch (request.method, request.path) {
        case ("POST", "/register"):
            handleRegister(request.body, fd: fd)
        case ("POST", "/status"):
            handleStatus(request.body, fd: fd)
        case ("POST", "/request"):
            handlePermissionRequest(request.body, fd: fd)
        case ("POST", "/unregister"):
            handleUnregister(request.body, fd: fd)
        default:
            sendHTTPResponse(fd: fd, statusCode: 404,
                             body: Data("{\"error\":\"not found\"}".utf8))
        }
    }

    // MARK: - HTTP Parsing

    private func readHTTPRequest(fd: Int32) -> HTTPRequest? {
        var accumulated = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

        // Read until header/body separator is found
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n <= 0 { return nil }
            accumulated.append(contentsOf: buffer[0..<n])

            if accumulated.range(of: separator) != nil { break }
            if accumulated.count > 1_048_576 { return nil } // 1 MB safety limit
        }

        guard let sepRange = accumulated.range(of: separator) else { return nil }

        let headerData = accumulated[accumulated.startIndex..<sepRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        // Parse Content-Length header
        var contentLength = 0
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("content-length:") {
                let val = line.dropFirst("content-length:".count)
                    .trimmingCharacters(in: .whitespaces)
                contentLength = Int(val) ?? 0
            }
        }

        // Collect body bytes
        var bodyData = Data(accumulated[sepRange.upperBound...])
        while bodyData.count < contentLength {
            let remaining = contentLength - bodyData.count
            let toRead = min(remaining, buffer.count)
            let n = Darwin.read(fd, &buffer, toRead)
            if n <= 0 { break }
            bodyData.append(contentsOf: buffer[0..<n])
        }

        return HTTPRequest(method: method, path: path, body: bodyData)
    }

    private func sendHTTPResponse(fd: Int32, statusCode: Int, body: Data) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default:  statusText = "Error"
        }

        var header = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var responseData = Data(header.utf8)
        responseData.append(body)

        let totalBytes = responseData.count
        responseData.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var totalSent = 0
            while totalSent < totalBytes {
                let sent = Darwin.write(fd, base + totalSent, totalBytes - totalSent)
                if sent <= 0 { break }
                totalSent += sent
            }
        }
    }

    // MARK: - Endpoint Handlers

    private func handleRegister(_ body: Data, fd: Int32) {
        guard let agent = try? JSONDecoder().decode(Agent.self, from: body) else {
            sendHTTPResponse(fd: fd, statusCode: 400,
                             body: Data("{\"error\":\"invalid payload\"}".utf8))
            return
        }

        agentRegistry.register(agent)

        NSLog("AgentVibeIsland: Agent registered: %@ (pid %d)", agent.agent, agent.pid)
        sendHTTPResponse(fd: fd, statusCode: 200,
                         body: Data("{\"status\":\"registered\"}".utf8))
    }

    private func handleStatus(_ body: Data, fd: Int32) {
        guard let update = try? JSONDecoder().decode(StatusUpdate.self, from: body) else {
            sendHTTPResponse(fd: fd, statusCode: 400,
                             body: Data("{\"error\":\"invalid payload\"}".utf8))
            return
        }

        agentRegistry.updateStatus(update)

        sendHTTPResponse(fd: fd, statusCode: 200,
                         body: Data("{\"status\":\"ok\"}".utf8))
    }

    private func handlePermissionRequest(_ body: Data, fd: Int32) {
        guard let request = try? JSONDecoder().decode(PermissionRequest.self, from: body) else {
            sendHTTPResponse(fd: fd, statusCode: 400,
                             body: Data("{\"error\":\"invalid payload\"}".utf8))
            return
        }

        // Check rules for automatic approval
        if let rule = rulesStore.matchingRule(for: request), rule.enabled {
            NSLog("AgentVibeIsland: Auto-approved by rule %@ for %@", rule.id, request.requestId)
            if let data = try? JSONEncoder().encode(
                PermissionDecision(requestId: request.requestId, decision: "allow")
            ) {
                sendHTTPResponse(fd: fd, statusCode: 200, body: data)
            }
            return
        }

        // Enqueue the request and hold the connection open until resolved
        let semaphore = DispatchSemaphore(value: 0)
        var resolvedDecision: PermissionDecision?

        requestQueue.enqueue(request) { decision in
            resolvedDecision = decision
            semaphore.signal()
        }

        // Notify UI of new request (for pulse animation)
        onNewRequest?()

        semaphore.wait()

        if let decision = resolvedDecision,
           let data = try? JSONEncoder().encode(decision) {
            sendHTTPResponse(fd: fd, statusCode: 200, body: data)
        } else {
            sendHTTPResponse(fd: fd, statusCode: 500,
                             body: Data("{\"error\":\"internal error\"}".utf8))
        }
    }

    private func handleUnregister(_ body: Data, fd: Int32) {
        guard let req = try? JSONDecoder().decode(UnregisterRequest.self, from: body) else {
            sendHTTPResponse(fd: fd, statusCode: 400,
                             body: Data("{\"error\":\"invalid payload\"}".utf8))
            return
        }

        agentRegistry.unregister(name: req.agent)

        NSLog("AgentVibeIsland: Agent unregistered: %@ (pid %d)", req.agent, req.pid)
        sendHTTPResponse(fd: fd, statusCode: 200,
                         body: Data("{\"status\":\"unregistered\"}".utf8))
    }
}
