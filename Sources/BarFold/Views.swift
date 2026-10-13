import SwiftUI
import BarFoldCore

extension ItemSection {
    var label: String { switch self { case .visible: return "常驻"; case .hidden: return "折叠"; case .alwaysHidden: return "始终隐藏" } }
    var symbol: String { switch self { case .visible: return "pin"; case .hidden: return "rectangle.compress.vertical"; case .alwaysHidden: return "eye.slash" } }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    private func binding<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { model.preferences[keyPath: key] }, set: { value in model.updatePreferences { $0[keyPath: key] = value } })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "menubar.rectangle").font(.system(size: 36, weight: .light)).foregroundStyle(.teal)
                    .frame(width: 64, height: 64).background(.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text("BarFold").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("把菜单栏的空间，留给正在用的工具。").foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.mode == .collapsed ? "已折叠" : "已展开").font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }.padding(24)
            Divider()
            Form {
                Section {
                    Text("按住 ⌘ Command，把不常用的图标拖到实线 │ 左侧。点击 BarFold 箭头即可展开或折叠，右键打开菜单。")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("整理图标") { model.showPalette(arrange: true) }
                        Button(model.mode == .collapsed ? "展开" : "折叠") { model.toggle() }
                        Spacer()
                        if !model.preferences.setupCompleted {
                            Button("完成设置") { model.updatePreferences { $0.setupCompleted = true } }.buttonStyle(.borderedProminent)
                        }
                    }
                } header: { Text("先整理一次，以后轻松展开") }
                Section("折叠习惯") {
                    Picker("自动收起", selection: binding(\.autoCollapseSeconds)) {
                        Text("不自动收起").tag(0.0)
                        Text("5 秒").tag(5.0); Text("8 秒").tag(8.0); Text("15 秒").tag(15.0); Text("30 秒").tag(30.0)
                    }
                    Toggle("启动时折叠", isOn: binding(\.launchCollapsed))
                    Toggle("光标停留在箭头上时展开", isOn: binding(\.hoverToExpand))
                    Toggle("启用“始终隐藏”分区", isOn: binding(\.alwaysHiddenEnabled))
                    if model.preferences.alwaysHiddenEnabled {
                        Text("整理时将图标拖到虚线 ┊ 左侧；日常展开仍保持隐藏。“整理全部”会临时显示它们。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(model.configurationLocked)
                Section("快捷键与启动") {
                    Toggle("启用全局快捷键", isOn: binding(\.shortcutEnabled))
                    Picker("展开 / 折叠", selection: binding(\.shortcutKeyCode)) {
                        Text("⌥⌘ B").tag(UInt32(11)); Text("⌥⌘ 空格").tag(UInt32(49)); Text("⌥⌘ M").tag(UInt32(46))
                    }.disabled(!model.preferences.shortcutEnabled || model.configurationLocked)
                    Toggle("登录时启动 BarFold", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                }
                Section("图标面板 · 可选权限") {
                    permissionRow("辅助功能", detail: "用于点击和移动真实菜单栏图标", granted: model.accessibilityGranted, action: model.requestAccessibility)
                    permissionRow("屏幕录制", detail: "仅截取图标窗口；图片只保存在内存", granted: model.screenGranted, action: model.requestScreenshots)
                    Toggle("显示图标缩略图", isOn: binding(\.thumbnailsEnabled)).disabled(!model.screenGranted || model.configurationLocked)
                    Text("基础折叠不需要这些权限。图标识别受系统版本限制，未识别时显示所属应用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.message.isEmpty { Section { Text(model.message).font(.callout).foregroundStyle(.orange).textSelection(.enabled) } }
            }.formStyle(.grouped)
            HStack {
                Text("0.1.0 · 原生 macOS · 本地运行").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("图标面板") { model.showPalette() }
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(minWidth: 630, minHeight: 630)
    }
    private func permissionRow(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if granted { Label("已授权", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
            else { Button("授权", action: action) }
        }
    }
}

struct PaletteView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    private var filtered: [MenuItem] {
        model.items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.appName.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("你的菜单栏").font(.title2.weight(.semibold))
                    Text(model.mode == .allVisible ? "整理模式 · 可按住 Command 直接拖动菜单栏图标" : "点击图标打开原菜单；面板开启期间暂停自动收起")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.refreshInProgress || model.operationInProgress { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("刷新图标")
                    .disabled(model.operationInProgress)
            }.padding(18)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("查找图标或应用", text: $query).textFieldStyle(.plain)
            }.padding(9).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 18).padding(.bottom, 12)
            if !model.accessibilityGranted || !model.screenGranted {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.teal)
                    Text("部分图标可能显示为待识别。可在设置中授权辅助功能以识别和操作，授权屏幕录制以显示真实图标。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("设置") { model.showSettings() }.controlSize(.small)
                }.padding(.horizontal, 18).padding(.bottom, 12)
            }
            Divider()
            ScrollView {
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "menubar.rectangle").font(.system(size: 38)).foregroundStyle(.secondary)
                        Text(query.isEmpty ? "暂未发现可管理图标" : "没有匹配的图标").font(.headline)
                        Text("点击“整理全部”后刷新。其他菜单栏管理器可能仍在隐藏图标；也可以直接按住 Command 手动整理。")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 370)
                    }.frame(maxWidth: .infinity).padding(32)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(ItemSection.allCases, id: \.self) { section in
                            let entries = filtered.filter { $0.section == section }
                            if !entries.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("\(section.label) · \(entries.count)", systemImage: section.symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 145))], spacing: 10) {
                                        ForEach(entries) { item in
                                            Button { model.activateItem(item) } label: {
                                                VStack(spacing: 7) {
                                                    if let image = item.image { Image(nsImage: image).resizable().scaledToFit().frame(width: 30, height: 27) }
                                                    else { Image(systemName: "app.dashed").font(.title2).frame(height: 27) }
                                                    Text(item.title).font(.caption).lineLimit(1)
                                                    if !item.isScreenshot { Text("应用图标").font(.system(size: 9)).foregroundStyle(.tertiary) }
                                                }.frame(maxWidth: .infinity).padding(.vertical, 11).contentShape(Rectangle())
                                            }.buttonStyle(.plain).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                                                .help("\(item.appName) · \(item.title)")
                                                .accessibilityLabel("打开 \(item.title)")
                                                .disabled(model.operationInProgress)
                                                .contextMenu {
                                                    ForEach(ItemSection.allCases, id: \.self) { destination in
                                                        Button("移到\(destination.label)") { model.moveItem(item, section: destination) }
                                                            .disabled(model.mode != .allVisible || (destination == .alwaysHidden && !model.preferences.alwaysHiddenEnabled))
                                                    }
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    }.padding(18)
                }
            }
            if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
            Divider()
            HStack {
                Button("整理全部") { model.beginArrangement() }
                Button("设置") { model.showSettings() }
                Spacer()
                Text("右键图标可移动分区").font(.caption).foregroundStyle(.secondary)
            }.padding(14)
        }.frame(minWidth: 520, minHeight: 310)
    }
}
