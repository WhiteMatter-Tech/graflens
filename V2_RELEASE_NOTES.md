# GrafLens 2.0

Version: **2.0**, build **2000**, for both the app and its iOS widget extension.

## Interface and charts

- Redesigned panel cards with restrained borders, clearer readings, wrapping titles, accessible action controls, and explicit expansion.
- Native Swift Charts for supported Prometheus time-series and stat panels, plus native gauges with configured bounds. Time-series charts offer stable series colors, solid/dashed lines, legend toggles, a crosshair, an accessible reading slider, and annotation details.
- Null samples break chart paths instead of becoming zeros or connecting across missing observations. Isolated readings remain visible.
- Built-in Grafana dashboard annotations appear as markers or time regions on supported native time-series charts.
- Adaptive rows use compact metric tiles and wider charts on iPad/Mac. Dashboard section headings and text panels are retained.
- Number panels (`stat` and legacy `singlestat`) use 108-point overview tiles: two columns on phones and up to four on wider layouts. Native stats use a 32-point value and a subtle threshold-color accent; sparklines appear only when configured and the readings vary. Tapping a tile expands it, and a corner menu retains refresh, sharing, and details. Timestamps and time ranges move into details and expanded views. Grafana-rendered stats preserve their original value mappings and visual styling in a fitted viewport. Accessibility text sizes use full-width cards.
- Supported native gauges use 130-point overview tiles with a value, thin bounded progress bar, and minimum/maximum labels; expanded views retain the dial. Unsupported gauge configurations keep Grafana rendering.
- Tables and logs use 180-point previews with explicit View all rows / View logs actions. Time-series previews retain a 200-point native plot, tighter spacing, and up to two legend entries, with access to all series, annotations, and the reading inspector in the expanded view. Maps, heatmaps, and complex panels keep larger rendering areas.
- Grafana panels retain their own title without a second title above it. Their web content can scroll; full-screen views have previous/next navigation and time-range controls.
- Dashboard search includes folders and tags, with a useful no-results state. Favorites have larger controls; favorites are excluded from recents. Alert views distinguish missing rules from no firing alerts and show the last successful check.

## Correctness and reliability

- Every dashboard panel starts loading when the dashboard opens, including panels below the visible area. Native queries run concurrently, and embedded Grafana pages begin loading as soon as their card has valid dimensions. Dashboard refreshes also reach every panel without scrolling.
- Embedded pages receive the full card viewport, without a second safe-area inset. A dedicated host protects cached pages when card layouts change. Loading stays visible until the page contains visible content; an empty page or terminated web process gets at most one automatic recovery per request, followed by a retry action if needed. Scrolling does not reset the retry limit.
- Dashboard panels keep their native results and live Grafana pages in memory while the dashboard is open. Scrolling offscreen and back preserves loaded content and interactive web state without restarting requests, including loads still in progress. Expanded views keep their own cache while browsing between panels. Each panel retains only its current request; refreshes, time-range, appearance, configuration, server, and sign-in changes invalidate it. Removed panels and closed screens release their sessions.
- API authentication errors distinguish HTTP 401/403 failures, browser sign-in pages, and unexpected HTML responses. They explain that either Grafana or a sign-in proxy can reject a request and that browser sessions do not currently authenticate native API requests. Connection help specifies Grafana service-account tokens; token-prefix and version-based warnings have been removed. Diagnostics do not display response bodies or redirect query values.
- Metadata edits retain the complete dashboard document, including graph settings, query fields, variables, transformations, and version information. Saves use version protection instead of forced overwrites.
- Panel requests respond to time range, appearance, authentication, and manual refresh changes. Optional 30-second, one-minute, and five-minute refresh pauses when the app leaves the foreground.
- Obsolete loads cannot replace a more recent load. Switching servers recreates the browsing/navigation state. Favorites, recents, authentication indicators, and widget caches are scoped to the connection.
- Sharing captures the current panel on demand, displays preparation state, and rejects images from obsolete requests. Native panels export high-resolution images.
- Native chart snapshots are cached automatically for widgets in dark appearance. Web panels can use an image shared from the app in dark mode or Grafana's image-renderer endpoint. Widget snapshots are scoped by connection, dashboard, panel, range, and theme; snapshots older than 15 minutes are rejected. Widgets show capture time and fit the image without cropping axes.
- The iOS widget is excluded from Mac Catalyst embedding, fixing a pre-existing Mac packaging failure.

## Native rendering boundaries

Native rendering is deliberately conservative. It currently supports Prometheus range queries with explicit datasource references, supported units, linear unstacked time-series charts, single-series stats using `last` or `lastNotNull`, and gauges with explicit minimum and maximum values. Built-in dashboard annotations are supported; custom annotation queries retain Grafana rendering.

Variable references, transformations, field overrides, value mappings, unsupported units/colors/scales/reducers, complex query shapes, and other panel types—including bar charts, tables, maps, and logs—use Grafana. An unrelated dashboard variable does not disable an otherwise supported panel. Users can force Grafana rendering or open the original panel from the panel menu. Unsupported or failed native queries also fall back to Grafana.

A web panel's footer says **Page loaded** after visible page content appears; this does not prove Grafana's asynchronous data queries have finished. Native footers show the successful query update time. Neither is labeled as guaranteed live data.

Existing widgets need their dashboard and panel reselected after this upgrade because widget identifiers now include the server. Unscoped snapshots are not reused across connections.

## Validation

- 59 passing Foundation regression checks: dashboard round trips, version protection, section preservation, rendering eligibility, annotations, schema-aware numeric fields, null gaps, query errors, number formatting, time-range parsing, and authentication-response classification.
- Authentication HTTP integration: successful JSON, a rejected credential, a followed browser-login redirect, POST permission denial, and an HTML DELETE response. Run `Tests/run-auth-error-tests.sh`; its isolated fixture uses localhost port 18768. These checks do not replace testing a live Authentik deployment.
- Local API integration: five-minute and six-hour requests, multi-series decoding, gaps, template fallback, and embed URL range/theme parameters.
- 37 simulator panel-cache and rendering checks: repeated appearances produce no extra native or web requests; in-flight loads finish offscreen; interactive web state survives reattachment; refresh and request changes invalidate cached content; superseded requests cannot overwrite newer results; closing a screen releases its sessions and pages; delayed rendering, bounded blank-page recovery, simulated process termination callbacks, viewport sizing, and replacement-host ownership are verified. Run `Tests/run-panel-cache-tests.sh` with a booted simulator (optionally set `SIMULATOR_ID`). The harness uses an isolated localhost fixture on port 18765 and removes its test app afterward.
- Large-dashboard check: all 76 locally simulated embedded panels render without scrolling, begin with positive viewport dimensions, and load exactly once even after the readiness timeout. Run `Tests/run-web-panel-stress-tests.sh` after building the Debug simulator app. It uses localhost port 18767. This is a lightweight viewport-sensitive fixture, not a reproduction of the reported live Grafana dashboard.
- Actual-app startup check: all six native fixture panels and the embedded Grafana panel load without scrolling, with six overlapping native requests and no duplicate requests after settling. Run `Tests/run-dashboard-load-tests.sh` after building the Debug simulator app; optionally set `APP_PATH` and `SIMULATOR_ID`. This check also uses localhost port 18765, so run it separately from the cache harness.
- Builds: iOS Simulator Debug, unsigned iOS Release, and unsigned Mac Catalyst Release.
- Visual checks: iPhone and iPad simulator captures using illustrative local fixtures, in light and dark appearance. These are not live-server or authenticated OIDC acceptance tests. The desktop UI automation connector could not access Simulator, so manual gesture/menu interaction was not verified through that connector.
- Compact number-panel previews: `python3 Tests/compact_panel_fixture.py` serves four illustrative Grafana-style counters, three native stats (including a long title), a bounded gauge, table and log previews, and a time-series graph on localhost port 18766. Launch the Debug app with `--fixture-server http://127.0.0.1:18766 --fixture-dashboard`.

Run `Tests/run-regressions.sh` for the deterministic regression checks. For local API and simulator checks, start `python3 Tests/fixture_server.py`; it binds only to localhost and rejects dashboard writes. Compile `Tests/APIIntegrationTests.swift` with `GrafanaModels.swift`, `NativePanelData.swift`, and `GrafanaAPIClient.swift`, then run the resulting executable. Debug builds accept `--fixture-server http://127.0.0.1:18764 --fixture-dashboard` to open the fixture dashboard. The launch override is absent from Release builds.

No App Store submission, release signing, or live Grafana dashboard modification was performed.
