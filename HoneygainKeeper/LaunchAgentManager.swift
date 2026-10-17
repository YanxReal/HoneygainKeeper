import AppKit
import Foundation

/// Gestiona el LaunchAgent com.yanx.honeygain-keepalive:
/// detecta Honeygain, instala/desinstala el plist y reporta el estado.
///
/// Todas las mutaciones de estado publicado ocurren en el MainActor.
/// El trabajo pesado (lanzar `launchctl` / `pgrep`) se ejecuta fuera del
/// hilo principal vía `Task.detached` para no congelar la UI.
@MainActor
final class LaunchAgentManager: ObservableObject {
    nonisolated static let label = "com.yanx.honeygain-keepalive"
    nonisolated static let honeygainPath = "/Applications/Honeygain.app"
    /// Bundle ID real de Honeygain (verificado en su Info.plist).
    /// Se usa para detección precisa sin confundirlo con HoneygainKeeper.
    nonisolated static let honeygainBundleID = "com.honeygain.Honeygain"
    nonisolated static let honeygainExecutableName = "Honeygain"
    nonisolated static let keepAliveDefaultsKey = "keepAliveEnabled"
    /// Rotación de logs: a partir de este tamaño se rota a .1/.2/.3.
    nonisolated static let maxLogBytes: UInt64 = 5 * 1024 * 1024
    nonisolated static let logGenerations = 3

    nonisolated static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist", isDirectory: false)
    }
    nonisolated static var plistPath: String { plistURL.path }

    nonisolated static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/honeygain-keepalive.log", isDirectory: false)
    }
    nonisolated static var logPath: String { logURL.path }

    @Published var honeygainInstalled = false
    @Published var plistExists = false
    @Published var agentLoaded = false
    @Published var honeygainRunning = false
    @Published var message = ""
    @Published var isBusy = false
    /// Interruptor KeepAlive. Activado por defecto: Honeygain se relanza
    /// incluso si el usuario lo cierra. Desactivado: se abre al iniciar
    /// sesión (RunAtLoad) pero ya no se relanza al cerrarlo.
    ///
    /// La elección del usuario se recuerda en UserDefaults; cuando el plist
    /// existe, su estado real es el que manda (refresh lo sincroniza aquí).
    @Published var keepAliveEnabled = true {
        didSet {
            UserDefaults.standard.set(keepAliveEnabled, forKey: Self.keepAliveDefaultsKey)
        }
    }
    @Published var restartCount: Int?
    @Published var lastExitCode: Int?
    @Published var crashLoopSuspected = false
    @Published var logSize: String?
    // MARK: - Descarga de Honeygain (fuente oficial)
    @Published var hgDownloading = false
    @Published var hgDownloadPhase = ""
    // MARK: - Visor de logs
    @Published var logLines: [String] = []
    @Published var logTailTruncated = false
    @Published var logViewerMessage = ""

    init() {
        // ON por defecto; si el usuario lo cambió alguna vez, se respeta su
        // última elección guardada en UserDefaults.
        if let stored = UserDefaults.standard.object(forKey: Self.keepAliveDefaultsKey) as? Bool {
            keepAliveEnabled = stored
        }
    }

    /// Plist esperado. Se genera dinámicamente para que las rutas de log
    /// apunten al HOME del usuario actual y no queden hardcodeadas.
    ///
    /// Notas:
    /// - Se lanza el binario real (no `open -a`): launchd supervisa el pid
    ///   real y KeepAlive funciona; con `open` supervisaría el shim de
    ///   `open(1)`, no la app.
    /// - `LimitLoadToSessionType=Aqua`: es una app GUI (menubar), solo tiene
    ///   sentido cargarla en sesión Aqua.
    /// - `ProcessType=Background`: Honeygain comparte ancho de banda en
    ///   segundo plano; prioridad eficiente en energía.
    nonisolated private static func expectedPlistContent(keepAlive: Bool, executablePath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(xmlEscaped(executablePath))</string>
            </array>
            <key>KeepAlive</key>
            <\(keepAlive ? "true" : "false")/>
            <key>RunAtLoad</key>
            <true/>
            <key>ThrottleInterval</key>
            <integer>30</integer>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
            <key>ProcessType</key>
            <string>Background</string>
            <key>StandardOutPath</key>
            <string>\(xmlEscaped(Self.logPath))</string>
            <key>StandardErrorPath</key>
            <string>\(xmlEscaped(Self.logPath))</string>
        </dict>
        </plist>
        """
    }

    /// Escapa entidades XML básicas: el plist es XML y las rutas se
    /// interpolan (un `&` o `<` en el HOME rompería el documento).
    nonisolated private static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// UID del usuario de la consola (`/dev/console`), con fallback a
    /// `getuid()`. Bajo fast-user-switching el proceso puede correr con un
    /// uid distinto al de la consola visible; el dominio `gui/<uid>` debe
    /// ser el de la consola.
    nonisolated private static func activeConsoleUID() -> uid_t {
        var st = stat()
        let ok: Int32 = "/dev/console".withCString { ptr in stat(ptr, &st) }
        if ok == 0, st.st_uid != 0, getpwuid(st.st_uid) != nil {
            return st.st_uid
        }
        return getuid()
    }

    private var uid: String { String(Self.activeConsoleUID()) }
    private var guiDomain: String { "gui/\(uid)" }
    private var serviceTarget: String { "\(guiDomain)/\(Self.label)" }

    /// Resuelve el binario de Honeygain desde su Info.plist
    /// (`CFBundleExecutable`) en vez de hardcodear el nombre, para sobrevivir
    /// a updates que lo renombren. Requiere que sea ejecutable.
    nonisolated static func resolvedExecutablePath() -> String {
        let path = HoneygainInstaller.executablePath(
            of: URL(fileURLWithPath: honeygainPath),
            fallbackName: honeygainExecutableName
        )
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return honeygainPath + "/Contents/MacOS/" + honeygainExecutableName
    }

    private func desiredPlistContent() -> String {
        Self.expectedPlistContent(
            keepAlive: keepAliveEnabled,
            executablePath: Self.resolvedExecutablePath()
        )
    }

    /// Lee el KeepAlive real del plist en disco (nil si no existe o usa forma
    /// de diccionario editada a mano, para no pisar el interruptor a ciegas).
    private func readKeepAliveFromDisk() -> Bool? {
        guard let data = try? Data(contentsOf: Self.plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        guard let value = plist["KeepAlive"] else { return false }
        if let b = value as? Bool { return b }
        return nil
    }

    /// KeepAlive que debe proponer el pop de instalación: el estado real del
    /// plist si existe; sin plist, la última elección del usuario — **ON por
    /// defecto**, y OFF si el usuario lo desactivó alguna vez.
    var installKeepAliveDefault: Bool {
        readKeepAliveFromDisk() ?? keepAliveEnabled
    }

    // MARK: - Estado

    func refresh() async {
        honeygainInstalled = FileManager.default.fileExists(atPath: Self.honeygainPath)
        plistExists = FileManager.default.fileExists(atPath: Self.plistPath)
        let (loaded, output) = await servicePrint()
        agentLoaded = loaded
        if loaded {
            let stats = Self.parseServiceStats(output)
            restartCount = stats.runs
            lastExitCode = stats.lastExit
            crashLoopSuspected = (stats.runs ?? 0) >= 5 && (stats.lastExit ?? 0) != 0
        } else {
            restartCount = nil
            lastExitCode = nil
            crashLoopSuspected = false
        }
        honeygainRunning = await isHoneygainRunning()
        if let onDisk = readKeepAliveFromDisk(), onDisk != keepAliveEnabled {
            keepAliveEnabled = onDisk
        }
        // La rotación solo es segura con el job descargado: launchd mantiene
        // abierto el fd del log mientras el agente está cargado.
        if !agentLoaded {
            Self.rotateLogsIfNeeded()
        }
        logSize = Self.formattedLogSize()
    }

    private func servicePrint() async -> (loaded: Bool, output: String) {
        let (code, out) = await run("/bin/launchctl", ["print", serviceTarget])
        return (code == 0, out)
    }

    /// Espera hasta que el servicio deje de estar cargado. `bootout` solo
    /// solicita la descarga; un `bootstrap` inmediato compite con el
    /// desmontaje y falla con "Input/output error" (código 5).
    private func waitForUnload(timeoutSeconds: Int) async {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if !(await servicePrint()).loaded { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Extrae `runs = N` y `last exit code = X` del `launchctl print`.
    nonisolated private static func parseServiceStats(_ output: String) -> (runs: Int?, lastExit: Int?) {
        var runs: Int?
        var lastExit: Int?
        for line in output.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("runs = ") {
                runs = Int(t.dropFirst("runs = ".count).trimmingCharacters(in: .whitespaces))
            } else if t.hasPrefix("last exit code = ") {
                lastExit = Int(t.dropFirst("last exit code = ".count).trimmingCharacters(in: .whitespaces))
            }
        }
        return (runs, lastExit)
    }

    private static let logSizeFormatter: ByteCountFormatter = {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt
    }()

    private static func formattedLogSize() -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let size = attrs[.size] as? UInt64
        else { return nil }
        return logSizeFormatter.string(fromByteCount: Int64(size))
    }

    /// Detección en dos niveles:
    /// 1. `NSWorkspace` por bundle ID (exacto, no confunde HoneygainKeeper).
    /// 2. Fallback `pgrep -x Honeygain` (exacto) + `pgrep -f <binario>` por si
    ///    el agent lanzó el binario fuera del contexto de app registrada.
    private func isHoneygainRunning() async -> Bool {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.honeygainBundleID
        }
        if running { return true }
        let (exactCode, _) = await run("/usr/bin/pgrep", ["-x", Self.honeygainExecutableName])
        if exactCode == 0 { return true }
        let binary = Self.resolvedExecutablePath()
        let (fullCode, _) = await run("/usr/bin/pgrep", ["-f", binary])
        return fullCode == 0
    }

    // MARK: - Install

    func install() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        // Re-chequear contra disco (no fiarse del @Published cacheado).
        let installed = FileManager.default.fileExists(atPath: Self.honeygainPath)
        honeygainInstalled = installed
        guard installed else {
            message = String(localized: "Honeygain no está instalado en /Applications. Usa «Descargar e instalar» o descárgalo desde honeygain.com.")
            await refresh()
            return
        }

        let executable = Self.resolvedExecutablePath()
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            message = String(localized: "No se encontró el ejecutable de Honeygain. La instalación puede estar incompleta; vuelve a instalarlo con «Descargar e instalar».")
            await refresh()
            return
        }

        let desired = Self.expectedPlistContent(keepAlive: keepAliveEnabled, executablePath: executable)
        let (currentlyLoaded, _) = await servicePrint()
        let existingContent = try? String(contentsOf: Self.plistURL, encoding: .utf8)

        if currentlyLoaded && existingContent == desired {
            message = String(localized: "El LaunchAgent ya está instalado y activo.")
            await refresh()
            return
        }

        // Punto seguro para rotar logs: el job viejo ya está descargado
        // (o nunca estuvo cargado).
        if currentlyLoaded {
            _ = await run("/bin/launchctl", ["bootout", serviceTarget])
            // bootout es asíncrono: si se hace bootstrap de inmediato,
            // launchd aún está desmontando el job y falla con
            // "Input/output error" (código 5). Esperar la descarga real.
            await waitForUnload(timeoutSeconds: 8)
        }
        Self.rotateLogsIfNeeded()

        do {
            try FileManager.default.createDirectory(
                at: Self.plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try desired.write(to: Self.plistURL, atomically: true, encoding: .utf8)
            // El plist debe ser legible por launchd pero no escribible por grupo/otros.
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: Self.plistPath)
        } catch {
            message = String(localized: "No se pudo guardar la configuración del servicio: \(error.localizedDescription)")
            await refresh()
            return
        }

        var (code, out): (Int32, String) = (-1, "")
        for attempt in 1...3 {
            (code, out) = await run("/bin/launchctl", ["bootstrap", guiDomain, Self.plistPath])
            if code == 0 { break }
            // launchd puede tardar en soltar el job tras bootout
            // ("Input/output error") o aún verlo cargado: descargar,
            // esperar a que se desmonte y reintentar.
            if attempt < 3,
               Self.isAlreadyExists(code: code, output: out) || Self.isTransient(code: code, output: out)
            {
                _ = await run("/bin/launchctl", ["bootout", serviceTarget])
                await waitForUnload(timeoutSeconds: 5)
                continue
            }
            break
        }

        if code != 0, (await servicePrint()).loaded {
            // El bootstrap devolvió error pero el servicio quedó cargado.
            code = 0
        }

        if code != 0 {
            message = String(localized: "El servicio no se pudo cargar (código \(Int(code))): \(Self.cleanOutput(out))")
            await refresh()
            return
        }

        // `bootstrap` con RunAtLoad debería arrancar el job, pero si launchd
        // lo deja en estado cargado-sin-correr, forzar arranque.
        if !(await servicePrint()).loaded {
            _ = await run("/bin/launchctl", ["kickstart", "-k", serviceTarget])
        }

        await refresh()
        if agentLoaded {
            message = keepAliveEnabled
                ? String(localized: "Servicio instalado y en marcha. Honeygain se relanzará automáticamente si se cierra.")
                : String(localized: "Servicio instalado. Honeygain se abrirá al iniciar sesión, pero no se relanzará si lo cierras.")
        } else {
            message = String(localized: "El servicio se instaló, pero aún no aparece como activo. Revisa la sección Registros.")
        }
    }

    // MARK: - Uninstall

    func uninstall() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        if (await servicePrint()).loaded {
            let (code, out) = await run("/bin/launchctl", ["bootout", serviceTarget])
            // `bootout` detiene el proceso gestionado por launchd; no se hace
            // `pkill` extra para no matar una instancia lanzada manualmente.
            // Solo abortar si el fallo es real: re-chequear estado como
            // autoridad en vez de fiarse del mensaje (depende de locale).
            if code != 0, (await servicePrint()).loaded, !Self.isNotFound(code: code, output: out) {
                message = String(localized: "No se pudo detener el servicio (código \(Int(code))): \(Self.cleanOutput(out))")
                await refresh()
                return
            }
        }
        do {
            if FileManager.default.fileExists(atPath: Self.plistPath) {
                try FileManager.default.removeItem(at: Self.plistURL)
            }
            message = String(localized: "Servicio desinstalado. Honeygain ya no se gestionará automáticamente.")
        } catch {
            message = String(localized: "No se pudo eliminar la configuración del servicio: \(error.localizedDescription)")
        }
        await refresh()
    }

    // MARK: - Instalar Honeygain desde la fuente oficial

    /// Descarga Honeygain desde la infraestructura oficial (feed Sparkle de
    /// su propia app), verifica firma e identificador, y lo copia a
    /// /Applications. Cancela limpiamente con Task.cancel().
    func installHoneygainFromOfficial() async {
        guard !isBusy else { return }
        if FileManager.default.fileExists(atPath: Self.honeygainPath) {
            await refresh()
            return
        }
        isBusy = true
        defer {
            isBusy = false
            hgDownloading = false
        }
        hgDownloading = true
        hgDownloadPhase = String(localized: "Contactando con el servidor oficial…")
        HoneygainInstaller.cleanupStaleTempDirs()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hk-hg-\(UUID().uuidString)", isDirectory: true)
        let mnt = tmp.appendingPathComponent("mnt", isDirectory: true)
        var mounted = false
        var outcome: String
        do {
            let (dmgURL, length) = try await HoneygainInstaller.fetchOfficialDmg()
            try Task.checkCancellation()
            hgDownloadPhase = String(localized: "Descargando Honeygain…")
            let dmg = try await HoneygainInstaller.downloadDmg(url: dmgURL, expectedLength: length, dir: tmp)
            try Task.checkCancellation()
            hgDownloadPhase = String(localized: "Abriendo la imagen descargada…")
            try FileManager.default.createDirectory(at: mnt, withIntermediateDirectories: true)
            let (ac, ao) = await run("/usr/bin/hdiutil", [
                "attach", "-nobrowse", "-readonly", "-mountpoint", mnt.path, dmg.path,
            ])
            guard ac == 0 else {
                throw HoneygainInstaller.Error(message: String(localized: "No se pudo abrir la imagen descargada: \(Self.cleanOutput(ao))"))
            }
            mounted = true
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: mnt, includingPropertiesForKeys: nil
            )) ?? []
            let apps = contents.filter { $0.pathExtension == "app" }
            guard let appURL = apps.first(where: { $0.lastPathComponent == "Honeygain.app" }) ?? apps.first else {
                throw HoneygainInstaller.Error(message: String(localized: "La imagen no contiene la aplicación de Honeygain."))
            }
            hgDownloadPhase = String(localized: "Verificando la firma digital…")
            let (vc, _) = await run("/usr/bin/codesign", [
                "--verify", "--deep", "--strict", appURL.path,
            ])
            guard vc == 0 else {
                throw HoneygainInstaller.Error(message: String(localized: "La firma digital no es válida. Instalación cancelada por seguridad."))
            }
            // Además de que la firma sea válida, debe pertenecer a Honeygain
            // UAB: un binario adhoc con el mismo bundle ID no pasa.
            guard await HoneygainInstaller.teamIdentifier(of: appURL) == HoneygainInstaller.teamID else {
                throw HoneygainInstaller.Error(message: String(localized: "La firma digital no pertenece a Honeygain. Instalación cancelada por seguridad."))
            }
            guard HoneygainInstaller.bundleID(of: appURL) == Self.honeygainBundleID else {
                throw HoneygainInstaller.Error(message: String(localized: "El archivo descargado no es la aplicación oficial de Honeygain. Instalación cancelada."))
            }
            hgDownloadPhase = String(localized: "Comprobando compatibilidad…")
            let downloadedVersion = HoneygainInstaller.shortVersion(of: appURL) ?? "?"
            guard await HoneygainInstaller.isRunnableOnThisMac(appURL, fallbackExecutableName: Self.honeygainExecutableName) else {
                throw HoneygainInstaller.Error(message: String(localized: "La versión \(downloadedVersion) no puede ejecutarse en este Mac. Instala Rosetta o descarga Honeygain desde su sitio oficial."))
            }
            try Task.checkCancellation()
            hgDownloadPhase = String(localized: "Instalando en /Applications…")
            if !FileManager.default.fileExists(atPath: Self.honeygainPath) {
                // La copia (~decenas de MB) corre fuera del hilo principal
                // para no congelar la UI.
                let source = appURL
                let destination = URL(fileURLWithPath: Self.honeygainPath)
                do {
                    try await Task.detached(priority: .utility) {
                        try FileManager.default.copyItem(at: source, to: destination)
                    }.value
                } catch {
                    throw HoneygainInstaller.Error(message: String(localized: "No se pudo copiar Honeygain a /Applications por falta de permisos. Descárgalo desde su sitio oficial e instálalo manualmente."))
                }
            }
            outcome = String(localized: "Honeygain \(downloadedVersion) se instaló correctamente en /Applications. Ya puedes instalar el LaunchAgent.")
        } catch is CancellationError {
            outcome = String(localized: "Descarga cancelada. No se ha realizado ningún cambio.")
        } catch let e as HoneygainInstaller.Error {
            outcome = e.message
        } catch {
            outcome = String(localized: "La instalación no se pudo completar: \(error.localizedDescription)")
        }
        if mounted {
            let (dc, _) = await run("/usr/bin/hdiutil", ["detach", mnt.path])
            if dc != 0 {
                // Spotlight o un antivirus pueden tener el volumen ocupado;
                // forzar el desmontaje para no dejar el DMG colgado.
                _ = await run("/usr/bin/hdiutil", ["detach", "-force", mnt.path])
            }
        }
        let cleanupURL = tmp
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: cleanupURL)
        }.value
        message = outcome
        await refresh()
    }

    // MARK: - Reinicio

    /// Fuerza el reinicio de Honeygain gestionado por launchd
    /// (`kickstart -k`: mata la instancia actual y arranca una nueva).
    func restartHoneygain() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        guard (await servicePrint()).loaded else {
            message = String(localized: "El servicio no está instalado. Instálalo primero.")
            await refresh()
            return
        }
        let (code, out) = await run("/bin/launchctl", ["kickstart", "-k", serviceTarget])
        if code != 0 {
            message = String(localized: "No se pudo reiniciar Honeygain (código \(Int(code))): \(Self.cleanOutput(out))")
            await refresh()
            return
        }
        // Dar un instante a launchd para arrancar el proceso nuevo antes de
        // consultar el estado.
        try? await Task.sleep(for: .seconds(1))
        message = String(localized: "Honeygain se ha reiniciado.")
        await refresh()
    }

    // MARK: - Logs

    /// Archivos de log existentes: actual + rotados (.1/.2/.3).
    nonisolated static func availableLogURLs() -> [URL] {
        var urls = [logURL]
        for i in 1...logGenerations {
            let u = logURL.appendingPathExtension("\(i)")
            if FileManager.default.fileExists(atPath: u.path) {
                urls.append(u)
            }
        }
        return urls
    }

    nonisolated static func logDisplayName(for url: URL) -> String {
        if url == logURL { return String(localized: "Actual") }
        if let generation = Int(url.pathExtension) {
            return String(localized: "Anterior \(generation)")
        }
        return url.lastPathComponent
    }

    /// "1 línea." / "N líneas." — frase completa para que la traducción
    /// mantenga la concordancia sin ensamblar fragmentos.
    nonisolated private static func linesSentence(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 línea.")
            : String(localized: "\(count) líneas.")
    }

    /// Carga la cola del log (últimos 256 KB / 1000 líneas) fuera del hilo
    /// principal y publica las líneas, aplicando el filtro si se indica.
    func loadLogLines(from url: URL, filter: String = "") async {
        let snapshot = await Task.detached(priority: .utility) {
            Self.readTailLines(from: url, maxBytes: 256 * 1024, maxLines: 1000)
        }.value
        let shown = snapshot.lines.count
        let f = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if f.isEmpty {
            logLines = snapshot.lines
        } else {
            logLines = snapshot.lines.filter { $0.localizedCaseInsensitiveContains(f) }
        }
        logTailTruncated = snapshot.truncated
        if !FileManager.default.fileExists(atPath: url.path) {
            logViewerMessage = String(localized: "Todavía no hay registros.")
        } else if shown == 0 {
            logViewerMessage = String(localized: "El archivo está vacío.")
        } else if !f.isEmpty {
            if logLines.count == shown {
                logViewerMessage = Self.linesSentence(shown)
            } else {
                logViewerMessage = shown == 1
                    ? String(localized: "\(logLines.count) de 1 línea.")
                    : String(localized: "\(logLines.count) de \(shown) líneas.")
            }
        } else if snapshot.truncated {
            logViewerMessage = shown == 1
                ? String(localized: "Mostrando la última línea (máx. 256 KB).")
                : String(localized: "Mostrando las últimas \(shown) líneas (máx. 256 KB).")
        } else {
            logViewerMessage = Self.linesSentence(shown)
        }
    }

    /// Lee la cola de un archivo: últimos `maxBytes`, máx. `maxLines`.
    /// Si el archivo es mayor que el chunk, se descarta la primera línea
    /// por estar potencialmente cortada a mitad de un caracter multibyte.
    nonisolated private static func readTailLines(from url: URL, maxBytes: Int, maxLines: Int) -> (lines: [String], truncated: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ([], false)
        }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize = min(UInt64(maxBytes), fileSize)
        guard readSize > 0 else { return ([], false) }
        do {
            try handle.seek(toOffset: fileSize - readSize)
            guard let data = try handle.read(upToCount: Int(readSize)), !data.isEmpty else {
                return ([], false)
            }
            var lines = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
            var truncated = fileSize > readSize
            if truncated, !lines.isEmpty { lines.removeFirst() }
            if lines.last?.isEmpty == true { lines.removeLast() }
            if lines.count > maxLines {
                lines = Array(lines.suffix(maxLines))
                truncated = true
            }
            return (lines, truncated)
        } catch {
            return ([], false)
        }
    }

    /// Vacía el log actual. Seguro con el job en marcha (truncate del fd).
    func clearLogs() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if FileManager.default.fileExists(atPath: Self.logPath) {
                let handle = try FileHandle(forWritingTo: Self.logURL)
                try handle.truncate(atOffset: 0)
                try handle.close()
            }
            message = String(localized: "Registro vaciado.")
        } catch {
            message = String(localized: "No se pudo vaciar el registro: \(error.localizedDescription)")
        }
        await refresh()
    }

    /// Rota honeygain-keepalive.log a .1/.2/.3 al superar el umbral.
    /// Llamar solo en punto seguro (job detenido), porque launchd mantiene
    /// el fd abierto del log actual.
    nonisolated private static func rotateLogsIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let size = attrs[.size] as? UInt64, size > maxLogBytes
        else { return }
        let fm = FileManager.default
        for i in stride(from: logGenerations - 1, through: 1, by: -1) {
            let src = "\(logPath).\(i)"
            let dst = "\(logPath).\(i + 1)"
            if fm.fileExists(atPath: src) {
                try? fm.removeItem(atPath: dst)
                try? fm.moveItem(atPath: src, toPath: dst)
            }
        }
        try? fm.removeItem(atPath: "\(logPath).1")
        try? fm.moveItem(atPath: logPath, toPath: "\(logPath).1")
    }

    // MARK: - Helpers launchctl

    /// Códigos primero (37 ya-cargado / 17 EEXIST), strings solo como fallback
    /// porque dependen del idioma del sistema.
    nonisolated private static func isAlreadyExists(code: Int32, output: String) -> Bool {
        if code == 37 || code == 17 { return true }
        let lower = output.lowercased()
        return lower.contains("already") && (lower.contains("exist") || lower.contains("loaded") || lower.contains("bootstrapped"))
    }

    /// 113 = no encontrado; el re-chequeo de estado en el llamador es la
    /// autoridad final, no el mensaje.
    nonisolated private static func isNotFound(code: Int32, output: String) -> Bool {
        if code == 113 { return true }
        let lower = output.lowercased()
        return lower.contains("could not find service")
            || lower.contains("no such process")
            || lower.contains("not found")
            || lower.contains("not running")
            || lower.contains("no such file")
    }

    /// Error transitorio de `bootstrap` tras un `bootout` reciente:
    /// launchd aún está desmontando el job ("Input/output error", código 5).
    /// Reintentable tras descargar y esperar.
    nonisolated private static func isTransient(code: Int32, output: String) -> Bool {
        if code == 5 { return true }
        return output.lowercased().contains("input/output error")
    }

    nonisolated private static func cleanOutput(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "sin detalles" : trimmed
    }

    // MARK: - Ejecución fuera del hilo principal

    /// Ejecuta un binario fuera del MainActor y devuelve (código, salida).
    private func run(_ path: String, _ args: [String]) async -> (Int32, String) {
        await ProcessRunner.run(path, args)
    }
}
