import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showBackup = false
    @State private var backupData: Data?
    @State private var showRestore = false
    @State private var restoreMsg: String?
    @State private var showAddRule = false
    @State private var newRuleName = ""
    @State private var newRulePattern = ""
    @State private var newRuleReplacement = ""
    @State private var newRuleRegex = true
    @State private var newRuleScope: ReplaceScope = .global
    @State private var newRuleAction: ReplaceAction = .replace
    @State private var ruleMsg: String?

    private var settings: ReaderSettings { store.settings }

    var body: some View {
        NavigationView {
            Form {
                Section("阅读默认配置（全局生效）") {
                    Picker("翻页方式", selection: Binding(get: { settings.pageMode }, set: { store.settings.pageMode = $0; store.save() })) {
                        ForEach(["scroll":"滚动","cover":"覆盖","simulation":"仿真","slide":"滑动","none":"无动画"], id: \.key) { Text($0.value) }
                    }
                    Picker("主题", selection: Binding(get: { settings.theme }, set: { store.settings.theme = $0; store.save() })) {
                        ForEach(["day":"白天","night":"夜间","eye":"护眼","paper":"羊皮纸"], id: \.key) { Text($0.value) }
                    }
                    Stepper("字号 \(Int(settings.fontSize))", value: Binding(get: { settings.fontSize }, set: { store.settings.fontSize = $0; store.save() }), in: 12...30)
                    Stepper("行距 \(Int(settings.lineSpacing))", value: Binding(get: { settings.lineSpacing }, set: { store.settings.lineSpacing = $0; store.save() }), in: 0...30)
                    Toggle("首行缩进", isOn: Binding(get: { settings.firstLineIndent }, set: { store.settings.firstLineIndent = $0; store.save() }))
                    Toggle("屏幕常亮", isOn: Binding(get: { settings.keepScreenOn }, set: { store.settings.keepScreenOn = $0; store.save() }))
                }

                Section("内容净化规则（三级）") {
                    ForEach(store.replaceRules) { rule in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rule.name).font(.body)
                                Text("\(rule.scope.label) · \(rule.action.label) · \(rule.isRegex ? "正则" : "关键词")")
                                    .font(.caption2).foregroundColor(.secondary)
                                Text(rule.pattern).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) { store.removeReplaceRule(rule) } label: { Image(systemName: "trash") }
                        }
                    }
                    Button { showAddRule = true } label: { Label("新增净化规则", systemImage: "plus") }
                }

                Section("备份与恢复") {
                    Button { backupData = store.backupBundle(); showBackup = true } label: { Label("完整备份（书源/书架/规则/设置）", systemImage: "square.and.arrow.up") }
                    Button { showRestore = true } label: { Label("恢复备份", systemImage: "square.and.arrow.down") }
                    Text("所有数据纯本地存储，无后台上传，无网络强制要求。").font(.caption).foregroundColor(.secondary)
                }

                Section("关于") {
                    Label("开源阅读·iOS 对标客户端", systemImage: "info.circle")
                    Text("书源规则引擎兼容 Legado 语法（CSS / XPath / JSONPath / 正则）。").font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showAddRule) { addRuleSheet }
            .sheet(isPresented: $showBackup) {
                if let data = backupData { ShareSheet(data: data, isPresented: $showBackup) }
            }
            .fileImporter(isPresented: $showRestore, allowedContentTypes: [.json]) { res in
                if case .success(let url) = res {
                    let secured = url.startAccessingSecurityScopedResource()
                    defer { if secured { url.stopAccessingSecurityScopedResource() } }
                    if let d = try? Data(contentsOf: url) { store.restoreBundle(d); restoreMsg = "恢复成功" }
                }
            }
            .alert("提示", isPresented: Binding(get: { restoreMsg != nil || ruleMsg != nil }, set: { if !$0 { restoreMsg = nil; ruleMsg = nil } })) {
                Button("好") {}
            } message: { Text(restoreMsg ?? ruleMsg ?? "") }
        }
    }

    private var addRuleSheet: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    TextField("规则名称", text: $newRuleName)
                    Picker("作用范围", selection: $newRuleScope) {
                        ForEach(ReplaceScope.allCases, id: \.self) { Text($0.label) }
                    }
                    Picker("动作", selection: $newRuleAction) {
                        ForEach(ReplaceAction.allCases, id: \.self) { Text($0.label) }
                    }
                    Toggle("使用正则", isOn: $newRuleRegex)
                }
                Section("匹配与替换") {
                    TextField(newRuleAction == .replace ? "匹配（关键词或正则）" : "匹配行（关键词或正则）", text: $newRulePattern)
                    if newRuleAction == .replace {
                        TextField("替换为（可空）", text: $newRuleReplacement)
                    }
                }
                if newRuleScope == .book {
                    Picker("选择书籍", selection: $newRuleBookId) {
                        Text("未选择").tag(nil as String?)
                        ForEach(store.books) { b in Text(b.name).tag(b.id as String?) }
                    }
                }
                if newRuleScope == .source {
                    Picker("选择书源", selection: $newRuleSourceId) {
                        Text("未选择").tag(nil as String?)
                        ForEach(store.sources) { s in Text(s.bookSourceName).tag(s.id as String?) }
                    }
                }
            }
            .navigationTitle("新增净化规则").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showAddRule = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard !newRulePattern.isEmpty else { ruleMsg = "匹配内容不能为空"; return }
                        var r = ReplaceRule(name: newRuleName.isEmpty ? "规则" : newRuleName,
                                            pattern: newRulePattern, replacement: newRuleReplacement,
                                            isRegex: newRuleRegex, scope: newRuleScope, action: newRuleAction)
                        if newRuleScope == .book { r.bookId = newRuleBookId }
                        if newRuleScope == .source { r.sourceId = newRuleSourceId }
                        store.addReplaceRule(r)
                        resetRuleForm(); showAddRule = false
                    }
                }
            }
        }
    }
    @State private var newRuleBookId: String?
    @State private var newRuleSourceId: String?
    private func resetRuleForm() {
        newRuleName = ""; newRulePattern = ""; newRuleReplacement = ""; newRuleRegex = true
        newRuleScope = .global; newRuleAction = .replace; newRuleBookId = nil; newRuleSourceId = nil
    }
}
