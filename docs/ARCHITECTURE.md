# Project Architecture

`build.sh` recursively compiles every `.swift` file in `Sources/` and `Tests/`:

```text
Sources/
  App.swift                   # NSApplicationDelegate, status bar item, NSPopover, CLI test flags
  Dashboard.swift             # Main 398pt popover views, tabs, settings, connection flows
  Store.swift                 # DashboardStore (@MainActor state, refresh loop, persistence)
  Models.swift                # Account, JSON/date/number parsing helpers
  PreviewRenderer.swift       # Offscreen AppKit/SwiftUI preview generator (--render-previews)
  Charting/
    UsageChart.swift          # Swift Charts stacked bar & pie views (7d / 30d, Cost / Tokens)
  Providers/
    Shared/                   # SubscriptionClient (allowlisted HTTPS), Keychain, ProxyClient
    <Provider>/               # Provider-specific API clients, models, controls & views
    ProviderLogo.swift        # Template PNG icon loader
    ProviderTheme.swift       # Light/dark brand colors
  Usage/
    UsageModels.swift         # QuotaWindow, DailyUsage, UsageCosts, UsageSeries, UsageFact
    UsageParsing.swift        # Shared parser helpers
    Providers/<Provider>/     # Pure, deterministic JSON -> model parsers
    Shared/                   # ProxyUsageReader (CLIProxyAPI SQLite WAL reader)
  Diagnostics/
    LiveCheck.swift           # Explicit live diagnostics (--live-check)
Tests/
  SelfTests.swift             # Parser, quota, cost, pagination & logo tests (--self-test)
  TransportTests.swift        # Isolated URLProtocol HTTP fixture tests (--transport-tests)
  Providers/                  # Provider parser, cookie & logo tests
  Usage/                      # Proxy SQLite usage-history tests
```
