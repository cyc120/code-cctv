import Foundation
import SwiftUI

struct ServiceConfiguration: Codable {
    let host: String
    let port: Int
    let token: String
}

struct StateSummary: Codable {
    let totalProjects: Int
    let activeProjects: Int
    let blockedProjects: Int
    let eventCount: Int
}

struct EventSummary: Codable, Identifiable {
    let id: String
    let eventType: String
    let source: String
    let timestamp: String
    let phase: String
    let status: String
    let focus: String
    let note: String
    let evidence: String
    let files: [String]
}

struct ProjectSummary: Codable, Identifiable {
    let workspace: String
    let name: String
    let status: String
    let phase: String
    let focus: String
    let note: String
    let evidence: String
    let eventType: String
    let updatedAt: String
    let eventCount: Int
    let active: Bool
    let recentEvents: [EventSummary]

    var id: String { workspace }
}

struct GlobalState: Codable {
    let generatedAt: String
    let summary: StateSummary
    let projects: [ProjectSummary]

    static let empty = GlobalState(
        generatedAt: "",
        summary: StateSummary(totalProjects: 0, activeProjects: 0, blockedProjects: 0, eventCount: 0),
        projects: []
    )
}

struct ActivitySummary {
    let projectName: String
    let status: String
    let phase: String
    let focus: String
    let note: String
    let timestamp: String
    let active: Bool
}

struct StreamEnvelope: Codable {
    let type: String
    let state: GlobalState
}

private enum StreamError: Error {
    case invalidResponse
}

@MainActor
final class StatusStore: ObservableObject {
    static let shared = StatusStore()

    @Published private(set) var state = GlobalState.empty
    @Published private(set) var connected = false

    private var streamTask: Task<Void, Never>?

    init() {
        DispatchQueue.main.async { [weak self] in
            self?.startStream()
        }
    }

    deinit {
        streamTask?.cancel()
    }

    var pillTitle: String {
        guard connected else { return "CCTV 未连接" }
        return "CCTV \(state.summary.activeProjects)/\(state.summary.totalProjects)"
    }

    var latestActivity: ActivitySummary? {
        guard let project = state.projects.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        let event = project.recentEvents.first
        return ActivitySummary(
            projectName: project.name,
            status: event.map { $0.status.isEmpty ? project.status : $0.status } ?? project.status,
            phase: event.map { $0.phase.isEmpty ? project.phase : $0.phase } ?? project.phase,
            focus: event.map { $0.focus.isEmpty ? project.focus : $0.focus } ?? project.focus,
            note: event.map { $0.note.isEmpty ? project.note : $0.note } ?? project.note,
            timestamp: event.map { $0.timestamp.isEmpty ? project.updatedAt : $0.timestamp } ?? project.updatedAt,
            active: project.active
        )
    }

    private func startStream() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let configuration = self.loadConfiguration(),
                      let url = URL(string: "http://\(configuration.host):\(configuration.port)/api/stream") else {
                    self.connected = false
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 30
                request.setValue(configuration.token, forHTTPHeaderField: "X-Code-CCTV-Token")

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200..<300).contains(httpResponse.statusCode) else {
                        throw StreamError.invalidResponse
                    }
                    self.connected = true
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        guard let data = json.data(using: .utf8) else { continue }
                        let decoder = JSONDecoder()
                        decoder.keyDecodingStrategy = .convertFromSnakeCase
                        if let envelope = try? decoder.decode(StreamEnvelope.self, from: data), envelope.type == "state" {
                            self.state = envelope.state
                            self.connected = true
                        }
                    }
                } catch {
                    self.connected = false
                }

                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
    }

    private func loadConfiguration() -> ServiceConfiguration? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodeCCTV/service.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(ServiceConfiguration.self, from: data)
    }
}

func statusColor(_ status: String, active: Bool = true) -> Color {
    if status.contains("阻塞") || status.localizedCaseInsensitiveContains("blocked") {
        return .red
    }
    if status.contains("风险") || status.localizedCaseInsensitiveContains("warning") {
        return .orange
    }
    if active || status.contains("监听") || status.localizedCaseInsensitiveContains("watch") {
        return .green
    }
    return .secondary
}
