import SwiftUI

public struct WiFiTransferSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "wifi.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.cyan)

                VStack(spacing: 8) {
                    Text("局域网无线传 GGUF 模型")
                        .font(.title3.bold())
                    Text("确保电脑与 iPhone 连接同一 Wi-Fi，在电脑浏览器中打开下方地址，即可直接把 4GB+ 的 GGUF 拖进手机。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if store.wifiServer.isRunning {
                    VStack(spacing: 10) {
                        Text(store.wifiServer.serverURLString)
                            .font(.title3.monospaced().bold())
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                            .textSelection(.enabled)

                        Text(store.wifiServer.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if store.wifiServer.uploadProgress > 0 && store.wifiServer.uploadProgress < 1 {
                            ProgressView(value: store.wifiServer.uploadProgress)
                                .padding(.horizontal, 32)
                        }
                    }
                } else {
                    Text(store.wifiServer.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(store.wifiServer.isRunning ? "停止接收服务" : "启动无线接收") {
                    if store.wifiServer.isRunning {
                        store.wifiServer.stop()
                    } else {
                        store.wifiServer.start()
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("Wi-Fi 传模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        store.wifiServer.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if !store.wifiServer.isRunning {
                    store.wifiServer.start()
                }
            }
            .onDisappear {
                store.wifiServer.stop()
            }
        }
    }
}
