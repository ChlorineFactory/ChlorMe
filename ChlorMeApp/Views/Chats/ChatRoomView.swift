import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import ChlorCore

public struct ChatRoomView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    public let conversationId: String
    public let characterId: String
    @Binding public var isInsideChatRoom: Bool
    public let onOpenDrawer: (() -> Void)?
    public let onOpenModels: (() -> Void)?

    @State private var draftText: String = ""
    @State private var pendingAttachments: [MessageAttachment] = []
    @State private var webSearchEnabled: Bool = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDocumentImporter = false

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

    public init(
        conversationId: String,
        characterId: String,
        isInsideChatRoom: Binding<Bool> = .constant(true),
        onOpenDrawer: (() -> Void)? = nil,
        onOpenModels: (() -> Void)? = nil
    ) {
        self.conversationId = conversationId
        self.characterId = characterId
        _isInsideChatRoom = isInsideChatRoom
        self.onOpenDrawer = onOpenDrawer
        self.onOpenModels = onOpenModels
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
        .toolbar(.hidden, for: .tabBar)
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
                    .onChange(of: store.streamingReasoning) { _, _ in
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                    .onAppear {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }

                liquidComposerBar(conversation: conversation, character: character, accent: accent)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let att = DocumentExtractor.makeImageAttachment(from: data, displayName: "照片-\(pendingAttachments.count + 1).jpg") {
                    pendingAttachments.append(att)
                    ChlorHaptics.light()
                }
                selectedPhotoItem = nil
            }
        }
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: [.pdf, .plainText, .sourceCode, .json, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                do {
                    let att = try DocumentExtractor.importDocument(from: url)
                    pendingAttachments.append(att)
                    ChlorHaptics.light()
                } catch {
                    store.alertError = "读取文档失败：\(error.localizedDescription)"
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
        LiquidGlassCluster(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    ChlorHaptics.light()
                    if let onOpenDrawer {
                        onOpenDrawer()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: onOpenDrawer != nil ? "line.3.horizontal" : "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 40, height: 40)
                        .liquidGlassCapsule(tint: accent, isDark: palette.isDark)
                }

                // Tappable Model & Companion Quick-Switch Capsule (RikkaHub style!)
                Menu {
                    Section("快速切换当前会话模型") {
                        if store.models.isEmpty {
                            Text("暂未配置模型，请前往模型舱添加")
                        } else {
                            ForEach(store.models) { model in
                                Button {
                                    var updated = conversation
                                    updated.modelIdOverride = model.id
                                    Task {
                                        await store.updateConversation(updated)
                                        ChlorHaptics.light()
                                        store.showToast("已切换至：\(model.name)")
                                    }
                                } label: {
                                    Label(
                                        "\(model.name) (\(model.backendKind.shortBadge))",
                                        systemImage: activeModel?.id == model.id ? "checkmark.circle.fill" : (model.backendKind == .localGGUF ? "cpu" : "network")
                                    )
                                }
                            }
                        }
                    }
                    if let onOpenModels {
                        Divider()
                        Button {
                            onOpenModels()
                        } label: {
                            Label("管理本地模型与 API 服务商…", systemImage: "slider.horizontal.below.rectangle")
                        }
                    }
                    Divider()
                    Button {
                        Task { _ = await store.createNewConversation(for: character) }
                    } label: {
                        Label("为 \(character.name) 新开一条对话", systemImage: "square.and.pencil")
                    }
                } label: {
                    HStack(spacing: 9) {
                        CompanionAvatarView(
                            symbol: character.avatarSymbol,
                            imageFileName: character.avatarImageFileName,
                            accentHex: character.accentHex,
                            size: 32
                        )
                        VStack(alignment: .leading, spacing: 1.5) {
                            HStack(spacing: 4) {
                                Text(character.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(palette.primaryText)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(palette.secondaryText)
                            }
                            HStack(spacing: 4) {
                                if store.isSearchingWeb {
                                    Text("正在联网检索…")
                                        .foregroundStyle(accent)
                                } else if store.isGenerating {
                                    Text(store.streamingReasoning.isEmpty ? "正在回复…" : "深度思考中…")
                                        .foregroundStyle(accent)
                                } else if store.isReflectingMemory {
                                    Text("正在珍藏回忆…")
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(activeModel?.name ?? "点击选择模型")
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
                    .liquidGlassCapsule(tint: accent, isDark: palette.isDark, interactive: true)
                }

                Button {
                    ChlorHaptics.light()
                    showMemorySheet = true
                } label: {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 40, height: 40)
                        .liquidGlassCapsule(tint: accent, isDark: palette.isDark)
                }

                Button {
                    ChlorHaptics.light()
                    showInspectorSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 40, height: 40)
                        .liquidGlassCapsule(tint: palette.secondaryAccent, isDark: palette.isDark)
                }
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
        .liquidGlass(cornerRadius: 16, tint: accent, isDark: palette.isDark, interactive: true)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func messageRow(msg: ChatMessage, conversation: Conversation, character: CharacterCard, accent: Color) -> some View {
        let isUser = msg.role == .user
        let hasCodeOrRichMD = msg.content.contains("```") || msg.content.contains("## ") || msg.content.contains("|---")
        let chunks = (isUser || hasCodeOrRichMD) ? [msg.content] : BubbleSplitter.split(msg.content, enabled: character.bubbleSplitEnabled)
        let groupVariants = store.variants(for: msg.groupId, in: conversation.id)
        let currentIndex = groupVariants.firstIndex(where: { $0.id == msg.id }) ?? 0
        let isSpeakingThis = store.voiceService.isSpeaking && store.voiceService.speakingMessageId == msg.id

        return HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                CompanionAvatarView(
                    symbol: character.avatarSymbol,
                    imageFileName: character.avatarImageFileName,
                    accentHex: character.accentHex,
                    size: 34
                )
                .padding(.top, 2)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 7) {
                if !msg.attachments.isEmpty {
                    MessageAttachmentsRow(attachments: msg.attachments, accent: accent, palette: palette)
                }

                if !isUser, let reasoning = msg.reasoningContent, !reasoning.isEmpty {
                    ThinkingDisclosureCard(
                        reasoning: reasoning,
                        isStillThinking: false,
                        accent: accent,
                        palette: palette
                    )
                }

                ForEach(Array(chunks.enumerated()), id: \.offset) { _, segment in
                    MarkdownMessageView(markdown: segment, isUser: isUser, accent: accent, palette: palette)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
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

                if !isUser && !msg.webSources.isEmpty {
                    WebSourcesStrip(sources: msg.webSources, accent: accent, palette: palette)
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
                            } label: { Image(systemName: "chevron.left") }
                            .disabled(currentIndex == 0)

                            Text("\(currentIndex + 1)/\(groupVariants.count)").monospacedDigit()

                            Button {
                                let next = min(groupVariants.count - 1, currentIndex + 1)
                                ChlorHaptics.light()
                                Task { await store.selectVariant(groupId: msg.groupId, messageId: groupVariants[next].id, conversationId: conversation.id) }
                            } label: { Image(systemName: "chevron.right") }
                            .disabled(currentIndex >= groupVariants.count - 1)
                        }

                        Button {
                            ChlorHaptics.light()
                            Task { await store.regenerateSwipe(for: msg, conversation: conversation, character: character) }
                        } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(store.isGenerating)

                        if let tps = msg.tokensPerSecond, tps > 0 {
                            Text(String(format: "%.1f tok/s", tps)).monospacedDigit()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.leading, 6)
                }
            }

            if !isUser { Spacer(minLength: 24) }
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

    private func streamingBubble(character: CharacterCard, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            CompanionAvatarView(
                symbol: character.avatarSymbol,
                imageFileName: character.avatarImageFileName,
                accentHex: character.accentHex,
                size: 34
            )
            VStack(alignment: .leading, spacing: 7) {
                if store.isSearchingWeb {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75).tint(accent)
                        Text("正在检索最新网络信息…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .liquidGlassCapsule(tint: accent, isDark: palette.isDark, interactive: false)
                }

                if !store.streamingReasoning.isEmpty {
                    ThinkingDisclosureCard(
                        reasoning: store.streamingReasoning,
                        isStillThinking: store.streamingText.isEmpty,
                        accent: accent,
                        palette: palette
                    )
                }

                if !store.streamingText.isEmpty || (store.streamingReasoning.isEmpty && !store.isSearchingWeb) {
                    MarkdownMessageView(
                        markdown: store.streamingText.isEmpty ? "正在凝聚思绪…" : store.streamingText,
                        isUser: false,
                        accent: accent,
                        palette: palette
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .liquidGlass(cornerRadius: 20, tint: accent, isDark: palette.isDark, strokeWidth: 1.1)
                }

                if store.currentTokensPerSecond > 0 {
                    Text(String(format: "%.1f tok/s", store.currentTokensPerSecond))
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                        .padding(.leading, 6)
                }
            }
            Spacer(minLength: 24)
        }
    }

    private func liquidComposerBar(conversation: Conversation, character: CharacterCard, accent: Color) -> some View {
        VStack(spacing: 8) {
            if let voiceErr = store.voiceService.voiceError {
                Text(voiceErr)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .liquidGlassCapsule(tint: .orange, isDark: palette.isDark, interactive: false)
            }

            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { att in
                            ZStack(alignment: .topTrailing) {
                                if att.kind == .image, let img = MediaStorage.loadImage(fileName: att.localFileName) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 58, height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                } else {
                                    HStack(spacing: 5) {
                                        Image(systemName: "doc.text.fill").foregroundStyle(accent)
                                        Text(att.displayName)
                                            .font(.caption2.weight(.semibold))
                                            .lineLimit(1)
                                            .frame(maxWidth: 110)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 12)
                                    .liquidGlass(cornerRadius: 12, tint: accent, isDark: palette.isDark)
                                }

                                Button {
                                    pendingAttachments.removeAll { $0.id == att.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white, .black.opacity(0.75))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }
            }

            LiquidGlassCluster(spacing: 8) {
                HStack(alignment: .bottom, spacing: 7) {
                    Menu {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("发送图片（多模态看图）", systemImage: "photo")
                        }
                        Button {
                            showDocumentImporter = true
                        } label: {
                            Label("发送 PDF / TXT / 代码文档", systemImage: "doc.badge.plus")
                        }
                        Divider()
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
                            .foregroundStyle(palette.primaryText)
                            .frame(width: 38, height: 38)
                            .liquidGlassCapsule(tint: accent, isDark: palette.isDark)
                    }

                    // Web Search toggle glass pill
                    Button {
                        ChlorHaptics.light()
                        webSearchEnabled.toggle()
                        store.showToast(webSearchEnabled ? "已开启本轮联网搜索 (\(store.settings.webSearchProvider.displayName))" : "已关闭联网搜索")
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(webSearchEnabled ? accent : palette.secondaryText)
                            .frame(width: 38, height: 38)
                            .liquidGlassCapsule(tint: webSearchEnabled ? accent : palette.secondaryAccent, isDark: palette.isDark)
                    }

                    // Voice dictation mic pill
                    Button {
                        ChlorHaptics.medium()
                        store.voiceService.toggleDictation { recognized in
                            draftText = recognized
                        }
                    } label: {
                        Image(systemName: store.voiceService.isRecording ? "waveform.circle.fill" : "mic.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(store.voiceService.isRecording ? .red : palette.secondaryText)
                            .frame(width: 38, height: 38)
                            .liquidGlassCapsule(tint: store.voiceService.isRecording ? .red : accent, isDark: palette.isDark)
                    }

                    TextField(store.voiceService.isRecording ? "正在聆听…" : "和 \(character.name) 说点什么…", text: $draftText, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .font(.subheadline)
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .liquidGlass(cornerRadius: 20, tint: accent, isDark: palette.isDark, interactive: true)

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
                        }
                    } else {
                        let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
                        Button {
                            ChlorHaptics.light()
                            store.voiceService.stopDictation()
                            let msg = draftText
                            let atts = pendingAttachments
                            let searchOn = webSearchEnabled
                            draftText = ""
                            pendingAttachments = []
                            Task {
                                await store.sendUserMessage(
                                    text: msg,
                                    attachments: atts,
                                    webSearchEnabled: searchOn,
                                    conversation: conversation,
                                    character: character
                                )
                            }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background {
                                    if canSend {
                                        Circle().fill(palette.userBubble)
                                    } else {
                                        Circle().fill(palette.secondaryText.opacity(0.28))
                                    }
                                }
                        }
                        .disabled(!canSend)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }
}
