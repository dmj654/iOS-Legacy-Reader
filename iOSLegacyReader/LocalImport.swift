import Foundation
import Compression

// MARK: - 本地文件导入（TXT / EPUB）
struct LocalImport {

    // MARK: TXT 导入：按常见章节标题正则切分
    static func `import`(txtURL: URL) -> Book? {
        guard let raw = try? String(contentsOf: txtURL, encoding: .utf8) ??
                         String(contentsOf: txtURL, encoding: String.Encoding(rawValue: 0x80000632)) else { return nil }
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let name = txtURL.deletingPathExtension().lastPathComponent
        let author = extractAuthor(from: text) ?? "未知"

        let chapterRegex = try? NSRegularExpression(pattern: #"(?m)^\s*(第[零一二三四五六七八九十百千0-9]+[章回卷节部篇集]\s*[^第\n]{0,30}|[Cc]hapter\s*\d+\s*[^\n]{0,30})"#, options: [])
        var chapters: [Chapter] = []
        let ns = text as NSString
        let matches = chapterRegex?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []

        if matches.isEmpty {
            // 无章节标记：整体作为一章
            chapters.append(Chapter(title: name, url: "txt://\(name)/0", index: 0, content: text))
        } else {
            for (i, m) in matches.enumerated() {
                let start = Int(m.range.location)
                let end = Int((i + 1 < matches.count) ? matches[i + 1].range.location : ns.length)
                let range = NSRange(location: start, length: end - start)
                let chunk = ns.substring(with: range)
                let title = ns.substring(with: m.range).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                chapters.append(Chapter(title: title, url: "txt://\(name)/\(i)", index: i, content: chunk))
            }
        }

        var book = Book(name: name, author: author, bookUrl: "txt://\(name)", source: localSource())
        book.intro = "本地导入 TXT"
        book.chapters = chapters
        book.coverUrl = nil
        return book
    }

    private static func extractAuthor(from text: String) -> String? {
        let patterns = [#"作者[：:]\s*([^\n]{1,20})"#, #"作\s*者[：:]\s*([^\n]{1,20})"#, #"著\s*[\/／]\s*([^\n]{1,20})"#]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: []),
               let m = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
               m.numberOfRanges > 1 {
                let a = (text as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !a.isEmpty { return a }
            }
        }
        return nil
    }

    // MARK: EPUB 导入（极简 ZIP + OPF 解析，best-effort）
    static func `import`(epubURL: URL) -> Book? {
        guard let data = try? Data(contentsOf: epubURL),
              let files = ZipArchive.unzip(data: data) else { return nil }
        let name = epubURL.deletingPathExtension().lastPathComponent

        // 1. container.xml -> OPF 路径
        guard let container = files["META-INF/container.xml"],
              let opfPath = parseOPFPath(container),
              let opfData = files[opfPath] else { return nil }

        let (chapters, coverPath) = parseOPF(opfData, opfPath: opfPath, files: files, name: name)
        var book = Book(name: name, author: "未知", bookUrl: "epub://\(name)", source: localSource())
        book.intro = "本地导入 EPUB"
        book.chapters = chapters
        if let coverPath = coverPath, files[coverPath] != nil {
            let dir = (opfPath as NSString).deletingLastPathComponent
            let full = dir.isEmpty ? coverPath : (dir + "/" + coverPath)
            if let c = files[full] { book.coverUrl = "data:image/png;base64," + c.base64EncodedString() }
        }
        return book
    }

    private static func parseOPFPath(_ container: Data) -> String? {
        guard let xml = String(data: container, encoding: .utf8) else { return nil }
        // 取第一个 full-path
        let re = try? NSRegularExpression(pattern: #"full-path="([^"]+)""#, options: [])
        if let m = re?.firstMatch(in: xml, range: NSRange(location: 0, length: (xml as NSString).length)),
           m.numberOfRanges > 1 {
            return (xml as NSString).substring(with: m.range(at: 1))
        }
        return nil
    }

    private static func parseOPF(_ opf: Data, opfPath: String, files: [String: Data], name: String) -> ([Chapter], String?) {
        guard let xml = String(data: opf, encoding: .utf8) else { return ([], nil) }
        // 提取 spine 顺序的 item href
        let itemRefRe = try? NSRegularExpression(pattern: #"<itemref[^>]*idref="([^"]+)""#, options: [])
        let itemRe = try? NSRegularExpression(pattern: #"<item[^>]*id="([^"]+)"[^>]*href="([^"]+)"[^>]*media-type="([^"]+)""#, options: [])

        var idToHref: [String: (href: String, type: String)] = [:]
        if let ms = itemRe?.matches(in: xml, range: NSRange(location: 0, length: (xml as NSString).length)) {
            for m in ms {
                let id = (xml as NSString).substring(with: m.range(at: 1))
                let href = (xml as NSString).substring(with: m.range(at: 2))
                let type = (xml as NSString).substring(with: m.range(at: 3))
                idToHref[id] = (href, type)
            }
        }
        var coverId: String?
        let coverRe = try? NSRegularExpression(pattern: #"name="cover"[^>]*content="([^"]+)""#, options: [])
        if let m = coverRe?.firstMatch(in: xml, range: NSRange(location: 0, length: (xml as NSString).length)),
           m.numberOfRanges > 1 {
            coverId = (xml as NSString).substring(with: m.range(at: 1))
        }

        var chapters: [Chapter] = []
        let dir = (opfPath as NSString).deletingLastPathComponent
        if let ms = itemRefRe?.matches(in: xml, range: NSRange(location: 0, length: (xml as NSString).length)) {
            for (i, m) in ms.enumerated() {
                let id = (xml as NSString).substring(with: m.range(at: 1))
                guard let (href, type) = idToHref[id], type.contains("html") else { continue }
                let path = dir.isEmpty ? href : (dir + "/" + href)
                guard let xhtmlData = files[path], let xhtml = String(data: xhtmlData, encoding: .utf8) else { continue }
                let title = parseTitle(xhtml) ?? "第\(i+1)节"
                chapters.append(Chapter(title: title, url: "epub://\(name)/\(i)", index: i, content: stripTags(xhtml)))
            }
        }
        let coverPath = coverId.flatMap { idToHref[$0]?.href }
        return (chapters, coverPath)
    }

    private static func parseTitle(_ xhtml: String) -> String? {
        if let re = try? NSRegularExpression(pattern: #"<h[1-6][^>]*>([^<]+)</h[1-6]>"#, options: []),
           let m = re.firstMatch(in: xhtml, range: NSRange(location: 0, length: (xhtml as NSString).length)),
           m.numberOfRanges > 1 {
            return (xhtml as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func stripTags(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "</p>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func localSource() -> BookSource {
        BookSource(name: "本地导入", url: "local://import")
    }
}

// MARK: - 极简 ZIP 读取（STORED + DEFLATE）
struct ZipArchive {
    static func unzip(data: Data) -> [String: Data]? {
        guard let eocd = findEOCD(data) else { return nil }
        let cdOffset = Int(eocd.cdOffset)
        var result: [String: Data] = [:]
        var p = cdOffset
        for _ in 0..<eocd.cdCount {
            guard p + 46 <= data.count else { break }
            let sig = readUInt32(data, p)
            guard sig == 0x02014b50 else { break }
            let method = readUInt16(data, p + 10)
            let csize = Int(readUInt32(data, p + 20))
            let usize = Int(readUInt32(data, p + 24))
            let nlen = Int(readUInt16(data, p + 28))
            let elen = Int(readUInt16(data, p + 30))
            let clen = Int(readUInt16(data, p + 32))
            let nameStart = p + 46
            guard nameStart + nlen <= data.count else { break }
            let name = String(data: data.subdata(in: nameStart..<nameStart+nlen), encoding: .utf8) ?? ""
            let localOffset = Int(readUInt32(data, p + 42))
            p += 46 + nlen + elen + clen
            // 读本地文件头
            guard localOffset + 30 <= data.count else { continue }
            let lnlen = Int(readUInt16(data, localOffset + 26))
            let lelen = Int(readUInt16(data, localOffset + 28))
            let dataStart = localOffset + 30 + lnlen + lelen
            guard dataStart + csize <= data.count else { continue }
            let comp = data.subdata(in: dataStart..<dataStart+csize)
            let out = inflate(comp: comp, method: method, uncompressedSize: usize)
            result[name] = out
        }
        return result
    }

    private static func findEOCD(_ data: Data) -> (cdOffset: UInt32, cdCount: UInt16)? {
        let minLen = 22
        guard data.count >= minLen else { return nil }
        var scan = data.count - minLen
        while scan >= 0 {
            if readUInt32(data, scan) == 0x06054b50 {
                let cdCount = readUInt16(data, scan + 10)
                let cdOffset = readUInt32(data, scan + 16)
                return (cdOffset, cdCount)
            }
            scan -= 1
        }
        return nil
    }

    private static func inflate(comp: Data, method: UInt16, uncompressedSize: Int) -> Data {
        if method == 0 { return comp } // stored
        // deflate：补 zlib 头后用 COMPRESSION_ZLIB 解码
        var withHeader = Data([0x78, 0x9C])
        withHeader.append(comp)
        let dstCap = max(uncompressedSize, comp.count * 4, 1 << 16)
        var dst = Data(count: dstCap)
        let written = dst.withUnsafeMutableBytes { dPtr -> Int in
            let d = dPtr.bindMemory(to: UInt8.self)
            return withHeader.withUnsafeBytes { sPtr in
                let s = sPtr.bindMemory(to: UInt8.self)
                return compression_decode_buffer(d.baseAddress!, dstCap, s.baseAddress!, withHeader.count, nil, COMPRESSION_ZLIB)
            }
        }
        if written > 0 && written <= dstCap { return dst.subdata(in: 0..<written) }
        // 兜底：直接尝试（某些存档已是 zlib 流）
        var dst2 = Data(count: dstCap)
        let written2 = dst2.withUnsafeMutableBytes { dPtr -> Int in
            let d = dPtr.bindMemory(to: UInt8.self)
            return comp.withUnsafeBytes { sPtr in
                let s = sPtr.bindMemory(to: UInt8.self)
                return compression_decode_buffer(d.baseAddress!, dstCap, s.baseAddress!, comp.count, nil, COMPRESSION_ZLIB)
            }
        }
        if written2 > 0 { return dst2.subdata(in: 0..<written2) }
        return comp
    }

    private static func readUInt32(_ d: Data, _ o: Int) -> UInt32 {
        guard o + 4 <= d.count else { return 0 }
        return d.subdata(in: o..<o+4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }
    private static func readUInt16(_ d: Data, _ o: Int) -> UInt16 {
        guard o + 2 <= d.count else { return 0 }
        return d.subdata(in: o..<o+2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    }
}
