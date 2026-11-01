import Foundation

struct HTTPError: LocalizedError {
    let status: Int
    var errorDescription: String? { "なろうがエラー(\(status))を返しました" }
}

struct ParseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 小説家になろうのページ・API を取得して解析する
enum NarouClient {
    private static let base = "https://ncode.syosetu.com"
    private static let apiBase = "https://api.syosetu.com/novelapi/api/"
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"

    // MARK: - 通信

    private static func makeRequest(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("over18=yes", forHTTPHeaderField: "Cookie")   // 年齢確認を通す
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("ja", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 25
        return req
    }

    private static func getData(_ url: URL) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: makeRequest(url))
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw HTTPError(status: http.statusCode)
        }
        return data
    }

    private static func getHTML(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw ParseError(message: "URLが不正です") }
        let data = try await getData(url)
        guard let s = String(data: data, encoding: .utf8) else { throw ParseError(message: "本文を読めませんでした") }
        return s
    }

    // MARK: - 話数一覧・本文

    /// 作品トップ(話数一覧)。連載でなければ episodes は空(短編)
    static func index(_ ncode: String) async throws -> (title: String, episodes: [EpisodeInfo]) {
        var title = ""
        var episodes: [EpisodeInfo] = []
        var seen = Set<Int>()
        var page = 1
        while page <= 40 {
            let html: String
            do {
                html = try await getHTML("\(base)/\(ncode)/?p=\(page)")
            } catch let e as HTTPError {
                if page > 1 && e.status == 404 { break }
                throw e
            }
            if page == 1 {
                let t1 = first(pattern: "<h1[^>]*class=\"[^\"]*p-novel__title[^\"]*\"[^>]*>(.*?)</h1>", in: html)
                let t2 = first(pattern: "<p[^>]*class=\"novel_title\"[^>]*>(.*?)</p>", in: html)
                let t3 = first(pattern: "<title>(.*?)</title>", in: html)
                title = clean(t1 ?? t2 ?? t3 ?? "")
            }
            var added = 0
            let pattern = "<a[^>]*href=\"/\(ncode)/(\\d+)/?\"[^>]*>(.*?)</a>"
            for m in allMatches(pattern: pattern, in: html) {
                guard m.count >= 2, let n = Int(m[0]), !seen.contains(n) else { continue }
                let label = clean(m[1])
                if label.isEmpty { continue }
                seen.insert(n)
                episodes.append(EpisodeInfo(n: n, title: label))
                added += 1
            }
            if added == 0 { break }
            page += 1
        }
        episodes.sort { $0.n < $1.n }
        return (title, episodes)
    }

    /// n == 0 のときは短編(作品トップが本文)
    static func episode(_ ncode: String, _ n: Int) async throws -> Episode {
        let url = n == 0 ? "\(base)/\(ncode)/" : "\(base)/\(ncode)/\(n)/"
        let html = try await getHTML(url)

        let t1 = first(pattern: "<h1[^>]*class=\"[^\"]*p-novel__title[^\"]*\"[^>]*>(.*?)</h1>", in: html)
        let t2 = first(pattern: "<p[^>]*class=\"novel_subtitle\"[^>]*>(.*?)</p>", in: html)
        let title = clean(t1 ?? t2 ?? "")

        // 本文ブロック(前書き・後書きは除く)
        var body: String?
        let blocks = allMatches(pattern: "(<div[^>]*class=\"[^\"]*js-novel-text[^\"]*\"[^>]*>)(.*?)</div>", in: html)
        for b in blocks where b.count >= 2 {
            if !b[0].contains("preface") && !b[0].contains("afterword") { body = b[1]; break }
        }
        if body == nil, let old = first(pattern: "<div[^>]*id=\"novel_honbun\"[^>]*>(.*?)</div>", in: html) {
            body = old
        }
        guard let bodyHTML = body else { throw ParseError(message: "本文を取得できませんでした") }

        var paragraphs: [String] = []
        for m in allMatches(pattern: "<p[^>]*>(.*?)</p>", in: bodyHTML) {
            if let s = m.first { paragraphs.append(clean(s)) }
        }
        if !paragraphs.contains(where: { !$0.isEmpty }) { throw ParseError(message: "本文を取得できませんでした") }
        return Episode(title: title, paragraphs: paragraphs)
    }

    // MARK: - 検索・ランキング・更新確認 (なろう小説API)

    static func search(word: String, title: Bool, story: Bool, keyword: Bool, writer: Bool,
                       order: String, type: String, start: Int) async throws -> (total: Int, items: [NovelSummary]) {
        var q: [URLQueryItem] = [
            URLQueryItem(name: "of", value: "t-n-w-s-nt-e-ga-gp-l-g"),
            URLQueryItem(name: "lim", value: "20"),
            URLQueryItem(name: "word", value: word),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "st", value: String(start)),
        ]
        if title { q.append(URLQueryItem(name: "title", value: "1")) }
        if story { q.append(URLQueryItem(name: "ex", value: "1")) }
        if keyword { q.append(URLQueryItem(name: "keyword", value: "1")) }
        if writer { q.append(URLQueryItem(name: "wname", value: "1")) }
        if !type.isEmpty { q.append(URLQueryItem(name: "type", value: type)) }
        return try await fetchList(q, periodKey: nil)
    }

    static let periods: [PeriodOption] = [
        PeriodOption(key: "d", label: "日間", order: "dailypoint", field: "daily_point"),
        PeriodOption(key: "w", label: "週間", order: "weeklypoint", field: "weekly_point"),
        PeriodOption(key: "m", label: "月間", order: "monthlypoint", field: "monthly_point"),
        PeriodOption(key: "q", label: "四半期", order: "quarterpoint", field: "quarter_point"),
        PeriodOption(key: "y", label: "年間", order: "yearlypoint", field: "yearly_point"),
        PeriodOption(key: "a", label: "累計", order: "hyoka", field: "global_point"),
    ]

    static func rank(period: String, genre: Int?, type: String, start: Int) async throws -> (total: Int, items: [NovelSummary]) {
        let p = periods.first(where: { $0.key == period }) ?? periods[0]
        var q: [URLQueryItem] = [
            URLQueryItem(name: "of", value: "t-n-w-s-nt-e-ga-g-l-gp-dp-wp-mp-qp-yp"),
            URLQueryItem(name: "lim", value: "20"),
            URLQueryItem(name: "order", value: p.order),
            URLQueryItem(name: "st", value: String(start)),
        ]
        if let g = genre { q.append(URLQueryItem(name: "genre", value: String(g))) }
        if !type.isEmpty { q.append(URLQueryItem(name: "type", value: type)) }
        return try await fetchList(q, periodKey: p.field)
    }

    /// お気に入りの最新話数を、まとめて確認する
    static func info(ncodes: [String]) async throws -> [String: (title: String, total: Int)] {
        guard !ncodes.isEmpty else { return [:] }
        let q: [URLQueryItem] = [
            URLQueryItem(name: "of", value: "t-n-ga-nt"),
            URLQueryItem(name: "lim", value: "500"),
            URLQueryItem(name: "ncode", value: ncodes.joined(separator: "-")),
        ]
        let (_, items) = try await fetchList(q, periodKey: nil)
        var out: [String: (title: String, total: Int)] = [:]
        for it in items { out[it.ncode] = (it.title, it.totalEpisodes) }
        return out
    }

    private static func fetchList(_ items: [URLQueryItem], periodKey: String?) async throws -> (Int, [NovelSummary]) {
        guard var comps = URLComponents(string: apiBase) else { throw ParseError(message: "URLが不正です") }
        comps.queryItems = [URLQueryItem(name: "out", value: "json")] + items
        guard let url = comps.url else { throw ParseError(message: "URLが不正です") }
        let data = try await getData(url)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ParseError(message: "検索結果を読めませんでした")
        }
        let total = intValue(arr.first?["allcount"])
        var list: [NovelSummary] = []
        for d in arr.dropFirst() {
            guard let code = d["ncode"] as? String else { continue }
            let noveltype = intValue(d["noveltype"])
            let isShort = noveltype == 2
            let eps = isShort ? 1 : intValue(d["general_all_no"])
            var point: Int? = nil
            if let key = periodKey { point = intValue(d[key]) }
            let s = NovelSummary(
                ncode: code.lowercased(),
                title: (d["title"] as? String) ?? "",
                writer: (d["writer"] as? String) ?? "",
                story: (d["story"] as? String) ?? "",
                isShort: isShort,
                isEnded: intValue(d["end"]) == 0,
                totalEpisodes: eps,
                length: intValue(d["length"]),
                globalPoint: intValue(d["global_point"]),
                genre: intValue(d["genre"]),
                periodPoint: point
            )
            list.append(s)
        }
        return (total, list)
    }

    private static func intValue(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String, let i = Int(s) { return i }
        return 0
    }

    // MARK: - 解析ヘルパー

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
    }

    /// 各マッチのキャプチャグループ(1番目以降)
    private static func allMatches(pattern: String, in s: String) -> [[String]] {
        guard let re = regex(pattern) else { return [] }
        let ns = s as NSString
        let results = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var out: [[String]] = []
        for m in results {
            var groups: [String] = []
            if m.numberOfRanges > 1 {
                for i in 1..<m.numberOfRanges {
                    let r = m.range(at: i)
                    groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
                }
            }
            out.append(groups)
        }
        return out
    }

    private static func first(pattern: String, in s: String) -> String? {
        return allMatches(pattern: pattern, in: s).first?.first
    }

    /// HTML → 読み上げ用テキスト(ルビは親文字だけ残す)
    private static func clean(_ html: String) -> String {
        var s = html
        let steps: [(String, String)] = [
            ("<rp>.*?</rp>", ""), ("<rt>.*?</rt>", ""), ("<br\\s*/?>", "\n"), ("<[^>]+>", ""),
        ]
        for (p, r) in steps {
            if let re = regex(p) {
                let range = NSRange(location: 0, length: (s as NSString).length)
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: r)
            }
        }
        let entities: [(String, String)] = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
            ("&nbsp;", " "), ("&amp;", "&"),
        ]
        for (a, b) in entities { s = s.replacingOccurrences(of: a, with: b) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
