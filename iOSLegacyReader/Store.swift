import Foundation
import SwiftUI
import Combine

// MARK: - 全局状态 / 本地持久化（纯本地，无后台上传）
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var sources: [BookSource] = []
    @Published var books: [Book] = []
    @Published var replaceRules: [ReplaceRule] = []
    @Published var settings: ReaderSettings = ReaderSettings()
    @Published var bookGroups: [String] = ["默认"]
    @Published var sourceGroups: [String] = []

    private let fm = FileManager.default
    private var baseURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LegacyReader", isDirectory: true)
    }

    init() { load() }

    // MARK: 加载 / 保存
    func load() {
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        sources       = loadJSON("sources.json") ?? []
        books         = loadJSON("books.json") ?? []
        replaceRules  = loadJSON("replaceRules.json") ?? []
        if let s: ReaderSettings = loadJSON("settings.json") { settings = s }
        recomputeGroups()
    }

    func save() {
        saveJSON(sources, "sources.json")
        saveJSON(books, "books.json")
        saveJSON(replaceRules, "replaceRules.json")
        saveJSON(settings, "settings.json")
    }

    private func loadJSON<T: Decodable>(_ name: String) -> T? {
        let url = baseURL.appendingPathComponent(name)
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    private func saveJSON<T: Encodable>(_ obj: T, _ name: String) {
        let url = baseURL.appendingPathComponent(name)
        if let d = try? JSONEncoder().encode(obj) { try? d.write(to: url) }
    }

    // MARK: 书源管理
    func upsertSource(_ s: BookSource) {
        if let idx = sources.firstIndex(where: { $0.id == s.id }) { sources[idx] = s }
        else { sources.append(s) }
        recomputeGroups(); save()
    }
    func removeSource(_ s: BookSource) {
        sources.removeAll { $0.id == s.id }; recomputeGroups(); save()
    }
    func toggleSource(_ s: BookSource) {
        guard let idx = sources.firstIndex(where: { $0.id == s.id }) else { return }
        sources[idx].enabled.toggle(); save()
    }
    func moveSource(from: Int, to: Int) {
        guard from < sources.count, to < sources.count else { return }
        let s = sources.remove(at: from); sources.insert(s, at: to); save()
    }
    func importSources(text: String) -> Int {
        let imported = SourceImporter.import(text: text)
        var added = 0
        for s in imported {
            if !sources.contains(where: { $0.id == s.id }) { sources.append(s); added += 1 }
        }
        recomputeGroups(); save(); return added
    }
    func exportSourcesData() -> Data { SourceImporter.export(sources: sources) }

    // MARK: 书籍管理
    func addBook(_ b: Book) {
        if !books.contains(where: { $0.id == b.id }) { books.append(b) }
        recomputeGroups(); save()
    }
    func removeBook(_ b: Book) {
        books.removeAll { $0.id == b.id }; save()
    }
    func updateBook(_ b: Book) {
        if let idx = books.firstIndex(where: { $0.id == b.id }) { books[idx] = b }
        else { books.append(b) }
        save()
    }
    func reorderBook(from: Int, to: Int) {
        guard from < books.count, to < books.count else { return }
        let b = books.remove(at: from); books.insert(b, at: to); save()
    }

    // MARK: 净化规则
    func addReplaceRule(_ r: ReplaceRule) { replaceRules.append(r); save() }
    func removeReplaceRule(_ r: ReplaceRule) { replaceRules.removeAll { $0.id == r.id }; save() }
    func rulesFor(bookId: String?, sourceId: String?) -> [ReplaceRule] {
        replaceRules.filter { rule in
            switch rule.scope {
            case .global: return true
            case .book:   return rule.bookId == bookId
            case .source: return rule.sourceId == sourceId
            }
        }
    }

    // MARK: 备份 / 恢复
    func backupBundle() -> Data {
        // 各段编码为 JSON 字符串后整体序列化（避免顶层含非 JSON 值的限制）
        var dict: [String: Any] = ["version": 1]
        if let d = try? JSONEncoder().encode(sources) { dict["sources"] = String(data: d, encoding: .utf8) }
        if let d = try? JSONEncoder().encode(books) { dict["books"] = String(data: d, encoding: .utf8) }
        if let d = try? JSONEncoder().encode(replaceRules) { dict["replaceRules"] = String(data: d, encoding: .utf8) }
        if let d = try? JSONEncoder().encode(settings) { dict["settings"] = String(data: d, encoding: .utf8) }
        return (try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)) ?? Data()
    }
    func restoreBundle(_ data: Data) {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let s = dict["sources"] as? String, let sd = s.data(using: .utf8) {
            let arr = SourceImporter.import(jsonData: sd); sources = arr
        }
        if let b = dict["books"] as? String, let bd = b.data(using: .utf8) {
            if let arr = try? JSONDecoder().decode([Book].self, from: bd) { books = arr }
        }
        if let r = dict["replaceRules"] as? String, let rd = r.data(using: .utf8) {
            if let arr = try? JSONDecoder().decode([ReplaceRule].self, from: rd) { replaceRules = arr }
        }
        if let st = dict["settings"] as? String, let std = st.data(using: .utf8) {
            if let s = try? JSONDecoder().decode(ReaderSettings.self, from: std) { settings = s }
        }
        recomputeGroups(); save()
    }

    private func recomputeGroups() {
        let sg = Set(sources.compactMap { $0.bookSourceGroup }).filter { !$0.isEmpty }
        sourceGroups = Array(sg).sorted()
        let bg = Set(books.map { $0.group }).filter { !$0.isEmpty }
        bookGroups = (["默认"] + Array(bg).filter { $0 != "默认" }).sorted()
    }
}
