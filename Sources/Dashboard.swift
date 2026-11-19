import SwiftUI

private let accent = Color.accentColor
private let subscriptionAccent = Color.orange

private enum RankingCategory: String, CaseIterable, Identifiable {
    case models = "Models", apps = "Apps", tasks = "Tasks"
    var id: String { rawValue }
}

private enum RankingSource: String, CaseIterable, Identifiable {
    case openRouter = "OpenRouter", artificialAnalysis = "Artificial Analysis"
    var id: String { rawValue }
}

private func brandTint(for account: Account) -> Color {
    ProviderTheme.color(for: account.providerName) ?? (account.origin == .proxy ? accent : subscriptionAccent)
}

private extension View {
    /// Inset grouped surface that adapts to light/dark and sits on the popover's vibrancy.
    func card(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct Dashboard: View {
    @ObservedObject var store: DashboardStore
    var expanded = false
    @State private var rankingCategory = RankingCategory.models
    @State private var rankingPeriod = OpenRouterRankingPeriod.week
    @State private var rankingSource = RankingSource.openRouter
    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.settingsVisible && !store.connectionVisible {
                sectionPicker
                if store.section != .rankings { tabs }
            }
            Divider()
            if expanded { page }
            else { ScrollView { page }.frame(maxHeight: 490) }
            footer
        }
        .frame(width: 398)
        .background(expanded ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .clipped()
        .animation(.easeInOut(duration: 0.22), value: store.settingsVisible)
        .animation(.easeInOut(duration: 0.22), value: store.connectionVisible)
        .simultaneousGesture(DragGesture(minimumDistance: 45).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            if store.settingsVisible && value.translation.width > 60 { store.settingsVisible = false }
            else if store.connectionVisible && value.translation.width < -60 { store.closeConnectionSettings() }
            else if !store.settingsVisible && !store.connectionVisible {
                if value.translation.width > 60 { store.settingsVisible = true }
                else if value.translation.width < -60, store.section != .rankings, store.tab != "Overview", let account = store.selected,
                        let origin = account.origin == .proxy ? account.proxyOrigin : account.origin {
                    store.openConnectionSettings(origin)
                }
            }
        })
        .onReceive(NotificationCenter.default.publisher(for: .refreshBurndownBar)) { _ in
            Task { await store.refresh() }
        }
    }

    @ViewBuilder private var page: some View {
        if store.settingsVisible {
            settings.padding(16).transition(.move(edge: .trailing).combined(with: .opacity))
        } else if store.connectionVisible {
            connectionSettings.padding(16).transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            content.transition(.opacity)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = store.connectionError, store.section == .subscriptions,
               store.tab == "Overview" || store.selected?.origin == .proxy {
                notice(error, icon: "wifi.exclamationmark", color: .orange)
            }
            if store.section == .rankings {
                rankings
            } else if store.sectionAccounts.isEmpty {
                emptyState
            } else if store.tab == "Overview" {
                overview
            } else if let account = store.selected {
                accountDetail(account)
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("BurndownBar").font(.headline)
                    Text(AppIdentity.version).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
                HStack(spacing: 5) {
                    Circle().fill(store.healthyCount > 0 ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(store.refreshing ? "Refreshing usage…" : store.lastRefresh == nil ? "Connecting to accounts…" : "\(store.healthyCount) of \(store.accounts.count) accounts connected")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.refreshing { ProgressView().controlSize(.small) }
            Button {
                store.connectionVisible = false
                store.settingsVisible.toggle()
            } label: {
                Image(systemName: "gearshape").symbolVariant(store.settingsVisible ? .fill : .none)
                    .font(.system(size: 14)).foregroundStyle(store.settingsVisible ? accent : Color.secondary)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }.buttonStyle(.borderless).help("Global preferences").accessibilityLabel("Settings")
        }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
    }

    private var sectionPicker: some View {
        Picker("Dashboard section", selection: Binding(
            get: { store.section }, set: { store.selectSection($0) })) {
                ForEach(DashboardSection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.bottom, 10)
    }

    private var tabs: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 2)], spacing: 2) {
            ForEach(["Overview"] + store.providers, id: \.self) { tab in
                let selected = store.tab == tab
                Button { store.tab = tab } label: {
                    VStack(spacing: 4) {
                        let brand = ProviderTheme.color(for: tab) ?? Color.secondary
                        let progress = tabProgress(tab)
                        ProviderLogo(provider: tab, size: 20)
                            .foregroundStyle(brand.opacity(selected ? 1 : 0.75))
                            .frame(width: 32, height: 32)
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(brand.opacity(0.2), lineWidth: 2)
                                if let progress {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .trim(from: 0, to: max(0.02, progress.fraction))
                                        .stroke(progress.stale ? Color.gray : brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(progress.map { "\(Int($0.fraction * 100))% remaining" } ?? "No usage data")
                        Text(tab).font(.caption).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .background(selected ? Color.primary.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }.buttonStyle(.plain).accessibilityLabel("\(tab) tab")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(.horizontal, 10).padding(.bottom, 10)
    }

    /// Lowest remaining quota among a tab's accounts, drawn as a frame around its icon.
    private func tabProgress(_ tab: String) -> (fraction: Double, stale: Bool)? {
        let accounts = store.sectionAccounts.filter { !$0.disabled && (tab == "Overview" || $0.providerName == tab) }
        let values = accounts.compactMap { account in account.minimum.map { (value: $0, stale: store.isStale(account)) } }
        guard let lowest = values.min(by: { $0.value < $1.value }) else { return nil }
        return (max(0, min(1, lowest.value / 100)), values.allSatisfy(\.stale))
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.section == .inference ? "Inference providers" : "Subscriptions").font(.headline)
                Spacer()
                Text("\(store.sectionAccounts.filter { !store.isStale($0) && $0.updatedAt != nil && !$0.disabled }.count) of \(store.sectionAccounts.count) ready")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.sectionAccounts) { account in
                let tint = brandTint(for: account)
                Button { store.select(account) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ProviderLogo(provider: account.providerName, size: 17)
                                .foregroundStyle(tint)
                                .frame(width: 30, height: 30).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.displayEmail(account)).font(.callout.weight(.medium)).lineLimit(1)
                                Text("\(account.providerName) · \(account.plan)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        if let error = account.error {
                            Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.leading)
                        }
                        if account.windows.isEmpty && account.error == nil && account.facts.isEmpty {
                            Text("Fetching quota…").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(account.keyWindows) { window in
                            quotaBar(window, compact: true, stale: store.isStale(account), tint: tint)
                        }
                        ForEach(Array(account.facts.prefix(2))) { fact in
                            HStack { Text(fact.label); Spacer(); Text(fact.value).multilineTextAlignment(.trailing) }
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .card(padding: 12)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).help("View quota details for \(store.displayEmail(account))")
            }
            Label("Updates every \(store.interval / 60) min · click an account for details", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(.tertiary).padding(.top, 2)
        }
    }

    private var rankings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Ranking source", selection: $rankingSource) {
                ForEach(RankingSource.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if rankingSource == .openRouter { openRouterRankings }
            else { ArtificialAnalysisChartsView(store: store) }
        }
    }

    private var openRouterRankings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("OpenRouter Rankings").font(.headline)
                Spacer()
                Link("Full rankings", destination: URL(string: "https://openrouter.ai/rankings")!)
                    .font(.caption)
            }
            Text("Global model popularity by tokens processed on OpenRouter.")
                .font(.caption).foregroundStyle(.secondary)
            if let snapshot = store.accounts.first(where: { $0.origin == .openrouter })?.openRouter?.rankings,
               !snapshot.isEmpty {
                Picker("Ranking category", selection: $rankingCategory) {
                    ForEach(RankingCategory.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                switch rankingCategory {
                case .models:
                    Picker("Ranking period", selection: $rankingPeriod) {
                        ForEach(OpenRouterRankingPeriod.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("Models ranked by tokens in the most recent complete \(rankingPeriod == .today ? "day" : rankingPeriod == .week ? "7 days" : "30 days").")
                        .font(.caption).foregroundStyle(.secondary)
                    let models = snapshot.models(for: rankingPeriod)
                    if models.isEmpty {
                        Text("No model ranking data for this period.").font(.callout).foregroundStyle(.secondary).card()
                    } else {
                        ForEach(Array(models.prefix(10).enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)").font(.callout.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.model.split(separator: "/", maxSplits: 1).last.map(String.init) ?? item.model)
                                        .font(.callout.weight(.medium)).lineLimit(2)
                                    Text(item.model.split(separator: "/").first.map(String.init) ?? "OpenRouter")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("\(compactCount(item.totalTokens)) tokens")
                                        .font(.callout.weight(.semibold).monospacedDigit())
                                    if let change = item.changePercent {
                                        Text(change > 999 ? ">999%" : String(format: "%+.0f%%", change))
                                            .font(.caption).foregroundStyle(change >= 0 ? Color.green : Color.orange)
                                    }
                                }
                            }.card(padding: 10)
                        }
                    }
                case .apps:
                    ForEach(snapshot.topApps.prefix(10)) { item in
                        HStack(spacing: 10) {
                            Text("\(item.rank)").font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
                            Text(item.name).font(.callout.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text("\(compactCount(item.totalTokens)) tokens").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.card(padding: 10)
                    }
                    if snapshot.topApps.isEmpty { Text("No app ranking data available.").font(.callout).foregroundStyle(.secondary) }
                case .tasks:
                    ForEach(snapshot.taskShares) { item in
                        HStack {
                            Text(item.name).font(.callout.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f%% of tokens", item.tokenSharePercent))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.card(padding: 10)
                    }
                    if snapshot.taskShares.isEmpty { Text("No task ranking data available.").font(.callout).foregroundStyle(.secondary) }
                }
                Text("Source: OpenRouter (openrouter.ai/rankings)\(snapshot.asOf.map { ", as of \($0)" } ?? ""). Licensed under CC BY 4.0.")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("Connect OpenRouter with an API key to load global model rankings.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open OpenRouter connection") { store.openConnectionSettings(.openrouter) }
            }
        }
    }

    private func accountDetail(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProviderLogo(provider: account.providerName, size: 22)
                    Text(account.providerName).font(.title2.weight(.semibold))
                    Spacer()
                    if account.origin == .proxy {
                        Text(account.plan).font(.caption.weight(.medium)).foregroundStyle(brandTint(for: account))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(brandTint(for: account).opacity(0.14), in: Capsule())
                    } else {
                        Button { Task { await store.refresh() } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 13)).foregroundStyle(.secondary)
                        }.buttonStyle(.borderless).disabled(store.refreshing).accessibilityLabel("Refresh \(account.providerName)")
                    }
                }
                if store.filtered.count > 1 {
                    Menu {
                        ForEach(store.filtered) { item in
                            Button { store.selectedID = item.id } label: {
                                if item.id == account.id { Label(store.displayEmail(item), systemImage: "checkmark") }
                                else { Text(store.displayEmail(item)) }
                            }
                        }
                    } label: {
                        Text(store.displayEmail(account)).lineLimit(1)
                    }.menuStyle(.button).fixedSize()
                    .accessibilityLabel("Switch account")
                } else {
                    Text(store.displayEmail(account)).font(.callout).foregroundStyle(.secondary)
                }
                if let updated = account.updatedAt {
                    Text("Updated \(updatedLabel(updated))\(store.isStale(account) ? " · stale data" : "")")
                        .font(.caption).foregroundStyle(store.isStale(account) ? Color.orange : Color.secondary)
                }
            }
            if let details = account.details { providerMetadata(account, details: details) }
            if let warning = account.details?.warning { notice(warning, icon: "info.circle", color: .orange) }
            if let error = account.error { notice(error, icon: "exclamationmark.triangle", color: .orange) }
            if account.windows.isEmpty && account.error == nil && account.facts.isEmpty {
                Text("Fetching quota…").font(.callout).foregroundStyle(.secondary)
            }
            if !account.windows.isEmpty {
                Text("Usage").font(.headline)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(account.windows.enumerated()), id: \.element.id) { index, window in
                    VStack(alignment: .leading, spacing: 8) {
                        quotaBar(window, compact: false, stale: store.isStale(account), tint: brandTint(for: account))
                        if !store.isStale(account), let pace = window.pace(now: store.now) {
                            Label(pace.text, systemImage: pace.healthy ? "checkmark.circle" : "chart.line.uptrend.xyaxis")
                                .font(.caption).foregroundStyle(pace.healthy ? Color.secondary : Color.orange)
                        }
                    }.padding(.vertical, 12)
                    if index < account.windows.count - 1 { Divider() }
                }
                if let costs = account.costs { costRows(costs) }
                if let balance = account.details?.extraBalanceUSD {
                    Divider()
                    HStack {
                        Text(account.provider == "xai" || account.provider == "grok" ? "Prepaid balance" : "Extra usage").font(.callout.weight(.medium))
                        Spacer()
                        Text("Balance: \(balance.formatted(.currency(code: "USD")))").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
                if !account.facts.isEmpty {
                    ForEach(account.facts) { fact in
                        metadataRow(fact.label, value: fact.value, last: fact.id == account.facts.last?.id)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(Color.primary.opacity(account.windows.isEmpty && account.facts.isEmpty && account.costs == nil ? 0 : 0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(account.windows.isEmpty && account.facts.isEmpty && account.costs == nil ? 0 : 0.08)))
            let series = usageSeries(for: account)
            if !series.isEmpty {
                UsageChart(series: series, tint: brandTint(for: account))
                    .id(account.id).card(padding: 14)
            }
            if let snapshot = account.openRouter {
                OpenRouterInsightsView(snapshot: snapshot, tint: brandTint(for: account), store: store)
            }
            if let credits = account.credits, account.details?.extraBalanceUSD == nil {
                HStack {
                    Label("Credit balance", systemImage: "circle.hexagongrid").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(credits).font(.callout.weight(.semibold).monospacedDigit())
                }.card(padding: 12)
            }
            if let origin = account.origin == .proxy ? account.proxyOrigin : account.origin {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Provider settings").font(.headline)
                    Button { store.openConnectionSettings(origin) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.left").frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Connection").font(.callout.weight(.medium))
                                Text("Manage \(account.providerName) sign-in").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Open \(account.providerName) connection settings")
                    .card()
                }
            }
        }
    }

    private func usageSeries(for account: Account) -> [UsageSeries] {
        var result = [UsageSeries]()
        if let costs = account.costs {
            result.append(UsageSeries(id: "usage-events", title: account.openRouter != nil ? "All Keys (Account)" : "\(account.providerName) usage events", daily: costs.daily, hasCost: true))
        }
        if let keySeries = account.openRouter?.keySeries {
            result += keySeries
        }
        result += store.localUsage[account.providerName] ?? []
        return result.filter(\.hasData)
    }

    private func quotaBar(_ window: QuotaWindow, compact: Bool, stale: Bool, tint: Color = accent) -> some View {
        let color: Color = stale ? .gray : (window.remaining ?? 100) <= 10 ? .red : (window.remaining ?? 100) <= 25 ? .orange : tint
        return VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(compact ? .callout : .body.weight(.medium))
                Spacer()
                Text("\(window.percent) left").font((compact ? Font.callout : .body).weight(.semibold).monospacedDigit()).foregroundStyle(color)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    if let remaining = window.remaining {
                        Capsule().fill(color.gradient).frame(width: max(0, geometry.size.width * remaining / 100))
                    }
                    if !compact, let period = window.period, let reset = window.reset, reset > store.now {
                        let fraction = min(1, max(0, reset.timeIntervalSince(store.now) / period))
                        Capsule().fill(stale ? Color.gray : Color.green).frame(width: 2.5, height: 11)
                            .overlay(Capsule().strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.6), lineWidth: 0.5))
                            .offset(x: min(max(0, geometry.size.width - 2.5), geometry.size.width * fraction))
                    }
                }
            }.frame(height: compact ? 5 : 7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.title): \(window.percent) remaining")
            Text(window.resetLabel(now: store.now)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func settingToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 24, height: 24)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.frame(minHeight: 30)
    }

    private func pageTitle(_ title: String, backEdge: Edge, backLabel: String = "Back to usage", action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: backEdge == .leading ? "arrow.left" : "arrow.right")
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(backLabel)
            Text(title).font(.headline)
            Spacer()
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageTitle("Preferences", backEdge: .leading) { store.settingsVisible = false }
            VStack(alignment: .leading, spacing: 10) {
                Text("Privacy").font(.headline)
                settingToggle("Hide account emails", icon: "eye.slash", isOn: $store.privacy)
            }.card(padding: 14)
            VStack(alignment: .leading, spacing: 10) {
                Text("Show providers").font(.headline)
                Grid(horizontalSpacing: 10, verticalSpacing: 12) {
                    ForEach([AccountOrigin.cursor, .factory] + AccountOrigin.additional, id: \.rawValue) { origin in
                        GridRow {
                            Button { store.openConnectionSettings(origin) } label: {
                                HStack(spacing: 10) {
                                    ProviderLogo(provider: origin.title, size: 18)
                                        .foregroundStyle(ProviderTheme.color(for: origin.title) ?? .secondary)
                                        .frame(width: 24, height: 24)
                                    Text("Show \(origin.title)")
                                    Circle()
                                        .fill(store.isProviderConnected(origin) ? Color.green : Color.secondary.opacity(0.45))
                                        .frame(width: 6, height: 6)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(origin.title) connection settings")
                            .accessibilityValue(store.isProviderConnected(origin) ? "Connected" : "Not connected")
                            .help("\(store.isProviderConnected(origin) ? "Connected" : "Not connected") · Open \(origin.title) connection settings")
                            Toggle("Show \(origin.title)", isOn: enabledBinding(origin))
                                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        }
                    }
                }
            }.card(padding: 14)
            VStack(alignment: .leading, spacing: 10) {
                Text("Quota source").font(.headline)
                Picker("Quota source", selection: Binding(get: { store.sharedQuotaSource }, set: { store.setQuotaSource($0) })) {
                    ForEach(QuotaSource.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.segmented)
                if store.sharedQuotaSource == .proxy {
                    Text("Choose CLIProxyAPI or Direct for each provider.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(AccountOrigin.proxyCapable, id: \.rawValue) { origin in
                        HStack(spacing: 10) {
                            ProviderLogo(provider: origin.title, size: 18).frame(width: 24, height: 24)
                            Text(origin.title)
                            Spacer()
                            Picker("\(origin.title) quota source", selection: Binding(
                                get: { store.quotaSource(for: origin) },
                                set: { store.setQuotaSource($0, for: origin) })) {
                                    ForEach(QuotaSource.allCases) { Text($0.title).tag($0) }
                                }
                            .labelsHidden().pickerStyle(.segmented).frame(width: 175)
                        }
                    }
                } else {
                    Text("Codex, Grok and Claude connect directly.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.card(padding: 14)
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise").foregroundStyle(.secondary).frame(width: 24)
                Text("Refresh every")
                Spacer()
                Picker("Refresh interval", selection: $store.interval) {
                    ForEach([60, 120, 300, 600], id: \.self) { Text("\($0 / 60) min").tag($0) }
                }.labelsHidden().frame(width: 100)
            }.card(padding: 14)
            VStack(alignment: .leading, spacing: 10) {
                Text("Developer mode").font(.headline)
                settingToggle("Allow rebuild while running", icon: "hammer", isOn: $store.developerMode)
                Text("Builds a replacement app bundle while this copy stays open. Relaunch to use the new build.")
                    .font(.caption).foregroundStyle(.secondary)
            }.card(padding: 14)
        }.font(.callout)
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageTitle("\(store.connectionProvider.title) connection", backEdge: .trailing,
                      backLabel: store.connectionReturnsToPreferences ? "Back to Preferences" : "Back to usage") {
                store.closeConnectionSettings()
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ProviderLogo(provider: store.connectionProvider.title, size: 18).frame(width: 24, height: 24)
                    Text(store.connectionProvider.title).font(.headline)
                    Spacer()
                    Text(connectionUsesProxy ? "CLIProxyAPI" : "Direct").font(.caption).foregroundStyle(.secondary)
                }
                if store.connectionProvider == .cursor {
                    Picker("Cursor source", selection: $store.cursorSource) {
                        Text("Default browser (cookies)").tag("browser")
                        Text("Manual cookie").tag("manual")
                        Text("Desktop sign-in").tag("desktop")
                    }.onChange(of: store.cursorSource) {
                        store.cancelSignIn()
                        Task { await store.refresh() }
                    }
                }
                Text(connectionInstructions).font(.caption).foregroundStyle(.secondary)
                Button(signInButtonTitle) {
                    store.connect(store.connectionProvider)
                }.disabled(store.signingIn)
                if let code = store.githubCode {
                    Text(code).font(.system(.title3, design: .monospaced).weight(.semibold)).textSelection(.enabled)
                    Button("Cancel GitHub sign-in") { store.cancelSignIn() }
                }
                if store.signingIn && store.githubCode == nil {
                    ProgressView().controlSize(.small)
                    Button("Cancel sign-in") { store.cancelSignIn() }
                }
                if store.connectionProvider != .antigravity && !connectionUsesProxy && !(store.connectionProvider == .cursor && store.cursorSource != "manual") {
                    if ![AccountOrigin.copilot, .grok, .codex, .openrouter].contains(store.connectionProvider) {
                        Text(store.connectionProvider == .cursor ? "Paste your Cursor cookie below, or choose Default browser (cookies) to import it automatically." : "Sign in in your default browser, then paste its Cookie header below. Browser cookies are not imported automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("How to copy the Cookie header") {
                            Text("In your browser's developer tools, open Network and reload the signed-in account page. Select a request to the provider, open Request Headers, and copy the Cookie value. Paste it below and choose Save & connect.")
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }.font(.caption)
                    }
                    if store.connectionProvider == .openrouter {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Management API Key").font(.caption.weight(.medium))
                                Spacer()
                                if store.openRouterHasManagementKey {
                                    Text("Saved").font(.caption2).foregroundStyle(.green)
                                }
                            }
                            SecureField("Credits, 30d analytics & key caps", text: $store.connectionCredential)
                                .textFieldStyle(.roundedBorder).accessibilityLabel("OpenRouter Management API Key")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Standard API Key (optional)").font(.caption.weight(.medium))
                                Spacer()
                                if store.openRouterHasStandardKey {
                                    Text("Saved").font(.caption2).foregroundStyle(.green)
                                }
                            }
                            SecureField("Global rankings, Top Apps & task share", text: $store.openRouterStandardKey)
                                .textFieldStyle(.roundedBorder).accessibilityLabel("OpenRouter Standard API Key")
                        }
                        Button("Save & connect") { store.saveConnectionCredential() }
                            .disabled(store.connectionCredential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      && store.openRouterStandardKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        if [.cursor, .claude].contains(store.connectionProvider) {
                            Text("Cookie header or session token").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Toggle("Paste Cookie header", isOn: $store.connectionUsesCookie).toggleStyle(.checkbox)
                                .disabled([AccountOrigin.copilot, .grok, .codex].contains(store.connectionProvider))
                        }
                        SecureField(store.connectionUsesCookie || [.cursor, .claude].contains(store.connectionProvider) ? "Cookie header or session token" : "API key or access token", text: $store.connectionCredential)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Provider credential")
                        Button("Save & connect") { store.saveConnectionCredential() }
                            .disabled(store.connectionCredential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if store.connectionProvider == .opencode {
                    TextField("Workspace ID (optional)", text: $store.workspaceID).textFieldStyle(.roundedBorder)
                }
                if let message = store.signInMessage { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }.font(.callout).card(padding: 14)
        }
    }


    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.refreshing ? "antenna.radiowaves.left.and.right" : "person.crop.circle.badge.plus")
                .font(.system(size: 30, weight: .light)).foregroundStyle(.secondary).padding(.top, 14)
            Text(store.refreshing ? "Connecting to accounts…" : store.section == .inference ? "No inference providers to show" : "No subscriptions to show")
                .font(.headline)
            Text(store.refreshing ? "Looking up your accounts and quotas…" : store.section == .inference
                 ? "Show OpenRouter in Preferences, then connect an API key."
                 : "Show a subscription provider in Preferences, then connect its account.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Preferences") { store.settingsVisible = true }.padding(.bottom, 14)
        }.frame(maxWidth: .infinity)
    }

    private func notice(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.callout)
            Text(text).font(.caption).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(color).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button { Task { await store.refresh() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise").font(.callout)
                }.buttonStyle(.borderless).disabled(store.refreshing).keyboardShortcut("r", modifiers: .command)
                    .help("Refresh (⌘R)")
                Spacer()
                Button { store.openProxy() } label: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 14))
                }.buttonStyle(.borderless).help("Open CLIProxyAPI").accessibilityLabel("Open CLIProxyAPI")
                Menu {
                    Text("BurndownBar \(AppIdentity.version)")
                    Divider()
                    Button("Open CLIProxyAPI") { store.openProxy() }
                    Button("Quit BurndownBar") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 14)).frame(width: 18) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("More options")
            }.foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(expanded ? AnyShapeStyle(Color.primary.opacity(0.04)) : AnyShapeStyle(.bar))
    }

    private func updatedLabel(_ date: Date) -> String {
        let seconds = store.now.timeIntervalSince(date)
        return seconds < 60 ? "just now" : "\(duration(seconds)) ago"
    }

    private func providerMetadata(_ account: Account, details: ProviderDetails) -> some View {
        VStack(spacing: 0) {
            metadataRow("Source", value: details.source)
            metadataRow("Version", value: details.version ?? "Not detected")
            metadataRow("Updated", value: account.updatedAt.map(updatedLabel) ?? "Not yet fetched")
            metadataRow("Status", value: details.status ?? "Unavailable", warning: details.statusIndicator.map { $0 != "none" } ?? false)
            metadataRow("Plan", value: account.plan, last: true)
        }.padding(.horizontal, 12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .contextMenu {
            Button("Open \(account.providerName) usage dashboard") { store.openDashboard(account) }
        }
    }
    private func metadataRow(_ label: String, value: String, warning: Bool = false, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label).font(.callout)
                Spacer(minLength: 4)
                Text(value).font(.callout).foregroundStyle(warning ? Color.orange : Color.secondary)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 8)
            if !last { Divider() }
        }
    }
    private func costRows(_ costs: UsageCosts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("Cost").font(.callout.weight(.medium))
                Spacer()
                Text("Today: \(costs.today.label)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Last 30 days: \(costs.last30Days.label)").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("API-rate cost · updated \(updatedLabel(costs.updatedAt))").font(.caption2).foregroundStyle(.tertiary)
            if let warning = costs.warning { Text(warning).font(.caption2).foregroundStyle(.orange) }
        }.padding(.bottom, 12)
    }
    private func enabledBinding(_ origin: AccountOrigin) -> Binding<Bool> {
        Binding(get: { store.isEnabled(origin) }, set: { store.setEnabled(origin, $0) })
    }
    private var connectionUsesProxy: Bool {
        store.connectionProvider.supportsProxy && store.quotaSource(for: store.connectionProvider) == .proxy
    }
    private var connectionInstructions: String {
        if connectionUsesProxy {
            return "\(store.connectionProvider.title) is read from CLIProxyAPI. Sign in to it there; set this provider to Direct in Preferences → Quota source to connect here instead."
        }
        switch store.connectionProvider {
        case .codex: return "Reads the Codex CLI's sign-in (~/.codex/auth.json) without changing it, or paste an access token below."
        case .copilot: return "Authorize a new GitHub device sign-in. The code appears here; finish approval in your browser."
        case .warp: return "Open Warp in your default browser to sign in, or use a Warp API key if browser cookies cannot read usage."
        case .antigravity: return "Sign into the Antigravity app. Quotas are read from its authenticated local Connect API."
        case .grok: return "Grok billing requires a Grok CLI access token; cookie-only billing is no longer supported by Grok."
        case .opencode: return "Open the OpenCode Console in your default browser, or paste a Go API key. Choose a workspace ID if needed."
        case .zed: return "Use your default browser's Zed sign-in and save its Cookie header to read predictions and token spend. The editor's Keychain is not accessed."
        case .factory: return "Open Factory in your default browser, or paste your Factory API key."
        case .cursor:
            switch store.cursorSource {
            case "browser": return "Cursor's session cookie is imported automatically from your default browser's current profile. Connect once to allow Keychain access if macOS asks, then usage refreshes automatically."
            case "desktop": return "Reads Cursor.app's local sign-in. Sign into the editor, then refresh."
            default: return "Paste a Cookie header or WorkosCursorSessionToken value and choose Save & connect."
            }
        case .claude: return "Open Claude in your default browser and save its Cookie header to read subscription quotas."
        case .openrouter: return "Add both keys for full insights: a Management Key (credits, 30d tokens/cache & key caps) and a Standard API Key (global rankings, Top Apps & task share)."
        default: return ""
        }
    }
    private var signInButtonTitle: String {
        if connectionUsesProxy { return "Open CLIProxyAPI" }
        switch store.connectionProvider {
        case .codex: return "Check Codex CLI sign-in"
        case .openrouter: return "Open OpenRouter management keys"
        case .copilot: return "Sign in with GitHub"
        case .antigravity: return "Open Antigravity to sign in"
        case .cursor where store.cursorSource == "desktop": return "Open Cursor to sign in"
        case .cursor where store.cursorSource == "browser": return "Connect from default browser"
        default: return "Open \(store.connectionProvider.title) in default browser"
        }
    }
}

extension Notification.Name { static let refreshBurndownBar = Notification.Name("refreshBurndownBar") }
