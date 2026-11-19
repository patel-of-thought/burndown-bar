import Charts
import SwiftUI

enum TokenKind: String, CaseIterable, Identifiable {
    case input = "Input", output = "Output", cacheRead = "Cache read", cacheWrite = "Cache write"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .input: return .blue
        case .output: return .green
        case .cacheRead: return .purple
        case .cacheWrite: return .orange
        }
    }
    func value(in day: DailyUsage) -> Int64 {
        switch self {
        case .input: return day.input
        case .output: return day.output
        case .cacheRead: return day.cacheRead
        case .cacheWrite: return day.cacheWrite
        }
    }
}

/// Daily cost and token (input, output, cache read, cache write) bar chart with hover inspection.
struct UsageChart: View {
    enum Metric: String, CaseIterable, Identifiable {
        case cost = "Cost", tokens = "Tokens"
        var id: String { rawValue }
    }
    enum Style: String, CaseIterable, Identifiable {
        case bars = "Bar chart", pie = "Pie chart"
        var id: String { rawValue }
        var symbol: String { self == .bars ? "chart.bar.fill" : "chart.pie.fill" }
    }
    enum Span: Int, CaseIterable, Identifiable {
        case week = 7, month = 30
        var id: Int { rawValue }
        var title: String { self == .week ? "7 days" : "30 days" }
    }

    let series: [UsageSeries]
    var tint: Color = .accentColor
    var calendar = Calendar.current
    @State private var chosenMetric: Metric
    @State private var chosenStyle: Style
    @State private var angleSelection: Double?
    @State private var seriesID: String?
    @State private var span = Span.month
    @State private var selection: Date?

    init(series: [UsageSeries], tint: Color = .accentColor, calendar: Calendar = .current, metric: Metric = .cost, style: Style = .bars) {
        self.series = series
        self.tint = tint
        self.calendar = calendar
        _chosenMetric = State(initialValue: metric)
        _chosenStyle = State(initialValue: style)
    }

    private var current: UsageSeries { series.first { $0.id == seriesID } ?? series[0] }
    /// Sources without dollar amounts (CLIProxyAPI records tokens only) fall back to the token view.
    private var metric: Metric { current.hasCost ? chosenMetric : .tokens }
    /// Cost has a single dimension, so only token usage can be split into shares.
    private var showsPie: Bool { chosenStyle == .pie && metric == .tokens }
    private var days: [DailyUsage] { Array(current.daily.suffix(span.rawValue)) }
    private var shares: [(kind: TokenKind, total: Int64)] {
        TokenKind.allCases.map { kind in (kind, days.reduce(0) { $0 + kind.value(in: $1) }) }
    }
    private var shareTotal: Int64 { shares.reduce(0) { $0 + $1.total } }
    private var selectedKind: TokenKind? {
        guard showsPie, let angleSelection else { return nil }
        var running = 0.0
        for share in shares where share.total > 0 {
            running += Double(share.total)
            if angleSelection <= running { return share.kind }
        }
        return nil
    }
    private func percent(_ value: Int64) -> String {
        guard shareTotal > 0, value > 0 else { return "0%" }
        let share = Double(value) / Double(shareTotal)
        return share < 0.001 ? "<0.1%" : share.formatted(.percent.precision(.fractionLength(1)))
    }
    private var selectedDay: DailyUsage? {
        guard !showsPie, let selection else { return nil }
        let day = calendar.startOfDay(for: selection)
        return days.first { $0.date == day }
    }
    private var hasData: Bool {
        days.contains { metric == .cost ? $0.dollars > 0 : $0.tokens > 0 }
    }
    private struct Point: Identifiable {
        let date: Date, kind: TokenKind, value: Double
        var id: String { "\(date.timeIntervalSince1970)-\(kind.rawValue)" }
    }
    private var points: [Point] {
        days.flatMap { day in TokenKind.allCases.map { Point(date: day.date, kind: $0, value: Double($0.value(in: day))) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(current.hasCost ? "Cost & Tokens" : "Token Usage").font(.headline)
                Spacer()
                if metric == .tokens {
                    Picker("Chart style", selection: $chosenStyle) {
                        ForEach(Style.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented).labelStyle(.iconOnly).fixedSize().controlSize(.small)
                }
                Picker("Span", selection: $span) {
                    ForEach(Span.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.menu).fixedSize().controlSize(.small)
            }
            if series.count > 1 {
                Picker("Source", selection: Binding(get: { current.id }, set: { seriesID = $0 })) {
                    ForEach(series) { Text($0.title).tag($0.id) }
                }.labelsHidden().pickerStyle(.menu).controlSize(.small)
            } else {
                Text(current.title).font(.caption).foregroundStyle(.secondary)
            }
            if current.hasCost {
                Picker("Metric", selection: $chosenMetric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.segmented)
            }
            summary
            chart
            if metric == .tokens { legend }
        }
    }

    private var summary: some View {
        let day = selectedDay
        let title = day.map { $0.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "Last \(span.rawValue) days"
        let dollars = day?.dollars ?? days.reduce(0) { $0 + $1.dollars }
        let tokens = day?.tokens ?? days.reduce(0) { $0 + $1.tokens }
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(metric == .cost ? dollars.formatted(.currency(code: "USD")) : "\(compactCount(tokens)) tokens")
                .font(.title3.weight(.semibold).monospacedDigit())
        }
    }

    @ViewBuilder private var chart: some View {
        if hasData && showsPie {
            pie
        } else if hasData {
            Chart {
                if metric == .cost {
                    ForEach(days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Cost", day.dollars))
                            .foregroundStyle(tint.gradient)
                            .opacity(selectedDay == nil || selectedDay?.date == day.date ? 1 : 0.4)
                    }
                } else {
                    ForEach(points) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Tokens", point.value))
                            .foregroundStyle(by: .value("Type", point.kind.rawValue))
                            .opacity(selectedDay == nil || selectedDay?.date == point.date ? 1 : 0.4)
                    }
                }
            }
            .chartForegroundStyleScale(domain: TokenKind.allCases.map(\.rawValue), range: TokenKind.allCases.map(\.color))
            .chartLegend(.hidden)
            .chartXSelection(value: $selection)
            .chartXScale(range: .plotDimension(endPadding: 28))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: span == .week ? 1 : 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: span == .week)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(metric == .cost ? (amount >= 10 ? String(format: "$%.0f", amount) : String(format: "$%.2f", amount))
                                                 : compactCount(Int64(amount)))
                        }
                    }
                }
            }
            .frame(height: 150)
            .accessibilityLabel(metric == .cost ? "Daily cost chart" : "Daily token usage chart")
        } else {
            Text("No \(metric == .cost ? "cost" : "token usage") recorded in this period.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private var pie: some View {
        let inspected = selectedKind
        let center = inspected.map { kind in shares.first { $0.kind == kind }?.total ?? 0 } ?? shareTotal
        return Chart(shares, id: \.kind) { share in
            SectorMark(angle: .value("Tokens", Double(share.total)), innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(by: .value("Type", share.kind.rawValue))
                .opacity(inspected == nil || inspected == share.kind ? 1 : 0.35)
        }
        .chartForegroundStyleScale(domain: TokenKind.allCases.map(\.rawValue), range: TokenKind.allCases.map(\.color))
        .chartLegend(.hidden)
        .chartAngleSelection(value: $angleSelection)
        .overlay {
            VStack(spacing: 1) {
                Text(inspected == nil ? compactCount(shareTotal) : percent(center)).font(.title2.weight(.semibold).monospacedDigit())
                Text(inspected.map { "\($0.rawValue) · \(compactCount(center))" } ?? "tokens")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(height: 170)
        .accessibilityLabel("Token usage by type")
        .accessibilityValue(shares.map { "\($0.kind.rawValue) \(percent($0.total))" }.joined(separator: ", "))
    }

    private var legend: some View {
        let day = selectedDay
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
            ForEach(TokenKind.allCases) { kind in
                let total = day.map { kind.value(in: $0) } ?? days.reduce(0) { $0 + kind.value(in: $1) }
                HStack(spacing: 6) {
                    Circle().fill(kind.color).frame(width: 8, height: 8)
                    Text(kind.rawValue).font(.caption).foregroundStyle(.secondary)
                    if showsPie { Text(compactCount(total)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary) }
                    Spacer(minLength: 4)
                    Text(showsPie ? percent(total) : compactCount(total)).font(.caption.weight(.medium).monospacedDigit())
                }
            }
        }
    }
}
