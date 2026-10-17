# Contributing to HoneygainKeeper

Thanks for taking the time to contribute! 🎉

This document describes the workflow, standards, and expectations for
contributions to **HoneygainKeeper**.

- [Ways to contribute](#ways-to-contribute)
- [Development setup](#development-setup)
- [Project structure](#project-structure)
- [Coding guidelines](#coding-guidelines)
- [Pull request process](#pull-request-process)
- [Commit messages](#commit-messages)
- [Verification](#verification)

---

## Ways to contribute

- 🐛 **Report bugs** — open an issue with the template, including the app version, `make agent-status` output and the relevant log lines.
- 💡 **Suggest features** — describe the use case and the expected behavior.
- 📝 **Improve documentation** — both `README.md` (English) and `README.es.md` (Spanish) must stay in sync.
- 🧪 **Test edge cases** — Intel Macs + Rosetta, fresh machines, rotated logs, feed outages.
- 🔧 **Send pull requests** — bug fixes, hardening, or features aligned with the roadmap.

## Development setup

Requirements: **macOS 26+** and **Xcode 26+**.

```bash
git clone https://github.com/YanxReal/HoneygainKeeper.git
cd HoneygainKeeper
make doctor     # verifies macOS 26+, Xcode 26+ and Python 3
make run        # builds Debug and opens the app
```

Useful day-to-day commands:

```bash
make build              # Debug build into build/DerivedData
make check              # localization parity + build (what CI runs)
make logs               # follow the LaunchAgent log
make agent-status       # launchd state of the keep-alive agent
```

> ⚠️ **Testing caution:** the app manages your real LaunchAgent
> (`com.yanx.honeygain-keepalive`) and can install/uninstall Honeygain. When testing
> destructive paths, be ready to reinstall from the app itself.

## Project structure

| Path | Responsibility |
|---|---|
| `HoneygainKeeperApp.swift` | `@main`, single-window scene, shared manager, removed «New Window» |
| `ContentView.swift` | Sidebar, header, status cards, actions and the install popover |
| `LogViewerView.swift` | Log tail viewer: search, follow, copy, export, Console.app |
| `LaunchAgentManager.swift` | Plist template + diff, `launchctl`, state polling, messages, logs |
| `HoneygainInstaller.swift` | Official feed resolution, download and verification pipeline |
| `ProcessRunner.swift` | Deadlock-safe process execution off the main actor |
| `es.lproj` / `en.lproj` | Localized UI strings (same keys in both files) |
| `scripts/check_localization.py` | es/en parity + code key-coverage check |

## Coding guidelines

- **Swift 6 language mode, zero warnings.** The project builds clean with the strict concurrency checks of Xcode 26 — keep it that way.
- **UI on the main actor; heavy work off it.** Process execution, downloads, file copies and log reading must not block the UI (`ProcessRunner`, `Task.detached`).
- **Localization is mandatory for every user-facing string:**
  1. Write the text in Spanish (source language) directly in the code inside a localizable context (`Text("…")`, `String(localized: "…")`, `LocalizedStringKey` values).
  2. Add the exact key to **both** `es.lproj/Localizable.strings` and `en.lproj/Localizable.strings`.
  3. Run `python3 scripts/check_localization.py` — it fails on missing keys or broken parity.
  - Use manual singular/plural phrasing when interpolating counts (see `linesSentence` in `LaunchAgentManager.swift`).
- **Never weaken the installer verification** (host pinning, `codesign --verify --deep --strict`, Team ID `L4S6563XXV`, bundle ID check, architecture check).
- **State lives in `LaunchAgentManager`** — don't duplicate it in views; the plist is the source of truth for the keep-alive option.
- Keep the fixed paths (`~/Library/LaunchAgents/…plist`, `/Applications/Honeygain.app`, `~/Library/Logs/honeygain-keepalive.log`) as constants — no hidden state anywhere else.

## Pull request process

1. Fork the repo and branch from `main` (`feat/…`, `fix/…`, `docs/…`).
2. Keep changes focused; update `CHANGELOG.md` under `[Unreleased]` when user-visible.
3. Run `make check` and `make run` (smoke test) before opening the PR.
4. Fill in the PR template, including screenshots for UI changes.
5. CI must be green: localization parity + Debug/Release builds on `macos-26`.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) with a short scope:

```txt
feat(ui): add crash-loop banner under the header
fix(installer): normalize URLSession cancellation to CancellationError
docs(readme): mirror quick start in Spanish
chore(ci): pin actions/checkout to v4
```

## Verification

The single gate that CI runs is:

```bash
make check      # python3 scripts/check_localization.py && xcodebuild (Debug)
```

For UI changes, also verify `make run` in both languages (System Settings →
General → Language & Region → Applications lets you switch the app's language).
