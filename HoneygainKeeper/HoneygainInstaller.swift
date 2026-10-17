import Foundation

/// Pipeline de descarga y verificación de Honeygain desde su infraestructura
/// oficial (feed Sparkle de la propia app, `appcast.xml`).
///
/// Todo es `nonisolated` y sin estado propio para poder ejecutarse fuera del
/// MainActor. La orquestación (estados de UI, montaje del DMG, copia a
/// /Applications) vive en `LaunchAgentManager`.
enum HoneygainInstaller {
    /// Equipo de firma de Honeygain UAB, comprobado en la 1.5.2 (feed) y la
    /// 1.5.4 (web). Un binario que no esté firmado por este equipo se
    /// rechaza aunque tenga el mismo bundle ID.
    static let teamID = "L4S6563XXV"

    struct Error: Swift.Error {
        let message: String
    }

    /// Sesión dedicada a descargas: sin caché y con límites de tiempo (una
    /// conexión estancada no puede dejar la instalación colgada para siempre).
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 15 * 60
        return URLSession(configuration: config)
    }()

    // MARK: - Feed Sparkle

    /// Lee el feed oficial y devuelve el DMG vigente. El host se fija para no
    /// seguir URLs inesperadas.
    static func fetchOfficialDmg() async throws -> (URL, Int64?) {
        let feed = URL(string: "https://resources.honeygain.com/macos-app/appcast.xml")!
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: feed)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Error(message: String(localized: "No se pudo conectar con honeygain.com. Comprueba tu conexión e inténtalo de nuevo."))
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw Error(message: String(localized: "El servidor de descargas respondió con un error (\(code)). Inténtalo más tarde o descarga Honeygain desde su sitio oficial."))
        }
        guard let xml = String(data: data, encoding: .utf8),
              // Nota: firstMatch devuelve el grupo 1, el patrón lo incluye.
              let tag = firstMatch(pattern: "(<enclosure[^>]*>)", in: xml),
              let urlString = firstMatch(pattern: "url=\"([^\"]+)\"", in: tag),
              let url = URL(string: urlString),
              url.scheme == "https",
              url.host == "resources.honeygain.com"
        else {
            throw Error(message: String(localized: "El servidor de descargas devolvió una respuesta inesperada. Descarga Honeygain desde su sitio oficial."))
        }
        let length = firstMatch(pattern: "length=\"(\\d+)\"", in: tag).flatMap(Int64.init)
        return (url, length)
    }

    /// Descarga el DMG a `dir` y verifica el tamaño contra el appcast.
    /// La cancelación se normaliza a `CancellationError` (UI: "cancelada"),
    /// porque URLSession la reporta como `URLError .cancelled`.
    static func downloadDmg(url: URL, expectedLength: Int64?, dir: URL) async throws -> URL {
        try Task.checkCancellation()
        let tmpURL: URL
        do {
            (tmpURL, _) = try await session.download(from: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Error(message: String(localized: "La descarga se interrumpió. Comprueba tu conexión e inténtalo de nuevo."))
        }
        try Task.checkCancellation()
        if let expectedLength {
            let size = (try? FileManager.default.attributesOfItem(atPath: tmpURL.path)[.size] as? UInt64) ?? 0
            guard Int64(size) == expectedLength else {
                try? FileManager.default.removeItem(at: tmpURL)
                throw Error(message: String(localized: "El archivo descargado está incompleto o dañado. Inténtalo de nuevo."))
            }
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("Honeygain.dmg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        return dest
    }

    // MARK: - Metadatos del bundle (sin lanzar la app)

    static func bundleID(of appURL: URL) -> String? {
        infoDictionary(of: appURL)?["CFBundleIdentifier"] as? String
    }

    static func shortVersion(of appURL: URL) -> String? {
        infoDictionary(of: appURL)?["CFBundleShortVersionString"] as? String
    }

    static func executableName(of appURL: URL, fallback: String) -> String {
        infoDictionary(of: appURL)?["CFBundleExecutable"] as? String ?? fallback
    }

    /// Ruta del ejecutable de un .app resolviéndolo desde su Info.plist.
    static func executablePath(of appURL: URL, fallbackName: String) -> String {
        let name = executableName(of: appURL, fallback: fallbackName)
        return appURL.appendingPathComponent("Contents/MacOS/\(name)", isDirectory: false).path
    }

    static func infoDictionary(of appURL: URL) -> [String: Any]? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist
    }

    /// Equipo de firma del bundle (`codesign -dv` escribe en stderr; el
    /// runner captura stdout y stderr juntos).
    static func teamIdentifier(of appURL: URL) async -> String? {
        let (_, out) = await ProcessRunner.run("/usr/bin/codesign", ["-dv", "--verbose=4", appURL.path])
        return firstMatch(pattern: "TeamIdentifier=(\\w+)", in: out)
    }

    /// Verifica que el binario pueda ejecutarse en esta Mac: nativo arm64 en
    /// Macs ARM (o x86_64 con Rosetta), x86_64 en Macs Intel. Evita dejar
    /// instalada una app que launchd no podría arrancar.
    static func isRunnableOnThisMac(_ appURL: URL, fallbackExecutableName: String) async -> Bool {
        let exec = appURL
            .appendingPathComponent("Contents/MacOS/\(executableName(of: appURL, fallback: fallbackExecutableName))", isDirectory: false)
            .path
        guard FileManager.default.isExecutableFile(atPath: exec) else { return false }
        let (code, out) = await ProcessRunner.run("/usr/bin/lipo", ["-info", exec])
        guard code == 0 else { return false }
        let (uc, unameOut) = await ProcessRunner.run("/usr/bin/uname", ["-m"])
        guard uc == 0 else { return false }
        if unameOut.contains("arm64") {
            if out.contains("arm64") { return true }
            guard out.contains("x86_64") else { return false }
            let (rc, _) = await ProcessRunner.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"])
            return rc == 0
        }
        return out.contains("x86_64")
    }

    /// Devuelve el grupo de captura 1 del primer match (los patrones deben
    /// incluir su propio grupo, p. ej. "(...)").
    static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    // MARK: - Limpieza

    /// Borra descargas temporales huérfanas de ejecuciones anteriores
    /// (cancelaciones, cierres de la app). Solo toca directorios propios
    /// (`hk-hg-`) con más de 6 horas de antigüedad, para no interferir con
    /// una descarga en curso.
    nonisolated static func cleanupStaleTempDirs() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let entries = try? fm.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-6 * 3600)
        for entry in entries where entry.lastPathComponent.hasPrefix("hk-hg-") {
            guard let date = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  date < cutoff
            else { continue }
            try? fm.removeItem(at: entry)
        }
    }
}
