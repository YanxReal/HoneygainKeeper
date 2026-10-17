import AppKit
import SwiftUI

/// Registros del LaunchAgent: cola del archivo actual o rotados, con
/// búsqueda, seguimiento (tail), copia y exportación.
struct LogsView: View {
    @ObservedObject var manager: LaunchAgentManager

    @State private var files: [URL] = LaunchAgentManager.availableLogURLs()
    @State private var selectedLog: URL = LaunchAgentManager.logURL
    @State private var filter = ""
    @State private var follow = true

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            Divider()
            logList
            footer
        }
        .navigationTitle("Registros")
        .searchable(text: $filter, prompt: Text("Buscar en el registro"))
        .task(id: selectedLog) {
            refreshFileList()
            await reload()
        }
        .task(id: filter) {
            // Anti-rebote: no releer el archivo en cada tecla.
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled {
                await reload()
            }
        }
        .task(id: follow) {
            while follow, !Task.isCancelled {
                let interval = NSApplication.shared.isActive ? 2 : 15
                try? await Task.sleep(for: .seconds(interval))
                if follow, !manager.isBusy {
                    refreshFileList()
                    await reload()
                }
            }
        }
    }

    // MARK: Controles

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Archivo", selection: $selectedLog) {
                ForEach(files, id: \.self) { url in
                    Text(LaunchAgentManager.logDisplayName(for: url)).tag(url)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)
            .help("Archivo de registro que se muestra")
            Spacer()
            Toggle("Seguir", isOn: $follow)
                .toggleStyle(.checkbox)
                .help("Desplazarse automáticamente a las líneas nuevas")
            Button {
                copyFiltered()
            } label: {
                Label("Copiar", systemImage: "square.on.square")
            }
            .buttonStyle(.glass)
            .disabled(manager.logLines.isEmpty)
            .help("Copia las líneas visibles al portapapeles")
            ShareLink(item: selectedLog) {
                Label("Exportar", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glass)
            .disabled(!FileManager.default.fileExists(atPath: selectedLog.path))
            .help("Comparte el archivo de registro")
            Button {
                Task {
                    await manager.clearLogs()
                    await reload()
                }
            } label: {
                Label("Vaciar", systemImage: "trash")
            }
            .buttonStyle(.glass)
            .disabled(manager.isBusy || manager.logSize == nil)
            .help("Vacía el registro actual. Los anteriores se conservan")
            Button("Consola") {
                openInConsole()
            }
            .buttonStyle(.glass)
            .disabled(!FileManager.default.fileExists(atPath: selectedLog.path))
            .help("Abre el registro en la app Consola")
        }
        .controlSize(.small)
    }

    // MARK: Lista

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if manager.logLines.isEmpty {
                        ContentUnavailableView(
                            "Nada que mostrar",
                            systemImage: "doc.text",
                            description: Text(
                                manager.logViewerMessage.isEmpty
                                    ? String(localized: "No hay contenido para mostrar.")
                                    : manager.logViewerMessage
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        ForEach(manager.logLines.indices, id: \.self) { i in
                            HStack(alignment: .top, spacing: 12) {
                                Text(verbatim: "\(i + 1)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 48, alignment: .trailing)
                                Text(verbatim: manager.logLines[i])
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 12)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .onChange(of: manager.logLines) { _, _ in
                if follow {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: Pie

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text(manager.logViewerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if manager.logTailTruncated {
                    Text("Vista parcial · numeración relativa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: Datos

    private func refreshFileList() {
        let urls = LaunchAgentManager.availableLogURLs()
        files = urls
        if !urls.contains(selectedLog) {
            selectedLog = LaunchAgentManager.logURL
        }
    }

    private func reload() async {
        refreshFileList()
        await manager.loadLogLines(from: selectedLog, filter: filter)
    }

    private func copyFiltered() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            manager.logLines.joined(separator: "\n"),
            forType: .string
        )
    }

    /// Abre el archivo en Consola.app (el doble clic normal abriría el editor
    /// de texto predeterminado, que no es lo útil para un log).
    private func openInConsole() {
        guard FileManager.default.fileExists(atPath: selectedLog.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Console", selectedLog.path]
        try? process.run()
    }
}
