import SwiftUI
import UIKit
import ChlorCore

public struct ChatRoomView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    public let conversationId: String
    public let characterId: String
    @Binding public var isInsideChatRoom: Bool

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
        ChlorPalette.palette(for: ChlorThemeMode.resolved(from: store.settings.themeMode), scheme: scheme)
    }

    private var conversation: Conversation? {
        store.conversations.first(where: { $0.id == conversationId })
    }

    private var character: CharacterCard? {
        store.characters.first(where: { $0.id == characterId })
    }

    public init(conversationId: String, characterId: String, isInsideChatRoom: Binding<Bool> = .constant(true)) {
        self.conversationId = conversationId
        self.characterId = characterId
        _isInsideChatRoom = isInsideChatRoom
    }

    public var body: some View {
        Group {
            if let conversation, let character {
                chatContent(conversation: conversation, character: character)
            } else {
                ZStack {
                    CosmicNebulaBackdrop(palette: palette)
                    Text("会话已不存在")
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            isInsideChatRoom = true
        }
        .onDisappear {
            isInsideChatRoom = false
            store.voiceService.stopDictation()
            store.voiceService.stopSpeaking()
        }
    }

    private func chatContent(conversation: Conversation, character: CharacterCard) -> some View {
        let messages = store.visibleMessages(for: conversation.id)
        let activeModel = store.resolvedModel(for: conversation, character: character)
        let accent = Color(hex: character.accentHex)

        return ZStack {
            ChatWallpaperBackground(
                style: character.wallpaperStyle,
                customImageFileName: character.wallpaperImageFileName,
                accentHex: character.accentHex,
                palette: palette
            )

            VStack(spacing: 0) {
                liquidTopBar(conversation: conversation, character: character, activeModel: activeModel, accent: accent)

                if !conversation.rollingSummary.isEmpty {
                    rollingSummaryBanner(conversation: conversation, accent: accent)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(messages) { msg in
                                messageRow(msg: msg, conversation: conversation, character: character, accent: accent)
                                    .id(msg.id)
                            }

                            if store.isGenerating && store.streamingConversationId == conversation.id {
                                streamingBubble(character: character, accent: accent)
                                    .id("streaming-anchor")
                            }

                            Color.clear.frame(height: 16).id("bottom-anchor")
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                    }
                    .scrollDismissesKeyboard(.interactively)
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

                liquidComposerBar(conversation: conversation, character: character, accent: accent)
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
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border))
                }
                .padding()
                .navigationTitle("编辑消息")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { editingMessage = nil } }
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
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border))
                }
                .padding()
                .navigationTitle("编辑滚动摘要")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { editingSummarySheet = false } }
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

    private func liquidTopBar(
        conversation: Conversation,
        character: CharacterCard,
        activeModel: ModelConfig?,
        accent: Color
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                ChlorHaptics.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 38, height: 38)
                    .liquidGlassCapsule(tint: accent, isDark: palette.isDark)
            }

            HStack(spacing: 10) {
                CompanionAvatarView(
                    symbol: character.avatarSymbol,
                    imageFileName: character.avatarImageFileName,
                    accentHex: character.accentHex,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(character.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.primaryText)
                    HStack(spacing: 4) {
                        if store.isGenerating {
                            Text("星光输入中…")
                                .foregroundStyle(accent)
                        } else if store.isReflectingMemory {
                            Text("正在珍藏回忆…")
                                .foregroundStyle(.orange)
                        } else if store.voiceService.isSpeaking {
                            Text("语音朗读中…")
                                .foregroundStyle(accent)
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
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassCapsule(tint: accent, isDark: palette.isDark)

            Button {
                ChlorHaptics.light()
                showMemorySheet = true
            } label: {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .liquidGlassCapsule(tint: accent, isDark: palette.isDark)
            }

            Button {
                ChlorHaptics.light()
                showInspectorSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 38, height: 38)
                    .liquidGlassCapsule(tint: palette.secondaryAccent, isDark: palette.isDark)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func rollingSummaryBanner(conversation: Conversation, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showSummaryExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("早期聊天记忆摘要", systemImage: "text.book.closed")
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
                    .foregroundStyle(palette.primaryText)
                Button("编辑摘要") {
                    summaryDraft = conversation.rollingSummary
                    editingSummarySheet = true
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: 16, tint: accent, isDark: palette.isDark)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func messageRow(msg: ChatMessage, conversation: Conversation, character: CharacterCard, accent: Color) -> some View {
        let isUser = msg.role == .user
        let chunks = isUser ? [msg.content] : BubbleSplitter.split(msg.content, enabled: character.bubbleSplitEnabled)
        let groupVariants = store.variants(for: msg.groupId, in: conversation.id)
        let currentIndex = groupVariants.firstIndex(where: { $0.id == msg.id }) ?? 0
        let isSpeakingThis = store.voiceService.isSpeaking && store.voiceService.speakingMessageId == msg.id

        return HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 44) }

            if !isUser {
                CompanionAvatarView(
                    symbol: character.avatarSymbol,
                    imageFileName: character.avatarImageFileName,
                    accentHex: character.accentHex,
                    size: 34
                )
                .padding(.top, 2)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { _, segment in
                    formattedBubbleText(segment)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(isUser ? Color.white : palette.primaryText)
                        .background {
                            if isUser {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(palette.userBubble)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .strokeBorder(.white.opacity(0.32), lineWidth: 0.9)
                                    )
                                    .shadow(color: palette.accent.opacity(0.28), radius: 12, y: 6)
                            } else {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(.clear)
                                    .liquidGlass(cornerRadius: 20, tint: accent, isDark: palette.isDark, strokeWidth: 0.95)
                            }
                        }
                        .contextMenu {
                            if !isUser {
                                Button {
                                    store.voiceService.speak(
                                        text: msg.content,
                                        messageId: msg.id,
                                        voiceIdentifier: character.voiceIdentifier,
                                        rate: character.voiceRate,
                                        pitch: character.voicePitch
                                    )
                                } label: {
                                    Label(isSpeakingThis ? "停止朗读" : "语音朗读此条", systemImage: isSpeakingThis ? "speaker.slash" : "speaker.wave.2")
                                }
                            }
                            Button {
                                editingMessage = msg
                                editingText = msg.content
                            } label: {
                                Label("编辑原文", systemImage: "pencil")
                            }
                            Button {
                                UIPasteboard.general.string = msg.content
                                store.showToast("已复制到剪贴板")
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
                                    ChlorHaptics.success()
                                    store.showToast("已置顶珍藏到共同回忆")
                                }
                            } label: {
                                Label("一键珍藏进共同回忆", systemImage: "bookmark.fill")
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

                if !isUser {
                    HStack(spacing: 11) {
                        Button {
                            ChlorHaptics.light()
                            store.voiceService.speak(
                                text: msg.content,
                                messageId: msg.id,
                                voiceIdentifier: character.voiceIdentifier,
                                rate: character.voiceRate,
                                pitch: character.voicePitch
                            )
                        } label: {
                            Image(systemName: isSpeakingThis ? "waveform.circle.fill" : "speaker.wave.2")
                                .foregroundStyle(isSpeakingThis ? accent : palette.secondaryText)
                        }

                        if groupVariants.count > 1 {
                            Button {
                                let prev = max(0, currentIndex - 1)
                                ChlorHaptics.light()
                                Task { await store.selectVariant(groupId: msg.groupId, messageId: groupVariants[prev].id, conversationId: conversation.id) }
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(currentIndex == 0)

                            Text("\(currentIndex + 1)/\(groupVariants.count)")
                                .monospacedDigit()

                            Button {
                                let next = min(groupVariants.count - 1, currentIndex + 1)
                                ChlorHaptics.light()
                                Task { await store.selectVariant(groupId: msg.groupId, messageId: groupVariants[next].id, conversationId: conversation.id) }
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(currentIndex >= groupVariants.count - 1)
                        }

                        Button {
                            ChlorHaptics.light()
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
                    .padding(.leading, 6)
                }
            }

            if !isUser { Spacer(minLength: 28) }
        }
        .gesture(
            DragGesture(minimumDistance: 36, coordinateSpace: .local)
                .onEnded { val in
                    guard !isUser, abs(val.translation.width) > abs(val.translation.height) * 1.4 else { return }
                    if val.translation.width < -45 {
                        ChlorHaptics.light()
                        if currentIndex < groupVariants.count - 1 {
                            Task { await store.selectVariant(groupId: msg.groupId, messageId: groupVariants[currentIndex + 1].id, conversationId: conversation.id) }
                        } else if !store.isGenerating {
                            Task { await store.regenerateSwipe(for: msg, conversation: conversation, character: character) }
                        }
                    } else if val.translation.width > 45 && currentIndex > 0 {
                        ChlorHaptics.light()
                        Task { await store.selectVariant(groupId: msg.groupId, messageId: groupVariants[currentIndex - 1].id, conversationId: conversation.id) }
                    }
                }
        )
    }

    private func formattedBubbleText(_ text: String) -> some View {
        let isAction = text.hasPrefix("*") && text.hasSuffix("*") && text.count > 2
        return Text(isAction ? String(text.dropFirst().dropLast()) : text)
            .font(isAction ? .subheadline.italic() : .body)
            .opacity(isAction ? 0.84 : 1.0)
            .textSelection(.enabled)
    }

    private func streamingBubble(character: CharacterCard, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            CompanionAvatarView(
                symbol: character.avatarSymbol,
                imageFileName: character.avatarImageFileName,
                accentHex: character.accentHex,
                size: 34
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(store.streamingText.isEmpty ? "正在凝聚思绪…" : store.streamingText)
                    .font(.body)
                    .foregroundStyle(palette.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .liquidGlass(cornerRadius: 20, tint: accent, isDark: palette.isDark, strokeWidth: 1.2)
                if store.currentTokensPerSecond > 0 {
                    Text(String(format: "%.1f tok/s", store.currentTokensPerSecond))
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                        .padding(.leading, 6)
                }
            }
            Spacer(minLength: 28)
        }
    }

    private func liquidComposerBar(conversation: Conversation, character: CharacterCard, accent: Color) -> some View {
        VStack(spacing: 6) {
            if let voiceErr = store.voiceService.voiceError {
                Text(voiceErr)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .liquidGlassCapsule(tint: .orange, isDark: palette.isDark)
            }

            HStack(alignment: .bottom, spacing: 8) {
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
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 36, height: 36)
                        .liquidGlassCapsule(tint: accent, isDark: palette.isDark)
                }

                // Voice dictation mic button
                Button {
                    ChlorHaptics.medium()
                    store.voiceService.toggleDictation { recognized in
                        draftText = recognized
                    }
                } label: {
                    Image(systemName: store.voiceService.isRecording ? "waveform.circle.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(store.voiceService.isRecording ? .red : accent)
                        .frame(width: 36, height: 36)
                        .liquidGlassCapsule(tint: store.voiceService.isRecording ? .red : accent, isDark: palette.isDark)
                }

                TextField(store.voiceService.isRecording ? "正在聆听你的声音…" : "和 \(character.name) 说点什么…", text: $draftText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .font(.subheadline)
                    .foregroundStyle(palette.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .liquidGlass(cornerRadius: 20, tint: accent, isDark: palette.isDark)

                if store.isGenerating {
                    Button {
                        ChlorHaptics.medium()
                        store.stopGeneration()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.red.gradient, in: Circle())
                            .shadow(color: .red.opacity(0.45), radius: 8)
                    }
                } else {
                    let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button {
                        ChlorHaptics.light()
                        store.voiceService.stopDictation()
                        let msg = draftText
                        draftText = ""
                        Task { await store.sendUserMessage(text: msg, conversation: conversation, character: character) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background {
                                if canSend {
                                    Circle().fill(palette.userBubble)
                                } else {
                                    Circle().fill(palette.secondaryText.opacity(0.25))
                                }
                            }
                            .shadow(color: canSend ? accent.opacity(0.45) : .clear, radius: 10, y: 4)
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }
}
