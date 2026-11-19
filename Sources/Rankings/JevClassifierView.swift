import SwiftUI

struct JevClassifierView: View {
    @ObservedObject var store: DashboardStore
    private let isPreview: Bool
    private var hasAPIKey: Bool { !isPreview && store.hasJevAPIKey }
    @State private var configExpanded = false
    @State private var customModel = false
    @State private var customTask = false

    private static let taskGroups: [(name: String, tasks: [String])] = [
        ("General", ["Daily coding and AI workload"]),
        ("Coding", ["Debug and fix bugs", "Implement a feature", "Refactor code", "Review code", "Write tests"]),
        ("Writing", ["Summarize content", "Draft documentation", "Edit and rewrite"]),
        ("Research", ["Research a topic", "Compare options", "Analyze documents"]),
        ("Data", ["Analyze data", "Generate SQL", "Extract structured data"])
    ]

    private static func taskPrompt(category: String, task: String) -> String {
        category == "General" ? "" : "\(category): \(task)"
    }

    private var taskCategory: String {
        if customTask { return "Custom" }
        return Self.taskGroups.first { group in
            group.tasks.contains { Self.taskPrompt(category: group.name, task: $0) == store.jevTaskInput }
        }?.name ?? "Custom"
    }

    init(store: DashboardStore, configExpanded: Bool = false, isPreview: Bool = false) {
        self.store = store
        self.isPreview = isPreview
        _configExpanded = State(initialValue: configExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Model Advisor").font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { configExpanded.toggle() }
                } label: {
                    Label("Configure", systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(configExpanded ? Color.accentColor : Color.secondary)
            }
            Text("Uses your selected decision model to recommend a generative LLM from pricing, cheapness, intelligence, and current token usage.")
                .font(.caption).foregroundStyle(.secondary)

            if configExpanded {
                configurationCard
            }
            taskControls

            if !hasAPIKey && store.jevClassification == nil {
                missingKeyCard
            } else {
                if store.jevLoading {
                    ProgressView("Finding a model recommendation…").controlSize(.small)
                }
                if let error = store.jevError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if let result = store.jevClassification {
                    recommendationCard(result)
                    signalsCard(result)
                    footer(result)
                }
            }
        }
        .task {
            if store.jevConfig.autoClassify && hasAPIKey && store.jevClassification == nil && !store.jevLoading {
                await store.runJevClassifier()
            }
        }
    }

    private var configurationCard: some View {
        let weights = store.jevConfig.normalizedWeights
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Advisor Settings").font(.caption.weight(.semibold))
                Spacer()
                Button("Reset") {
                    store.jevConfig = JevClassifierConfig()
                    customModel = false
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Advisor model").font(.caption2).foregroundStyle(.secondary)
                Picker("Advisor model", selection: Binding(
                    get: { customModel || !JevClassifierConfig.presets.contains(where: { $0.id == store.jevConfig.jevModel }) ? "custom" : store.jevConfig.jevModel },
                    set: { value in
                        customModel = value == "custom"
                        if !customModel { store.jevConfig.jevModel = value }
                    }
                )) {
                    ForEach(JevClassifierConfig.presets, id: \.id) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Advisor model")
                if customModel || !JevClassifierConfig.presets.contains(where: { $0.id == store.jevConfig.jevModel }) {
                    TextField("Decision model ID (provider/model)", text: $store.jevConfig.jevModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
                Text(store.jevConfig.resolvedJevModel)
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if store.jevConfig.resolvedJevModel == "cloudflare/clef-flash" {
                    Text("Cloudflare Workers AI currently reads only roughly the first 2K tokens of text state.")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Factor weights").font(.caption2).foregroundStyle(.secondary)
                weightSlider("Pricing", value: $store.jevConfig.pricingWeight, normalized: weights.pricing)
                weightSlider("Cheapness", value: $store.jevConfig.cheapnessWeight, normalized: weights.cheapness)
                weightSlider("Intelligence", value: $store.jevConfig.intelligenceWeight, normalized: weights.intelligence)
                weightSlider("Token usage", value: $store.jevConfig.tokenUsageWeight, normalized: weights.tokenUsage)
            }

            Divider()

            HStack {
                Text("Max blended price").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Max blended price", selection: Binding(
                    get: { store.jevConfig.maxBlendedPriceUSD ?? 0 },
                    set: { store.jevConfig.maxBlendedPriceUSD = $0 > 0 ? $0 : nil }
                )) {
                    Text("No cap").tag(0.0)
                    Text("≤ $1/1M").tag(1.0)
                    Text("≤ $3/1M").tag(3.0)
                    Text("≤ $10/1M").tag(10.0)
                    Text("≤ $20/1M").tag(20.0)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 105)
            }

            HStack {
                Text("Candidate LLMs").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper("\(store.jevConfig.clampedMaxCandidates)", value: $store.jevConfig.maxCandidates, in: 4...12)
                    .font(.caption.monospacedDigit())
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Exclude models (comma-separated)").font(.caption2).foregroundStyle(.secondary)
                TextField("e.g. deepseek, llama", text: $store.jevConfig.excludedModels)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Text("Decision classifiers and non-LLM models are always excluded from results.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Toggle("Get advice when opening tab", isOn: $store.jevConfig.autoClassify)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)

            HStack {
                Spacer()
                Button("Apply & Get Advice") {
                    Task { await store.runJevClassifier(force: true) }
                }
                .font(.caption)
                .disabled(store.jevLoading || !hasAPIKey)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func weightSlider(_ title: String, value: Binding<Double>, normalized: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text("\(Int((normalized * 100).rounded()))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1, step: 0.05)
                .controlSize(.mini)
        }
    }

    private var missingKeyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect an OpenRouter Standard API Key to get model advice with \(store.jevConfig.resolvedJevModel).")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open OpenRouter Connections") {
                store.openConnectionSettings(.openrouter)
            }
            .font(.caption)
            Text("Uses your saved OpenRouter Standard API Key or OPENROUTER_API_KEY.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var taskControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task").font(.caption.weight(.semibold))
            Picker("Category", selection: Binding(
                get: { taskCategory },
                set: { category in
                    customTask = category == "Custom"
                    if let group = Self.taskGroups.first(where: { $0.name == category }), let task = group.tasks.first {
                        store.jevTaskInput = Self.taskPrompt(category: category, task: task)
                    }
                }
            )) {
                ForEach(Self.taskGroups, id: \.name) { group in
                    Text(group.name).tag(group.name)
                }
                Text("Custom").tag("Custom")
            }
            .pickerStyle(.menu)
            .font(.caption)

            if let group = Self.taskGroups.first(where: { $0.name == taskCategory }) {
                Picker("Task", selection: Binding(
                    get: { group.tasks.first { Self.taskPrompt(category: group.name, task: $0) == store.jevTaskInput } ?? group.tasks[0] },
                    set: { task in store.jevTaskInput = Self.taskPrompt(category: group.name, task: task) }
                )) {
                    ForEach(group.tasks, id: \.self) { task in
                        Text(task).tag(task)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
            } else {
                TextField("Describe your task…", text: $store.jevTaskInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        if !isPreview { Task { await store.runJevClassifier(force: true) } }
                    }
            }

            HStack {
                Spacer()
                Button(store.jevClassification == nil ? "Get Advice" : "Refresh Advice") {
                    Task { await store.runJevClassifier(force: true) }
                }
                .font(.caption)
                .disabled(store.jevLoading || !hasAPIKey)
            }
        }
    }

    private func recommendationCard(_ result: JevClassificationResult) -> some View {
        let tierColor = color(for: result.tier)
        let modelName = result.recommendedCandidate?.displayName ?? result.recommendedKey
        let modelID = result.recommendedCandidate?.modelID ?? result.recommendedKey

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommended LLM").font(.caption2).foregroundStyle(.secondary)
                    Text(modelName).font(.headline).lineLimit(1)
                    if modelID != modelName {
                        Text(modelID).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(result.tier.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .foregroundStyle(tierColor)
                        .background(tierColor.opacity(0.15), in: Capsule())
                    if result.modelConfidence > 0 {
                        Text("\(Int((result.modelConfidence * 100).rounded()))% conf")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }

            if let candidate = result.recommendedCandidate {
                HStack(spacing: 12) {
                    metricPill("Pricing", candidate.priceLabel)
                    if let cheap = candidate.cheapnessScore {
                        metricPill("Cheapness", "\(Int(cheap))/100")
                    }
                    if let intel = candidate.intelligence {
                        metricPill("Intelligence", String(format: "%.0f", intel))
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Spend efficiency").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(min(4, max(1, result.spendEfficiencyScore + 1)))/4").font(.caption.monospacedDigit().weight(.medium))
                }
                Text(result.spendEfficiencyLegend).font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(index <= result.spendEfficiencyScore ? efficiencyColor(result.spendEfficiencyScore) : Color.primary.opacity(0.1))
                            .frame(height: 5)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                let pct = Int((result.prioritizeCheapnessProbability * 100).rounded())
                HStack {
                    Text("Prioritize cheapness").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pct)%").font(.caption.monospacedDigit().weight(.medium))
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule().fill((pct >= 60 ? Color.orange : Color.green).gradient)
                            .frame(width: max(2, geometry.size.width * result.prioritizeCheapnessProbability))
                    }
                }.frame(height: 6)
            }

            if result.modelProbabilities.count > 1 {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("Candidate LLM probabilities").font(.caption2).foregroundStyle(.secondary)
                    ForEach(Array(result.modelProbabilities.prefix(4).enumerated()), id: \.offset) { _, entry in
                        let label = entry.candidate?.displayName ?? entry.key
                        HStack(spacing: 6) {
                            Text(label).font(.caption2).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Int((entry.probability * 100).rounded()))%")
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule().fill(Color.accentColor.opacity(entry.key == result.recommendedKey ? 0.85 : 0.35))
                                    .frame(width: max(2, geometry.size.width * min(1, entry.probability)))
                            }
                        }.frame(height: 4)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func signalsCard(_ result: JevClassificationResult) -> some View {
        let context = result.context
        return VStack(alignment: .leading, spacing: 7) {
            Text("Signals evaluated").font(.caption.weight(.semibold))
            signalRow("Pricing", pricingSummary(context))
            signalRow("Cheapness", cheapnessSummary(context))
            signalRow("Intelligence", intelligenceSummary(context))
            signalRow("Token usage", tokenUsageSummary(context))
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func footer(_ result: JevClassificationResult) -> some View {
        let costText = result.costUSD.map { String(format: " · $%.5f", $0) } ?? ""
        return Text("Advisor: \(result.provider) (\(result.jevModel)) via OpenRouter · \(result.inputTokens) in\(costText) · \(result.classifiedAt.formatted(date: .omitted, time: .shortened))")
            .font(.caption2).foregroundStyle(.tertiary)
    }

    private func metricPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption2.monospacedDigit().weight(.medium)).lineLimit(1)
        }
    }

    private func signalRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).font(.caption.monospacedDigit()).multilineTextAlignment(.trailing).lineLimit(2)
        }
    }

    private func pricingSummary(_ context: JevUsageContext) -> String {
        if let blended = context.blendedCostPerMillionUSD {
            return String(format: "$%.2f / 1M blended", blended)
        }
        if let avg = context.averageCandidateBlendedPrice {
            return String(format: "$%.2f / 1M pool avg", avg)
        }
        return "\(context.candidates.count) LLMs compared"
    }

    private func cheapnessSummary(_ context: JevUsageContext) -> String {
        if let cheapest = context.cheapestCandidate, let price = cheapest.blendedPerMillion {
            return "\(cheapest.displayName) (\(String(format: "$%.2f", price))/1M)"
        }
        return "Relative cost tiering"
    }

    private func intelligenceSummary(_ context: JevUsageContext) -> String {
        if let best = context.highestIntelligenceCandidate, let index = best.intelligence {
            return "Top \(best.displayName) (\(String(format: "%.0f", index)))"
        }
        return "Add Artificial Analysis key for live index"
    }

    private func tokenUsageSummary(_ context: JevUsageContext) -> String {
        var parts: [String] = []
        if context.totalTokens30d > 0 {
            parts.append("\(compactCount(context.totalTokens30d)) tok (30d)")
        }
        if let spend = context.openRouterSpend30dUSD, spend > 0 {
            parts.append(spend.formatted(.currency(code: "USD")))
        }
        if let quota = context.lowestQuotaRemainingPercent {
            parts.append("\(Int(quota.rounded()))% min quota")
        }
        return parts.isEmpty ? "No recent token usage yet" : parts.joined(separator: " · ")
    }

    private func color(for tier: JevModelTier) -> Color {
        switch tier {
        case .budget: return .green
        case .balanced: return .blue
        case .frontier: return .purple
        }
    }

    private func efficiencyColor(_ score: Int) -> Color {
        switch score {
        case ...0: return .red
        case 1: return .orange
        case 2: return .blue
        default: return .green
        }
    }
}
