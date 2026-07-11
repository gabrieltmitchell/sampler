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
}
#endif
