import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @State private var keyword: String = ""
    @State private var results: [SearchResult] = []
    @State private var searching = false
    @State private var searchMsg: String?
    @State private var selectedSourceId: String? = nil
    @State private var exploreResults: [SearchResult] = []
    @State private var exploring = false

    var enabledSources: [BookSource] { store.sources.filter { $0.enabled } }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索栏
                HStack {
                    TextField("输入书名/作者搜索", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                    Button { Task { await doSearch() } } label: { Image(systemName: "magnifyingglass") }
                        .disabled(keyword.isEmpty || searching)
                }.padding(12)

                if searching { ProgressView("正在聚合搜索…").padding() }

                List {
                    if !results.isEmpty {
                        Section("聚合搜索结果（\(results.count)）") {
                            ForEach(results) { r in
                                ResultRow(result: r) { Task { await addToShelf(r) } }
                            }
                        }
                    }
                    // 发现板块
                    Section("发现") {
                        if enabledSources.isEmpty {
                            Text("暂无启用的书源，请先到「书源」导入。").foregroundColor(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(enabledSources) { s in
                                        Button {
                                            selectedSourceId = s.id
                                            Task { await explore(source: s) }
                                        } label: {
                                            Text(s.bookSourceName).padding(6)
                                                .background(Color(.secondarySystemBackground))
                                                .cornerRadius(8)
                                        }
                                    }
                                }.padding(.horizontal, 4)
                            }
                            if exploring { ProgressView("加载发现…").padding(4) }
                            ForEach(exploreResults) { r in
                                ResultRow(result: r) { Task { await addToShelf(r) } }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("发现 / 搜索")
            .alert("提示", isPresented: Binding(get: { searchMsg != nil }, set: { if !$0 { searchMsg = nil } })) {
                Button("好") {}
            } message: { Text(searchMsg ?? "") }
        }
    }

    private func doSearch() async {
        searching = true; results = []
        defer { searching = false }
        guard !enabledSources.isEmpty else { searchMsg = "没有启用的书源"; return }
        var all: [SearchResult] = []
        await withTaskGroup(of: [SearchResult].self) { group in
            for s in enabledSources {
                group.addTask { await BookSourceEngine.search(source: s, keyword: keyword) }
            }
            for await batch in group { all.append(contentsOf: batch) }
        }
        // 去重：同名同作者只保留第一个
        var seen = Set<String>()
        var dedup: [SearchResult] = []
        for r in all {
            let k = r.name + "|" + r.author
            if !seen.contains(k) { seen.insert(k); dedup.append(r) }
        }
        results = dedup
        if dedup.isEmpty { searchMsg = "未找到结果，请检查书源或网络" }
    }

    private func explore(source: BookSource) async {
        exploring = true; exploreResults = []
        defer { exploring = false }
        guard let eu = source.exploreUrl, !eu.isEmpty else { return }
        // 取第一个发现分组地址（支持 && 分隔）
        let firstUrl = eu.components(separatedBy: "&&").first?
            .components(separatedBy: "::").last?
            .trimmingCharacters(in: .whitespaces) ?? eu
        exploreResults = await BookSourceEngine.explore(source: source, groupUrl: firstUrl)
    }

    private func addToShelf(_ r: SearchResult) async {
        guard let source = store.sources.first(where: { $0.id == r.sourceId }) else { return }
        let info = await BookSourceEngine.bookInfo(source: source, bookUrl: r.bookUrl)
        let toc = await BookSourceEngine.toc(source: source, bookUrl: info.tocUrl ?? r.bookUrl)
        var book = Book(name: r.name, author: r.author, bookUrl: r.bookUrl, source: source)
        book.coverUrl = info.coverUrl ?? r.coverUrl
        book.intro = info.intro
        book.kind = info.kind
        book.lastChapter = info.lastChapter
        book.wordCount = info.wordCount
        book.tocUrl = info.tocUrl ?? r.bookUrl
        book.chapters = toc
        store.addBook(book)
        searchMsg = "已加入书架：\(book.name)（\(toc.count) 章）"
    }
}

struct ResultRow: View {
    let result: SearchResult
    let onAdd: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            CoverView(url: result.coverUrl, name: result.name).frame(width: 44, height: 60).cornerRadius(4)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).font(.body)
                Text(result.author).font(.caption).foregroundColor(.secondary)
                if let last = result.lastChapter { Text("最新：\(last)").font(.caption2).foregroundColor(.secondary).lineLimit(1) }
                Text("来源：\(result.sourceName)").font(.caption2).foregroundColor(.accentColor)
            }
            Spacer()
            Button(action: onAdd) { Image(systemName: "plus.circle").foregroundColor(.accentColor) }
        }.padding(.vertical, 3)
    }
}
