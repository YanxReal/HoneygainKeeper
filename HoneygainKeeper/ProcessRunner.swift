import Foundation

/// Ejecutor de procesos auxiliares (`launchctl`, `pgrep`, `hdiutil`…).
///
/// `runSync` drena el pipe **antes** de esperar al proceso: si se espera
/// primero, un hijo que llene el buffer del pipe (64 KB) se queda bloqueado
/// escribiendo y el padre esperando su salida — deadlock. `launchctl print`
/// puede superar ese buffer, así que el orden importa.
enum ProcessRunner {
    nonisolated static func runSync(_ path: String, _ args: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        // Drenar primero, esperar después (evita el deadlock del pipe).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Versión async: el trabajo corre fuera del actor que llama.
    static func run(_ path: String, _ args: [String]) async -> (Int32, String) {
        await Task.detached(priority: .utility) {
            runSync(path, args)
        }.value
    }
}
