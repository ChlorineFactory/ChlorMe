import SwiftUI
import UniformTypeIdentifiers
import ChlorCore

public struct ChatListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var showNewCharacter = false
    @State private var showCardImporter = false

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode(rawValue: store.settings.themeMode) ?? .darkGlass, scheme: scheme)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        runtimeStatusCapsule
                        conversationListSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("ChlorMe")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showNewCharacter = true
                        } label: {
                            Label("创建新伴侣", systemImage: "person.badge.plus")
                        }
                        Button {
                            showCardImporter = true
                        } label: {
                            Label("导入角色卡 (V2 JSON / PNG)", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .sheet(isPresented: $showNewCharacter) {
                NavigationStack {
                    CharacterEditorView(character: nil)
                }
            }
            .fileImporter(
                isPresented: $showCardImporter,
                allowedContentTypes: [.json, .png],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await store.importCharacterCard(from: url) }
                }
            }
        }
    }

    private var runtimeStatusCapsule: some View {
        let loadedModel = store.models.first(where: { $0.id == store.loadedModelId })
        let availText = MemoryBudgetAdvisor.formatBytes(store.availableMemoryBytes)

        return HStack(spacing: 12) {
            Circle()
                .fill(loadedModel != nil ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
                .shadow(color: (loadedModel != nil ? Color.green : Color.orange).opacity(0.6), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                if store.isLoadingModel {
                    Text("正在加载本地权重…")
                        .font(.subheadline.weight(.semibold))
                } else if let m = loadedModel {
                    Text("已加载：\(m.name)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                } else if let remote = store.models.first(where: { $0.backendKind == .openAICompatible }) {
                    Text("远程就绪：\(remote.name)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text("尚未加载本地模型")
                        .font(.subheadline.weight(.semibold))
                }
                Text("可用内存 \(availText)\(store.currentTokensPerSecond > 0 ? String(format: " · %.1f tok/s", store.currentTokensPerSecond) : "")")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            if loadedModel != nil {
                Button("卸载") {
                    Task { await store.unloadLocalModel() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private var conversationListSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(store.conversations) { conv in
                if let character = store.characters.first(where: { $0.id == conv.characterId }) {
                    NavigationLink {
                        ChatRoomView(conversationId: conv.id, characterId: character.id)
                    } label: {
                        conversationRow(conv: conv, character: character)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func conversationRow(conv: Conversation, character: CharacterCard) -> some View {
        let lastMsg = store.visibleMessages(for: conv.id).last
        let memCount = (store.episodicMemoriesByCharacter[character.id] ?? []).count

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: character.accentHex).opacity(0.22))
                    .frame(width: 54, height: 54)
                Image(systemName: character.avatarSymbol)
                    .font(.title2)
                    .foregroundStyle(Color(hex: character.accentHex))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(character.name)
                        .font(.headline)
                    if !character.moodLabel.isEmpty {
                        Text(character.moodLabel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(hex: character.accentHex).opacity(0.16), in: Capsule())
                            .foregroundStyle(Color(hex: character.accentHex))
                    }
                    Spacer()
                    Text(relativeTime(conv.lastMessageAt))
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }

                Text(lastMsg?.content.replacingOccurrences(of: "\n", with: " ") ?? character.tagline)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Label(character.relationshipLabel, systemImage: "heart.fill")
                    Label("\(memCount) 条回忆", systemImage: "sparkles")
                }
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.opacity(0.85))
            }
        }
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
