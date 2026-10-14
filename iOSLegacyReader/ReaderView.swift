import SwiftUI
import UIKit

// 主题预设（白天 / 夜间 / 护眼 / 羊皮纸）
let readerThemes: [String: (bg: String, text: String)] = [
    "day":   ("#FFFFFF", "#212121"),
    "night": ("#1A1A1A", "#B0B0B0"),
    "eye":   ("#C7EDCC", "#2E3B2E"),
    "paper": ("#F5ECD7", "#5B4636")
]

struct ReaderView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var book: Book
    @State private var currentIndex: Int = 0
    @State private var contents: [Int: String] = [:]
    @State private var loading = false
    @State private var showCatalog = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showBookmarks = false
    @State private var brightness: Double
    @State private var autoTimer: Timer?
    @State private var autoAnchor = 0

    init(book: Book) {
        _book = State(initialValue: book)
        _currentIndex = State(initialValue: max(0, book.readProgress))
        _brightness = State(initialValue: Double(UIScreen.main.brightness))
    }

    private var chapters: [Chapter] { book.chapters ?? [] }
    private var settings: ReaderSettings { store.settings }
    private var bgColor: Color { Color(hex: settings.backgroundColor) }
    private var textColor: Color { Color(hex: settings.textColor) }
    private var font: Font { fontFrom(settings.fontName, size: settings.fontSize) }

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            if settings.pageMode == "scroll" {
                scrollReader
            } else {
                pageReader
            }
        }
        .preferredColorScheme(settings.theme == "night" ? .dark : .light)
        .statusBar(hidden: settings.fullScreen)
        .navigationBarHidden(true)
        .ignoresSafeArea(edges: settings.fullScreen ? .all : [])
        .onAppear {
            UIScreen.main.brightness = CGFloat(settings.brightness)
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
            Task { await loadAround(currentIndex) }
        }
        .onDisappear {
            autoTimer?.invalidate(); autoTimer = nil
            UIApplication.shared.isIdleTimerDisabled = false
            saveProgress()
        }
        .onChange(of: settings.brightness) { v in UIScreen.main.brightness = CGFloat(v) }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomBar }
        .sheet(isPresented: $showCatalog) { catalogSheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showSearch) { searchSheet }
        .sheet(isPresented: $showBookmarks) { bookmarkSheet }
    }

    // MARK: 滚动阅读
    private var scrollReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let blocks = contentBlocks()
                    ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                        Text(block)
                            .font(font)
                            .foregroundColor(textColor)
                            .lineSpacing(settings.lineSpacing)
                            .padding(.horizontal, settings.marginHorizontal)
                            .padding(.bottom, settings.paragraphSpacing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                    Color.clear.frame(height: 40).id("end")
                }
                .padding(.vertical, settings.marginVertical)
            }
            .onChange(of: currentIndex) { _ in proxy.scrollTo(0, anchor: .top) }
            .onChange(of: autoAnchor) { v in
                withAnimation { proxy.scrollTo(min(v, contentBlocks().count - 1), anchor: .top) }
            }
            .gesture(TapGesture().onEnded { location in handleTap() })
        }
    }

    // MARK: 分页阅读（覆盖/仿真/滑动/无动画 统一以翻页形式呈现）
    private var pageReader: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(chapters.enumerated()), id: \.element.id) { i, ch in
                ScrollView {
                    Text(contents[i] ?? "加载中…")
                        .font(font)
                        .foregroundColor(textColor)
                        .lineSpacing(settings.lineSpacing)
                        .padding(.horizontal, settings.marginHorizontal)
                        .padding(.vertical, settings.marginVertical)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(bgColor)
        .onChange(of: currentIndex) { i in Task { await loadAround(i) } }
        .overlay(alignment: .leading) { edgeTap(leading: true) }
        .overlay(alignment: .trailing) { edgeTap(leading: false) }
    }

    private func edgeTap(leading: Bool) -> some View {
        Color.clear
            .frame(width: 60)
            .contentShape(Rectangle())
            .onTapGesture {
                if leading { if currentIndex > 0 { currentIndex -= 1 } }
                else { if currentIndex < chapters.count - 1 { currentIndex += 1 } }
                saveProgress()
            }
    }

    private func handleTap() {
        // 滚动模式：点屏幕左右 1/3 翻页
        // 简化：点击中部不处理，左右区域翻页由 overlay 处理；此处仅占位
    }

    // 将正文按段落切块（用于自动阅读步进）
    private func contentBlocks() -> [String] {
        let raw = contents[currentIndex] ?? "加载中…"
        let paras = raw.components(separatedBy: "\n").map { settings.firstLineIndent ? "　　" + $0 : $0 }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return paras.isEmpty ? ["加载中…"] : paras
    }

    // MARK: 顶栏
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.left").foregroundColor(textColor) }
            Spacer()
            Text(book.name).font(.headline).foregroundColor(textColor).lineLimit(1)
            Spacer()
            Button { showBookmarks = true } label: { Image(systemName: "bookmark").foregroundColor(textColor) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(bgColor.opacity(0.9))
    }

    // MARK: 底栏
    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack {
                Button { if currentIndex > 0 { currentIndex -= 1; saveProgress() } }
                label: { Image(systemName: "chevron.left").foregroundColor(textColor) }
                Spacer()
                Text("\(currentIndex + 1) / \(chapters.count)").foregroundColor(textColor).font(.caption)
                Spacer()
                Button { if currentIndex < chapters.count - 1 { currentIndex += 1; saveProgress() } }
                label: { Image(systemName: "chevron.right").foregroundColor(textColor) }
            }
            HStack(spacing: 18) {
                Button { showCatalog = true } label: { Label("目录", systemImage: "list.bullet").foregroundColor(textColor) }
                Button { showSearch = true } label: { Label("搜索", systemImage: "magnifyingglass").foregroundColor(textColor) }
                Button { toggleAutoRead() } label: { Label(settings.autoRead ? "停止" : "自动", systemImage: "play.circle").foregroundColor(textColor) }
                Button { toggleBookmark() } label: { Label("书签", systemImage: "bookmark").foregroundColor(textColor) }
                Button { showSettings = true } label: { Label("设置", systemImage: "textformat.size").foregroundColor(textColor) }
            }.font(.caption)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(bgColor.opacity(0.9))
    }

    // MARK: 目录
    private var catalogSheet: some View {
        NavigationView {
            List {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { i, ch in
                    Button { currentIndex = i; saveProgress(); showCatalog = false; Task { await loadAround(i) } }
                    label: { Text(ch.title).foregroundColor(i == currentIndex ? .accentColor : .primary) }
                }
            }
            .navigationTitle("目录").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { showCatalog = false } }
            }
        }
    }

    // MARK: 正文内搜索
    private var searchSheet: some View {
        NavigationView {
            SearchInBookView(book: $book, onJump: { i in currentIndex = i; saveProgress(); showSearch = false; Task { await loadAround(i) } })
                .navigationTitle("本书搜索").toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { showSearch = false } }
                }
        }
    }

    // MARK: 书签
    private var bookmarkSheet: some View {
        NavigationView {
            List {
                ForEach(book.bookmarks ?? []) { bm in
                    Button { currentIndex = bm.chapterIndex; saveProgress(); showBookmarks = false; Task { await loadAround(bm.chapterIndex) } }
                    label: {
                        VStack(alignment: .leading) {
                            Text(bm.chapterTitle).foregroundColor(.primary)
                            if !bm.note.isEmpty { Text(bm.note).font(.caption).foregroundColor(.secondary) }
                        }
                    }
                }
                .onDelete { idx in
                    var list = book.bookmarks ?? []
                    list.remove(at: offsets(idx))
                    book.bookmarks = list; store.updateBook(book)
                }
            }
            .navigationTitle("书签").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { showBookmarks = false } }
            }
        }
    }
    private func offsets(_ idx: IndexSet) -> Int { idx.first! }

    // MARK: 阅读设置
    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section("翻页方式") {
                    Picker("模式", selection: Binding(get: { settings.pageMode }, set: { store.settings.pageMode = $0; store.save() })) {
                        ForEach([("scroll","滚动"),("cover","覆盖"),("simulation","仿真"),("slide","滑动"),("none","无动画")], id: \.0) { Text($0.1) }
                    }.pickerStyle(.segmented)
                }
                Section("主题") {
                    Picker("主题", selection: Binding(get: { settings.theme }, set: { applyTheme($0) })) {
                        ForEach([("day","白天"),("night","夜间"),("eye","护眼"),("paper","羊皮纸")], id: \.0) { Text($0.1) }
                    }.pickerStyle(.segmented)
                    HexColorField(label: "文字颜色", hex: Binding(get: { settings.textColor }, set: { store.settings.textColor = $0; store.save() }))
                    HexColorField(label: "背景颜色", hex: Binding(get: { settings.backgroundColor }, set: { store.settings.backgroundColor = $0; store.save() }))
                }
                Section("排版") {
                    Stepper("字号 \(Int(settings.fontSize))", value: Binding(get: { settings.fontSize }, set: { store.settings.fontSize = $0; store.save() }), in: 12...30)
                    Stepper("行距 \(Int(settings.lineSpacing))", value: Binding(get: { settings.lineSpacing }, set: { store.settings.lineSpacing = $0; store.save() }), in: 0...30)
                    Stepper("段距 \(Int(settings.paragraphSpacing))", value: Binding(get: { settings.paragraphSpacing }, set: { store.settings.paragraphSpacing = $0; store.save() }), in: 0...30)
                    Stepper("左右边距 \(Int(settings.marginHorizontal))", value: Binding(get: { settings.marginHorizontal }, set: { store.settings.marginHorizontal = $0; store.save() }), in: 0...60)
                    Stepper("上下边距 \(Int(settings.marginVertical))", value: Binding(get: { settings.marginVertical }, set: { store.settings.marginVertical = $0; store.save() }), in: 0...60)
                    Toggle("首行缩进", isOn: Binding(get: { settings.firstLineIndent }, set: { store.settings.firstLineIndent = $0; store.save() }))
                }
                Section("屏幕") {
                    Toggle("屏幕常亮", isOn: Binding(get: { settings.keepScreenOn }, set: { store.settings.keepScreenOn = $0; UIApplication.shared.isIdleTimerDisabled = $0; store.save() }))
                    Toggle("全屏沉浸", isOn: Binding(get: { settings.fullScreen }, set: { store.settings.fullScreen = $0; store.save() }))
                    Slider(value: Binding(get: { settings.brightness }, set: { store.settings.brightness = $0; UIScreen.main.brightness = CGFloat($0); store.save() }), in: 0.1...1) {
                        Text("亮度 \(Int(settings.brightness * 100))%")
                    }
                }
            }
            .navigationTitle("阅读设置").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { showSettings = false } }
            }
        }
    }

    // MARK: 行为
    private func applyTheme(_ name: String) {
        store.settings.theme = name; store.save()
        if let t = readerThemes[name] {
            store.settings.backgroundColor = t.bg
            store.settings.textColor = t.text
            store.save()
        }
    }

    private func toggleAutoRead() {
        store.settings.autoRead.toggle(); store.save()
        if store.settings.autoRead {
            autoTimer = Timer.scheduledTimer(withTimeInterval: max(0.3, 2.4 - store.settings.autoReadSpeed), repeats: true) { _ in
                if settings.pageMode == "scroll" {
                    autoAnchor += 1
                }
            }
        } else {
            autoTimer?.invalidate(); autoTimer = nil
        }
    }

    private func toggleBookmark() {
        let ch = chapters.indices.contains(currentIndex) ? chapters[currentIndex] : Chapter(title: "未知", url: "", index: currentIndex)
        var list = book.bookmarks ?? []
        list.append(Bookmark(chapterIndex: currentIndex, chapterTitle: ch.title))
        book.bookmarks = list; store.updateBook(book)
        showBookmarks = true
    }

    private func saveProgress() {
        var b = book
        b.readProgress = currentIndex
        b.totalProgress = chapters.isEmpty ? 0 : Double(currentIndex + 1) / Double(chapters.count)
        b.lastReadTime = Date().timeIntervalSince1970
        book = b
        store.updateBook(b)
    }

    // MARK: 正文加载（带缓存 + 净化）
    private func loadAround(_ index: Int) async {
        guard !chapters.isEmpty else { return }
        for i in (index-1)...(index+1) where i >= 0 && i < chapters.count {
            if contents[i] == nil { await loadChapter(i) }
        }
    }

    private func loadChapter(_ index: Int) async {
        guard index >= 0, index < chapters.count else { return }
        let ch = chapters[index]
        if let c = ch.content, !c.isEmpty {
            contents[index] = c; return
        }
        loading = true
        defer { loading = false }
        let text: String
        if book.bookSourceUrl == "local://import" {
            text = ch.content ?? ""
        } else if let source = store.sources.first(where: { $0.id == book.bookSourceId }) {
            let raw = await BookSourceEngine.content(source: source, chapterUrl: ch.url)
            let rules = store.rulesFor(bookId: book.id, sourceId: source.id)
            text = CleanupEngine.apply(rules: rules, to: raw, bookId: book.id, sourceId: source.id)
        } else { text = "" }
        contents[index] = text
        // 写回章节缓存
        var mutable = book
        var chs = mutable.chapters ?? []
        if chs.indices.contains(index) { chs[index].content = text }
        mutable.chapters = chs
        book = mutable
    }
}

// MARK: 本书内搜索
struct SearchInBookView: View {
    @Binding var book: Book
    @State private var q = ""
    @State private var hits: [(index: Int, title: String, snippet: String)] = []
    let onJump: (Int) -> Void

    var body: some View {
        VStack {
            TextField("输入关键词", text: $q).textFieldStyle(.roundedBorder).padding()
            Button("搜索") { run() }.padding(.bottom, 6)
            List(hits, id: \.index) { h in
                Button { onJump(h.index) } label: {
                    VStack(alignment: .leading) {
                        Text(h.title).foregroundColor(.primary)
                        Text(h.snippet).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                }
            }
        }
    }
    private func run() {
        guard !q.isEmpty else { return }
        var res: [(Int, String, String)] = []
        for ch in book.chapters ?? [] {
            let content = ch.content ?? ""
            if let range = content.range(of: q) {
                let start = content.index(range.lowerBound, offsetBy: -min(20, content.distance(from: content.startIndex, to: range.lowerBound)), limitedBy: content.startIndex) ?? content.startIndex
                let end = content.index(range.upperBound, offsetBy: min(20, content.distance(from: range.upperBound, to: content.endIndex)), limitedBy: content.endIndex) ?? content.endIndex
                res.append((ch.index, ch.title, "...\(content[start..<end])..."))
            }
        }
        hits = res
    }
}

// MARK: - 工具扩展
extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6 { s += "FF" }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF000000) >> 24) / 255
        let g = Double((rgb & 0x00FF0000) >> 16) / 255
        let b = Double((rgb & 0x0000FF00) >> 8) / 255
        let a = Double(rgb & 0x000000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// 十六进制颜色输入行（避免 SwiftUI Color -> UIColor 的不可用转换）
struct HexColorField: View {
    let label: String
    @Binding var hex: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("#RRGGBB", text: $hex)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: hex))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary, lineWidth: 0.5))
        }
    }
}

func fontFrom(_ name: String, size: Double) -> Font {
    if name == "System" { return .system(size: size) }
    return Font.custom(name, size: size)
}
