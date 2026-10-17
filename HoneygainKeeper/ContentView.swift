import AppKit
import SwiftUI

// MARK: - Navegación

enum Panel: String, CaseIterable, Identifiable {
    case overview
    case logs

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Resumen"
        case .logs: "Registros"
        }
    }

    var icon: String {
        switch self {
        case .overview: "speedometer"
        case .logs: "terminal.fill"
        }
    }
}

struct ContentView: View {
    @ObservedObject var manager: LaunchAgentManager
    @State private var selection: Panel? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Panel") {
                    ForEach(Panel.allCases) { panel in
                        Label(panel.title, systemImage: panel.icon)
                            .tag(panel)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                Text("HoneygainKeeper v\(Self.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        } detail: {
            switch selection ?? .overview {
            case .overview:
                OverviewView(manager: manager)
            case .logs:
                LogsView(manager: manager)
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .task {
            await manager.refresh()
            while !Task.isCancelled {
                // En segundo plano el polling se relaja para no gastar energía.
                let interval = NSApplication.shared.isActive ? 5 : 30
                try? await Task.sleep(for: .seconds(interval))
                if !manager.isBusy {
                    await manager.refresh()
                }
            }
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

// MARK: - Resumen

struct OverviewView: View {
    @ObservedObject var manager: LaunchAgentManager
    @Namespace private var glassNamespace
    @State private var showInstallPop = false
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !manager.message.isEmpty {
                    messageBanner
                }
                if !manager.honeygainInstalled {
                    downloadCard
                }
                statusGrid
                activityCard
                if manager.crashLoopSuspected {
                    crashBanner
                }
                actions
            }
            .padding(28)
        }
        .navigationTitle("Resumen")
        .background(alignment: .top) {
            LinearGradient(
                colors: [.orange.opacity(0.12), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 320)
            .ignoresSafeArea()
        }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
                .clipShape(.rect(cornerRadius: 15))
                .shadow(color: .orange.opacity(0.35), radius: 12, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("HoneygainKeeper")
                    .font(.title.bold())
                Text("Mantiene Honeygain activo en tu Mac")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        let state: (label: LocalizedStringKey, color: Color) = if !manager.honeygainInstalled {
            ("Honeygain no instalado", .gray)
        } else if manager.agentLoaded && manager.honeygainRunning {
            ("Protegido", .green)
        } else if manager.agentLoaded || manager.honeygainRunning {
            ("Parcial", .orange)
        } else {
            ("Detenido", .red)
        }
        return HStack(spacing: 8) {
            Circle()
                .fill(state.color)
                .frame(width: 10, height: 10)
                .shadow(color: state.color, radius: 6)
            Text(state.label)
                .font(.callout.bold())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(state.color.opacity(0.35)), in: Capsule())
    }

    // MARK: Descarga de Honeygain

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Honeygain no está instalado")
                        .font(.headline)
                    Text("Se descargará desde el canal oficial y se instalará en /Applications.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if manager.hgDownloading {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(manager.hgDownloadPhase)
                        .font(.callout)
                    Spacer()
                    Button("Cancelar", systemImage: "xmark") {
                        downloadTask?.cancel()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            } else {
                HStack(spacing: 12) {
                    Button("Descargar e instalar", systemImage: "arrow.down.circle") {
                        downloadTask = Task {
                            await manager.installHoneygainFromOfficial()
                            downloadTask = nil
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(manager.isBusy)
                    .help("Descarga la última versión oficial y la instala en /Applications.")
                    Link(destination: URL(string: "https://www.honeygain.com/download/")!) {
                        Label("Sitio oficial", systemImage: "safari")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .help("Abrir honeygain.com en tu navegador.")
                    Spacer()
                }
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .rect(cornerRadius: 20))
    }

    // MARK: Tarjetas de estado

    private var statusGrid: some View {
        GlassEffectContainer(spacing: 12) {
            LazyVGrid(
                columns: [.init(.flexible()), .init(.flexible())],
                spacing: 12
            ) {
                StatusCard(
                    title: "Honeygain",
                    value: manager.honeygainInstalled ? "Instalado" : "No instalado",
                    ok: manager.honeygainInstalled,
                    icon: "app.fill",
                    glassID: "status-honeygain",
                    namespace: glassNamespace
                )
                StatusCard(
                    title: "LaunchAgent (plist)",
                    value: manager.plistExists ? "Instalado" : "No instalado",
                    ok: manager.plistExists,
                    icon: "doc.fill",
                    glassID: "status-plist",
                    namespace: glassNamespace
                )
                StatusCard(
                    title: "Agente cargado",
                    value: manager.agentLoaded ? "Sí" : "No",
                    ok: manager.agentLoaded,
                    icon: "bolt.fill",
                    glassID: "status-loaded",
                    namespace: glassNamespace
                )
                StatusCard(
                    title: "En ejecución",
                    value: manager.honeygainRunning ? "Sí" : "No",
                    ok: manager.honeygainRunning,
                    icon: "play.fill",
                    glassID: "status-running",
                    namespace: glassNamespace
                )
            }
        }
    }

    // MARK: Actividad

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actividad")
                .font(.headline)
            LabeledContent("Reinicios del agente", value: manager.restartCount.map(String.init) ?? "—")
            Divider()
            LabeledContent {
                Text(lastExitText).foregroundStyle(lastExitColor)
            } label: {
                Text("Última salida")
            }
            Divider()
            LabeledContent("Tamaño del registro", value: manager.logSize ?? "—")
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var lastExitText: LocalizedStringKey {
        guard let code = manager.lastExitCode else { return "—" }
        return code == 0 ? "Correcta (0)" : "Error (código \(code))"
    }

    private var lastExitColor: Color {
        guard let code = manager.lastExitCode else { return .primary }
        return code == 0 ? .green : .red
    }

    // MARK: Avisos y acciones

    private var crashBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Honeygain se está reiniciando repetidamente por errores. Abre «Registros» para ver los detalles.")
                .font(.callout)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.orange.opacity(0.3)), in: .rect(cornerRadius: 16))
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Instalar LaunchAgent", systemImage: "arrow.down.circle.fill") {
                showInstallPop = true
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!manager.honeygainInstalled || manager.isBusy)
            .help(manager.honeygainInstalled
                ? "Instala o reinstala el LaunchAgent. Desde aquí puedes cambiar la opción «Mantener siempre activo»."
                : "Instala Honeygain antes de activar el servicio.")
            .popover(isPresented: $showInstallPop, arrowEdge: .bottom) {
                InstallOptionsPopover(manager: manager, isPresented: $showInstallPop)
            }
            Button("Reiniciar", systemImage: "arrow.triangle.2.circlepath") {
                Task { await manager.restartHoneygain() }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(!manager.agentLoaded || manager.isBusy)
            .help("Cierra y vuelve a abrir Honeygain ahora.")
            Button("Desinstalar", systemImage: "trash") {
                Task { await manager.uninstall() }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled((!manager.plistExists && !manager.agentLoaded) || manager.isBusy)
            .help("Detiene el servicio y elimina su configuración. Honeygain seguirá instalado.")
            Button("Actualizar", systemImage: "arrow.clockwise") {
                Task { await manager.refresh() }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(manager.isBusy)
            .help("Actualiza el estado ahora.")
            if manager.isBusy {
                ProgressView()
                    .scaleEffect(0.8)
            }
            Spacer()
        }
    }

    private var messageBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text(manager.message)
                .font(.callout)
            Spacer()
            Button {
                manager.message = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Descartar el mensaje")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.blue.opacity(0.22)), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Tarjeta de estado

struct StatusCard: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey
    let ok: Bool
    let icon: String
    let glassID: String
    let namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background((ok ? Color.green : Color.red).gradient, in: Circle())
                Spacer()
                Circle()
                    .fill(ok ? .green : .red)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.bold())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffectID(glassID, in: namespace)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }
}

// MARK: - Pop de instalación

/// Pop previo a la instalación: elige "Mantener siempre activo" antes
/// de instalar. Usa estado local para que Cancelar no deje efectos.
struct InstallOptionsPopover: View {
    @ObservedObject var manager: LaunchAgentManager
    @Binding var isPresented: Bool
    @State private var keepAlive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Instalar LaunchAgent")
                        .font(.headline)
                    Text("Elige cómo quieres mantener activo Honeygain.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $keepAlive) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mantener siempre activo")
                        .font(.callout.bold())
                    Text("Activado: si cierras Honeygain, se vuelve a abrir automáticamente. Desactivado: solo se abre al iniciar sesión.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            HStack {
                Spacer()
                Button("Cancelar") {
                    isPresented = false
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                Button("Instalar", systemImage: "checkmark") {
                    manager.keepAliveEnabled = keepAlive
                    isPresented = false
                    Task { await manager.install() }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 370)
        .onAppear {
            // Refleja el plist real; sin plist, la última elección del
            // usuario (ON por defecto).
            keepAlive = manager.installKeepAliveDefault
        }
    }
}
