# AGENTS — How AI Should Work in This Repo

> **This is the single source of truth for any AI agent (OpenCode, Codex, Claude Code, Cursor, Copilot, etc.) working in this repository.**
> If you are an AI, read this whole file before editing anything. If you are a human, this tells you what to expect from AI.

**Version:** 1.0.0 · **Applies to:** `YanxReal/HoneygainKeeper` · **Stack:** Swift 6 (language mode) / SwiftUI on macOS 26+, Xcode project, Make, Python (parity script)

---

## 1. Bilingual Rule — NON-NEGOTIABLE

This repo is **bilingual by design**:

| Language | Canonical files | Audience |
|---|---|---|
| **English (primary)** | `README.md` | International, GitHub default |
| **Español (mirror)** | `README.es.md` | Hispanohablante |

**Rule:** *Every change to a user-facing file MUST be mirrored in both languages in the same commit.*

- If you edit `README.md`, you **must** edit `README.es.md` with the equivalent Spanish translation.
- If you add a UI string, you **must** add it to **both** `HoneygainKeeper/es.lproj/Localizable.strings` and `HoneygainKeeper/en.lproj/Localizable.strings`.
- Do **not** leave one language behind.

**Verification (run before commit):**

```bash
python3 scripts/check_localization.py    # es/en .strings parity + code key coverage
```

- Keys must match **exactly** between `es` and `en` (same count, same format specifiers `%@` / `%lld`).
- The Spanish literal in the code **is the lookup key** — if you change the Spanish text, update both `.strings` files in the same commit.
- Keep structure identical across READMEs (same headings, order, tables). Only language changes.

## 2. Language Switcher

Every bilingual markdown file has a switcher at the top:

- English files: `> 🌐 **Language:** **English** | [Español](README.es.md)`
- Spanish files: `> 🌐 **Idioma:** [English](README.md) | **Español**`

## 3. Project Conventions

- **macOS 26.0+ only** (`MACOSX_DEPLOYMENT_TARGET = 26.0`). Do not add fallbacks for older systems.
- **Swift 6 language mode, zero warnings.** `xcodebuild` must succeed clean — no exceptions.
- **UI runs on the main actor; all heavy work does not.** Process execution, downloads, file copies and log reads go through `ProcessRunner` or `Task.detached` — never block the UI.
- **Single source of state:** `LaunchAgentManager` (owned at `@main`, shared with `@ObservedObject`). Views never duplicate state.
- **The plist is the source of truth** for the keep-alive option; `UserDefaults` only remembers the user's last choice for *new* installs (ON by default).
- **Fixed paths live as constants in `LaunchAgentManager`** (`plistPath`, `logPath`, `honeygainPath`). Do not hardcode them anywhere else.
- **No third-party dependencies.** System frameworks only (SwiftUI, AppKit, Foundation).
- **Localization:** write strings in Spanish (source) inside a localizable context — `Text("…")`, `String(localized: "…")`, or a `LocalizedStringKey` parameter. For interpolated counts, use full sentences with manual singular/plural (see `linesSentence`); never assemble fragments across languages.
- **Log viewer message sentences** are built in `LaunchAgentManager` with `String(localized:)`; the views only render them.

## 4. Security Invariants — DO NOT WEAKEN

The installer verification chain in `HoneygainInstaller.swift` / `LaunchAgentManager.swift` is load-bearing:

1. Feed host pinned to `https://resources.honeygain.com` (HTTPS only).
2. `codesign --verify --deep --strict` on the downloaded app.
3. Team ID must equal `L4S6563XXV` (Honeygain UAB).
4. Bundle ID must equal `com.honeygain.Honeygain`.
5. The binary must be runnable on this Mac (arm64 native, or x86_64 with Rosetta).

Never relax, skip or reorder these checks, and keep all download requests under explicit timeouts.

## 5. Verification Gates

Run these before considering any task complete:

```bash
make check    # localization parity + Debug build (this is what CI runs)
make run      # smoke test: app launches, state matches, no warnings
```

For UI changes, verify in **both languages** (System Settings → General → Language & Region → Applications → HoneygainKeeper).

## 6. Repo Hygiene

- Keep `CHANGELOG.md` updated under `[Unreleased]` for user-visible changes.
- Do not commit `build/`, `DerivedData/`, `xcuserdata/` or `*.app` bundles (see `.gitignore`).
- Only the shared scheme under `HoneygainKeeper.xcodeproj/xcshareddata/xcschemes/` is versioned — keep it working with `xcodebuild -scheme HoneygainKeeper`.
