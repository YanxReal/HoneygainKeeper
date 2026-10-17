# Security Policy

> 🌐 **Language:** **English** (primary) | [Español](#-política-de-seguridad-es)

We take the security of **HoneygainKeeper** seriously. This document describes how to
report vulnerabilities, what to expect, and which versions are supported. For the safety
of all users, **please do not report security issues via public GitHub Issues**.

---

## Supported Versions

Only the latest `main` branch and the latest tagged release are actively supported with
security fixes.

| Version | Supported |
|---|---|
| `main` (latest commit) | ✅ |
| Latest release (`v1.x`) | ✅ |
| Older tags / forks | ❌ — please update |

## Reporting a Vulnerability

### Preferred: GitHub Private Vulnerability Reporting

1. Go to **Security** → **Report a vulnerability**
   (direct: `https://github.com/YanxReal/HoneygainKeeper/security/advisories/new`)
2. Include:
   - Affected file(s) and line(s) — e.g. `HoneygainInstaller.swift`, `LaunchAgentManager.swift`
   - Steps to reproduce and the exact app message shown
   - macOS version (`sw_vers`) and Xcode version (`xcodebuild -version`)
   - `make agent-status` output and relevant log lines
3. You will receive an acknowledgment within **48 hours**.

## Scope notes (what this app touches)

- **Downloads and installs Honeygain.** The verification chain is intentionally strict
  and must never be bypassed: HTTPS-only, host pinned to `resources.honeygain.com`,
  `codesign --verify --deep --strict`, Team ID `L4S6563XXV` (Honeygain UAB), bundle ID
  `com.honeygain.Honeygain`, and a runnable-architecture check before copying to
  `/Applications`. Reports that demonstrate a way around any of these checks are the
  most valuable findings.
- **Runs `launchctl` and writes `~/Library/LaunchAgents`.** The app is deliberately
  **not sandboxed**; command arguments are fixed (no shell interpolation of user input).
- **Reads and truncates log files** under `~/Library/Logs/`. Paths are constants; the
  app never follows user-supplied paths.
- **Network access is limited** to Honeygain's official Sparkle feed and the same-host
  DMG it points to, with timeouts on every request.

## Out of scope

- Honeygain itself, its feed contents or its binaries — report those to Honeygain.
- Issues that require an already-compromised Mac or a malicious local admin.
- Missing Developer ID signing / notarization (tracked in the roadmap).

---

## 🛡️ Política de seguridad (ES)

Nos tomamos muy en serio la seguridad de **HoneygainKeeper**. **No publiques problemas de
seguridad en Issues públicos** — usa el canal privado descrito arriba
(**Security** → **Report a vulnerability**) e incluye versión de macOS, versión de la app,
pasos para reproducir, mensajes exactos de la app y el estado del LaunchAgent
(`make agent-status`). Recibirás acuse de recibo en un máximo de **48 horas**.

Notas de alcance:

- La app **descarga e instala Honeygain**: la cadena de verificación (HTTPS con host
  fijado a `resources.honeygain.com`, `codesign --verify --deep --strict`, Team ID
  `L4S6563XXV` de Honeygain UAB, bundle ID y arquitectura ejecutable) **no debe
  debilitarse nunca**. Los informes que demuestren cómo saltarse alguno de estos
  controles son los más valiosos.
- La app **ejecuta `launchctl` y escribe en `~/Library/LaunchAgents`**, deliberadamente
  **sin sandbox**; los argumentos de los comandos son fijos y no se interpola entrada
  del usuario.
- **Lee y trunca archivos de registro** en `~/Library/Logs/` con rutas constantes,
  sin seguir rutas proporcionadas por el usuario.
- **Acceso de red limitado** al feed Sparkle oficial de Honeygain y al DMG de su mismo
  host, con límites de tiempo en cada petición.
