import Foundation

// MARK: - 书源模型（与安卓开源阅读 Legado 的 JSON 结构通用）
struct BookSource: Codable, Identifiable, Hashable {
    var bookSourceName: String
    var bookSourceUrl: String
    var bookSourceType: Int?           // 0=图书 1=音频 3=图片
    var bookSourceGroup: String?
    var bookSourceComment: String?
    var enabled: Bool
    var enabledExplore: Bool
    var header: String?               // 请求头，JSON 字符串
    var searchUrl: String?            // 搜索地址，支持 {{key}} 占位
    var exploreUrl: String?           // 发现页地址
    var ruleSearch: RuleSearch?
    var ruleExplore: RuleSearch?
    var ruleBookInfo: RuleBookInfo?
    var ruleToc: RuleToc?
    var ruleContent: RuleContent?
    var ruleFindUrl: String?
    var contentCharset: String?       // 正文编码
    var concurrentRate: String?       // 并发数
    var loginUrl: String?
    var loginUi: String?
    var loginCheckJs: String?
    var lastUpdateTime: String?
    var respondTime: Int?

    var id: String { bookSourceUrl + "|" + bookSourceName }
    var isInvalid: Bool { bookSourceUrl.isEmpty }

    enum CodingKeys: String, CodingKey {
        case bookSourceName, bookSourceUrl, bookSourceType, bookSourceGroup, bookSourceComment
        case enabled, enabledExplore, header, searchUrl, exploreUrl
        case ruleSearch, ruleExplore, ruleBookInfo, ruleToc, ruleContent
        case ruleFindUrl, contentCharset, concurrentRate, loginUrl, loginUi, loginCheckJs, lastUpdateTime, respondTime
    }

    init(name: String, url: String) {
        self.bookSourceName = name
        self.bookSourceUrl = url
        self.bookSourceType = nil
        self.bookSourceGroup = nil
        self.bookSourceComment = nil
        self.enabled = true
        self.enabledExplore = true
        self.header = nil
        self.searchUrl = nil
        self.exploreUrl = nil
        self.ruleSearch = nil
        self.ruleExplore = nil
        self.ruleBookInfo = nil
        self.ruleToc = nil
        self.ruleContent = nil
        self.ruleFindUrl = nil
        self.contentCharset = nil
        self.concurrentRate = nil
        self.loginUrl = nil
        self.loginUi = nil
        self.loginCheckJs = nil
        self.lastUpdateTime = nil
        self.respondTime = nil
    }
}

struct RuleSearch: Codable, Hashable {
    var bookList: String?
    var name: String?
    var author: String?
    var bookUrl: String?
    var coverUrl: String?
    var kind: String?
    var lastChapter: String?
    var intro: String?
    var wordCount: String?
}

struct RuleBookInfo: Codable, Hashable {
    var `init`: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var coverUrl: String?
    var tocUrl: String?
    var wordCount: String?

    enum CodingKeys: String, CodingKey {
        case `init`, name, author, intro, kind, lastChapter, coverUrl, tocUrl, wordCount
    }
}

struct RuleToc: Codable, Hashable {
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var nextTocUrl: String?
}

struct RuleContent: Codable, Hashable {
    var content: String?
    var nextContentUrl: String?
    var replaceRegex: String?
    var webJs: String?
    var sourceRegex: String?
}

// MARK: - 书籍 / 章节
struct Book: Codable, Identifiable, Hashable {
    var id: String                  // 唯一标识（bookUrl 或 uuid）
    var name: String
    var author: String
    var coverUrl: String?
    var bookUrl: String
    var bookSourceId: String
    var bookSourceName: String
    var bookSourceUrl: String
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var wordCount: String?
    var tocUrl: String?
    var chapters: [Chapter]?
    var latestChapterUpdate: String?
    var addTime: TimeInterval
    var order: Int
    var group: String
    var customCover: String?
    var variable: String?            // 动态参数(JSON)
    var lastReadTime: TimeInterval
    var readProgress: Int            // 已读章节索引
    var totalProgress: Double        // 0~1
    var bookmarks: [Bookmark]?

    var idHash: String { id }

    init(name: String, author: String, bookUrl: String, source: BookSource) {
        self.id = bookUrl
        self.name = name
        self.author = author
        self.coverUrl = nil
        self.bookUrl = bookUrl
        self.bookSourceId = source.id
        self.bookSourceName = source.bookSourceName
        self.bookSourceUrl = source.bookSourceUrl
        self.intro = nil
        self.kind = nil
        self.lastChapter = nil
        self.wordCount = nil
        self.tocUrl = nil
        self.chapters = nil
        self.latestChapterUpdate = nil
        self.addTime = Date().timeIntervalSince1970
        self.order = 0
        self.group = "默认"
        self.customCover = nil
        self.variable = nil
        self.lastReadTime = 0
        self.readProgress = 0
        self.totalProgress = 0
        self.bookmarks = nil
    }
}

struct Chapter: Codable, Identifiable, Hashable {
    var title: String
    var url: String
    var index: Int
    var content: String?
    var isVip: Bool?
    var updateTime: String?
    var isDownload: Bool?

    var id: String { url }

    init(title: String, url: String, index: Int, content: String? = nil,
         isVip: Bool? = nil, updateTime: String? = nil, isDownload: Bool? = nil) {
        self.title = title
        self.url = url
        self.index = index
        self.content = content
        self.isVip = isVip
        self.updateTime = updateTime
        self.isDownload = isDownload
    }
}

// MARK: - 书签
struct Bookmark: Codable, Identifiable, Hashable {
    var id: String
    var chapterIndex: Int
    var chapterTitle: String
    var note: String
    var time: TimeInterval

    init(chapterIndex: Int, chapterTitle: String, note: String = "") {
        self.id = UUID().uuidString
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.note = note
        self.time = Date().timeIntervalSince1970
    }
}

// MARK: - 净化 / 替换规则（三级：全局 / 单书 / 单源）
struct ReplaceRule: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var pattern: String             // 关键词或正则
    var replacement: String
    var isRegex: Bool
    var scope: ReplaceScope
    var bookId: String?
    var sourceId: String?
    var action: ReplaceAction

    init(name: String, pattern: String, replacement: String = "", isRegex: Bool = true,
         scope: ReplaceScope = .global, action: ReplaceAction = .replace) {
        self.id = UUID().uuidString
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
        self.isRegex = isRegex
        self.scope = scope
        self.action = action
    }
}

enum ReplaceScope: String, Codable, Hashable, CaseIterable {
    case global = "global"
    case book = "book"
    case source = "source"
    var label: String {
        switch self {
        case .global: return "全局"
        case .book: return "单本书"
        case .source: return "单书源"
        }
    }
}

enum ReplaceAction: String, Codable, Hashable, CaseIterable {
    case replace = "replace"
    case deleteLine = "deleteLine"
    case keepLine = "keepLine"
    var label: String {
        switch self {
        case .replace: return "替换"
        case .deleteLine: return "删除整行"
        case .keepLine: return "保留整行"
        }
    }
}

// MARK: - 阅读设置（全局生效）
struct ReaderSettings: Codable {
    var fontSize: Double = 18
    var lineSpacing: Double = 8
    var paragraphSpacing: Double = 10
    var firstLineIndent: Bool = true
    var fontName: String = "System"
    var backgroundColor: String = "#FFFFFF"
    var textColor: String = "#212121"
    var theme: String = "day"        // day / night / eye / paper
    var pageMode: String = "scroll"  // scroll 滚动 / cover 覆盖 / simulation 仿真 / slide 滑动 / none 无动画
    var marginHorizontal: Double = 20
    var marginVertical: Double = 24
    var brightness: Double = 1.0
    var autoRead: Bool = false
    var autoReadSpeed: Double = 1.5  // 每秒滚动行数基准
    var keepScreenOn: Bool = false
    var fullScreen: Bool = false
    var showStatusbar: Bool = true
}

// MARK: - 搜索结果
struct SearchResult: Identifiable, Hashable {
    var id: String { bookUrl + sourceId }
    var name: String
    var author: String
    var coverUrl: String?
    var bookUrl: String
    var sourceId: String
    var sourceName: String
    var kind: String?
    var lastChapter: String?
    var intro: String?
    var wordCount: String?
}

// MARK: - 发现分组
struct ExploreGroup: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var url: String
    var bookList: [SearchResult]
}
