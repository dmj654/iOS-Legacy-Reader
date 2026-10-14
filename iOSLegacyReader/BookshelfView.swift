import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BookshelfView: View {
    @EnvironmentObject var store: AppStore
    @State private var viewMode: ViewMode = .grid
    @State private var sortMode: SortMode = .addTime
    @State private var groupFilter: String = "全部"
    @State private var showingImporter = false
    @State private var importMsg: String?
    @State private var updating = false
    @State private var updateLog: String = ""

    enum ViewMode: String, CaseIterable { case grid = "网格", list = "列表" }
    enum SortMode: String, CaseIterable { case name = "名称", update = "更新时间", progress = "阅读进度", addTime = "添加时间" }

    var filteredBooks: [Book] {
        var list = store.books
        if groupFilter != "全部" { list = list.filter { $0.group == groupFilter } }
        switch sortMode {
        case .name:    list.sort { $0.name < $1.name }
        case .update:  list.sort { ($0.latestChapterUpdate ?? "") > ($1.latestChapterUpdate ?? "") }
        case .progress:list.sort { $0.totalProgress > $1.totalProgress }
        case .addTime: list.sort { $0.addTime > $1.addTime }
        }
        // 置顶优先
        list.sort { $0.order > $1.order }
        return list
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 工具栏
                HStack {
                    Picker("分组", selection: $groupFilter) {
                        ForEach(["全部"] + store.bookGroups, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Picker("排序", selection: $sortMode) {
                        ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                    Picker("视图", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                if updating {
                    ProgressView("正在检测更新…").padding()
                    Text(updateLog).font(.caption).foregroundColor(.secondary).padding(.horizontal)
                }

                ScrollView {
                    if viewMode == .grid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                            ForEach(filteredBooks) { book in
                                NavigationLink { ReaderView(book: book) } label: { BookGridCell(book: book) }
                            }
                        }
                        .padding()
                    } else {
                        LazyVStack {
                            ForEach(filteredBooks) { book in
                                NavigationLink { ReaderView(book: book) } label: { BookListRow(book: book) }
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { Task { await updateAll() } } label: { Image(systemName: "arrow.clockwise") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingImporter = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.plainText, .epub]) { res in
                handleImport(res)
            }
            .alert("导入结果", isPresented: Binding(get: { importMsg != nil }, set: { if !$0 { importMsg = nil } })) {
                Button("好") {}
            } message: { Text(importMsg ?? "") }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let book: Book?
            if url.pathExtension.lowercased() == "txt" { book = LocalImport.import(txtURL: url) }
            else if url.pathExtension.lowercased() == "epub" { book = LocalImport.import(epubURL: url) }
            else { book = nil }
            if let b = book { store.addBook(b); importMsg = "已导入：\(b.name)（\(b.chapters?.count ?? 0) 章）" }
            else { importMsg = "导入失败：文件无法解析" }
        case .failure(let e):
            importMsg = "导入失败：\(e.localizedDescription)"
        }
    }

    private func updateAll() async {
        updating = true; updateLog = ""
        for book in store.books where book.bookSourceUrl != "local://import" {
            guard let source = store.sources.first(where: { $0.id == book.bookSourceId }) else { continue }
            let info = await BookSourceEngine.bookInfo(source: source, bookUrl: book.bookUrl)
            if let last = info.lastChapter, last != book.lastChapter {
                var b = book
                b.lastChapter = last
                store.updateBook(b)
                updateLog += "● \(book.name) 有新章节：\(last)\n"
            }
        }
        updating = false
        if updateLog.isEmpty { updateLog = "全部书籍已是最新" }
    }
}

struct BookGridCell: View {
    let book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverView(url: book.coverUrl, name: book.name)
                .frame(width: 100, height: 140)
                .cornerRadius(6)
            Text(book.name).font(.caption).lineLimit(1)
            Text(book.author).font(.caption2).foregroundColor(.secondary).lineLimit(1)
        }
    }
}

struct BookListRow: View {
    let book: Book
    var body: some View {
        HStack(spacing: 10) {
            CoverView(url: book.coverUrl, name: book.name).frame(width: 48, height: 64).cornerRadius(4)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.name).font(.body)
                Text(book.author).font(.caption).foregroundColor(.secondary)
                if let last = book.lastChapter { Text("最新：\(last)").font(.caption2).foregroundColor(.secondary).lineLimit(1) }
            }
            Spacer()
            if book.totalProgress > 0 {
                Text("\(Int(book.totalProgress * 100))%").font(.caption2).foregroundColor(.accentColor)
            }
        }.padding(.vertical, 4)
    }
}

struct CoverView: View {
    let url: String?
    let name: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(.secondarySystemBackground)
                    Text(name.prefix(1)).font(.largeTitle).foregroundColor(.secondary)
                }
            }
        }
        .onAppear { load() }
        .clipped()
    }
    private func load() {
        guard let url = url, image == nil else { return }
        if url.hasPrefix("data:") {
            if let comma = url.firstIndex(of: ","),
               let d = Data(base64Encoded: String(url[url.index(after: comma)...])) { image = UIImage(data: d) }
            return
        }
        guard let u = URL(string: url) else { return }
        Task {
            if let data = try? await NetworkManager.shared.fetchData(url: u.absoluteString) {
                await MainActor.run { self.image = UIImage(data: data) }
            }
        }
    }
}
