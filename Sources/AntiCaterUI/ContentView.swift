import SwiftUI
import AntiCaterCore

public struct ContentView: View {
    @ObservedObject var model: DeviceModel
    @Environment(\.openWindow) private var openWindow
    @State private var confirmWrite = false
    @State private var confirmClearAll = false
    @State private var showError = false

    public init(model: DeviceModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 272, max: 320)
        } detail: {
            EditorView(model: model)
                .navigationSplitViewColumnWidth(min: 400, ideal: 480)
                .overlay(alignment: .top) { toast }
        }
        .toolbar { toolbar }
        .frame(minWidth: 780, minHeight: 560)
        // 开窗即连，但失败要静默：主窗口每显示一次就会走一遍这里（菜单栏 app
        // 关窗再开是常事），没插线的人会被反复拦住。占位页已经在讲该怎么做了。
        .onAppear { model.connect(silentOnFailure: true) }
        .onChange(of: model.errorMessage) { showError = $0 != nil }
        .animation(.easeOut(duration: 0.18), value: model.message)
        .confirmationDialog("¿Escribir \(model.changeCount) cambios en el mando?",
                            isPresented: $confirmWrite, titleVisibility: .visible) {
            Button("Escribir", role: .destructive) { model.writeChanges() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Sobrescribirá la configuración actual de las acciones correspondientes del mando; al terminar se volverá a leer para comprobarla.")
        }
        .confirmationDialog("¿Vaciar las cinco acciones del mando?",
                            isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("Vaciar", role: .destructive) { model.clearAll(in: model.layer) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Solo cambia la zona de edición; se puede deshacer hasta pulsar «Escribir en el mando».")
        }
        .alert("Se produjo un error", isPresented: $showError) {
            // 连不上时远程排障全靠这个。放在报错弹窗里而不是只在菜单深处，
            // 因为需要它的时刻就是这一刻。
            // 打开窗口而不是直接拷贝：让用户先看清要发出去的是什么再决定拷不拷。
            Button("Ver información de diagnóstico…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "diagnostics")
            }
            Button("Aceptar") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - 侧栏

    private var sidebar: some View {
        VStack(spacing: 0) {
            KnobControl(
                selection: $model.selected,
                summary: { key in
                    model.binding(key, in: model.layer).map(Summary.short) ?? "—"
                },
                isDirty: { model.isDirty($0, in: model.layer) })
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 10)

            linkBar
                .padding(.bottom, 12)

            List(selection: Binding(get: { model.selected },
                                    set: { model.selected = $0 ?? model.selected })) {
                Section("Acciones del mando") {
                    ForEach(PhysicalKey.displayOrder, id: \.self) { key in
                        row(key).tag(key)
                    }
                }

                Section("Luz") {
                    Picker("Efecto de luz", selection: Binding(get: { model.lightMode },
                                                    set: { model.setLight(mode: $0) })) {
                        ForEach(Proto.lightModes, id: \.mode) { item in
                            Text(item.name).tag(item.mode)
                        }
                    }
                    .disabled(!model.connection.isConnected || !model.lightAvailable)

                    // 连上了却读不到灯效，说明这台固件不认这组命令。说一句，
                    // 否则用户只会看到一个点不动的选择器，不知道是坏了还是没连上。
                    if model.connection.isConnected, !model.lightAvailable {
                        Text("El firmware de este mando no admite el ajuste del efecto de luz; la configuración de teclas no se ve afectada.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            Button(role: .destructive) { confirmClearAll = true } label: {
                Label("Vaciar toda la configuración", systemImage: "eraser")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(!model.connection.isConnected)
            .padding(10)
            .help("Vacía las cinco acciones del mando. Primero se pedirá confirmación y se puede deshacer antes de escribir.")
        }
    }

    /// 两条链路的在线状态。挂在旋钮图下方——工具栏太挤，放这儿正好接着旋钮读。
    private var linkBar: some View {
        HStack(spacing: 10) {
            linkBadge("Cable de datos", systemImage: "cable.connector", on: model.links.usb,
                      help: model.links.usb
                          ? "Cable USB conectado; ya se puede cambiar la configuración" : "Cable USB no conectado; para cambiar la configuración hay que conectarlo")
            linkBadge("Bluetooth", systemImage: "dot.radiowaves.left.and.right",
                      on: model.links.bluetooth,
                      help: model.links.bluetooth
                          ? "El mando está conectado a este equipo por Bluetooth. Por Bluetooth no hay canal de configuración; "
                            + "para leer y escribir la configuración hay que conectar el cable USB"
                          : "Bluetooth no conectado")
        }
        .frame(maxWidth: .infinity)
    }

    private func linkBadge(_ title: String, systemImage: String,
                           on: Bool, help: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 11, weight: .medium))
            Text(title).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(on ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(on ? Color.accentColor.opacity(0.14)
                              : Color.secondary.opacity(0.10))
        }
        .help(help)
    }

    private func row(_ key: PhysicalKey) -> some View {
        let binding = model.binding(key, in: model.layer)
        return HStack(spacing: 10) {
            Image(systemName: key.symbolName)
                .font(.system(size: 15))
                .frame(width: 22)
                .foregroundStyle(model.selected == key ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(key.label)
                    .font(.system(size: 13))
                Text(binding.map(Summary.short) ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if model.isDirty(key, in: model.layer) {
                Circle().fill(.orange).frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 3)
        .help(binding.map(Summary.full) ?? "Sin asignar")
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if model.busy { ProgressView().controlSize(.small) }

            Menu {
                Button {
                    model.connection.isConnected ? model.reload() : model.connect()
                } label: {
                    Label(model.connection.isConnected ? "Volver a leer" : "Conectar mando",
                          systemImage: model.connection.isConnected
                              ? "arrow.clockwise" : "cable.connector")
                }
                .disabled(model.busy)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .help(connectionDetail)

            if model.hasChanges {
                Button("Descartar") { model.discardChanges() }
                    .help("Volver a la configuración actual del mando")
            }

            Button {
                confirmWrite = true
            } label: {
                Text(model.hasChanges ? "Escribir en el mando (\(model.changeCount))" : "Escribir en el mando")
            }
            .keyboardShortcut("s")
            .buttonStyle(.borderedProminent)
            .disabled(!model.hasChanges || model.busy)
        }
    }

    private var connectionDetail: String {
        if case .connected(let name, let serial, let firmware) = model.connection {
            return "\(name)\nNúmero de serie \(serial)\nFirmware \(firmware)"
        }
        if model.links.bluetooth {
            return "Bluetooth conectado, pero el canal de configuración solo está por USB\nAl conectar el cable de datos se conectará automáticamente"
        }
        return "Conecta el mando al equipo con el cable USB de datos; se conectará automáticamente"
    }

    // MARK: - 瞬时提示

    /// 成功类提示浮在编辑区顶部，几秒后自己消失，不常驻占版面。
    @ViewBuilder
    private var toast: some View {
        if let message = model.message {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                }
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
