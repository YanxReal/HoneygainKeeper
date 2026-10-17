# Changelog

All notable changes to HoneygainKeeper are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/); versioning is SemVer.

## [Unreleased]

## [1.0.0] - 2026-10-17

### Added

- **Dashboard (Resumen / Overview)**: Liquid Glass status pill (Protected / Partial /
  Stopped), four state cards (Honeygain, plist, agent loaded, running), activity card
  (restarts, last exit code, log size) and a dismissable message banner right under
  the header.
- **LaunchAgent manager**: install / uninstall / restart (`launchctl bootstrap`,
  `bootout`, `kickstart -k`) with the plist as the single source of truth; the
  «keep always running» choice is mirrored from the plist and remembered in
  `UserDefaults` for new installs (ON by default).
- **Official Honeygain installer**: resolves the current DMG from Honeygain's own
  Sparkle feed, downloads with timeouts, mounts and verifies the signature
  (`codesign --verify --deep --strict`), the Team ID (`L4S6563XXV`, Honeygain UAB),
  the bundle ID and the runnable architecture; copies to `/Applications` off the
  main thread. Foreign-but-valid signatures, tampered formats and unreachable hosts
  are rejected with user-facing messages.
- **Log viewer (Registros / Logs)**: 256 KB / 1000-line tail of the current and
  rotated logs, live search, follow mode, copy, export, open in Console.app, safe
  live truncate and automatic rotation at 5 MB while the agent is unloaded.
- **Crash-loop detection**: warns when Honeygain accumulates repeated error exits.
- **Bilingual UI (es/en)** built on `Localizable.strings` with 100% key parity
  (109 keys per language), Spanish as the source language; `scripts/check_localization.py`
  enforces parity in CI.
- **Tooling**: Makefile (`make doctor/build/run/release/dist/check/logs/agent-status`),
  GitHub Actions CI on `macos-26` with the DMG + ZIP uploaded as workflow
  artifacts, shared Xcode scheme, issue/PR templates and Dependabot.
- **Distribution**: `make dist` packages the Release build into
  `HoneygainKeeper-<version>.dmg` (drag & drop to Applications), `.zip`
  (signature preserved via `ditto`) and `SHA256SUMS.txt`; a tag-triggered
  Release workflow (`.github/workflows/release.yml`) builds from the tag and
  attaches all three to the GitHub Release. The READMEs and release notes
  document the first-launch quarantine steps (System Settings → Open Anyway,
  or `xattr -cr` in Terminal).
- Project builds clean under **Swift 6 language mode** with zero warnings;
  target: macOS 26.0+, ad-hoc signing, no sandbox.
