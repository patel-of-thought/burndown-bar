import SwiftUI

struct OpenRouterInsightsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case keys = "Keys", models = "Models", health = "Health", rankings = "Rankings"
        var id: String { rawValue }
    }
    enum RankingsSlice: String, CaseIterable, Identifiable {
        case models = "Top Models", apps = "Top Apps"
        var id: String { rawValue }
    }

    let snapshot: OpenRouterSnapshot
    let tint: Color
    @ObservedObject var store: DashboardStore

    @State private var activeTab = Tab.keys
    @State private var rankingsSlice = RankingsSlice.models
    @State private var editingKeyHash: String?
    @State private var limitInput = ""
    @State private var limitReset = "monthly"
    @State private var confirmingPauseHash: String?
    @State private var confirmingZDR = false
    @State private var busy = false
    @State private var actionError: String?
    @State private var guardrailError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let status = snapshot.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.33percent").font(.caption).foregroundStyle(tint)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }

            if snapshot.isManagementKey {
                breakdownCard
                guardrailsCard
            } else if snapshot.rankings != nil {
                standardRankingsCard
            }
        }
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Breakdown").font(.headline)
                Spacer()
                Picker("Breakdown", selection: $activeTab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize().controlSize(.small)
            }

            if let actionError {
                Text(actionError).font(.caption).foregroundStyle(.orange)
            }

            switch activeTab {
            case .keys: keysContent
            case .models: modelsContent
            case .health: healthContent
            case .rankings: rankingsContent
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var standardRankingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Global Rankings").font(.headline)
            rankingsContent
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    @ViewBuilder private var keysContent: some View {
        if snapshot.keys.isEmpty {
            Text("No API keys returned.").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                let visible = Array(snapshot.keys.prefix(6))
                ForEach(Array(visible.enumerated()), id: \.element.id) { idx, key in
                    keyRow(key)
                    if idx < visible.count - 1 { Divider() }
                }
            }
        }
    }

    private func keyRow(_ key: OpenRouterKeySummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(key.disabled ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(key.displayName).font(.callout.weight(.medium)).lineLimit(1)
                if key.disabled {
                    Text("Paused").font(.caption2).foregroundStyle(.orange)
                }
                Spacer(minLength: 4)
                let spend = key.spend30dUSD ?? key.usageUSD
                Text(spend.formatted(.currency(code: "USD")))
                    .font(.callout.weight(.semibold).monospacedDigit())
            }
            HStack(spacing: 8) {
                if let limit = key.limitUSD, limit > 0 {
                    let rem = key.limitRemainingUSD ?? max(0, limit - key.usageUSD)
                    Text("\(rem.formatted(.currency(code: "USD"))) / \(limit.formatted(.currency(code: "USD")))\(key.limitReset.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No cap").font(.caption).foregroundStyle(.tertiary)
                }
                if let hit = key.cacheHitRate {
                    Text(String(format: "· %.0f%% cache", hit)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cap") {
                    confirmingPauseHash = nil
                    if editingKeyHash == key.hash {
                        editingKeyHash = nil
                    } else {
                        editingKeyHash = key.hash
                        limitInput = key.limitUSD.map { String(format: "%.2f", $0) } ?? ""
                        limitReset = key.limitReset ?? "monthly"
                    }
                }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(tint).disabled(busy)
                Button(key.disabled ? "Resume" : "Pause") {
                    editingKeyHash = nil
                    confirmingPauseHash = (confirmingPauseHash == key.hash) ? nil : key.hash
                }
                .buttonStyle(.borderless).font(.caption)
                .foregroundStyle(key.disabled ? Color.green : Color.orange).disabled(busy)
            }

            if confirmingPauseHash == key.hash {
                HStack(spacing: 8) {
                    Text(key.disabled ? "Resume this key?" : "Pause this key?")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(key.disabled ? "Confirm Resume" : "Confirm Pause") {
                        perform { try await store.setOpenRouterKeyDisabled(hash: key.hash, disabled: !key.disabled) }
                        confirmingPauseHash = nil
                    }.controlSize(.small).disabled(busy)
                    Button("Cancel") { confirmingPauseHash = nil }.controlSize(.small).buttonStyle(.borderless)
                }.padding(.top, 2)
            }

            if editingKeyHash == key.hash {
                HStack(spacing: 6) {
                    TextField("USD cap", text: $limitInput).textFieldStyle(.roundedBorder).frame(width: 76)
                    Picker("Reset", selection: $limitReset) {
                        Text("Daily").tag("daily")
                        Text("Weekly").tag("weekly")
                        Text("Monthly").tag("monthly")
                        Text("None").tag("")
                    }.labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
                    Spacer()
                    Button("Save") {
                        let parsed = Double(limitInput.trimmingCharacters(in: .whitespaces))
                        perform {
                            try await store.setOpenRouterKeyLimit(hash: key.hash, limitUSD: parsed, reset: parsed == nil ? "" : limitReset)
                        }
                        editingKeyHash = nil
                    }.controlSize(.small).disabled(busy)
                    if key.limitUSD != nil {
                        Button("Clear") {
                            perform { try await store.setOpenRouterKeyLimit(hash: key.hash, limitUSD: nil, reset: "") }
                            editingKeyHash = nil
                        }.controlSize(.small).buttonStyle(.borderless).disabled(busy)
                    }
                }.padding(.top, 2)
            }
        }.padding(.vertical, 8)
    }

    @ViewBuilder private var modelsContent: some View {
        if snapshot.models.isEmpty {
            Text("No model usage in the last 7 days.").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                let visible = Array(snapshot.models.prefix(5))
                ForEach(Array(visible.enumerated()), id: \.element.id) { idx, item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.model).font(.callout.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text(item.spendUSD.formatted(.currency(code: "USD")))
                                .font(.callout.weight(.semibold).monospacedDigit())
                        }
                        HStack(spacing: 8) {
                            Text("\(compactCount(item.tokens)) tok")
                            if let hit = item.cacheHitRate { Text(String(format: "%.0f%% cache", hit)) }
                            if let p90 = item.p90LatencyMs { Text(String(format: "P90 %.1fs", p90 / 1000)) }
                            Spacer()
                            Text("\(item.requests) req")
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 7)
                    if idx < visible.count - 1 { Divider() }
                }
            }
        }
    }

    @ViewBuilder private var healthContent: some View {
        if snapshot.endpoints.isEmpty {
            Text("Endpoint health appears once top models are detected.").font(.caption).foregroundStyle(.secondary)
        } else {
            let items = Array(snapshot.endpoints.prefix(6))
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, ep in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle().fill(ep.isHealthy ? Color.green : Color.orange).frame(width: 6, height: 6)
                            Text(ep.providerName).font(.callout.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text(ep.uptimeLast30m.map { String(format: "%.1f%% up", $0) } ?? ep.status.capitalized)
                                .font(.caption).foregroundStyle(ep.isHealthy ? Color.secondary : Color.orange)
                        }
                        HStack {
                            Text(ep.model).lineLimit(1)
                            Spacer()
                            if let p = ep.promptPricePerMillion, let c = ep.completionPricePerMillion {
                                Text(String(format: "$%.2f/$%.2f per 1M", p, c))
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 7)
                    if idx < items.count - 1 { Divider() }
                }
            }
        }
    }

    @ViewBuilder private var rankingsContent: some View {
        if let rankings = snapshot.rankings, !rankings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Rankings slice", selection: $rankingsSlice) {
                    ForEach(RankingsSlice.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.small)

                switch rankingsSlice {
                case .models:
                    if rankings.topModels.isEmpty {
                        Text("No model ranking data available.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            let visible = Array(rankings.topModels.prefix(6))
                            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, item in
                                HStack {
                                    Text("\(idx + 1).").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 18, alignment: .leading)
                                    Text(item.model).font(.callout).lineLimit(1)
                                    Spacer()
                                    Text(compactCount(item.totalTokens)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    if let share = item.sharePercent {
                                        Text(String(format: "%.1f%%", share)).font(.caption.weight(.medium).monospacedDigit()).frame(width: 42, alignment: .trailing)
                                    }
                                }.padding(.vertical, 6)
                                if idx < visible.count - 1 { Divider() }
                            }
                        }
                    }
                case .apps:
                    if rankings.topApps.isEmpty {
                        Text("No app ranking data available.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            let visible = Array(rankings.topApps.prefix(6))
                            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, item in
                                HStack {
                                    Text("\(item.rank).").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 18, alignment: .leading)
                                    Text(item.name).font(.callout).lineLimit(1)
                                    Spacer()
                                    Text("\(compactCount(item.totalTokens)) tok").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                                if idx < visible.count - 1 { Divider() }
                            }
                        }
                    }
                }

                let citation = rankings.asOf.map { "Source: OpenRouter (openrouter.ai/rankings), as of \($0)" } ?? "Source: OpenRouter (openrouter.ai/rankings)"
                Text(citation).font(.caption2).foregroundStyle(.tertiary)
            }
        } else if !snapshot.hasStandardKey {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add a Standard API Key in Connections to fetch OpenRouter's global Top Models and Top Apps.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Add Standard API Key") { store.openConnectionSettings(.openrouter) }
                    .controlSize(.small)
            }
        } else {
            Text("Global rankings data is unavailable right now.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var guardrailsCard: some View {
        let activeGuardrail = snapshot.primaryZDRGuardrail
        let zdrEnabled = activeGuardrail?.enforceZDR ?? false
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Guardrails").font(.headline)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
            if let guardrailError {
                Text(guardrailError).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zero Data Retention (ZDR)").font(.callout)
                    Text(activeGuardrail.map { "Guardrail: \($0.name)" } ?? "Route only to zero-retention endpoints")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(zdrEnabled ? "Enabled" : "Enable") {
                    confirmingZDR.toggle()
                }
                .controlSize(.small).disabled(busy)
            }
            if confirmingZDR {
                HStack(spacing: 8) {
                    Text(zdrEnabled ? "Disable ZDR enforcement?" : "Enforce ZDR on active keys?")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(zdrEnabled ? "Confirm Disable" : "Confirm Enable") {
                        let hashes = snapshot.keys.filter { !$0.disabled }.map(\.hash)
                        perform(guardrail: true) {
                            try await store.setOpenRouterZDR(enabled: !zdrEnabled, guardrailID: activeGuardrail?.id, keyHashes: hashes)
                        }
                        confirmingZDR = false
                    }.controlSize(.small).disabled(busy)
                    Button("Cancel") { confirmingZDR = false }.controlSize(.small).buttonStyle(.borderless)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func perform(guardrail: Bool = false, _ operation: @escaping () async throws -> Void) {
        if guardrail { guardrailError = nil } else { actionError = nil }
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() }
            catch {
                let message = SubscriptionClient.message(error, provider: "OpenRouter")
                if guardrail { guardrailError = message } else { actionError = message }
            }
        }
    }
}
