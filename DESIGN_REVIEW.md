# GrafLens design and functionality review

Reviewed September 28, 2026. Based on the supplied iPhone/iPad screenshots and the local Swift sources. This is a source and screenshot review, not a live authenticated device test. Application source files were not changed.

The largest visual improvement would come from giving charts more room and a consistent native presentation: one title, a clear current value where appropriate, restrained axes, readable legends, and useful inspection gestures. Keep the orange identity, but use it selectively for actions and chart emphasis. Support both light and dark appearance rather than making a dark theme the redesign itself.

## Priority findings

| Priority | Finding | Recommended change | Relative effort |
| --- | --- | --- | --- |
| P1 | Editing dashboard metadata drops graph configuration from the outgoing payload. | Preserve the complete dashboard JSON and update only edited fields; retain version checking. | Medium |
| P1 | Existing embedded graphs do not respond to time-range or theme changes. | Update the web view when its request identity changes; provide explicit refresh and loading/error state. | Small–medium |
| P1 | Switching servers can leave the previous dashboard list visible. | Scope tasks, navigation, and cached data to connection identity; cancel obsolete requests. | Medium |
| P2 | Native charts exist but are not used by the dashboard viewer. | Introduce native rendering for a deliberately supported subset, with a Grafana fallback. | Large |
| P2 | Repeated titles, type badges, and controls crowd the graphs. | Simplify panel headers, allow title wrapping, and consolidate secondary actions. | Small |
| P2 | iPad panels remain one full-width vertical stack. | Use an adaptive layout with compact stat tiles and wider trend panels. | Medium |
| P2 | Sharing depends on a delayed snapshot with no readiness feedback. | Capture on demand, show progress, and reject obsolete captures. | Medium |
| P2 | Widget snapshots lack server, time-range, and age identity. | Scope snapshots by connection and range and label capture time. | Medium |

### 1. Preserve graph configuration when editing

[DashboardEditView.swift:76](GrafLens/Views/DashboardEditView.swift#L76) constructs a replacement `DashboardSavePayload` and sends it with `overwrite: true`. The decoded models omit panel `fieldConfig`, `options`, `transformations`, query-specific properties, dashboard variables, schema version, and other configuration.

A local Swift serialization check confirmed that `fieldConfig`, `options`, `transformations`, `templating`, `schemaVersion`, the original `version`, and a target's `legendFormat` disappear from a representative dashboard payload. No server write was performed. This means a title change can send a dashboard that no longer contains its original graph settings. Preserve the original document, patch metadata, and retain concurrency/version protection. Add a round-trip regression test before shipping dashboard editing changes.

### 2. Make displayed data follow the controls

[PanelCardView.swift:257](GrafLens/Views/PanelCardView.swift#L257) has an empty `updateUIView`; `loadPanel` is called only from `makeUIView`. Updating the selected range or theme therefore does not reload an already mounted graph. The dashboard view provides no explicit graph refresh action or refresh schedule.

Track connection, dashboard, panel, range, theme, and refresh generation. Reload only when these change; cancel obsolete work. Show panel-specific loading and retry states. Show the last successful update time, and distinguish cached data from current data. A “Live” label should appear only when refresh actually runs.

### 3. Scope the experience to the active server

[DashboardListView.swift:60](GrafLens/Views/DashboardListView.swift#L60) loads only when its existing list is empty. The server switcher updates the connection without an accompanying connection-scoped list task or root identity reset. The source therefore permits a previous server's dashboards to remain visible after switching.

Reload on connection identity changes, clear invalid navigation, and prevent late responses from the old server replacing the new result. Include the connection in favorite, recent, panel-cache, and widget-cache identities. Verify switching between servers with matching dashboard UIDs.

## Recommended visual direction

**One clear chart card.** The screenshots show a native title above another Grafana title. Raw badges such as `timeseries` consume space without helping most viewing decisions. Remove that badge from the primary header, allow long titles up to two lines, and move share/details into a secondary menu. Make Expand a real, accessible button; the current expand image is not a button, while the outer card has a tap gesture that can compete with chart interactions.

**Charts as the focal point.** Use a consistent 2–2.5-point line weight, subtle horizontal grid lines, and a small number of readable ticks. Use a faint area gradient for a single highlighted series; avoid filling every overlapping series. Place units on the axis and values, and keep series colors stable when ordering changes. Use line patterns or symbols as well as color. Give legends short display names, latest values, and tap-to-isolate behavior while retaining full names in details.

**Beauty without changing the meaning.** Retain linear or stepped interpolation where appropriate; do not smooth operational spikes away or invent intermediate values. Honor explicit axis bounds, logarithmic scales, stacking, threshold rules, null gaps, units, decimals, and reduction functions. Keep a zero baseline for ordinary magnitude bars. If a native renderer cannot reproduce these settings, use Grafana. Swift Charts exposes interpolation choices, but the choice must follow the data: [Apple interpolation documentation](https://developer.apple.com/documentation/charts/chartcontent/interpolationmethod(_:)).

**Useful inspection.** Add a crosshair with timestamp and values for all visible series, touch scrubbing, and a keyboard/VoiceOver-accessible reading control. Keep inspection separate from expansion. On a fullscreen chart, provide time-range controls and readable series details. Preserve any source-defined thresholds and annotations.

**Responsive composition.** On phones, use one column with chart-specific heights instead of multiplying desktop grid height by 30. On iPad/Mac, place related stat tiles together and use two trend columns only when labels have enough room; allow tables and dense time series to span the width. Preserve dashboard row headings and explanatory text, which the current flattening/filtering loses. Respect Dynamic Type and multitasking widths.

**A calmer surface system.** Use neutral grouped backgrounds, subtle card borders, consistent spacing, and less shadow. Keep orange for navigation and emphasis; reserve red/amber/green status meaning for actual thresholds or health. Give large readings tabular digits and quieter units. Validate contrast in both appearances rather than applying a fixed palette globally.

## Native rendering: a staged implementation

The four views in `GrafLens/Views/NativeCharts` are compiled into the project, but the viewer always constructs `GrafanaPanelWebView`. Restyling these native files alone will not change the displayed dashboards.

Start with simple time-series and stat panels from one explicitly supported data source. Define capability checks that include query type, variables, transformations, units, overrides, stacking, axes, and reducers—not just panel type. Offer Grafana rendering when any required behavior is unsupported, and preserve the user's ability to open the original panel.

The existing `queryPanelValue` is not a general chart data pipeline: it requests instant Prometheus values, constructs a fixed six-hour range despite accepting range parameters, and assumes the last column contains values. Build schema-aware frame decoding that identifies time and numeric fields, retains labels and nulls, and handles multiple series and per-target data sources. Grafana's query API supports backend data sources and requires data-source-specific query properties: [Grafana query documentation](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/api-legacy/data_source/#query-a-data-source).

Before activating the dormant native components, correct their edge cases: selection state is declared but unused; multi-series area stacking is not explicitly controlled; stat/gauge base thresholds with null values are ignored; numeric formatting can convert non-finite or out-of-range values to integers; series identity and color assignment need stability. Test these as data correctness behavior, not merely appearance.

## Other functional polish

- Add a useful “No matching dashboards” state and search by folder as well as title/tags. Reduce repetition between favorites, recents, and the complete list.
- Distinguish “No rules configured,” “No firing alerts,” and “Could not load alerts.” Include the last successful check; avoid implying healthy monitoring when no rules exist.
- Make share and favorite controls easy to hit and explicitly labeled for accessibility. Disable or explain unavailable actions instead of silently doing nothing.
- For Grafana fallbacks, ensure tables can scroll and maps can be manipulated in fullscreen. The shared web view currently disables its scroll view; nested plugin scrolling needs device validation.
- Snapshots currently capture two seconds after navigation finishes, which does not establish that Grafana has finished loading data. Capture readiness, stale captures, theme changes, and panel switches need explicit handling.

## Suggested delivery order and validation

1. Fix metadata preservation, request updates, and server switching. Add focused regression coverage.
2. Simplify existing card chrome, introduce adaptive layouts, improve loading/error/share states, and add freshness feedback.
3. Build one complete native time-series path with inspection and a reliable Grafana fallback; then extend to stat, bar, and gauge panels.
4. Compare native values and rendering against reference Grafana panels. Exercise null gaps, negative/large values, units, thresholds, multiple fields, unsupported plugins, rapid range changes, expired sessions, offline use, dark/light appearance, large text, and iPhone/iPad/Catalyst sizes.

The accompanying design concept uses illustrative temperature data. It demonstrates one title, a prominent latest reading, quieter chart framing, differentiated series, legend toggles, and an accessible reading selector. It is a proposed treatment, not a screenshot of an implemented app change.
