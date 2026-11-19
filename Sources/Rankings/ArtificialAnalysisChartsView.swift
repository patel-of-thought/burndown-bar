import SwiftUI

struct ArtificialAnalysisChartsView: View {
    @ObservedObject var store: DashboardStore

    private enum Metric: CaseIterable {
        case intelligence, time, cost
        var title: String {
            switch self {
            case .intelligence: return "Intelligence"
            case .time: return "Time per Task"
            case .cost: return "Cost per Task"
            }
        }
        var description: String {
            switch self {
            case .intelligence: return "Artificial Analysis Intelligence Index · higher is better"
            case .time: return "Minutes per Intelligence Index task · lower is better"
            case .cost: return "USD per Intelligence Index task · lower is better"
            }
        }
        var color: Color {
            switch self {
            case .intelligence: return .purple
            case .time: return .yellow
            case .cost: return .orange
            }
        }
        func value(_ model: ArtificialAnalysisModel) -> Double? {
            switch self {
            case .intelligence: return model.intelligence
            case .time: return model.minutesPerTask
            case .cost: return model.costPerTaskUSD
            }
        }
        func label(_ value: Double) -> String {
            switch self {
            case .intelligence: return String(format: "%.0f", value)
            case .time: return String(format: "%.1f min", value)
            case .cost: return value.formatted(.currency(code: "USD"))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Artificial Analysis").font(.headline)
                Spacer()
                Link("Leaderboard", destination: URL(string: "https://artificialanalysis.ai/leaderboards/models")!)
                    .font(.caption)
            }
            Text("The same top 12 intelligence models are compared across all three graphs.")
                .font(.caption).foregroundStyle(.secondary)
            if !store.hasArtificialAnalysisKey && store.artificialAnalysis == nil {
                keyEntry
            } else {
                if store.artificialAnalysisLoading { ProgressView("Loading model data…").controlSize(.small) }
                if let error = store.artificialAnalysisError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if let snapshot = store.artificialAnalysis {
                    ForEach(Metric.allCases, id: \.title) { metric in
                        graph(metric, models: snapshot.topModels, tier: snapshot.tier)
                    }
                    Text("Source: Artificial Analysis \(snapshot.timeFromPublicLeaderboard ? "API + public leaderboard" : "API") · fetched \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)) · \(snapshot.tier.capitalized) tier")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Button("Refresh Artificial Analysis") { Task { await store.refreshArtificialAnalysis(force: true) } }
                    .font(.caption).disabled(store.artificialAnalysisLoading)
                DisclosureGroup("Change API key") { keyEntry }.font(.caption)
            }
        }
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add an Artificial Analysis API key for Intelligence and Cost per Task. Time per Task comes from the public leaderboard when available, or from a Pro API key.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("Artificial Analysis API key", text: $store.artificialAnalysisKeyInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save key") { store.saveArtificialAnalysisKey() }
                    .disabled(store.artificialAnalysisKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Link("Get a key", destination: URL(string: "https://artificialanalysis.ai/data-api/docs")!)
            }.font(.caption)
            Text("Saved in this app's macOS Keychain. ARTIFICIAL_ANALYSIS_API_KEY is also supported.")
                .font(.caption2).foregroundStyle(.tertiary)
        }.padding(12)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func graph(_ metric: Metric, models: [ArtificialAnalysisModel], tier: String) -> some View {
        let ranked = models.filter { metric.value($0) != nil }.sorted {
            let left = metric.value($0) ?? 0, right = metric.value($1) ?? 0
            return metric == .intelligence ? left > right : left < right
        }
        let maximum = metric == .intelligence ? 100 : max(1, ranked.compactMap(metric.value).max() ?? 1)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(metric.color).frame(width: 12, height: 12)
                Text(metric.title).font(.headline)
            }
            Text(metric.description).font(.caption).foregroundStyle(.secondary)
            if ranked.isEmpty {
                Text(metric == .time && tier == "free" ? "Time per Task could not be read from the public leaderboard. A Pro API key also supplies it." : "No measured values are available for these models.")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 10)
            } else {
                ForEach(ranked) { model in
                    let value = metric.value(model) ?? 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(model.name).font(.caption.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(metric.label(value)).font(.caption.monospacedDigit())
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.1))
                                Capsule().fill(metric.color.gradient)
                                    .frame(width: max(2, geometry.size.width * min(1, value / maximum)))
                            }
                        }.frame(height: 7)
                        .accessibilityLabel("\(model.name): \(metric.label(value))")
                    }
                }
            }
        }.padding(12)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}
