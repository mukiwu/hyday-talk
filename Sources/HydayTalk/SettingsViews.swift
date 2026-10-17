import SwiftUI
import AppKit
import Speech
import TalkCore

/// Settings pages read best at a limited width: rows keep labels on the left and controls on the right.
private let settingsWidth: CGFloat = 760

struct SettingsGroup<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typography.font(.body, weight: .medium)).singleLineHeading()
                if let detail {
                    Text(detail).font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineSpacing(Typography.paragraphSpacing)
                }
            }.padding(.horizontal, 4)
            VStack(spacing: 0) {
                _VariadicView.Tree(DividedLayout()) { content }
            }.padding(.horizontal, 18).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius).strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
        }.frame(maxWidth: settingsWidth, alignment: .leading)
    }
}

/// Puts a hairline between rows so a group reads as one list.
private struct DividedLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        ForEach(children) { child in
            child
            if child.id != children.last?.id { Hairline() }
        }
    }
}

/// A one-pixel line at the screen's own scale, rather than a one-point divider.
struct Hairline: View {
    @Environment(\.displayScale) private var scale
    var body: some View { Rectangle().fill(Palette.border).frame(height: 1 / scale) }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var badge: String? = nil
    @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(Typography.font(.body))
                    if let badge {
                        Text(badge).font(Typography.font(.caption, weight: .medium)).foregroundStyle(Palette.accentInk)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Palette.accentSurface, in: Capsule())
                    }
                }
                if let detail {
                    Text(detail).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                        .lineSpacing(Typography.paragraphSpacing).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            control
        }.padding(.vertical, 14).frame(minHeight: 52)
    }
}

/// Free-form content inside a group, such as a note, an example or a list.
struct SettingsBlock<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineSpacing(Typography.paragraphSpacing)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SpeechSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("辨識來源").font(Typography.font(.body, weight: .medium)).padding(.horizontal, 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(SpeechBackend.availableSources) { backend in
                        let selected = model.settings.speechBackend == backend
                        Button { model.settings.speechBackend = backend } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: backend.symbol).font(IconToken.font(.small)).foregroundStyle(selected ? Palette.action : Palette.muted)
                                        .frame(width: 30, height: 30).background(selected ? Palette.actionSurface : Palette.subtleSurface, in: Circle())
                                    Spacer(minLength: 0)
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Palette.action : Palette.faint)
                                }
                                Text(backend.title).font(Typography.font(.body, weight: .medium)).singleLineHeading()
                                Text(backend.detail).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                        }.buttonStyle(AlignChoiceStyle(selected: selected)).accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
            }.frame(maxWidth: settingsWidth)
            switch model.settings.speechBackend {
            case .system:
                SettingsGroup(title: "macOS 系統辨識", detail: "不需 API Key。部分語言可能由 Apple 伺服器處理音訊，單次錄音最多 55 秒。") {
                    let offline = SFSpeechRecognizer(locale: Locale(identifier: model.settings.locale))?.supportsOnDeviceRecognition == true
                    SettingsRow(title: "僅使用離線辨識",
                                detail: offline ? "目前語言支援系統離線辨識" : "目前語言的離線支援需由系統確認；不支援時會提示切換來源") {
                        Toggle("僅使用離線辨識", isOn: $model.settings.systemOfflineOnly).labelsHidden()
                    }
                    if !model.speechAllowed {
                        SettingsRow(title: "語音辨識權限") {
                            Button("設定語音辨識權限") { model.openPermissionGuide(at: .speech) }.buttonStyle(AlignButtonStyle())
                        }
                    }
                }
            case .whisper, .cli:
                LocalModelSettingsView(model: model, manager: model.localModels)
            case .api:
                SettingsGroup(title: "語音辨識 API", detail: "錄音會傳送至你設定的服務。支援 /audio/transcriptions；本機相容服務可不填 Key。") {
                    SettingsBlock { APISettingsFields(settings: $model.settings.speechAPI, account: "speech", purpose: .speech, model: model) }
                }
            }
            SettingsGroup(title: "語音辨識語言") {
                SettingsRow(title: "辨識語言", detail: "繁體中文會套用字形轉換、全形標點與個人辭典，中英混說的準確度取決於辨識來源。") {
                    AlignMenuPicker(title: "辨識語言", values: ["zh-TW", "en-US", "ja-JP", "zh-CN"], selection: $model.settings.locale,
                                    label: { ["zh-TW": "繁體中文 · 台灣", "en-US": "English · United States", "ja-JP": "日本語", "zh-CN": "简体中文"][$0] ?? $0 },
                                    showsTitle: false).frame(width: 220)
                }
            }
        }.disabled(model.phase.busy)
    }
}

struct TextSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "文字整理來源") {
                SettingsRow(title: "整理方式", detail: model.settings.textBackend == .basic
                            ? "保留辨識原文、轉換字形與既有標點並套用辭典，如需補上標點或整理列表，請選擇本機 AI 或 API Key。" : nil) {
                    AlignSegmentedPicker(title: "文字整理來源", values: TextBackend.availableSources,
                                         selection: $model.settings.textBackend, label: { $0.title }).frame(width: 380)
                }
            }
            switch model.settings.textBackend {
            case .basic: EmptyView()
            case .local, .cli:
                LocalTextSettingsView(model: model, installer: model.textModelInstaller)
            case .claude:
                ClaudeTextSettingsView(model: model)
            case .api:
                SettingsGroup(title: "文字 AI API", detail: "逐字稿、個人辭典與提問時選取的文字會送至這個服務。支援 /chat/completions，也可連接本機模型服務。") {
                    SettingsBlock { APISettingsFields(settings: $model.settings.textAPI, account: "text", purpose: .text, model: model) }
                }
            }
            SettingsGroup(title: "聽寫風格", detail: "設定會自動儲存，於下一次聽寫套用。") {
                SettingsRow(title: "風格", detail: model.settings.textBackend == .basic
                            ? "目前使用基礎整理，如需套用自然或正式風格，請選擇本機 AI 或 API Key。"
                            : model.settings.writingStyle.detail) {
                    AlignSegmentedPicker(title: "聽寫風格", values: WritingStyle.allCases,
                                         selection: $model.settings.writingStyle, label: { $0.title }).frame(width: 260)
                        .disabled(model.settings.textBackend == .basic)
                }
                if model.settings.textBackend != .basic {
                    SettingsBlock { ExamplePair(input: WritingStyle.exampleInput, output: model.settings.writingStyle.exampleOutput) }
                }
            }
            if model.settings.textBackend != .basic {
                SettingsGroup(title: "畫面上下文", detail: "開始錄音時讀取游標所在的 App、視窗標題與前後的文字，讓文字 AI 參考人名、術語與語氣，不會插入或保存這些文字。密碼欄位與保留原話不會讀取。") {
                    SettingsRow(title: "參考畫面上下文", detail: model.settings.textBackend == .api || model.settings.textBackend == .claude
                                ? "開啟後，畫面上的文字會與逐字稿一起送至文字 AI 的服務商。"
                                : "文字只交給這台 Mac 上的文字 AI，不會離開電腦。") {
                        Toggle("參考畫面上下文", isOn: $model.settings.readsScreenContext).labelsHidden()
                    }
                    if model.settings.readsScreenContext {
                        SettingsRow(title: "不讀取上下文的 App", detail: "以頓號或逗號分隔 App 名稱。") {
                            TextField("App 名稱", text: Binding(
                                get: { model.settings.screenContextExcludedApps.joined(separator: "、") },
                                set: { model.settings.screenContextExcludedApps = $0
                                    .components(separatedBy: CharacterSet(charactersIn: "、,，"))
                                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                                .textFieldStyle(.roundedBorder).frame(width: 260)
                        }
                    }
                }
            }
            SettingsGroup(title: "翻譯目標語言", detail: "翻譯需要本機 AI 或 API Key，右 Shift 不會啟動翻譯。") {
                SettingsRow(title: "目標語言", detail: "按住左 Shift 並按 fn 開始翻譯，說完後再按 fn 完成。") {
                    AlignMenuPicker(title: "目標語言", values: ["英文", "台灣繁體中文", "日文", "韓文", "西班牙文"],
                                    selection: $model.settings.targetLanguage, label: { $0 }, showsTitle: false).frame(width: 200)
                }
            }
        }.disabled(model.phase.busy)
    }
}

struct DictionaryView: View {
    @ObservedObject var model: AppModel
    @State private var term = ""
    @State private var misheard = ""
    @State private var filter: Bool? = nil
    @State private var search = ""
    @State private var hovered: UUID?
    @State private var adding = false
    private var entries: [DictionaryEntry] {
        RecognitionHints.ordered(model.settings.dictionary).filter { entry in
            (filter == nil || entry.isAutomatic == filter)
                && (search.isEmpty || entry.term.localizedCaseInsensitiveContains(search) || (entry.misheard ?? "").localizedCaseInsensitiveContains(search))
        }
    }
    private func add() { add(term, misheard: misheard) }
    private func add(_ text: String, misheard heard: String = "") {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrong = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        // A manual entry replaces any term with the same spelling apart from case.
        model.settings.dictionary.removeAll { $0.term.lowercased() == word.lowercased() }
        model.settings.dictionary.append(DictionaryEntry(term: word, misheard: wrong.isEmpty ? nil : wrong))
        term = ""; misheard = ""; adding = false
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "個人辭典", detail: "自動新增的詞彙來自你對插入文字的修正，可於一般設定關閉此功能。") {
                if model.settings.learnsFromCorrections {
                    SettingsRow(title: "最近一次比對結果",
                                detail: model.lastCorrectionCheck.map { "\($0.app) · \($0.date.formatted(date: .omitted, time: .shortened))" }
                                    ?? "聽寫插入文字後，修改再離開輸入框，這裡會顯示比對結果。") {
                        Text(model.lastCorrectionCheck?.message ?? "尚未比對")
                            .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.trailing).frame(maxWidth: 260, alignment: .trailing)
                    }
                }
                SettingsBlock {
                    HStack(spacing: 12) {
                        AlignSegmentedPicker(title: "詞彙來源", values: [nil, true, false] as [Bool?], selection: $filter) {
                            switch $0 { case nil: return "所有"; case true?: return "自動新增"; case false?: return "手動新增" }
                        }.fixedSize()
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").font(IconToken.font(.small)).foregroundStyle(Palette.muted)
                            TextField("搜尋辭典", text: $search, prompt: Text("搜尋辭典").foregroundStyle(Palette.muted))
                                .textFieldStyle(.plain).accessibilityLabel("搜尋辭典")
                            if !search.isEmpty {
                                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.faint) }
                                    .buttonStyle(.plain).help("清除搜尋").accessibilityLabel("清除搜尋")
                            }
                        }
                        .padding(.horizontal, 10).frame(height: 36)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.border, lineWidth: 1))
                        Button { term = search.trimmingCharacters(in: .whitespacesAndNewlines); adding = true } label: {
                            Label("新增詞彙", systemImage: "plus")
                        }
                        .buttonStyle(AlignButtonStyle(kind: .primary)).fixedSize()
                        .popover(isPresented: $adding, arrowEdge: .bottom) { addPanel }
                    }
                    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
                    if entries.isEmpty, !query.isEmpty {
                        HStack(spacing: 12) {
                            Label("辭典裡沒有「\(query)」。", systemImage: "magnifyingglass")
                                .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                            Button("加入「\(query)」") { add(query); search = ""; filter = nil }
                                .buttonStyle(AlignButtonStyle(kind: .primary))
                        }.padding(.vertical, 6)
                    } else if entries.isEmpty {
                        Label(model.settings.dictionary.isEmpty ? "尚無詞彙，可按右上方的新增詞彙，加入經常說到的人名、產品或術語。" : "這個分類沒有詞彙。",
                              systemImage: "character.book.closed")
                            .font(Typography.font(.caption)).foregroundStyle(Palette.muted).padding(.vertical, 6)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(entries) { entry in chip(entry) }
                        }
                    }
                }
            }
        }.disabled(model.phase.busy)
    }

    private var addPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.settings.dictionary.contains { $0.term.lowercased() == term.trimmingCharacters(in: .whitespaces).lowercased() && !term.isEmpty } ? "編輯詞彙" : "新增詞彙")
                    .font(Typography.font(.body).weight(.medium))
                Text("加入的詞彙可協助語音辨識與文字 AI 寫出正確的內容。")
                    .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            }
            LabeledField("詞彙", placeholder: "例如：Hyday", text: $term).onSubmit(add)
            LabeledField("常聽錯成（選填）", placeholder: "例如：海得、hide day", text: $misheard).onSubmit(add)
            Text("可填多個寫法，以頓號或逗號分隔。辨識結果中的這些文字會換成詞彙。")
                .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            HStack {
                Spacer()
                Button("取消") { term = ""; misheard = ""; adding = false }
                    .buttonStyle(AlignButtonStyle()).keyboardShortcut(.cancelAction)
                Button("儲存", action: add).buttonStyle(AlignButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
                    .disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20).frame(width: 340)
    }

    private func chip(_ entry: DictionaryEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isAutomatic ? "sparkle" : "pencil")
                .font(IconToken.font(.small)).foregroundStyle(entry.isAutomatic ? Palette.accent : Palette.faint)
                .help(entry.isAutomatic ? "自動新增" : "手動新增")
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.term).font(Typography.font(.body)).lineLimit(1)
                if let wrong = entry.misheard {
                    Text("常聽錯成 \(wrong)").font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button { DictionaryLearning.remove(entry, from: &model.settings) } label: { Image(systemName: "xmark").frame(width: 14, height: 14) }
                .buttonStyle(AlignButtonStyle(kind: .ghost)).help("刪除詞彙 \(entry.term)").accessibilityLabel("刪除詞彙 \(entry.term)")
                // Faint until hovered, but never invisible, so keyboard users can see what they focus.
                .opacity(hovered == entry.id ? 1 : 0.35)
        }
        .padding(.leading, 12).padding(.trailing, 4).frame(minHeight: 38)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.border, lineWidth: 1))
        .onHover { inside in hovered = inside ? entry.id : (hovered == entry.id ? nil : hovered) }
        .contentShape(Rectangle())
        .onTapGesture { term = entry.term; misheard = entry.misheard ?? ""; adding = true }
        .help("點一下編輯詞彙")
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PermissionsView(model: model).frame(maxWidth: settingsWidth)
            SettingsGroup(title: "快捷鍵", detail: "按一次 fn 開始，再按 fn 完成。如 fn 同時開啟表情符號或系統聽寫，請在系統設定 → 鍵盤，將「按下 🌐 鍵來」設為「不執行動作」。") {
                ForEach(VoiceAction.allCases) { action in
                    SettingsRow(title: action.title) { Keycap(action.shortcut) }
                }
                SettingsRow(title: "取消錄音 / 處理") { Keycap("esc") }
                SettingsRow(title: "鍵盤設定") {
                    Button("開啟鍵盤設定") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(AlignButtonStyle())
                }
            }
            SettingsGroup(title: "輸入與紀錄", detail: "錄音依下方的保留期限存在這台 Mac，取消的錄音會立即刪除，API Key 儲存在 macOS 鑰匙圈。") {
                SettingsRow(title: "聽寫與翻譯完成後，自動插入原本的文字框",
                            detail: model.settings.autoInsert ? "未偵測到輸入框或輸入位置已變更時，自動複製文字。" : nil) {
                    Toggle("聽寫與翻譯完成後，自動插入原本的文字框", isOn: $model.settings.autoInsert).labelsHidden()
                }
                SettingsRow(title: "從修改內容自動學習詞彙",
                            detail: "插入文字後，Hyday Talk 會讀取該輸入框的內容並與插入文字比對，僅將修正過的詞彙加入個人辭典，不保存其他內容。") {
                    Toggle("從修改內容自動學習詞彙", isOn: $model.settings.learnsFromCorrections).labelsHidden()
                }
                SettingsRow(title: "在這台 Mac 保留文字紀錄") {
                    Toggle("在這台 Mac 保留文字紀錄", isOn: $model.settings.saveHistory).labelsHidden()
                }
                RecordingRetentionRow(model: model)
                SettingsRow(title: "播放開始與完成提示音") {
                    Toggle("播放開始與完成提示音", isOn: $model.settings.interactionSounds).labelsHidden()
                }
                SettingsRow(title: "我的打字速度", detail: "用於估算洞察頁的節省時間，台灣常見的注音打字速度約為每分鐘 20 至 50 字。") {
                    Stepper(value: $model.settings.typingWordsPerMinute, in: 10...200, step: 5) {
                        Text("每分鐘 \(model.settings.typingWordsPerMinute) 字").monospacedDigit()
                    }.fixedSize()
                }
            }.disabled(model.phase.busy)
            SettingsGroup(title: "Hyday Talk 0.1.0") {
                SettingsBlock { Note("支援 macOS 14 以上及系統預設麥克風，提供聽寫、翻譯與文字提問功能，提問不包含網路搜尋或外部操作。") }
            }
        }
    }
}

struct APISettingsFields: View {
    @Binding var settings: APISettings
    let account: String
    let purpose: APIProvider.Purpose
    @ObservedObject var model: AppModel
    @State private var key = ""
    @State private var saved = false
    private var provider: Binding<APIProvider> {
        // A known address this purpose does not offer, such as Groq for text, shows as custom.
        Binding(get: { [settings, purpose] in
                    let match = APIProvider.matching(baseURL: settings.baseURL)
                    return APIProvider.choices(for: purpose).contains(match) ? match : .custom },
                set: { $0.apply(to: &settings, for: purpose) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                AlignMenuPicker(title: "服務", values: APIProvider.choices(for: purpose), selection: provider,
                                label: { $0.title }).frame(width: 220)
                if let page = provider.wrappedValue.keyPage {
                    Link("取得 \(provider.wrappedValue.title) API Key", destination: page)
                        .font(Typography.font(.caption)).pointingCursor()
                }
            }
            LabeledField("服務基底網址", placeholder: "https://api.openai.com/v1", text: $settings.baseURL, monospaced: true)
            LabeledField("模型名稱", placeholder: "服務提供的模型名稱", text: $settings.model, monospaced: true)
            VStack(alignment: .leading, spacing: 7) {
                Text("API Key").font(Typography.font(.caption, weight: .medium))
                HStack {
                    SecureField("API Key", text: $key, prompt: Text("sk-…（本機服務可留白）").foregroundStyle(Palette.muted))
                        .textFieldStyle(AlignTextFieldStyle()).accessibilityLabel("API Key")
                        .onChange(of: key) { _, _ in saved = false }
                    Button("儲存 Key") {
                        do {
                            let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !value.contains("\n"), !value.contains("\r") else { throw TalkError("API Key 不可包含換行，請重新貼上。") }
                            try KeyStore.write(value, account: account); saved = true
                            model.notice = value.isEmpty ? "已清除 API Key。" : "API Key 已存入 macOS 鑰匙圈。"
                        } catch { model.report(error) }
                    }.buttonStyle(AlignButtonStyle())
                }
                if saved { Label(key.isEmpty ? "未設定 Key" : "已儲存至鑰匙圈", systemImage: "lock").font(Typography.font(.caption)).foregroundStyle(Palette.action) }
            }
        }.onAppear { key = KeyStore.read(account); saved = !key.isEmpty }
    }
}

struct FilePathField: View {
    let title: String
    @Binding var path: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Typography.font(.caption, weight: .medium))
            HStack {
                TextField(title, text: $path, prompt: Text("/完整/檔案路徑").foregroundStyle(Palette.muted))
                    .textFieldStyle(AlignTextFieldStyle(monospaced: true)).accessibilityLabel(title)
                Button("選擇檔案") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                    panel.message = "選擇\(title)"
                    if panel.runModal() == .OK, let url = panel.url { path = url.path }
                }.buttonStyle(AlignButtonStyle())
            }
        }
    }
}

struct LabeledField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var monospaced = false
    init(_ title: String, placeholder: String, text: Binding<String>, monospaced: Bool = false) {
        self.title = title; self.placeholder = placeholder; _text = text; self.monospaced = monospaced
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Typography.font(.caption, weight: .medium))
            TextField(title, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.muted))
                .textFieldStyle(AlignTextFieldStyle(monospaced: monospaced)).accessibilityLabel(title)
        }
    }
}

struct SectionTitle: View {
    let title: String
    let symbol: String
    init(_ title: String, symbol: String) { self.title = title; self.symbol = symbol }
    /// Each section keeps its own hue so titles are told apart at a glance.
    private var tint: Color {
        switch symbol {
        case "chart.bar": return Palette.action
        case "keyboard": return Palette.ai
        case "slider.horizontal.3": return Palette.success
        case "text.alignleft": return Palette.accent
        case "text.bubble": return Palette.warning
        default: return Palette.muted
        }
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(IconToken.font(.regular, weight: .regular))
                .foregroundStyle(tint).frame(width: 20)
                .accessibilityHidden(true)
            Text(title).font(Typography.font(.section, weight: .medium)).foregroundStyle(Palette.ink).singleLineHeading()
        }
    }
}

/// Picks how long recordings stay, with a custom number of days and a size readout.
private struct RecordingRetentionRow: View {
    @ObservedObject var model: AppModel
    private enum Choice: Hashable { case off, failedOnly, days(Int), custom, forever }
    private static let presets = [1, 3, 7, 30]
    /// Stays on once chosen, so stepping onto 7 days does not hide the stepper.
    @State private var custom = false
    private var choice: Binding<Choice> {
        Binding {
            if custom { return .custom }
            switch model.settings.recordingRetention {
            case .off: return .off
            case .failedOnly: return .failedOnly
            case .forever: return .forever
            case .days(let days): return Self.presets.contains(days) ? .days(days) : .custom
            }
        } set: { choice in
            custom = choice == .custom
            switch choice {
            case .off: model.settings.recordingRetention = .off
            case .failedOnly: model.settings.recordingRetention = .failedOnly
            case .forever: model.settings.recordingRetention = .forever
            case .days(let days): model.settings.recordingRetention = .days(days)
            case .custom: model.settings.recordingRetention = .days(14)
            }
            model.pruneRecordings()
        }
    }
    private var customDays: Binding<Int> {
        Binding {
            if case .days(let days) = model.settings.recordingRetention { return days }
            return 14
        } set: { model.settings.recordingRetention = .days($0); model.pruneRecordings() }
    }
    private var isCustom: Bool { choice.wrappedValue == .custom }

    var body: some View {
        SettingsRow(title: "錄音保留期限",
                    detail: "辨識失敗時，可到聽寫紀錄用保留的錄音重新處理，不用再講一次。失敗的錄音會一直保留，直到重新處理成功或手動刪除。目前佔用 \(ByteCountFormatter.string(fromByteCount: model.recordingBytes, countStyle: .file))。") {
            HStack(spacing: 8) {
                Picker("錄音保留期限", selection: choice) {
                    Text("不保留").tag(Choice.off)
                    Text("只保留失敗的").tag(Choice.failedOnly)
                    ForEach(Self.presets, id: \.self) { Text("\($0) 天").tag(Choice.days($0)) }
                    Text("自訂天數").tag(Choice.custom)
                    Text("永久").tag(Choice.forever)
                }.labelsHidden().fixedSize()
                if isCustom {
                    Stepper(value: customDays, in: 1...365) { Text("\(customDays.wrappedValue) 天").monospacedDigit() }.fixedSize()
                }
                Button("刪除所有錄音", role: .destructive) { model.removeAllRecordings() }
                    .buttonStyle(AlignButtonStyle(kind: .destructive)).disabled(model.recordingBytes == 0)
            }
        }.onAppear {
            if case .days(let days) = model.settings.recordingRetention { custom = !Self.presets.contains(days) }
        }
    }
}
