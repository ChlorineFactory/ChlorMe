import Foundation
import Darwin
import Network
import ChlorCore

public struct ActiveModelDownload: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let fileName: String
    public var progress: Double
    public var bytesWritten: Int64
    public var totalBytes: Int64
    public let quantization: String
    public let recommendedContext: Int
    public let chatTemplate: ChatTemplateStyle
}

@MainActor
public final class ModelDownloadManager: NSObject, ObservableObject {
    @Published public var activeDownloads: [String: ActiveModelDownload] = [:]
    @Published public var lastError: String?

    private var urlSession: URLSession!
    private var taskMap: [Int: (id: String, completion: (Result<ModelConfig, Error>) -> Void)] = [:]
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    public func startDownload(
        name: String,
        urlString: String,
        fileName: String,
        quantization: String = "Q4_K_M",
        recommendedContext: Int = 8192,
        chatTemplate: ChatTemplateStyle = .auto,
        onComplete: @escaping (Result<ModelConfig, Error>) -> Void
    ) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            onComplete(.failure(NSError(domain: "Download", code: -1, userInfo: [NSLocalizedDescriptionKey: "下载链接格式无效"])))
            return
        }
        let id = UUID().uuidString
        let safeFileName = fileName.isEmpty ? (url.lastPathComponent.isEmpty ? "\(id).gguf" : url.lastPathComponent) : fileName
        activeDownloads[id] = ActiveModelDownload(
            id: id,
            name: name,
            fileName: safeFileName,
            progress: 0,
            bytesWritten: 0,
            totalBytes: 0,
            quantization: quantization,
            recommendedContext: recommendedContext,
            chatTemplate: chatTemplate
        )
        let task = urlSession.downloadTask(with: url)
        taskMap[task.taskIdentifier] = (id: id, completion: onComplete)
        downloadTasks[id] = task
        task.resume()
    }

    public func cancelDownload(id: String) {
        downloadTasks[id]?.cancel()
        downloadTasks.removeValue(forKey: id)
        activeDownloads.removeValue(forKey: id)
    }

    public func importLocalGGUF(from securityScopedURL: URL) throws -> ModelConfig {
        let accessed = securityScopedURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { securityScopedURL.stopAccessingSecurityScopedResource() }
        }
        let fileName = securityScopedURL.lastPathComponent
        let dest = LocalLlamaBackend.modelsDirectoryURL.appendingPathComponent(fileName)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: securityScopedURL, to: dest)
        let attrs = try fm.attributesOfItem(atPath: dest.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        return Self.makeModelConfig(fromFileName: fileName, fileSizeBytes: size)
    }

    public static func makeModelConfig(fromFileName fileName: String, fileSizeBytes: Int64) -> ModelConfig {
        let baseName = fileName.replacingOccurrences(of: ".gguf", with: "", options: .caseInsensitive)
        let upper = baseName.uppercased()
        let quantCandidates = ["Q8_0", "Q6_K", "Q5_K_M", "Q5_K_S", "Q4_K_M", "Q4_K_S", "IQ4_XS", "Q3_K_L", "Q3_K_M", "Q2_K"]
        let detectedQuant = quantCandidates.first(where: { upper.contains($0) }) ?? "GGUF"
        let lower = baseName.lowercased()
        let template: ChatTemplateStyle
        if lower.contains("llama-3") || lower.contains("llama3") { template = .llama3 }
        else if lower.contains("gemma") { template = .gemma }
        else if lower.contains("mistral") || lower.contains("nemo") { template = .mistral }
        else { template = .chatML }

        return ModelConfig(
            name: baseName,
            backendKind: .localGGUF,
            localFileName: fileName,
            fileSizeBytes: fileSizeBytes,
            quantizationLabel: detectedQuant,
            contextLength: 8192,
            kvQuantType: .q8_0,
            gpuLayers: 99,
            chatTemplate: template
        )
    }
}

extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskId = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let entry = self.taskMap[taskId],
                  var dl = self.activeDownloads[entry.id] else { return }
            dl.bytesWritten = totalBytesWritten
            dl.totalBytes = totalBytesExpectedToWrite
            if totalBytesExpectedToWrite > 0 {
                dl.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
            self.activeDownloads[entry.id] = dl
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier
        // Move file synchronously before URLSession deletes the temp file!
        let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent("chlorme-dl-\(UUID().uuidString).gguf")
        do {
            try FileManager.default.moveItem(at: location, to: tempCopy)
        } catch {
            Task { @MainActor in
                if let entry = self.taskMap.removeValue(forKey: taskId) {
                    self.activeDownloads.removeValue(forKey: entry.id)
                    self.downloadTasks.removeValue(forKey: entry.id)
                    entry.completion(.failure(error))
                }
            }
            return
        }

        Task { @MainActor in
            guard let entry = self.taskMap.removeValue(forKey: taskId),
                  let dl = self.activeDownloads.removeValue(forKey: entry.id) else {
                try? FileManager.default.removeItem(at: tempCopy)
                return
            }
            self.downloadTasks.removeValue(forKey: entry.id)
            do {
                let dest = LocalLlamaBackend.modelsDirectoryURL.appendingPathComponent(dl.fileName)
                let fm = FileManager.default
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.moveItem(at: tempCopy, to: dest)
                let attrs = try fm.attributesOfItem(atPath: dest.path)
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? dl.bytesWritten
                let config = ModelConfig(
                    name: dl.name,
                    backendKind: .localGGUF,
                    localFileName: dl.fileName,
                    fileSizeBytes: size,
                    quantizationLabel: dl.quantization,
                    contextLength: dl.recommendedContext,
                    kvQuantType: .q8_0,
                    gpuLayers: 99,
                    chatTemplate: dl.chatTemplate
                )
                entry.completion(.success(config))
            } catch {
                try? FileManager.default.removeItem(at: tempCopy)
                entry.completion(.failure(error))
            }
        }
    }

    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        Task { @MainActor in
            guard let entry = self.taskMap.removeValue(forKey: taskId) else { return }
            self.activeDownloads.removeValue(forKey: entry.id)
            self.downloadTasks.removeValue(forKey: entry.id)
            if (error as NSError).code != NSURLErrorCancelled {
                self.lastError = error.localizedDescription
                entry.completion(.failure(error))
            }
        }
    }
}

// MARK: - Lightweight LAN Wi-Fi GGUF Upload Server (Zero Dependencies, Streaming to Disk)

@MainActor
public final class WiFiModelTransferServer: ObservableObject {
    @Published public var isRunning = false
    @Published public var serverURLString: String = ""
    @Published public var statusText: String = "未启动"
    @Published public var uploadProgress: Double = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.chlorme.wifi.server", qos: .utility)
    public var onModelReceived: ((ModelConfig) -> Void)?

    public func start(port: UInt16 = 8088) {
        stop()
        do {
            let nwPort = NWEndpoint.Port(rawValue: port) ?? 8088
            let listener = try NWListener(using: .tcp, on: nwPort)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        let ip = Self.localWiFiIPAddress() ?? "你的iPhone局域网IP"
                        self?.isRunning = true
                        self?.serverURLString = "http://\(ip):\(port)"
                        self?.statusText = "等待电脑浏览器连接上传 .gguf 模型…"
                    case .failed(let err):
                        self?.isRunning = false
                        self?.statusText = "启动失败：\(err.localizedDescription)"
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            statusText = "端口监听失败：\(error.localizedDescription)"
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        serverURLString = ""
        statusText = "已停止"
        uploadProgress = 0
    }

    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPHeader(connection: connection, buffer: Data())
    }

    private nonisolated func receiveHTTPHeader(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            var acc = buffer
            if let data { acc.append(data) }

            let delimiter = Data("\r\n\r\n".utf8)
            if let range = acc.range(of: delimiter) {
                let headerData = acc[..<range.lowerBound]
                let bodyStart = Data(acc[range.upperBound...])
                let headerStr = String(data: headerData, encoding: .utf8) ?? ""
                self.dispatchHTTPRequest(connection: connection, header: headerStr, initialBody: bodyStart)
            } else if !isComplete && acc.count < 32768 {
                self.receiveHTTPHeader(connection: connection, buffer: acc)
            } else {
                connection.cancel()
            }
        }
    }

    private nonisolated func dispatchHTTPRequest(connection: NWConnection, header: String, initialBody: Data) {
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        var contentLength: Int64 = 0
        var headerFileName: String?
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                contentLength = Int64(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            } else if lower.hasPrefix("x-file-name:") {
                let raw = line.dropFirst("x-file-name:".count).trimmingCharacters(in: .whitespaces)
                headerFileName = raw.removingPercentEncoding ?? raw
            }
        }

        if method == "GET" {
            let html = Self.uploadPageHTML
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        if method == "POST" && path.hasPrefix("/upload") {
            let rawName = headerFileName ?? "uploaded-\(Int(Date().timeIntervalSince1970)).gguf"
            let safeName = URL(fileURLWithPath: rawName).lastPathComponent
            let destURL = LocalLlamaBackend.modelsDirectoryURL.appendingPathComponent(safeName)
            FileManager.default.createFile(atPath: destURL.path, contents: nil)
            guard let fileHandle = try? FileHandle(forWritingTo: destURL) else {
                sendText(connection: connection, status: "500 Internal Server Error", body: "Cannot create file")
                return
            }
            if !initialBody.isEmpty {
                try? fileHandle.write(contentsOf: initialBody)
            }
            let received = Int64(initialBody.count)
            Task { @MainActor in
                self.statusText = "正在接收：\(safeName)"
                self.uploadProgress = contentLength > 0 ? Double(received) / Double(contentLength) : 0
            }
            streamBodyToFile(
                connection: connection,
                fileHandle: fileHandle,
                destURL: destURL,
                fileName: safeName,
                received: received,
                expected: contentLength
            )
            return
        }

        sendText(connection: connection, status: "404 Not Found", body: "Not Found")
    }

    private nonisolated func streamBodyToFile(
        connection: NWConnection,
        fileHandle: FileHandle,
        destURL: URL,
        fileName: String,
        received: Int64,
        expected: Int64
    ) {
        if expected > 0 && received >= expected {
            try? fileHandle.close()
            let config = ModelDownloadManager.makeModelConfig(fromFileName: fileName, fileSizeBytes: received)
            sendText(connection: connection, status: "200 OK", body: "OK")
            Task { @MainActor in
                self.uploadProgress = 1.0
                self.statusText = "接收完成：\(fileName) (\(MemoryBudgetAdvisor.formatBytes(received)))"
                self.onModelReceived?(config)
            }
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
            guard let self else {
                try? fileHandle.close()
                return
            }
            var total = received
            if let data, !data.isEmpty {
                try? fileHandle.write(contentsOf: data)
                total += Int64(data.count)
                if expected > 0 {
                    let pct = Double(total) / Double(expected)
                    Task { @MainActor in
                        self.uploadProgress = min(1.0, pct)
                    }
                }
            }
            if error != nil || (isComplete && (expected == 0 || total >= expected)) {
                try? fileHandle.close()
                if error == nil && total > 0 {
                    let config = ModelDownloadManager.makeModelConfig(fromFileName: fileName, fileSizeBytes: total)
                    self.sendText(connection: connection, status: "200 OK", body: "OK")
                    Task { @MainActor in
                        self.uploadProgress = 1.0
                        self.statusText = "接收完成：\(fileName)"
                        self.onModelReceived?(config)
                    }
                } else {
                    try? FileManager.default.removeItem(at: destURL)
                    connection.cancel()
                }
                return
            }
            self.streamBodyToFile(
                connection: connection,
                fileHandle: fileHandle,
                destURL: destURL,
                fileName: fileName,
                received: total,
                expected: expected
            )
        }
    }

    private nonisolated func sendText(connection: NWConnection, status: String, body: String) {
        let resp = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(resp.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func localWiFiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }

    private static let uploadPageHTML = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width,initial-scale=1" />
      <title>ChlorMe 局域网模型传输</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #0d1117; color: #e6edf3; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
        .card { background: #161b22; border: 1px solid #30363d; border-radius: 20px; padding: 32px; width: 90%; max-width: 460px; text-align: center; box-shadow: 0 20px 50px rgba(0,0,0,0.4); }
        h1 { font-size: 22px; margin-bottom: 8px; color: #64d2ff; }
        p { color: #8b949e; font-size: 14px; }
        .drop { border: 2px dashed #30363d; border-radius: 16px; padding: 36px 20px; margin: 20px 0; cursor: pointer; transition: 0.2s; }
        .drop:hover { border-color: #64d2ff; background: rgba(100,210,255,0.06); }
        progress { width: 100%; height: 12px; border-radius: 8px; }
        #status { margin-top: 12px; font-size: 14px; color: #7ee787; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>ChlorMe 模型无线传输</h1>
        <p>选择或拖入电脑上的 <code>.gguf</code> 模型文件，直接高速流式写入 iPhone（不占云盘）</p>
        <div class="drop" onclick="document.getElementById('file').click()">
          点击选择 .gguf 文件
          <input id="file" type="file" accept=".gguf" style="display:none" />
        </div>
        <progress id="bar" value="0" max="100" style="display:none"></progress>
        <div id="status"></div>
      </div>
      <script>
        const input = document.getElementById('file');
        const bar = document.getElementById('bar');
        const status = document.getElementById('status');
        input.addEventListener('change', () => {
          const file = input.files[0];
          if (!file) return;
          bar.style.display = 'block';
          bar.value = 0;
          status.textContent = '正在传输 ' + file.name + ' ...';
          const xhr = new XMLHttpRequest();
          xhr.open('POST', '/upload', true);
          xhr.setRequestHeader('X-File-Name', encodeURIComponent(file.name));
          xhr.upload.onprogress = (e) => {
            if (e.lengthComputable) {
              const pct = Math.round((e.loaded / e.total) * 100);
              bar.value = pct;
              status.textContent = '传输中 ' + pct + '% (' + (e.loaded/1048576).toFixed(1) + ' MB)';
            }
          };
          xhr.onload = () => {
            status.textContent = xhr.status === 200 ? '✅ 传输完成！模型已出现在 ChlorMe 模型列表中' : '❌ 失败: ' + xhr.responseText;
          };
          xhr.onerror = () => { status.textContent = '❌ 连接中断，请保持 iPhone 屏幕常亮'; };
          xhr.send(file);
        });
      </script>
    </body>
    </html>
    """
}
