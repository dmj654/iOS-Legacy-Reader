import Foundation
import Kanna

// MARK: - 规则类型
enum RuleType { case css, xpath, json, regex }

// MARK: - 规则引擎（兼容开源阅读 Legado 语法）
/// 支持四种解析规则：CSS选择器、XPath、JSONPath、正则表达式
/// 规则结构：以 && 串联多段；以 ## 拆分「规则 + 替换」
/// 前缀强制类型：@CSS:  @XPath:  @JSon:/@JSON:  @Regex:  （无前缀时按内容类型自动判定）
struct RuleEngine {

    // 入口：对 content（HTML 或 JSON 文本）执行整条规则
    static func eval(rule: String?, content: String, isHtml: Bool) -> [String] {
        guard let rule = rule, !rule.isEmpty else { return [] }
        let steps = rule.components(separatedBy: "&&")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var inputs: [String] = [content]
        for step in steps {
            inputs = applyStep(step, inputs: inputs, isHtml: isHtml)
            if inputs.isEmpty { return [] }
        }
        return inputs
    }

    // 取第一个非空结果（用于单值字段）
    static func first(_ rule: String?, content: String, isHtml: Bool) -> String? {
        eval(rule: rule, content: content, isHtml: isHtml).first(where: { !$0.isEmpty })
    }

    // MARK: 单步执行
    private static func applyStep(_ step: String, inputs: [String], isHtml: Bool) -> [String] {
        let parts = step.components(separatedBy: "##")
        let rulePart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let replacePart = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil

        let (type, body) = detectType(rulePart, isHtml: isHtml)
        var results: [String] = []
        for input in inputs {
            results.append(contentsOf: applyRule(type: type, body: body, input: input, isHtml: isHtml))
        }
        if let rp = replacePart, !rp.isEmpty {
            results = results.map { applyReplace(replace: rp, on: $0) }
        }
        return results
    }

    private static func detectType(_ rule: String, isHtml: Bool) -> (RuleType, String) {
        if rule.hasPrefix("@CSS:")        { return (.css,   String(rule.dropFirst(5))) }
        if rule.hasPrefix("@XPath:")      { return (.xpath, String(rule.dropFirst(7))) }
        if rule.hasPrefix("@JSon:")       { return (.json,  String(rule.dropFirst(6))) }
        if rule.hasPrefix("@JSON:")       { return (.json,  String(rule.dropFirst(6))) }
        if rule.hasPrefix("@Regex:")      { return (.regex, String(rule.dropFirst(7))) }
        return (isHtml ? .css : .json, rule)
    }

    private static func applyRule(type: RuleType, body: String, input: String, isHtml: Bool) -> [String] {
        switch type {
        case .css, .xpath: return applyHtmlRule(type: type, selector: body, input: input)
        case .json:        return applyJsonRule(path: body, input: input)
        case .regex:       return applyRegex(pattern: body, input: input)
        }
    }

    // MARK: HTML 规则（CSS / XPath）
    private static func applyHtmlRule(type: RuleType, selector: String, input: String) -> [String] {
        guard let doc = try? HTML(html: input, encoding: .utf8) else { return [] }
        let nodes: XPathObject = (type == .css) ? doc.css(selector) : doc.xpath(selector)
        var out: [String] = []
        for case let node? in nodes {
            if let html = node.toHTML, !html.isEmpty { out.append(html) }
            else if let text = node.text, !text.isEmpty { out.append(text) }
        }
        return out
    }

    // MARK: JSON 规则（JSONPath）
    private static func applyJsonRule(path: String, input: String) -> [String] {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return JSONPath.query(path, on: json).map { stringify($0) }
    }

    // MARK: 正则规则
    private static func applyRegex(pattern: String, input: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        var out: [String] = []
        for m in matches {
            if m.numberOfRanges > 1 { out.append(ns.substring(with: m.range(at: 1))) }
            else { out.append(ns.substring(with: m.range)) }
        }
        return out
    }

    // MARK: ## 替换（支持 "正则-->替换" 或 "正则##替换"）
    private static func applyReplace(replace: String, on text: String) -> String {
        let sep: String
        let pat: String
        let rep: String
        if let r = replace.range(of: "-->") {
            sep = "-->"; pat = String(replace[..<r.lowerBound]); rep = String(replace[r.upperBound...])
        } else if let r = replace.range(of: "##") {
            sep = "##"; pat = String(replace[..<r.lowerBound]); rep = String(replace[r.upperBound...])
        } else {
            return text
        }
        _ = sep
        guard let regex = try? NSRegularExpression(pattern: pat, options: []) else { return text }
        let out = regex.stringByReplacingMatches(in: text,
                     range: NSRange(location: 0, length: (text as NSString).length),
                     withTemplate: rep)
        return out
    }

    private static func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let d = try? JSONSerialization.data(withJSONObject: value),
           let s = String(data: d, encoding: .utf8) { return s }
        return "\(value)"
    }
}

// MARK: - 极简 JSONPath 求值器
/// 支持： $  $.a.b  $.a[0]  $.a[*]  $.a[-1]  $.a[:2]  $[2:]  $.a[1:3]  $..key(递归)
struct JSONPath {
    static func query(_ path: String, on object: Any) -> [Any] {
        var current: [Any] = [object]
        for token in tokenize(path) {
            var next: [Any] = []
            for item in current { next.append(contentsOf: evalToken(token, on: item)) }
            current = next
        }
        return current
    }

    private static func tokenize(_ path: String) -> [String] {
        var tokens: [String] = []
        var i = path.startIndex
        while i < path.endIndex {
            let c = path[i]
            if c == "$" || c == "." || c == "[" || c == "]" || c == ":" || c == "*" {
                i = path.index(after: i); continue
            }
            if c == "." && i < path.index(before: path.endIndex) {
                let n = path.index(after: i)
                if path[n] == "." { tokens.append(".."); i = path.index(after: n); continue }
            }
            var buf = ""
            while i < path.endIndex {
                let ch = path[i]
                if ch == "." || ch == "[" { break }
                buf.append(ch); i = path.index(after: i)
            }
            if !buf.isEmpty { tokens.append(buf) }
        }
        return tokens
    }

    private static func evalToken(_ token: String, on item: Any) -> [Any] {
        if token == ".." {
            // 递归查找：token 后需跟 key，但此处简单返回所有后代中匹配 key 的值；
            // 由于递归 key 已并入单独 token，这里返回自身与递归结果由调用方处理
            return recursiveAll(item)
        }
        if token == "*" {
            if let arr = item as? [Any] { return arr }
            if let dict = item as? [String: Any] { return Array(dict.values) }
            return []
        }
        // 数组索引 / 切片
        if token.first == "[" || token.contains(":") {
            return evalArray(token, on: item)
        }
        // 普通 key
        if let dict = item as? [String: Any] {
            if let v = dict[token] { return [v] }
        }
        return []
    }

    private static func evalArray(_ token: String, on item: Any) -> [Any] {
        guard let arr = item as? [Any] else { return [] }
        let cleaned = token.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        if cleaned.contains(":") {
            let parts = cleaned.components(separatedBy: ":")
            let start = (parts[0].isEmpty ? 0 : (Int(parts[0]) ?? 0)).clamped(arr.count)
            let end = (parts.count > 1 && !parts[1].isEmpty) ? (Int(parts[1]) ?? arr.count).clamped(arr.count) : arr.count
            return Array(arr[start..<max(start, end)])
        }
        if let idx = Int(cleaned) {
            let i = idx < 0 ? arr.count + idx : idx
            if i >= 0 && i < arr.count { return [arr[i]] }
        }
        return []
    }

    private static func recursiveAll(_ item: Any) -> [Any] {
        var out: [Any] = [item]
        if let arr = item as? [Any] { for e in arr { out.append(contentsOf: recursiveAll(e)) } }
        else if let dict = item as? [String: Any] { for (_, v) in dict { out.append(contentsOf: recursiveAll(v)) } }
        return out
    }
}

private extension Int {
    func clamped(_ max: Int) -> Int { Swift.min(Swift.max(self, 0), max) }
}
