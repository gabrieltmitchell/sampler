#if DEBUG && os(iOS)
import Foundation

@MainActor
final class SamplerAgentClient {
    #if targetEnvironment(simulator)
    static let defaultEndpoint = URL(string: "http://localhost:4747")
    #else
    static let defaultEndpoint: URL? = nil
    #endif

    let endpoint: URL
    let sessionID = UUID().uuidString

    init(endpoint: URL) {
        self.endpoint = endpoint
    }

    func isReachable() async -> Bool {
        do {
            let healthURL = endpoint.appending(path: "health")
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 1.5
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func send(capture: CapturedScreen, annotations: [Annotation]) async throws {
        let payload = try ExportBuilder.makeAgentSyncPayload(
            sessionID: sessionID,
            capture: capture,
            annotations: annotations
        )
        let sendURL = endpoint
            .appending(path: "sessions")
            .appending(path: sessionID)
            .appending(path: "annotations")
        var request = URLRequest(url: sendURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw SamplerError.agentSyncFailed
        }
    }

    func fetchStatuses() async throws -> [AgentAnnotationStatus] {
        let statusesURL = endpoint
            .appending(path: "sessions")
            .appending(path: sessionID)
            .appending(path: "statuses")
        var request = URLRequest(url: statusesURL)
        request.timeoutInterval = 2

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw SamplerError.agentSyncFailed
        }

        return try JSONDecoder().decode(AgentAnnotationStatusResponse.self, from: data).annotations
    }

    func fetchServerStatus() async throws -> AgentServerStatus {
        let statusURL = endpoint.appending(path: "status")
        var request = URLRequest(url: statusURL)
        request.timeoutInterval = 2

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw SamplerError.agentSyncFailed
        }

        return try JSONDecoder().decode(AgentServerStatus.self, from: data)
    }
}

struct AgentAnnotationStatus: Decodable {
    let id: String
    let status: Status
    let progress: String?
    let resolution: String?

    enum Status: String, Decodable {
        case pending
        case acknowledged
        case resolved
        case dismissed
    }
}

private struct AgentAnnotationStatusResponse: Decodable {
    let annotations: [AgentAnnotationStatus]
}

struct AgentServerStatus: Decodable {
    let autoDispatch: AutoDispatch?

    struct AutoDispatch: Decodable {
        let state: State?
        let healthy: Bool?
        let reason: String?
        let lastError: String?
        let lastLogPath: String?
        let lastLogEmpty: Bool?
        let lastOutput: String?
        let retryCount: Int?

        enum State: String, Decodable {
            case ready
            case disabled
            case missingCursorAgent = "missing_cursor_agent"
            case invalidCursorConfig = "invalid_cursor_config"
            case authRequired = "auth_required"
            case logsNotWritable = "logs_not_writable"
            case queued
            case agentStarting = "agent_starting"
            case agentStarted = "agent_started"
            case agentStalled = "agent_stalled"
            case agentReconnecting = "agent_reconnecting"
            case agentNetworkError = "agent_network_error"
            case running
            case agentCompleted = "agent_completed"
            case lastRunFailed = "last_run_failed"
        }
    }
}
#endif
