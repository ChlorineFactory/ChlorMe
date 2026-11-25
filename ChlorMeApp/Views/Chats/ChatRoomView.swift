import SwiftUI
import UIKit
import ChlorCore

public struct ChatRoomView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme

    public let conversationId: String
    public let characterId: String

    @State private var draftText: String = ""
    @State private var showMemorySheet = false
    @State private var showInspectorSheet = false
    @State private var showSummaryExpanded = false
    @State private var editingMessage: ChatMessage?
    @State private var editingText: String = ""
    @State private var editingSummarySheet = false
    @State private var summaryDraft: String = ""
    @FocusState private var isInputFocused: Bool

    private var palette: ChlorPalette {
        ChlorPalette.palette(for: ChlorThemeMode(rawValue: store.settings.themeMode) ?? .darkGlass, scheme: scheme)
    }

    private var conversation: Conversation? {
        store.conversations.first(where: { $0.id == conversationId })
    }

    private var character: CharacterCard? {
        store.characters.first(where: { $0.id == characterId })
    }

    public init(conversationId: String, characterId: String) {
        self.conversationId = conversationId
        self.characterId = characterId
    }

    public var body: some View {
        Group {
            if let conversation, let character {
                chatContent(conversation: conversation, character: character)
            } else {
                Text("会话不存在")
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private func chatContent(conversation: Conversation, character: CharacterCard) -> some View {
        let messages = store.visibleMessages(for: conversation.id)
        let activeModel = store.resolvedModel(for: conversation, character: character)

        return ZStack {
            ChatWallpaperBackground(
                style: character.wallpaperStyle,
                accentHex: character.accentHex,
                palette: palette
            )

            VStack(spacing: 0) {
                if !conversation.rollingSummary.isEmpty {
                    rollingSummaryBanner(conversation: conversation)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(messages) { msg in
                                messageRow(msg: msg, conversation: conversation, character: character)
                                    .id(msg.id)
                            }

                            if store.isGenerating && store.streamingConversationId == conversation.id {
                                streamingBubble(character: character)
                                    .id("streaming-anchor")
                            }

                            Color.clear.frame(height: 12).id("bottom-anchor")
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom-anchor", anchor: .bottom)
                        }
                    }
                    .onChange(of: store.streamingText) { _, _ in
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                    .onAppear {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }

                composerBar(conversation: conversation, character: character)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(character.name)
                        .font(.headline)
                    HStack(spacing: 4) {
                        if store.isGenerating {
                            Text("正在输入…")
                                .foregroundStyle(palette.accent)
                        } else if store.isReflectingMemory {
                            Text("整理回忆中…")
                                .foregroundStyle(.orange)
                        } else {
                            Text(activeModel?.name ?? "未选模型")
                            if !character.moodLabel.isEmpty {
                                Text("· \(character.moodLabel)")
                            }
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showMemorySheet = true
                } label: {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(palette.accent)
                }
                Button {
                    showInspectorSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showMemorySheet) {
            MemoryNotebookSheet(conversation: conversation, character: character)
        }
        .sheet(isPresented: $showInspectorSheet) {
            SessionInspectorSheet(conversation: conversation, character: character)
        }
        .sheet(item: $editingMessage) { msg in
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("直接修改这条消息内容，修正人设或语气偏差")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editingText)
                        .padding(8)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
                }
                .padding()
                .navigationTitle("编辑消息")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editingMessage = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            Task {
                                await store.editMessage(msg, newContent: editingText)
                                editingMessage = nil
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $editingSummarySheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("滚动摘要会常驻发给模型，可随时手动修正关键剧情")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $summaryDraft)
                        .padding(8)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
                }
                .padding()
                .navigationTitle("编辑滚动摘要")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editingSummarySheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            var updated = conversation
                            updated.rollingSummary = summaryDraft
                            Task {
                                await store.updateConversation(updated)
                                editingSummarySheet = false
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func rollingSummaryBanner(conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSummaryExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("更早聊天的滚动摘要", systemImage: "text.book.closed")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: showSummaryExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(palette.secondaryText)
            }
            .buttonStyle(.plain)

            if showSummaryExpanded {
                Text(conversation.rollingSummary)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Button("编辑摘要") {
                    summaryDraft = conversation.rollingSummary
                    editingSummarySheet = true
                }
                .font(.caption2.weight(.semibold))
                .tint(palette.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(palette.surface.opacity(0.85))
        .overlay(Divider(), alignment: .bottom)
    }

    private func messageRow(msg: ChatMessage, conversation: Conversation, character: CharacterCard) -> some View {
        let isUser = msg.role == .user
        let chunks = isUser ? [msg.content] : BubbleSplitter.split(msg.content, enabled: character.bubbleSplitEnabled)
        let groupVariants = store.variants(for: msg.groupId, in: conversation.id)
        let currentIndex = groupVariants.firstIndex(where: { $0.id == msg.id }) ?? 0

        return HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 44) }

            if !isUser {
                ZStack {
                    Circle()
                        .fill(Color(hex: character.accentHex).opacity(0.22))
                        .frame(width: 34, height: 34)
                    Image(systemName: character.avatarSymbol)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: character.accentHex))
                }
                .padding(.top, 2)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { _, segment in
                    formattedBubbleText(segment, isUser: isUser)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            if isUser {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(palette.userBubble)
                            } else {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(palette.assistantBubble)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(palette.border, lineWidth: 1)
                                    )
                            }
                        }
                        .foregroundStyle(isUser ? Color.white : Color.primary)
                        .contextMenu {
                            Button {
                                editingMessage = msg
                                editingText = msg.content
                            } label: {
                                Label("编辑原文", systemImage: "pencil")
                            }
                            Button {
                                UIPasteboard.general.string = msg.content
                                store.showToast("已复制")
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                            if !isUser {
                                Button {
                                    Task { await store.regenerateSwipe(for: msg, conversation: conversation, character: character) }
                                } label: {
                                    Label("重生成一条候选 (Swipe)", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            Button {
                                Task {
                                    await store.addOrUpdateEpisodicMemory(
                                        characterId: character.id,
                                        content: msg.content,
                                        category: .event,
                                        importance: 4,
                                        mood: character.moodLabel,
                                        isPinned: true
                                    )
                                    store.showToast("已置顶记入共同回忆")
                                }
                            } label: {
                                Label("一键记入共同回忆", systemImage: "bookmark.fill")
                            }
                            Button {
                                Task { await store.branchFromMessage(msg) }
                            } label: {
                                Label("从此条截断后续", systemImage: "scissors")
                            }
                            Button(role: .destructive) {
                                Task { await store.deleteMessage(msg) }
                            } label: {
                                Label("删除此消息", systemImage: "trash")
                            }
                        }
                }

                // Swipe controls & TPS footer for assistant turns
                if !isUser {
                    HStack(spacing: 10) {
                        if groupVariants.count > 1 {
                            Button {
                                let prev = max(0, currentIndex - 1)
                                Task { await store.selectVariant(groupId: msg.groupId, messageId: groupVariants[prev].id, conversationId: conversation.id) }
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(currentIndex == 0)

                            Text("\(currentIndex + 1)/\(groupVariants.count)")
                                .monospacedDigit()

                            Button {
                                let next = min(groupVariants.count - 1, currentIndex + 1)
                                Task { await store.selectVariant(groupId: msg.groupId, messageId: groupVariants[next].id, conversationId: conversation.id) }
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(currentIndex >= groupVariants.count - 1)
                        }

                        Button {
                            Task { await store.regenerateSwipe(for: msg, conversation: conversation, character: character) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(store.isGenerating)

                        if let tps = msg.tokensPerSecond, tps > 0 {
                            Text(String(format: "%.1f tok/s", tps))
                                .monospacedDigit()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.leading, 4)
                }
            }

            if !isUser { Spacer(minLength: 32) }
        }
        .gesture(
            DragGesture(minimumDistance: 36, coordinateSpace: .local)
                .onEnded { val in
                    guard !isUser, abs(val.translation.width) > abs(val.translation.height) * 1.4 else { return }
                    if val.translation.width < -45 {
                        if currentIndex < groupVariants.count - 1 {
                            Task { await store.selectVariant(groupId: msg.groupId, messageId: groupVariants[currentIndex + 1].id, conversationId: conversation.id) }
                        } else if !store.isGenerating {
                            Task { await store.regenerateSwipe(for: msg, conversation: conversation, character: character) }
                        }
                    } else if val.translation.width > 45 && currentIndex > 0 {
                        Task { await store.selectVariant(groupId: msg.groupId, messageId: groupVariants[currentIndex - 1].id, conversationId: conversation.id) }
                    }
                }
        )
    }

    private func formattedBubbleText(_ text: String, isUser: Bool) -> some View {
        let isAction = text.hasPrefix("*") && text.hasSuffix("*") && text.count > 2
        return Text(isAction ? String(text.dropFirst().dropLast()) : text)
            .font(isAction ? .subheadline.italic() : .body)
            .opacity(isAction ? 0.82 : 1.0)
            .textSelection(.enabled)
    }

    private func streamingBubble(character: CharacterCard) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(hex: character.accentHex).opacity(0.22))
                    .frame(width: 34, height: 34)
                Image(systemName: character.avatarSymbol)
                    .font(.footnote)
                    .foregroundStyle(Color(hex: character.accentHex))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(store.streamingText.isEmpty ? "正在思考…" : store.streamingText)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(palette.assistantBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.accent.opacity(0.35), lineWidth: 1))
                if store.currentTokensPerSecond > 0 {
                    Text(String(format: "%.1f tok/s", store.currentTokensPerSecond))
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                        .padding(.leading, 4)
                }
            }
            Spacer(minLength: 32)
        }
    }

    private func composerBar(conversation: Conversation, character: CharacterCard) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                Button {
                    draftText += "**"
                } label: {
                    Label("插入动作描写 (*...*)", systemImage: "sparkles")
                }
                Button {
                    Task { await store.generateAssistantReply(conversation: conversation, character: character, swipeGroupId: nil) }
                } label: {
                    Label("让 \(character.name) 继续说", systemImage: "text.append")
                }
                .disabled(store.isGenerating)

                Button {
                    Task { await store.reflectMemories(for: conversation, character: character, silent: false) }
                } label: {
                    Label("立即整理本次回忆", systemImage: "brain")
                }
                .disabled(store.isGenerating || store.isReflectingMemory)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.bottom, 6)
            }

            TextField("和 \(character.name) 说点什么…", text: $draftText, axis: .vertical)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(palette.border, lineWidth: 1))

            if store.isGenerating {
                Button {
                    store.stopGeneration()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.red)
                }
                .padding(.bottom, 2)
            } else {
                Button {
                    let msg = draftText
                    draftText = ""
                    Task { await store.sendUserMessage(text: msg, conversation: conversation, character: character) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? palette.secondaryText.opacity(0.4) : palette.accent)
                }
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
