import Foundation

protocol AgentRegistryObserver: AnyObject {
    func agentRegistryDidChange(_ registry: AgentRegistry)
}

/// Thread-safe registry of connected agents and their latest status.
final class AgentRegistry {

    struct AgentState {
        let agent: Agent
        var status: StatusUpdate?
    }

    private var agents: [String: AgentState] = [:]
    private let lock = NSLock()

    private struct WeakObserver { weak var value: AgentRegistryObserver? }
    private var observers: [WeakObserver] = []

    // MARK: - Observers

    func addObserver(_ observer: AgentRegistryObserver) {
        lock.lock()
        observers.append(WeakObserver(value: observer))
        lock.unlock()
    }

    // MARK: - Mutations (called from IPCServer on background thread)

    func register(_ agent: Agent) {
        lock.lock()
        agents[agent.agent] = AgentState(agent: agent, status: nil)
        lock.unlock()
        notifyObservers()
    }

    func updateStatus(_ update: StatusUpdate) {
        lock.lock()
        agents[update.agent]?.status = update
        lock.unlock()
        notifyObservers()
    }

    func unregister(name: String) {
        lock.lock()
        agents.removeValue(forKey: name)
        lock.unlock()
        notifyObservers()
    }

    // MARK: - Queries

    var allStates: [AgentState] {
        lock.lock()
        defer { lock.unlock() }
        return Array(agents.values)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return agents.count
    }

    func state(for agentName: String) -> AgentState? {
        lock.lock()
        defer { lock.unlock() }
        return agents[agentName]
    }

    // MARK: - Private

    private func notifyObservers() {
        lock.lock()
        let active = observers.compactMap { $0.value }
        lock.unlock()
        for o in active { o.agentRegistryDidChange(self) }
    }
}
