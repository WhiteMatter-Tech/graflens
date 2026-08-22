# macOS Widget Support — Spec

Status: draft, awaiting review
Owner: gkesaev
Fork: `gkesaev/graflens` (upstream: `WhiteMatter-Tech/graflens`)

## Goal

Make `GrafLensWidget` available on macOS — both in Notification Center ("the side panel") and as a
Desktop widget — on top of the existing Mac Catalyst app, without requiring a paid Apple Developer
Program membership on this fork.

## Current state (verified against source, not assumed)

- `GrafLensWidget` only declares iOS/iPadOS as supported destinations. It has never run on macOS.
- The widget already has real per-instance configuration: `SelectPanelIntent`
  (`WidgetConfigurationIntent`) with `DashboardEntity`/`PanelEntity` (`AppEntity` +
  `EntityQuery`), letting each widget instance point at a different dashboard/panel/time range.
  This is a solid foundation — the work below extends it, not replaces it.
- `GrafLens/GrafLens.entitlements` and `GrafLensWidget/GrafLensWidget.entitlements` both currently
  declare an **empty** `com.apple.security.application-groups` array. They previously declared
  `group.tech.whitematter.graflens`; that got dropped when the bundle IDs were repointed from
  `tech.whitematter.*` to `com.georgek.*` for this fork's free-tier signing.
- `GrafLens/Services/SharedDataManager.swift:5` still hardcodes
  `appGroupID = "group.tech.whitematter.graflens"` — a stale reference to an App Group this fork no
  longer declares. Every `SharedDataManager` call (used by `ConnectionManager`,
  `DashboardListViewModel`, `DashboardDetailViewModel`, `PanelCardView`, and read by the widget)
  is currently a silent no-op on this fork.
- `ConnectionManager` only ever shares **one** connection to the widget — whatever is
  `activeConnection` — via `SharedDataManager.saveActiveConnection`. This is fine for this fork's
  actual use case (one machine, one Grafana instance at a time — confirmed with the project owner,
  not assumed) and is not something this spec changes.
- The main `GrafLens` app target currently has `SUPPORTS_MACCATALYST = NO` and no
  `maccatalyst`-specific bundle ID override, despite the README describing "Universal app - Runs on
  iPhone, iPad, and Mac (Catalyst)". There is currently no Mac-capable host app for a widget to
  attach to at all.
- Confirmed via Apple's own documentation and multiple independent sources: a free Apple ID
  ("Personal Team") **cannot** provision App Groups or cross-target Keychain Sharing. Both require a
  paid Apple Developer Program membership ($99/yr). This fork is on a free Personal Team.
- `SharedDataManager.saveActiveConnection` JSON-encodes the entire `ServerConnection` — including
  `apiKey` in plaintext — into the shared App Group `UserDefaults` suite. This is a real
  at-rest security gap independent of everything else in this spec (flagged in an earlier review).
- The widget's timeline refresh policy (`PanelWidgetProvider.timeline`, 15-minute `.after()`) is
  already reasonable. No change needed there.

## Key design decision: dual-mode connection source

The widget needs Grafana connection details (URL, token) and, ideally, cached dashboard/panel
lists and a rendered panel snapshot. Today it gets all of that from the main app via
`SharedDataManager` (App Group). That mechanism is unavailable on this fork's free account.

Rather than ripping App Group support out (which would make this fork permanently diverge from
upstream, where the maintainer's paid account presumably already has it working), the widget will
support **two interchangeable connection sources**, selected by a single build-time switch:

1. **App Group mode** (existing behavior, default in the committed project) — widget reads the
   active connection + cached dashboard/panel lists + panel snapshot from the shared App Group
   container, exactly as today. Requires a paid Developer Program membership to build.
2. **Self-contained mode** (new) — each widget instance holds its own Grafana URL + API token,
   entered directly in the widget's own configuration UI. The widget calls `GrafanaAPIClient`
   directly for the dashboard/panel picker and the panel image; it never touches
   `SharedDataManager` or any App Group. Builds and runs on a free Personal Team.

The committed default stays App Group mode, matching upstream's current expectation and keeping
this change a pure addition rather than a behavior change for anyone who already has it working.
This fork's own machines (home + work) opt into self-contained mode via a **gitignored local
override**, so the switch never needs to be committed and this fork's tracked history reads as
"add an option," not "remove a capability."

### Why self-contained mode doesn't need App Groups

- Per-widget configuration values (the `@Parameter`s on a `WidgetConfigurationIntent`) are
  persisted by WidgetKit itself, scoped to that single widget instance's own extension container —
  no App Group involved. This is the same mechanism any built-in widget uses to remember, e.g.,
  which city a weather widget shows.
- `GrafanaAPIClient.getDashboard(uid:)` and `.searchDashboards()` already exist and can be called
  directly from the widget extension with a `ServerConnection` built from the intent's own
  parameters — no dependency on the main app's cache.
- The existing `fetchPanelImage` fallback in `PanelWidgetProvider` (calls Grafana's
  `/render/d-solo/...` endpoint directly) already works without any shared container. In
  self-contained mode it becomes the only path instead of a fallback — not a new server
  requirement, since it's already exercised today whenever no cached snapshot exists.
- Each target gets its own default Keychain access group for free, with no entitlement or paid
  account required. Self-contained mode's token doesn't need to be *shared* with anything, only
  read by the widget extension that stored it.

### Accepted limitation (documented, not silently glossed over)

WidgetKit gives a configuration intent no `perform()`-style hook to intercept a saved value, and no
way to swap a plaintext parameter for a stored reference after the fact. So in self-contained mode,
`apiToken` is a plain `@Parameter` text field, persisted by WidgetKit's own per-widget configuration
storage (protected by the device's standard container encryption, never shared with another
process). This is not Keychain-grade, but it is strictly better than the current bug — today's
`apiKey` sits in plaintext inside a container shared with a second process; the self-contained
token sits in a container nothing else can read. Revisit only if a real need for stronger protection
shows up later — not a blocker for v1.

## Mechanism: the build-time switch

Swift's `#if` only compiles/skips code — it can't change which `.entitlements` file gets signed.
The compilation flag and the entitlements file must be switched together, from one place, so they
can't drift out of sync.

**xcconfig files** (new — this project has none today):
- `Config/Shared.xcconfig` — checked in. Sets the App-Group-mode defaults: adds
  `APP_GROUP_SHARING` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS`, and points
  `GRAFLENS_ENTITLEMENTS` / `GRAFLENSWIDGET_ENTITLEMENTS` at the App-Group entitlements files.
  Ends with an optional include of a local override file, so its absence doesn't break the build.
- `Config/Local.xcconfig` — **gitignored**, not committed. Each machine that needs self-contained
  mode creates this locally and overrides the three settings above to point at the
  `-SelfContained` entitlements files and drop `APP_GROUP_SHARING` from the compilation
  conditions. A `Config/Local.xcconfig.example` is committed as a template/doc, not as the real
  file.
- Wired in at the **project** level (Project > Info > Configurations), so both targets inherit the
  same flag from one source of truth, rather than each target configuring it independently.
- Each target's `CODE_SIGN_ENTITLEMENTS` build setting becomes a variable reference
  (`$(GRAFLENS_ENTITLEMENTS)` / `$(GRAFLENSWIDGET_ENTITLEMENTS)`) instead of a hardcoded path.

**Entitlements files** (four total, two per target):
- `GrafLens/GrafLens.entitlements` — App Group variant. Restore
  `group.tech.whitematter.graflens` (matching upstream's already-registered value, so a future
  upstream contribution doesn't require the maintainer to change anything in their Developer
  Portal).
- `GrafLens/GrafLens-SelfContained.entitlements` — empty App Groups array (this is what's
  currently in place today).
- `GrafLensWidget/GrafLensWidget.entitlements` — App Group variant, same group ID.
- `GrafLensWidget/GrafLensWidget-SelfContained.entitlements` — empty array.

**Swift files** (widget target): keep everything mode-agnostic in `GrafLensWidget.swift` —
`PanelWidgetEntry`, `DashboardEntity`/`PanelEntity` (shape doesn't differ by mode, only how they're
queried does), `PanelWidgetView`, `GrafLensPanelWidget`, `GrafLensWidgetBundle`. Split only the
parts that genuinely differ:
- `GrafLensWidget/AppGroupConnectionSource.swift`, wrapped in `#if APP_GROUP_SHARING` — today's
  `SelectPanelIntent` (dashboard/panel/timeRange params only), `DashboardEntityQuery`/
  `PanelEntityQuery` reading from `SharedDataManager`, and `PanelWidgetProvider` resolving the
  connection via `SharedDataManager.loadActiveConnection()`.
- `GrafLensWidget/SelfContainedConnectionSource.swift`, wrapped in `#if !APP_GROUP_SHARING` — a
  `SelectPanelIntent` with two extra `@Parameter`s (`serverURL`, `apiToken`) plus
  dashboard/panel/timeRange, entity queries that build a `ServerConnection` from those parameters
  and call `GrafanaAPIClient` directly, and a `PanelWidgetProvider` that does the same for image
  fetching.

Both files stay in the target's compile sources at all times; the inactive one simply compiles to
nothing. The exact xcconfig include/override syntax will be nailed down and verified by building in
Xcode during implementation, not fully pre-specified here.

### Upstream contribution note (flagged, not solved now)

This fork's bundle IDs (`com.georgek.*`) and team ID differ from upstream's
(`tech.whitematter.*`, `AD2VN8P4JY`). If any of this work is ever offered upstream as a PR, those
identity changes need to be excluded from that diff — they're specific to this fork's signing, not
part of the feature. Worth a reminder when that day comes; not a task for now.

## Deliverables

One GitHub issue per item, one branch + PR per issue, rebased onto `main`, reviewed by CodeRabbit.

### 1. Repo setup and conventions
- Add `.claude/` to `.gitignore` (session checkpoint files, e.g. `.claude/RESUME.md`, should never
  be committed).
- Add `CLAUDE.md` and this spec (already drafted above — commit them as part of this issue).
- Set this fork's GitHub merge button to rebase-only: disable "Allow merge commits" and "Allow
  squash merging", enable only "Allow rebase merging".

### 2. Widget: dual-mode connection source
- Add `Config/Shared.xcconfig` + `Config/Local.xcconfig.example`, wire into the project, gitignore
  the real `Config/Local.xcconfig`.
- Split `GrafLens.entitlements` / `GrafLensWidget.entitlements` into App-Group and
  `-SelfContained` variants as described above; restore the real App Group ID in the App-Group
  variants; wire `CODE_SIGN_ENTITLEMENTS` to the new xcconfig variables.
- Split `GrafLensWidget.swift` into the shared file plus `AppGroupConnectionSource.swift` /
  `SelfContainedConnectionSource.swift` as described above.
- Create a local `Config/Local.xcconfig` on this fork's own machines (not committed) selecting
  self-contained mode.
- **Verify:** build and run in the iOS Simulator with self-contained mode active; add the widget,
  enter a real Grafana URL + token, pick a dashboard and panel, confirm it renders and refreshes.
  App-Group mode is not testable on this fork (no paid account) — leave it to compile cleanly and
  match today's existing behavior exactly; call this out explicitly in the PR description as
  unverified, and welcome verification from anyone with a paid-account checkout.

### 3. App-Group mode: fix plaintext apiKey storage
- Independent of #2 — only touches the App-Group code path. Move `apiKey` out of the JSON blob
  `SharedDataManager.saveActiveConnection` writes to shared `UserDefaults`, into a Keychain item
  under a shared **Keychain Sharing** access group (also paid-tier-gated, which is fine since this
  code path only ever runs in App-Group mode). Keep the non-secret fields (`id`, `name`, `url`,
  `useServiceAccount`) in `UserDefaults` as before.
- **Verify:** same caveat as #2 — cannot be tested on this fork's free account. Write it carefully
  against Apple's documented Keychain Sharing behavior, flag as unverified in the PR.

### 4. Restore Mac Catalyst on the main `GrafLens` app target
- Re-enable Mac Catalyst as a supported destination on `GrafLens` (currently fully off, not just
  missing widget support).
- Resolve whatever signing/build issues surface — expected to be more straightforward now that
  App Groups isn't part of this fork's active configuration.
- **Verify:** run with "My Mac" selected as the destination; smoke-test core flows (connect, browse
  dashboards, view a panel).

### 5. Add Mac Catalyst destination to `GrafLensWidget`
- Add Mac Catalyst to the widget target's Supported Destinations. Depends on #2 (dual-mode split
  must exist first — no point fixing entitlements for a mechanism about to change) and #4 (needs a
  Mac-capable host app to attach to).
- **Verify:** widget appears under Notification Center > Edit Widgets, and can be dragged onto the
  Desktop.

### 6. macOS layout polish
- Adjust `PanelWidgetView` for macOS-specific sizing/padding quirks across `.systemSmall` /
  `.systemMedium` / `.systemLarge`, checked in the Xcode preview canvas targeting "My Mac" and live
  on the Desktop/Notification Center.

## Explicitly out of scope (flag as separate future issues, don't fold in here)

- A checked-in shared Xcode scheme for `xcodebuild`/CI use.
- SwiftLint or any other formatter/linter adoption.
- An automated test target.
- Supporting more than one active Grafana connection per machine (self-contained mode incidentally
  makes this easier later, but it's not a goal now).
- Any actual upstream PR to `WhiteMatter-Tech/graflens`.
