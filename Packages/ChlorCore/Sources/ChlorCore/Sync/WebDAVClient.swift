import Foundation

public struct WebDAVRemoteBackup: Identifiable, Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let href: String
    public let lastModified: String

    public init(fileName: String, href: String, lastModified: String = "") {
        self.id = fileName
        self.fileName = fileName
        self.href = href
        self.lastModified = lastModified
    }
}

public enum WebDAVError: LocalizedError {
    case invalidConfig
    case httpError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfig: return "请填写完整的 WebDAV 服务器地址、用户名和应用密码"
        case .httpError(let code, let msg): return "WebDAV 请求失败 (\(code))：\(msg)"
        }
    }
}

/// Zero-dependency native WebDAV client compatible with Jianguoyun (坚果云), Nextcloud, Alist, etc.
public struct WebDAVClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func testConnection(config: WebDAVConfig) async throws {
        let folderURL = try resolvedFolderURL(config: config)
        var req = makeAuthorizedRequest(url: folderURL, method: "PROPFIND", config: config)
        req.setValue("0", forHTTPHeaderField: "Depth")
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw WebDAVError.httpError(-1, "无响应")
        }
        if http.statusCode == 404 {
            // Folder doesn't exist yet -> create it to prove write access
            try await ensureFolderExists(config: config)
            return
        }
        guard (200...299).contains(http.statusCode) || http.statusCode == 207 else {
            throw WebDAVError.httpError(http.statusCode, "认证失败或路径不可访问")
        }
    }

    public func uploadBackup(localFileURL: URL, remoteFileName: String, config: WebDAVConfig) async throws {
        try await ensureFolderExists(config: config)
        let folderURL = try resolvedFolderURL(config: config)
        let targetURL = folderURL.appendingPathComponent(remoteFileName)
        let data = try Data(contentsOf: localFileURL)

        var req = makeAuthorizedRequest(url: targetURL, method: "PUT", config: config)
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw WebDAVError.httpError(code, "上传备份文件失败")
        }
    }

    public func listBackups(config: WebDAVConfig) async throws -> [WebDAVRemoteBackup] {
        let folderURL = try resolvedFolderURL(config: config)
        var req = makeAuthorizedRequest(url: folderURL, method: "PROPFIND", config: config)
        req.setValue("1", forHTTPHeaderField: "Depth")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw WebDAVError.httpError(-1, "无响应")
        }
        if http.statusCode == 404 { return [] }
        guard (200...299).contains(http.statusCode) || http.statusCode == 207 else {
            throw WebDAVError.httpError(http.statusCode, "列出远程备份失败")
        }
        let xml = String(data: data, encoding: .utf8) ?? ""
        return Self.parseSQLiteBackupsFromPropfind(xml: xml)
    }

    public func downloadBackup(remoteFileName: String, config: WebDAVConfig, to destinationURL: URL) async throws {
        let folderURL = try resolvedFolderURL(config: config)
        let targetURL = folderURL.appendingPathComponent(remoteFileName)
        let req = makeAuthorizedRequest(url: targetURL, method: "GET", config: config)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw WebDAVError.httpError(code, "下载云端备份失败")
        }
        try data.write(to: destinationURL, options: .atomic)
    }

    private func ensureFolderExists(config: WebDAVConfig) async throws {
        let folderURL = try resolvedFolderURL(config: config)
        let req = makeAuthorizedRequest(url: folderURL, method: "MKCOL", config: config)
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return }
        // 201 Created, 405 Method Not Allowed (already exists), 301/200 are all fine
        if ![200, 201, 204, 301, 405].contains(http.statusCode) {
            throw WebDAVError.httpError(http.statusCode, "无法在 WebDAV 上创建目录")
        }
    }

    private func resolvedFolderURL(config: WebDAVConfig) throws -> URL {
        let baseStr = config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseStr.isEmpty,
              !config.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !config.password.isEmpty,
              var url = URL(string: baseStr.hasSuffix("/") ? baseStr : baseStr + "/") else {
            throw WebDAVError.invalidConfig
        }
        let folder = config.remoteFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !folder.isEmpty {
            url = url.appendingPathComponent(folder, isDirectory: true)
        }
        return url
    }

    private func makeAuthorizedRequest(url: URL, method: String, config: WebDAVConfig) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        let creds = "\(config.username):\(config.password)"
        let b64 = Data(creds.utf8).base64EncodedString()
        req.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        return req
    }

    public static func parseSQLiteBackupsFromPropfind(xml: String) -> [WebDAVRemoteBackup] {
        let pattern = #"<[^:>]*:?href[^>]*>([^<]+)</[^:>]*:?href>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        var seen: Set<String> = []
        var items: [WebDAVRemoteBackup] = []
        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let rawHref = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let decoded = rawHref.removingPercentEncoding ?? rawHref
            let fileName = URL(fileURLWithPath: decoded).lastPathComponent
            if fileName.lowercased().hasSuffix(".sqlite") && !seen.contains(fileName) {
                seen.insert(fileName)
                items.append(WebDAVRemoteBackup(fileName: fileName, href: rawHref))
            }
        }
        return items.sorted { $0.fileName > $1.fileName }
    }
}
