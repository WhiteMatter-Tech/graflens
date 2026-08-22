# CLAUDE.md

Guidance for working on GrafLens with Claude Code. Keep this file in sync with reality — update it
when a convention below stops being true, rather than letting it drift.

## What this project is

A native SwiftUI app for iOS/iPadOS/macOS (via Mac Catalyst) that browses Grafana dashboards and
panels. Zero third-party dependencies — every import is a first-party Apple framework. No
analytics/telemetry. All network calls go to whatever Grafana host the user types in
(`ServerConnection.baseURL`); nothing phones home elsewhere.

Two targets:
- `GrafLens` — the main app (`GrafLens/`)
- `GrafLensWidget` — a WidgetKit extension showing a single configurable Grafana panel
  (`GrafLensWidget/`), currently iOS/iPadOS only

Fork setup: `origin` = `gkesaev/graflens` (this fork, do all work here), `upstream` =
`WhiteMatter-Tech/graflens` (the original project).

## Building and running

There is no command-line build path yet — no shared Xcode scheme is checked in, so `xcodebuild`
won't work out of the box. Build and run through Xcode:

1. `open GrafLens.xcodeproj`
2. Select the `GrafLens` target > Signing & Capabilities > set your own Team (not the upstream
   maintainer's — bundle IDs and team ID here are already repointed to this fork owner's account).
   Repeat for `GrafLensWidget`.
3. Pick a run destination (iOS Simulator, a device, or "My Mac" once Mac Catalyst support is
   restored — see `docs/specs/macos-widget-support.md`) and Cmd+R.

**Known account constraint:** this fork is currently signed with a free Apple "Personal Team".
Personal Teams cannot provision App Groups, cross-target Keychain Sharing, iCloud, Push, or a
handful of other entitlement-gated capabilities. Don't assume any of those are available unless
you've confirmed the active Apple ID has a paid Developer Program membership — check
`DEVELOPMENT_TEAM` in the project's build settings and ask before building a feature around one of
these.

There is no automated test target in this project yet. Verification is manual: build, run, and
exercise the feature in the Simulator or on "My Mac". Say so explicitly if you haven't been able to
test something rather than claiming it works.

## Architecture

- `Models/` — `Codable` API response types + `ServerConnection` (id, name, url, apiKey,
  useServiceAccount)
- `Services/` — one enum/class per concern (`GrafanaAPIClient`, `ConnectionManager`,
  `KeychainManager`, `SharedDataManager`, `PanelCacheManager`, etc.). Managers are plain
  `enum`s with static methods when they hold no instance state; `ConnectionManager` is an
  `ObservableObject` because it drives UI.
- `ViewModels/` — `@MainActor` `ObservableObject`s, one per major screen
- `Views/` — SwiftUI views, async/await throughout, no Combine
- `GrafLensWidget/GrafLensWidget.swift` — the widget extension; already uses AppIntents
  (`WidgetConfigurationIntent`, `AppEntity`, `EntityQuery`) for per-widget dashboard/panel
  selection — follow that existing pattern rather than introducing a different configuration
  approach

`KeychainManager` and `SharedDataManager` are the two secret/shared-state boundaries in this
codebase — read both fully before touching persistence logic near the widget.

## Git and GitHub workflow

- Work happens on feature branches off `main` in this fork (`gkesaev/graflens`), never directly on
  `main`.
- Open PRs against `origin/main`. Don't open PRs against `upstream` unless explicitly asked to
  contribute back.
- **Rebase only.** Update feature branches with `git rebase main`, never `git merge main` into a
  feature branch. No merge commits in the history.
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`,
  `test:`) — some existing commits already do this; extend the convention going forward rather than
  inventing a new one.
- One GitHub issue per deliverable, one branch + PR per issue. Link the PR to its issue.
- Use CodeRabbit as the review assistant on every PR before merging.
- Stay scoped to the issue at hand. If something else broken or worth doing turns up mid-task,
  don't fix it inline — note it and open a separate issue.

## Code style

Match the existing style exactly rather than introducing new conventions:
- SwiftUI + async/await, no Combine, no third-party dependencies
- Plain `enum` namespaces for stateless managers (see `KeychainManager`)
- No SwiftLint/formatter configured — match surrounding code by eye

## In-progress work

macOS widget support (Notification Center + Desktop) is being designed and built — see
`docs/specs/macos-widget-support.md` for the current architecture decisions, the App-Group vs.
self-contained dual-mode split, and the deliverable breakdown. Update that spec (not this file) as
implementation details change; update this file only when a durable, cross-feature convention
changes.
