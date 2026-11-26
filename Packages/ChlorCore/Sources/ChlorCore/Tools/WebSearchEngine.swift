import Foundation

public enum WebSearchError: LocalizedError {
    case missingAPIKey(String)
    case invalidResponse
    case httpError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let name): return "请先在「工坊 → 联网搜索」中填写 \(name) 的 API Key，或切换为 DuckDuckGo 免 Key 模式"
        case .invalidResponse: return "搜索服务返回数据异常"
        case .httpError(let code, let body): return "联网搜索失败 (\(code))：\(body.prefix(120))"
        }
    }
}

/// Real-time web search aggregator supporting DuckDuckGo (free), Tavily, Brave Search, and Exa.
public struct WebSearchEngine: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(
        query: String,
        provider: WebSearchProviderKind,
        apiKey: String,
        maxResults: Int = 4
    ) async throws -> [WebSearchSource] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let limit = max(1, min(8, maxResults))

        switch provider {
        case .duckDuckGoFree:
            return try await searchDuckDuckGoHTML(query: trimmed, limit: limit)
        case .tavily:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw WebSearchError.missingAPIKey("Tavily") }
            return try await searchTavily(query: trimmed, apiKey: key, limit: limit)
        case .brave:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw WebSearchError.missingAPIKey("Brave Search") }
            return try await searchBrave(query: trimmed, apiKey: key, limit: limit)
        case .exa:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw WebSearchError.missingAPIKey("Exa") }
            return try await searchExa(query: trimmed, apiKey: key, limit: limit)
        }
    }

    public static func formatContextBlock(query: String, sources: [WebSearchSource]) -> String {
        guard !sources.isEmpty else { return "" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = [
            "【实时联网搜索结果（检索词：\(query)，时间：\(df.string(from: Date()))）】",
            "请自然参考以下最新网络信息回答用户，不要生硬照搬 URL："
        ]
        for (idx, item) in sources.enumerated() {
            lines.append("[\(idx + 1)] \(item.title) (\(item.url))\n摘要：\(item.snippet)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Tavily

    private func searchTavily(query: String, apiKey: String, limit: Int) async throws -> [WebSearchSource] {
        guard let url = URL(string: "https://api.tavily.com/search") else { throw WebSearchError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "max_results": limit,
            "search_depth": "basic"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WebSearchError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        return results.prefix(limit).compactMap { item in
            guard let title = item["title"] as? String, let link = item["url"] as? String else { return nil }
            let snippet = (item["content"] as? String) ?? ""
            return WebSearchSource(title: title, url: link, snippet: String(snippet.prefix(320)))
        }
    }

    // MARK: - Brave Search

    private func searchBrave(query: String, apiKey: String, limit: Int) async throws -> [WebSearchSource] {
        var comps = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "\(limit)")
        ]
        guard let url = comps?.url else { throw WebSearchError.invalidResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WebSearchError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = json["web"] as? [String: Any],
              let results = web["results"] as? [[String: Any]] else {
            return []
        }
        return results.prefix(limit).compactMap { item in
            guard let title = item["title"] as? String, let link = item["url"] as? String else { return nil }
            let snippet = (item["description"] as? String) ?? ""
            return WebSearchSource(title: title, url: link, snippet: String(snippet.prefix(320)))
        }
    }

    // MARK: - Exa Search

    private func searchExa(query: String, apiKey: String, limit: Int) async throws -> [WebSearchSource] {
        guard let url = URL(string: "https://api.exa.ai/search") else { throw WebSearchError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        let body: [String: Any] = [
            "query": query,
            "numResults": limit,
            "contents": ["text": ["maxCharacters": 350]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WebSearchError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        return results.prefix(limit).compactMap { item in
            guard let link = item["url"] as? String else { return nil }
            let title = (item["title"] as? String) ?? link
            let snippet = (item["text"] as? String) ?? ""
            return WebSearchSource(title: title, url: link, snippet: String(snippet.prefix(320)))
        }
    }

    // MARK: - DuckDuckGo Free Lite Fallback (No API Key)

    private func searchDuckDuckGoHTML(query: String, limit: Int) async throws -> [WebSearchSource] {
        var comps = URLComponents(string: "https://html.duckduckgo.com/html/")
        comps?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = comps?.url else { throw WebSearchError.invalidResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WebSearchError.httpError(http.statusCode, "DuckDuckGo HTTP \(http.statusCode)")
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        return Self.parseDuckDuckGoHTML(html, limit: limit)
    }

    public static func parseDuckDuckGoHTML(_ html: String, limit: Int) -> [WebSearchSource] {
        var results: [WebSearchSource] = []
        let linkPattern = #"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a[^>]*class="result__snippet"[^>]*>(.*?)</a>|<div[^>]*class="result__snippet"[^>]*>(.*?)</div>"#

        let ns = html as NSString
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [.dotMatchesLineSeparators]),
              let snipRegex = try? NSRegularExpression(pattern: snippetPattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let linkMatches = linkRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        let snipMatches = snipRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        for (i, m) in linkMatches.prefix(limit).enumerated() {
            guard m.numberOfRanges >= 3 else { continue }
            let rawHref = ns.substring(with: m.range(at: 1))
            let rawTitle = ns.substring(with: m.range(at: 2))
            let cleanURL = extractActualDDGURL(rawHref)
            let cleanTitle = stripHTML(rawTitle)
            var snippet = ""
            if i < snipMatches.count {
                let sm = snipMatches[i]
                if sm.range(at: 1).location != NSNotFound {
                    snippet = stripHTML(ns.substring(with: sm.range(at: 1)))
                } else if sm.numberOfRanges > 2 && sm.range(at: 2).location != NSNotFound {
                    snippet = stripHTML(ns.substring(with: sm.range(at: 2)))
                }
            }
            if !cleanTitle.isEmpty && !cleanURL.isEmpty {
                results.append(WebSearchSource(title: cleanTitle, url: cleanURL, snippet: snippet))
            }
        }
        return results
    }

    private static func extractActualDDGURL(_ raw: String) -> String {
        if let comps = URLComponents(string: raw.hasPrefix("//") ? "https:" + raw : raw),
           let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value {
            return uddg
        }
        return raw.hasPrefix("//") ? "https:" + raw : raw
    }

    private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
