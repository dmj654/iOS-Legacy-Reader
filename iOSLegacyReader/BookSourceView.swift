import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BookSourceView: View {
    @EnvironmentObject var store: AppStore
    @State private var groupFilter: String = "全部"
    @State private var showingPaste = false
    @State private var pasteText: String = ""
    @State private var pasteMsg: String?
    @State private var showingEdit = false
    @State private var editJSON: String = ""
    @State private var editTarget: BookSource?
    @State private var exportData: Data?
    @State private var showingExporter = false
    @State private var showingFileImporter = false
    @State private var checkMsg: String?

    var filtered: [BookSource] {
        let list = groupFilter == "全部" ? store.sources : store.sources.filter { ($0.bookSourceGroup ?? "") == groupFilter }
        return list
    }

    var body: some View {
        NavigationView {
            VStack {
                if store.sources.isEmpty {
                    VStack(spacing: 12) {
                        Text("暂无书源").font(.headline).foregroundColor(.secondary)
                        Text("可粘贴社区公开的 Legado 书源 JSON，或导入 .json 文件").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    }.padding()
                }
                List {
                    ForEach(filtered) { s in
                        SourceRow(source: s,
                                  onToggle: { store.toggleSource(s) },
                                  onEdit: { beginEdit(s) },
                                  onCheck: { Task { await check(s) } },
                                  onDelete: { store.removeSource(s) })
                    }
                    .onMove { from, to in
                        // 在过滤视图下简单处理：仅在「全部」时重排
                        if groupFilter == "全部" { store.moveSource(from: from, to: to) }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("书源管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Picker("分组", selection: $groupFilter) {
                        ForEach(["全部"] + store.sourceGroups, id: \.self) { Text($0) }
                    }.pickerStyle(.menu)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingPaste = true } label: { Image(systemName: "doc.on.clipboard") }
                    Button { showingFileImporter = true } label: { Image(systemName: "folder") }
                    Button { exportAll() } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.json]) { res in
                if case .success(let url) = res {
                    let secured = url.startAccessingSecurityScopedResource()
                    defer { if secured { url.stopAccessingSecurityScopedResource() } }
                    if let t = try? String(contentsOf: url) { let n = store.importSources(text: t); pasteMsg = "已导入 \(n) 条书源" }
                }
            }
            .sheet(isPresented: $showingPaste) {
                NavigationView {
                    VStack {
                        Text("粘贴 Legado 书源 JSON（支持数组或单条）").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: $pasteText).border(Color.secondary).padding()
                    }
                    .navigationTitle("导入书源").toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showingPaste = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入") {
                                let n = store.importSources(text: pasteText)
                                pasteMsg = "已导入 \(n) 条书源"
                                showingPaste = false; pasteText = ""
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingEdit) {
                NavigationView {
                    VStack {
                        Text("编辑书源（Legado 兼容 JSON）").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: $editJSON).border(Color.secondary).padding()
                    }
                    .navigationTitle("编辑书源").toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showingEdit = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                saveEdit()
                                showingEdit = false
                            }
                        }
                    }
                }
            }
            .alert("提示", isPresented: Binding(get: { pasteMsg != nil || checkMsg != nil }, set: { if !$0 { pasteMsg = nil; checkMsg = nil } })) {
                Button("好") {}
            } message: { Text(pasteMsg ?? checkMsg ?? "") }
            .sheet(isPresented: $showingExporter) {
                if let data = exportData { ShareSheet(data: data, isPresented: $showingExporter) }
            }
        }
    }

    private func beginEdit(_ s: BookSource) {
        editTarget = s
        if let d = try? JSONEncoder().encode(s),
           let obj = try? JSONSerialization.jsonObject(with: d),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let str = String(data: pretty, encoding: .utf8) {
            editJSON = str
        }
        showingEdit = true
    }

    private func saveEdit() {
        guard let data = editJSON.data(using: .utf8),
              let arr = SourceImporter.import(jsonData: data), let s = arr.first else {
            pasteMsg = "JSON 解析失败"; return
        }
        store.upsertSource(s)
    }

    private func exportAll() {
        exportData = store.exportSourcesData()
        showingExporter = true
    }

    private func check(_ s: BookSource) async {
        let start = Date()
        let headers = BookSourceEngine.parseHeaders(s.header)
        let url = s.searchUrl != nil ? BookSourceEngine.buildUrl(s.searchUrl!, keyword: "测试") : s.bookSourceUrl
        do {
            _ = try await NetworkManager.shared.fetch(url: url, headers: headers, charset: s.contentCharset)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            checkMsg = "\(s.bookSourceName)：连通，耗时 \(ms)ms"
        } catch {
            checkMsg = "\(s.bookSourceName)：连接失败"
        }
    }
}

struct SourceRow: View {
    let source: BookSource
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onCheck: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: source.enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(source.enabled ? .accentColor : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(source.bookSourceName).font(.body)
                HStack {
                    if let g = source.bookSourceGroup { Text(g).font(.caption2).padding(2).background(Color(.secondarySystemBackground)).cornerRadius(4) }
                    Text(source.enabledExplore ? "可发现" : "仅搜索").font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: onCheck) { Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(.secondary) }
            Button(action: onEdit) { Image(systemName: "pencil").foregroundColor(.secondary) }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }
        }.padding(.vertical, 3)
    }
}

// 简单分享sheet（用于导出数据）
struct ShareSheet: UIViewControllerRepresentable {
    let data: Data
    @Binding var isPresented: Bool
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bookSources.json")
        try? data.write(to: tmp)
        let vc = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in isPresented = false }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
