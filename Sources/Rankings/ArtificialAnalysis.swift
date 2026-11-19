import Foundation

struct ArtificialAnalysisModel: Identifiable {
    let id: String
    let name: String
    let creator: String
    let intelligence: Double?
    let minutesPerTask: Double?
    let costPerTaskUSD: Double?
}

struct ArtificialAnalysisSnapshot {
    let models: [ArtificialAnalysisModel]
    let tier: String
    let fetchedAt: Date
    let timeFromPublicLeaderboard: Bool

    var topModels: [ArtificialAnalysisModel] {
        Array(models.filter { $0.intelligence != nil }
            .sorted { ($0.intelligence ?? 0) > ($1.intelligence ?? 0) }.prefix(12))
    }
}

enum ArtificialAnalysisError: LocalizedError {
    case unauthorized, rateLimited, unavailable(Int), invalidResponse
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Artificial Analysis rejected the API key. Check it in Rankings."
        case .rateLimited: return "Artificial Analysis's daily request limit was reached. Try again after it resets."
        case .unavailable(let status): return "Artificial Analysis returned HTTP \(status). Try refreshing later."
        case .invalidResponse: return "Artificial Analysis returned an unexpected model response."
        }
    }
}

enum ArtificialAnalysisParser {
    static func models(_ raw: JSON) -> [ArtificialAnalysisModel] {
        guard let rows = raw["data"] as? [JSON] else { return [] }
        return rows.compactMap { row in
            guard let name = string(row["name"]),
                  let id = string(row["id"] ?? row["slug"]) else { return nil }
            let evaluations = row["evaluations"] as? JSON ?? [:]
            let cost = row["artificial_analysis_intelligence_index_cost"] as? JSON ?? [:]
            let costPerTask = cost["cost_per_task"] as? JSON ?? [:]
            let performance = row["performance_v3"] as? JSON ?? [:]
            let creator = row["model_creator"] as? JSON ?? [:]
            let intelligence = number(evaluations["artificial_analysis_intelligence_index"])
            let minutes = number(performance["time_per_task_seconds"]).map { $0 / 60 }
            let taskCost = number(costPerTask["total_cost"])
            guard intelligence != nil || minutes != nil || taskCost != nil else { return nil }
            return ArtificialAnalysisModel(id: id, name: name,
                creator: string(creator["name"]) ?? "Unknown",
                intelligence: intelligence, minutesPerTask: minutes, costPerTaskUSD: taskCost)
        }
    }

    static func publicTimes(from html: Data) -> [String: Double] {
        guard let document = try? XMLDocument(data: html, options: .documentTidyHTML),
              let rows = try? document.nodes(forXPath: "//table/tbody/tr") else { return [:] }
        var times: [String: Double] = [:]
        for row in rows {
            guard let cells = try? row.nodes(forXPath: "./td"), cells.count >= 4,
                  let name = cells[0].stringValue,
                  let minutes = Double((cells[3].stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)),
                  minutes.isFinite && minutes > 0 else { continue }
            times[normalizedName(name)] = minutes
        }
        return times
    }

    static func normalizedName(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}

final class ArtificialAnalysisClient {
    private let session: URLSession
    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    private func page(_ page: Int, full: Bool, key: String) async throws -> JSON {
        let path = full ? "models" : "models/free"
        let url = URL(string: "https://artificialanalysis.ai/api/v2/language/\(path)?page=\(page)")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ArtificialAnalysisError.invalidResponse }
        switch response.statusCode {
        case 200...299: break
        case 401: throw ArtificialAnalysisError.unauthorized
        case 429: throw ArtificialAnalysisError.rateLimited
        default: throw ArtificialAnalysisError.unavailable(response.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? JSON,
              json["data"] is [JSON] else { throw ArtificialAnalysisError.invalidResponse }
        return json
    }

    func rankings(key: String, now: Date = Date()) async throws -> ArtificialAnalysisSnapshot {
        let firstFree = try await page(1, full: false, key: key)
        let tier = string(firstFree["tier"]) ?? "free"
        let full = tier == "pro" || tier == "commercial"
        var response = full ? try await page(1, full: true, key: key) : firstFree
        var models = ArtificialAnalysisParser.models(response)
        var pageNumber = 1
        while (response["pagination"] as? JSON)?["has_more"] as? Bool == true && pageNumber < 5 {
            pageNumber += 1
            response = try await page(pageNumber, full: full, key: key)
            models += ArtificialAnalysisParser.models(response)
        }
        guard !models.isEmpty else { throw ArtificialAnalysisError.invalidResponse }
        var timeFromPublicLeaderboard = false
        if !full {
            let url = URL(string: "https://artificialanalysis.ai/leaderboards/models")!
            var request = URLRequest(url: url)
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            if let (html, response) = try? await session.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200, html.count < 8_000_000 {
                let publicTimes = ArtificialAnalysisParser.publicTimes(from: html)
                if !publicTimes.isEmpty {
                    models = models.map { model in
                        ArtificialAnalysisModel(id: model.id, name: model.name, creator: model.creator,
                            intelligence: model.intelligence,
                            minutesPerTask: model.minutesPerTask ?? publicTimes[ArtificialAnalysisParser.normalizedName(model.name)],
                            costPerTaskUSD: model.costPerTaskUSD)
                    }
                    timeFromPublicLeaderboard = true
                }
            }
        }
        return ArtificialAnalysisSnapshot(models: models, tier: tier, fetchedAt: now,
            timeFromPublicLeaderboard: timeFromPublicLeaderboard)
    }
}
