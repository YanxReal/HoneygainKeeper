# HoneygainKeeper

**Gestor para macOS 26+ (SwiftUI) del LaunchAgent de Honeygain** — keep-alive para que nunca se caiga, instalador oficial de un clic con verificación de firma, detección de crash-loops y visor de registros integrado, con interfaz Liquid Glass y documentación bilingüe completa (EN/ES).

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple&logoColor=white)](#-requisitos)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI Liquid Glass](https://img.shields.io/badge/UI-Liquid_Glass-0A84FF?logo=apple&logoColor=white)](#-funciones)
[![CI](https://github.com/YanxReal/HoneygainKeeper/actions/workflows/ci.yml/badge.svg)](https://github.com/YanxReal/HoneygainKeeper/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> 🌐 **Idioma:** [English](README.md) | **Español**

[Visión general](#-visión-general) • [Funciones](#-funciones) • [Requisitos](#-requisitos) • [Descarga e instalación](#-descarga-e-instalación) • [Inicio rápido](#-inicio-rápido) • [Estructura](#-estructura) • [Capturas](#-capturas) • [Cómo funciona](#-cómo-funciona) • [Comandos make](#-comandos-make) • [Seguridad](#-seguridad) • [Problemas](#-problemas) • [Roadmap](#-roadmap) • [Contribuir](#-contribuir) • [Licencia](#-licencia)

---

## Tabla de contenidos

1. [Visión general](#-visión-general)
2. [Funciones](#-funciones)
3. [Requisitos](#-requisitos)
4. [Descarga e instalación](#-descarga-e-instalación)
5. [Inicio rápido](#-inicio-rápido)
6. [Estructura](#-estructura)
7. [Capturas](#-capturas)
8. [Cómo funciona](#-cómo-funciona)
9. [Comandos make](#-comandos-make)
10. [Seguridad](#-seguridad)
11. [Problemas](#-problemas)
12. [Roadmap](#-roadmap)
13. [Contribuir](#-contribuir)
14. [Licencia](#-licencia)
15. [Agradecimientos](#-agradecimientos)

---

## 🔭 Visión general

HoneygainKeeper es una app nativa para **macOS 26 (Tahoe)** que supervisa **Honeygain** mediante un **LaunchAgent** (`com.yanx.honeygain-keepalive`): si Honeygain se cierra o falla, launchd lo vuelve a levantar — y esta app te da los controles, el estado en vivo y los registros a su alrededor.

| | |
|---|---|
| 🟢 **Keep-alive** | LaunchAgent con `KeepAlive=true`: Honeygain se relanza solo si lo cierras |
| 📥 **Instalador oficial** | Descarga Honeygain desde su propio feed Sparkle y verifica firma + Team ID antes de instalar |
| 📊 **Panel de estado** | Tarjetas de cristal con el estado de la app / agente / proceso, contador de reinicios, última salida y tamaño del registro |
| 🪵 **Visor de registros** | Cola del log actual y rotados, con búsqueda, seguimiento, copia, exportación y apertura en Consola.app |
| ⚠️ **Detección de crash-loop** | Avisa cuando Honeygain acumula salidas con error repetidas |
| 🌐 **Bilingüe** | Interfaz completa en español e inglés con paridad total de claves (`Localizable.strings`) |

## ✨ Funciones

- **Instalar / desinstalar / reiniciar** el LaunchAgent desde la app (`launchctl bootstrap` / `bootout` / `kickstart -k`).
- **«Mantener siempre activo»** al instalar: activado, Honeygain se relanza si lo cierras; desactivado, solo se abre al iniciar sesión. El plist es la fuente de verdad; la app recuerda tu última elección para instalaciones nuevas (ON por defecto).
- **Instalación de Honeygain en un clic**: resuelve el DMG vigente desde el `appcast.xml` oficial de Sparkle, lo descarga con límites de tiempo, lo monta y lo verifica — `codesign --verify --deep --strict`, **Team ID `L4S6563XXV` (Honeygain UAB)** y bundle ID `com.honeygain.Honeygain` —, comprueba que el binario pueda ejecutarse en tu Mac (arm64 nativo o x86_64 + Rosetta) y lo copia a `/Applications` fuera del hilo principal.
- **Gestión de registros**: cola de 256 KB, máximo 1000 líneas, búsqueda en vivo, modo seguimiento, rotaciones `.1`–`.3`, vaciado seguro en caliente y rotación automática a los 5 MB (solo con el agente descargado — mientras corre, launchd mantiene el descriptor).
- **Aviso de crash-loop** al detectar ≥ 5 salidas con error consecutivas.
- **Interfaz Liquid Glass** (macOS 26), una sola ventana, tooltips por todas partes y mensajes descartables justo bajo la cabecera.
- **Eficiente**: sondeo cada 5 s en primer plano y cada 30 s en segundo plano; las descargas y copias nunca corren en el hilo principal.
- **Firma ad-hoc, sin sandbox**: necesita escribir en `~/Library/LaunchAgents` y ejecutar `launchctl`. La firma Developer ID / notarización queda fuera de alcance por ahora.

## 📦 Requisitos

| Requisito | Versión | Notas |
|---|---|---|
| **macOS** | 26.0+ (Tahoe) | APIs de Liquid Glass |
| **Xcode** | 26+ | Compilar y ejecutar |
| **Swift** | 6 (modo de lenguaje) | Incluido con Xcode 26 |
| **Python 3** | cualquiera | Solo para `make check` (paridad de traducciones) |
| **Honeygain** | opcional | La app puede descargarlo e instalarlo por ti |

## 📥 Descarga e instalación

Descarga la última versión desde [Releases](https://github.com/YanxReal/HoneygainKeeper/releases/latest):

| Asset | Uso |
|---|---|
| **`HoneygainKeeper-<versión>.dmg`** | Recomendado — ábrelo y arrastra la app a **Aplicaciones** |
| `HoneygainKeeper-<versión>.zip` | App portátil — descomprímela y muévela a Aplicaciones |
| `SHA256SUMS.txt` | Sumas de verificación — compruébalas con `shasum -a 256 -c SHA256SUMS.txt` |
| Código fuente | Compílalo tú mismo (ver [Inicio rápido](#-inicio-rápido)) |

Verificar una descarga (opcional):

```bash
cd ~/Downloads
shasum -a 256 -c SHA256SUMS.txt
```

### Primera apertura (cuarentena de macOS)

La app va **firmada ad-hoc** (la notarización está en el [roadmap](#-roadmap)), así que macOS
bloqueará la primera apertura con un aviso tipo *«Apple no puede verificar…»* — o incluso
*«HoneygainKeeper está dañada»*. No es malware: es el **atributo de cuarentena** que macOS
pone a todo lo que se descarga de internet. Quítalo con cualquiera de estas dos vías:

**A. Ajustes del Sistema (sin Terminal):**

1. Haz doble clic en la app una vez y pulsa **Fin/Hecho** en el aviso (no la muevas a la papelera).
2. Abre **Ajustes del Sistema → Privacidad y seguridad** y baja del todo hasta **Seguridad**.
3. Pulsa **Abrir de todas formas**, autentica con Touch ID / contraseña y confirma **Abrir**.

> El botón «Abrir de todas formas» solo aparece justo después de un intento bloqueado y caduca en ~1 hora.

**B. Terminal (funciona siempre — necesaria si el aviso dice «está dañada»):**

```bash
xattr -cr /Applications/HoneygainKeeper.app
```

Después, ábrela con normalidad.

> 💡 El truco de toda la vida (clic derecho → Abrir) ya no existe desde macOS 15 — las vías
> actuales son las dos de arriba. Si prefieres saltarte Gatekeeper, [compílala desde el código](#-inicio-rápido)
> con `make run`.

## 🚀 Inicio rápido

```bash
git clone https://github.com/YanxReal/HoneygainKeeper.git
cd HoneygainKeeper

make doctor     # comprueba macOS 26+ y Xcode 26+
make run        # compila en Debug y abre la app
```

¿Prefieres Xcode? Abre `HoneygainKeeper.xcodeproj` y pulsa ⌘R. La app está firmada ad-hoc: no necesita Apple ID ni certificados.

## 🗂️ Estructura

```txt
HoneygainKeeper/
├── HoneygainKeeper.xcodeproj          # target macOS 26 (Swift 6, esquema compartido)
├── HoneygainKeeper/
│   ├── HoneygainKeeperApp.swift       # @main, escena de una ventana, manager compartido
│   ├── ContentView.swift              # barra lateral, cabecera, tarjetas, acciones, pop de instalación
│   ├── LogViewerView.swift            # visor de registros (cola, búsqueda, seguimiento, exportar)
│   ├── LaunchAgentManager.swift       # plantilla del plist, launchctl, estado, registros
│   ├── HoneygainInstaller.swift       # instalador oficial (feed, descarga, verificación)
│   ├── ProcessRunner.swift            # ejecución de procesos sin deadlocks, fuera del main actor
│   ├── es.lproj/Localizable.strings   # Español (idioma fuente)
│   └── en.lproj/Localizable.strings   # Inglés (espejo, mismas claves)
├── scripts/check_localization.py      # paridad es/en + cobertura de claves del código
└── docs/images/                       # capturas usadas por los README
```

## 🖼️ Capturas

| Resumen (Español) | Overview (English) |
|---|---|
| ![Resumen ES](docs/images/overview-es.png) | ![Overview EN](docs/images/overview-en.png) |

## 🔌 Cómo funciona

Todo lo que gestiona la app vive en tres rutas fijas (sin estado oculto):

| Qué | Dónde |
|---|---|
| Plist del LaunchAgent | `~/Library/LaunchAgents/com.yanx.honeygain-keepalive.plist` |
| App de Honeygain | `/Applications/Honeygain.app` (`Contents/MacOS/Honeygain` vía `CFBundleExecutable`) |
| Registro del servicio | `~/Library/Logs/honeygain-keepalive.log` (+ rotaciones `.1`–`.3`) |

El plist ejecuta Honeygain con `RunAtLoad=true` y `KeepAlive` según tu elección:

```xml
<key>Label</key><string>com.yanx.honeygain-keepalive</string>
<key>ProgramArguments</key>
<array>
  <string>/Applications/Honeygain.app/Contents/MacOS/Honeygain</string>
</array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
```

El estado se lee con `launchctl print gui/$UID/com.yanx.honeygain-keepalive`, el plist y la tabla de procesos; **Reiniciar** es un único `launchctl kickstart -k`.

## 🧰 Comandos make

| Comando | Qué hace |
|---|---|
| `make doctor` | Comprueba macOS 26+, Xcode 26+ y Python 3 |
| `make build` | Compila la app en Debug (`build/DerivedData`) |
| `make release` | Compila la app en Release |
| `make dist` | Compila Release y empaqueta `dist/HoneygainKeeper-<versión>.{dmg,zip}` + `SHA256SUMS.txt` (para GitHub Releases) |
| `make run` | Compila y abre la app |
| `make check` | Paridad de localización + compilación Debug (lo que corre CI) |
| `make logs` | Sigue el registro del servicio (`tail -f`) |
| `make agent-status` | Muestra el estado del LaunchAgent en launchd |
| `make open` / `make clean` | Abre el proyecto en Xcode / borra artefactos de compilación |

## 🔐 Seguridad

- **Toda descarga se verifica** antes de copiar nada a `/Applications`:
  `codesign --verify --deep --strict`, **Team ID `L4S6563XXV` (Honeygain UAB)** y bundle ID `com.honeygain.Honeygain`. Una firma válida pero ajena también se rechaza.
- El host de descarga está **fijado** a `resources.honeygain.com` sobre HTTPS, y cada petición tiene límite de tiempo (60 s de petición / 15 min de recurso).
- La app **no está en sandbox** (escribe en `~/Library/LaunchAgents` y ejecuta `launchctl`) y va **firmada ad-hoc**; compílala desde el código.
- Reporta vulnerabilidades en privado — consulta [SECURITY.md](SECURITY.md).

## 🩺 Problemas

| Síntoma | Qué hacer |
|---|---|
| *«Apple no puede verificar…»* o *«está dañada»* al abrir por primera vez | Es la cuarentena de una app firmada ad-hoc — ver [Descarga e instalación](#-descarga-e-instalación) |
| «El servicio se instaló, pero aún no aparece como activo» | `make agent-status`; desinstala y reinstala desde la app; revisa el panel Registros |
| La instalación de Honeygain falla con error de red | Comprueba tu conexión con `resources.honeygain.com` o usa la descarga manual desde honeygain.com |
| La píldora de estado muestra «Detenido» | El agente no está cargado: instálalo desde la app (la `launchctl bootstrap` la hace la app por ti) |
| Mac Intel sin Rosetta | El feed oficial puede publicar binarios solo arm64; instala Rosetta o descarga Honeygain desde su web |
| El registro no muestra nada tras reiniciar | Honeygain guarda stdout en memoria y lo vuelca cuando su buffer se llena — es normal |

## 🗺️ Roadmap

- [ ] Tests unitarios de la plantilla del plist, el diff del plist y el parseo de la cola del log
- [ ] Firma Developer ID + notarización (fuera de alcance por ahora)
- [ ] Selector manual de `.dmg` cuando el feed no esté disponible
- [ ] Modo opcional en la barra de menús con acciones rápidas

## 🤝 Contribuir

Lee [CONTRIBUTING.md](CONTRIBUTING.md). La paridad bilingüe (README.md ↔ README.es.md y los `.strings` es/en) está verificada por `make check` y CI.

## 📄 Licencia

[MIT](LICENSE) © 2026 Yanx Studio

## 🙏 Agradecimientos

- **Honeygain** — por el feed Sparkle oficial del que esta app resuelve las descargas.
- El patrón comunitario de keep-alive con `launchd` que inspiró esta app.
