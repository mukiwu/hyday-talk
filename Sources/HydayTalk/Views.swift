import SwiftUI
import AppKit
import Speech
import TalkCore

/*
THESIS: A native dictation workspace makes fn, output and configuration immediately legible.
OWN-WORLD: Light gray workspace, soft cards, orange voice details,
precise native controls and SF Symbols.
STORY: Check readiness, configure speech and text, then dictate at the destination cursor.
FIRST VIEWPORT: Persistent sidebar, compact page heading, white dictation and output cards,
then paired settings/shortcut cards on a neutral workspace. White recording feedback floats below.
FORM: Native behavior and the approved white floating panel remain.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md
*/
enum Page: String, CaseIterable, Identifiable {
    case home = "總覽", insights = "洞察", history = "聽寫紀錄", hyday = "Hyday", speech = "語音辨識", text = "文字整理", dictionary = "個人辭典", settings = "一般設定"
    var id: String { rawValue }
    var title: String { self == .home ? "語音輸入" : rawValue }
    var detail: String {
        switch self {
        case .home: return "按 fn 開始聽寫，支援文字插入與複製。"
        case .insights: return "查看口述字數、節省時間與使用習慣。"
        case .history: return "查看這台 Mac 的聽寫紀錄，最多保留 200 筆。"
        case .hyday: return "設定 Hyday 資料夾，將語音內容記到 Hyday 日誌。"
        case .speech: return "選擇辨識來源與語言，設定會自動儲存。"
        case .text: return "設定文字模型、聽寫風格與輸出格式。"
        case .dictionary: return "設定人名、品牌與術語的替換規則。"
        case .settings: return "管理權限、快捷鍵與語音輸入偏好。"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .insights: return "chart.bar"
        case .history: return "doc.text"
        case .hyday: return "sun.horizon"
        case .speech: return "waveform"
        case .text: return "text.alignleft"
        case .dictionary: return "book.closed"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var page: Page = .home
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    PageHeading(title: page.title, detail: page.detail)
                    Spacer(minLength: 8)
                    Button { model.openPermissionGuide() } label: {
                        AlignStatusBadge(title: model.phase.busy ? model.phase.title : (model.permissionsReady ? "已就緒" : "待設定"), ready: model.permissionsReady && !model.phase.busy)
                    }.buttonStyle(.plain).pointingCursor().disabled(model.phase.busy).help("開啟權限指引")
                }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !model.notice.isEmpty { notice }
                        switch page {
                        case .home: HomeView(model: model, selectPage: { page = $0 })
                        case .insights: InsightsView(model: model)
                        case .history: HistoryView(model: model)
                        case .hyday: HydaySettingsView(model: model)
                        case .speech: SpeechSettingsView(model: model)
                        case .text: TextSettingsView(model: model)
                        case .dictionary: DictionaryView(model: model)
                        case .settings: GeneralSettingsView(model: model)
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.id(page)
            }.background(Palette.workspace)
        }.foregroundStyle(Palette.ink).frame(minWidth: 950, minHeight: 720).focusEffectDisabled()
            .font(Typography.font(.body)).lineSpacing(Typography.paragraphSpacing).tint(Palette.action).toggleStyle(.switch).preferredColorScheme(.light)
            .onAppear { model.presentPermissionGuideIfNeeded(); model.updater.checkIfDue() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.updater.checkIfDue() }
            .sheet(isPresented: $model.showPermissionGuide) {
                PermissionGuideView(model: model, initialStep: model.permissionGuideStartStep).focusEffectDisabled()
            }
    }
    private var notice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.phase == .failed ? "exclamationmark.circle" : "info.circle").foregroundStyle(Palette.action)
            Text(model.notice).font(Typography.font(.caption)).textSelection(.enabled)
            Spacer(minLength: 0)
            Button { model.notice = "" } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                .buttonStyle(.plain).pointingCursor().help("關閉訊息").accessibilityLabel("關閉訊息")
        }.padding(12).background(Palette.subtleSurface, in: RoundedRectangle(cornerRadius: 8))
    }
    private func navigationItem(_ item: Page) -> some View {
        Button { page = item } label: {
            HStack(spacing: 12) {
                if item == .hyday, let icon = HydayBrand.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        // The icon is full-bleed, so match the optical size of the 16 pt line icons.
                        .frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: item.symbol).font(.system(size: 16, weight: .regular))
                        .foregroundStyle(page == item ? Palette.accent : Palette.ink.opacity(0.78)).frame(width: 20)
                }
                Text(item.rawValue).font(Typography.font(.body, weight: page == item ? .medium : .regular))
                    .foregroundStyle(page == item ? Palette.ink : Palette.ink.opacity(0.85))
                Spacer(minLength: 0)
            }.frame(minHeight: 20)
        }.buttonStyle(AlignNavigationStyle(selected: page == item, horizontalPadding: 12, verticalPadding: 9))
            .accessibilityAddTraits(page == item ? [.isSelected] : [])
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 9) {
                HydayLogo(size: 28)
                Text("Hyday Talk").font(Typography.font(.section, weight: .semibold)).fixedSize()
            }.padding(.horizontal, 8).padding(.top, 10)
            VStack(alignment: .leading, spacing: 4) {
                ForEach([Page.home, .insights, .history]) { item in navigationItem(item) }
                Text("設定").font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 6)
                ForEach([Page.hyday, .speech, .text, .dictionary, .settings]) { item in navigationItem(item) }
            }
            Spacer(minLength: 24)
            SidebarJobs(installer: model.textModelInstaller, speechModels: model.localModels, updater: model.updater,
                        openText: { page = .text }, openSpeech: { page = .speech })
                .padding(.bottom, -10)
            VStack(spacing: 0) {
                Button { model.openPermissionGuide() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.settings.speechBackend.symbol).font(IconToken.font(.regular))
                            .foregroundStyle(Palette.action).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.settings.speechBackend.title).font(Typography.font(.caption, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(model.settings.locale == "zh-TW" ? "繁體中文 · 台灣" : model.settings.locale)
                                .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: model.permissionsReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(model.permissionsReady ? Palette.success : Palette.warning)
                            .accessibilityLabel(model.permissionsReady ? "權限已就緒" : "權限待設定")
                    }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).pointingCursor().help("開啟權限指引")
                Divider().padding(.horizontal, 12)
                Button { model.openPermissionGuide() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield").font(IconToken.font(.regular)).foregroundStyle(Palette.muted).frame(width: 20)
                        Text("權限指引").font(Typography.font(.caption))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(IconToken.font(.small)).foregroundStyle(Palette.faint)
                    }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).pointingCursor().disabled(model.phase.busy)
            }
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                .font(Typography.font(.caption)).foregroundStyle(Palette.faint).padding(.horizontal, 12).padding(.top, -16)
        }.padding(12).frame(width: 210).background(Palette.sidebar)
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    let selectPage: (Page) -> Void
    @State private var copiedPreview = false
    @State private var copiedResult = false
    @State private var resultExpanded = false
    @State private var resultOverflows = false
    @State private var homeWidth: CGFloat = 1000
    private var previewInput: String { "呃明天先確認權限，然後再測試錄音，唉最後還要檢查文字插入這樣" }
    private var previewOutput: String {
        guard model.settings.requiresTextModel(for: .dictate), model.settings.textBackend != .basic else { return previewInput }
        switch model.settings.writingStyle {
        case .verbatim: return previewInput
        case .natural: return "明天先確認權限，再測試錄音，唉，最後還要檢查文字插入。"
        case .professional: return "明天確認權限、測試錄音，並檢查文字插入。"
        }
    }
    /// One line on what the selected style keeps and drops.
    private var styleNote: String {
        switch model.settings.writingStyle {
        case .verbatim: return "保留原話會照辨識結果輸出，不刪任何字，也跳過 AI 整理與排版。"
        case .natural: return "自然會刪掉呃、然後這類沒有意思的詞，但保留你的用詞和唉、好啦這類帶情緒的語氣。"
        case .professional: return "正式會刪掉所有語助詞和口頭禪，並改成簡潔的書面用語。"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeSummary(insights: UsageInsights(ledger: model.usage, typingSpeed: model.settings.typingWordsPerMinute),
                        typingSpeed: model.settings.typingWordsPerMinute)
            Group {
                if homeWidth >= 760 {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) { mainColumn; lowerRow }
                        HomeStatsCard(stats: DictationStats(history: model.history),
                                      insights: UsageInsights(ledger: model.usage, typingSpeed: model.settings.typingWordsPerMinute)) { selectPage(.insights) }
                            .frame(width: 300).frame(maxHeight: .infinity, alignment: .top)
                    }.fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        mainColumn; lowerRow
                        HomeStatsCard(stats: DictationStats(history: model.history),
                                      insights: UsageInsights(ledger: model.usage, typingSpeed: model.settings.typingWordsPerMinute)) { selectPage(.insights) }
                    }
                }
            }.background(GeometryReader { proxy in
                Color.clear.onAppear { homeWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in homeWidth = width }
            })
        }
        .onChange(of: previewOutput) { _, _ in copiedPreview = false }
    }
    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("目前設定", symbol: "slider.horizontal.3")
            VStack(spacing: 2) {
                HomeSettingButton(title: "語音辨識", value: speechModelName, symbol: model.settings.speechBackend.symbol, tint: Palette.action) { selectPage(.speech) }
                HomeSettingButton(title: "文字整理", value: textModelName,
                                  symbol: "text.alignleft", tint: Palette.ai) { selectPage(.text) }
            }
        }.equalHeightCard()
    }
    private var lowerRow: some View {
        HStack(alignment: .top, spacing: 16) { settingsCard; ShortcutSummary().equalHeightCard() }
            .fixedSize(horizontal: false, vertical: true)
    }
    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            recordingRegion
            if !model.permissionsReady { PermissionsView(model: model) }
            if homeWidth < 760 {
                recentResult; outputPreview
            } else {
                // Demo and latest result share a row 2 : 1, so the column is not a stack of full-width strips.
                HStack(alignment: .top, spacing: 16) {
                    outputPreview
                    recentResult.frame(width: max(220, (homeWidth - 316 - 16) / 3))
                }.fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var recordingRegion: some View {
        HStack(spacing: 20) {
            HomeVoiceKeycap(recording: model.phase == .recording)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.phase == .recording ? "正在錄音 · \(model.action.title)" : (model.phase.busy ? model.phase.title : "按 fn 開始聽寫"))
                    .font(Typography.font(.brand, weight: .semibold)).singleLineHeading()
                Text(model.phase == .recording ? (model.action == .translate ? "目標語言：\(model.settings.targetLanguage)，再按 fn 完成。" : "再按 fn 完成，或按 esc 取消。")
                     : (model.phase.busy ? "正在處理語音輸入。"
                        : (model.settings.autoInsert ? "再按 fn 完成，無法插入時自動複製。" : "完成後保留結果供複製。")))
                    .font(Typography.font(.caption)).foregroundStyle(Palette.accentInk)
            }
            Spacer(minLength: 0)
            if model.phase == .recording {
                ViewThatFits(in: .horizontal) {
                    WaveformView(level: model.level, count: 15, color: Palette.accent).frame(width: 87)
                    Color.clear.frame(width: 0, height: 32)
                }
            }
            Button(action: toggleRecording) {
                HStack(spacing: 8) {
                    if model.phase.busy && model.phase != .recording {
                        ProgressView().controlSize(.small).tint(Palette.muted).frame(width: 16, height: 16)
                    } else {
                        Image(systemName: model.phase == .recording ? "stop.fill" : "mic").font(IconToken.font(.regular, weight: .medium))
                    }
                    Text(model.phase == .recording ? "完成錄音" : (model.phase.busy ? "處理中" : "開始聽寫")).fontWeight(.regular).fixedSize()
                }
            }.buttonStyle(AlignButtonStyle(kind: .accent, prominent: true))
                .homeKeyboardActivation(toggleRecording)
                .disabled(model.phase.busy && model.phase != .recording)
                .help(model.settings.autoInsert ? "完成後插入原輸入框，無法插入時自動複製文字。" : "開始聽寫，結果保留供複製。")
        }.padding(.horizontal, DesignTokens.Surfaces.padding).padding(.vertical, 18).frame(maxWidth: .infinity, minHeight: 96)
            // The one card framed by its own orange border instead of the shared white shell.
            .background(LinearGradient(colors: [Palette.accentSurface, Palette.card], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius).strokeBorder(Palette.accentBorder, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
    }
    /// Sits under the record button so the output reads as that recording's result.
    private var recentResult: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle("最近結果", symbol: "text.bubble")
                    if let source = recentSource {
                        Text(source).font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !latestText.isEmpty { Button { TextInsertion.copy(latestText); copiedResult = true } label: {
                    Image(systemName: copiedResult ? "checkmark" : "doc.on.doc").frame(width: 16, height: 16)
                }.buttonStyle(AlignButtonStyle()).help(copiedResult ? "已複製" : "複製文字")
                    .accessibilityLabel(copiedResult ? "已複製" : "複製文字") }
            }
            if latestText.isEmpty {
                Text("還沒有結果，按 fn 說一段話，結果會留在這裡。").font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            } else {
            Text(latestText).font(Typography.font(.body)).textSelection(.enabled)
                .lineLimit(resultExpanded ? nil : 6).frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { full in
                    // Measure the untruncated height to know whether 展開 is needed.
                    Text(latestText).font(Typography.font(.body)).fixedSize(horizontal: false, vertical: true)
                        .frame(width: full.size.width).hidden()
                        .background(GeometryReader { natural in
                            Color.clear.onAppear { resultOverflows = natural.size.height > full.size.height + 1 || resultExpanded }
                                .onChange(of: natural.size.height) { _, height in resultOverflows = height > full.size.height + 1 || resultExpanded }
                        })
                })
            if resultOverflows {
                Button(resultExpanded ? "收合" : "展開") { resultExpanded.toggle() }
                    .buttonStyle(.link).font(Typography.font(.caption))
            }
            }
        }.frame(maxHeight: .infinity, alignment: .topLeading).surface()
            .onChange(of: latestText) { _, _ in copiedResult = false; resultExpanded = false }
    }
    /// The latest output: this session's result, or the newest saved record after a relaunch.
    private var latestText: String { model.result.isEmpty ? (model.history.first?.text ?? "") : model.result }
    private var recentSource: String? {
        guard let record = model.history.first, record.text == latestText else { return nil }
        let place = record.destination == "結果區" ? "保留在結果區" : "插入到 \(record.destination)"
        return "\(place) · \(record.date.formatted(.relative(presentation: .named)))"
    }
    private var outputPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SectionTitle("輸出示範", symbol: "text.alignleft")
                Spacer(minLength: 0)
                Button(action: copyPreview) {
                    Label(copiedPreview ? "已複製" : "複製範例", systemImage: "doc.on.doc")
                }
                    .buttonStyle(AlignButtonStyle())
                    .homeKeyboardActivation(copyPreview)
                    .accessibilityLabel(copiedPreview ? "示範文字已複製" : "複製範例")
            }
            HStack(spacing: 12) {
                AlignSegmentedPicker(title: "聽寫風格", values: WritingStyle.allCases, selection: $model.settings.writingStyle, label: { $0.title })
                    .frame(width: 260).disabled(model.settings.textBackend == .basic || model.phase.busy)
                if model.settings.textBackend == .basic {
                    Text("風格需要文字 AI，可從下方「文字整理」啟用。")
                        .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                }
            }
            HomeOutputComparison(input: previewInput, output: previewOutput)
            if model.settings.textBackend != .basic {
                Text(styleNote).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxHeight: .infinity, alignment: .topLeading).surface()
    }
    private var speechModelName: String {
        if model.settings.speechBackend == .whisper {
            return LocalSpeechModel.all.first { model.settings.whisperModel.hasSuffix($0.filename) }?.title ?? "本機模型"
        }
        if model.settings.speechBackend == .api { return apiTitle(model.settings.speechAPI.model) }
        return model.settings.speechBackend.title
    }
    private var textModelName: String {
        switch model.settings.textBackend {
        case .local: return model.settings.localTextModel ?? "未選擇模型"
        case .api: return apiTitle(model.settings.textAPI.model)
        case .claude: return "Claude \(model.settings.claudeModel.title)"
        default: return model.settings.textBackend.title
        }
    }
    private func apiTitle(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "API Key" : "API Key · \(trimmed)"
    }
    private func toggleRecording() { if model.phase == .recording { model.finish() } else { model.begin() } }
    private func copyPreview() { TextInsertion.copy(previewOutput); copiedPreview = true }
}

struct ShortcutSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("快捷鍵", symbol: "keyboard")
            shortcut("聽寫", keys: ["fn"])
            shortcut("翻譯", keys: ["fn", "左 ⇧"])
            shortcut("文字提問", keys: ["fn", "Control"])
            shortcut("記到 Hyday", keys: ["fn", "Space"])
            shortcut("取消", keys: ["esc"])
        }
    }
    private func shortcut(_ title: String, keys: [String]) -> some View {
        HStack(spacing: 6) {
            Text(title).font(Typography.font(.body)).foregroundStyle(Palette.muted).frame(width: 84, alignment: .leading)
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 { Text("+").font(Typography.font(.caption)).foregroundStyle(Palette.muted) }
                Keycap(key)
            }
            Spacer(minLength: 0)
        }.frame(minHeight: 32)
    }
}

struct PermissionsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                SectionTitle(model.permissionsReady ? "權限已就緒" : "權限設定", symbol: "checkmark.shield")
                Spacer()
                Button("查看設定指引") { model.openPermissionGuide() }.buttonStyle(AlignButtonStyle()).controlSize(.regular)
            }
            Text("已完成 \(model.completedPermissionCount) / \(model.requiredPermissions.count) 項權限，可按「查看設定指引」了解操作方式。")
                .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            ForEach(model.requiredPermissions) { permission in
                permissionRow(permission)
            }
        }.surface().disabled(model.phase.busy)
    }
    private func permissionRow(_ permission: PermissionKind) -> some View {
        let allowed = model.permissionAllowed(permission)
        return HStack(spacing: 12) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle").foregroundStyle(allowed ? Palette.action : Palette.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(permission.title).font(Typography.font(.caption, weight: .medium))
                Text(permission.purpose).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            }
            Spacer()
            if allowed { Text("已開啟").font(Typography.font(.caption)).foregroundStyle(Palette.action) }
            else {
                Button("設定\(permission.title)") { model.openPermissionGuide(at: permission) }
                    .buttonStyle(AlignButtonStyle()).controlSize(.regular)
            }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    @State private var filter: VoiceAction? = nil
    @State private var confirmClear = false
    @State private var hovered: UUID?
    private var records: [DictationRecord] {
        model.history.filter { record in
            (filter == nil || record.action == filter)
                && (search.isEmpty || record.text.localizedCaseInsensitiveContains(search) || record.destination.localizedCaseInsensitiveContains(search))
        }
    }
    /// Records grouped by day, newest first, so a long history stays scannable.
    private var days: [(day: Date, records: [DictationRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
    }
    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        return day.formatted(.dateTime.month(.defaultDigits).day().weekday(.wide).locale(Locale(identifier: "zh-TW")))
    }
    private func filterTitle(_ value: VoiceAction?) -> String {
        switch value {
        case nil: return "所有"
        case .dictate: return "聽寫"
        case .translate: return "翻譯"
        case .ask: return "提問"
        case .hyday: return "Hyday"
        }
    }
    private func tint(_ action: VoiceAction) -> Color {
        switch action {
        case .dictate: return Palette.accent
        case .translate: return Palette.action
        case .ask: return Palette.ai
        case .hyday: return Palette.success
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AlignSegmentedPicker(title: "紀錄類型", values: [nil] + VoiceAction.allCases.map { Optional($0) },
                                     selection: $filter, label: filterTitle).fixedSize()
                TextField("搜尋聽寫紀錄", text: $search, prompt: Text("搜尋文字或 App").foregroundStyle(Palette.muted))
                    .textFieldStyle(AlignTextFieldStyle()).accessibilityLabel("搜尋聽寫紀錄")
                Button("清除紀錄", role: .destructive) { confirmClear = true }.buttonStyle(AlignButtonStyle(kind: .destructive)).disabled(model.history.isEmpty)
            }
            if !model.settings.saveHistory { Label("已關閉紀錄儲存，既有紀錄仍可手動清除。", systemImage: "info.circle").font(Typography.font(.caption)).foregroundStyle(Palette.muted) }
            if records.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "text.bubble").font(IconToken.font(.large, weight: .medium)).foregroundStyle(Palette.action)
                        .frame(width: 56, height: 56).background(Palette.actionSurface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.actionBorder, lineWidth: 1))
                    Text(search.isEmpty && filter == nil ? "尚無聽寫紀錄" : "查無符合的紀錄").font(Typography.font(.brand, weight: .medium)).singleLineHeading()
                    Text(search.isEmpty && filter == nil ? "完成聽寫後，文字紀錄將顯示於此。" : "請更換關鍵字或類型。")
                        .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                    if !search.isEmpty || filter != nil { Button("清除搜尋條件") { search = ""; filter = nil } }
                }.frame(maxWidth: .infinity).padding(.vertical, 70).surface()
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(days, id: \.day) { group in
                        Text(dayTitle(group.day)).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                            .padding(.top, 10).padding(.leading, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { Divider().padding(.leading, 16) }
                                row(record)
                            }
                        }
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.border, lineWidth: 1))
                    }
                }
            }
        }.alert("清除這台 Mac 的所有聽寫紀錄？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清除所有紀錄", role: .destructive) { model.clearHistory() }
        } message: { Text("這項操作無法復原。") }
    }

    private func row(_ record: DictationRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(record.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                .font(Typography.font(.caption)).monospacedDigit().foregroundStyle(Palette.muted).frame(width: 40, alignment: .leading)
            if record.action != .dictate {
                Text(filterTitle(record.action)).font(Typography.font(.caption, weight: .medium)).foregroundStyle(tint(record.action)).fixedSize()
            }
            Text(record.text).font(Typography.font(.body)).lineSpacing(3).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                Button { TextInsertion.copy(record.text); model.notice = "已複製文字。" } label: {
                    Image(systemName: "doc.on.doc").frame(width: 18, height: 18)
                }.buttonStyle(AlignButtonStyle(kind: .ghost)).help("複製文字").accessibilityLabel("複製文字")
                Button { model.removeRecord(record.id) } label: {
                    Image(systemName: "trash").frame(width: 18, height: 18)
                }.buttonStyle(AlignButtonStyle(kind: .ghost)).help("刪除此筆紀錄").accessibilityLabel("刪除此筆紀錄")
            }.opacity(hovered == record.id ? 1 : 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 9).contentShape(Rectangle())
        .onHover { inside in hovered = inside ? record.id : (hovered == record.id ? nil : hovered) }
        .help("\(record.destination) · \(record.backend.title) · \(TextProcessing.wordCount(record.text)) 字 · \(Int(record.duration)) 秒")
    }
}

struct PageHeading: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typography.font(.pageTitle, weight: .semibold)).singleLineHeading()
            Text(detail).font(Typography.font(.body)).foregroundStyle(Palette.muted).lineSpacing(Typography.paragraphSpacing)
        }
    }
}

struct Keycap: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label).font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.ink.opacity(0.85))
            .frame(minWidth: 26, minHeight: 22).padding(.horizontal, 5)
            .background(LinearGradient(colors: [Palette.surface, Palette.card], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.12), lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.1)).offset(y: 1.5))
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
    }
}

extension View {
    func singleLineHeading() -> some View {
        lineLimit(1).fixedSize(horizontal: true, vertical: false).accessibilityAddTraits(.isHeader)
    }

    /// Cards in one row stretch to the tallest so the row reads as one band.
    func equalHeightCard() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).surface()
    }

    func surface() -> some View {
        frame(maxWidth: .infinity, alignment: .leading).padding(DesignTokens.Surfaces.padding)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius))
            // Depth from soft shadow and an inner highlight, not an outline.
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius).strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
    }
}

/// Sidebar notices for work that runs in the background: the text model
/// download and app updates. Shows nothing when there is nothing to report.
private struct SidebarJobs: View {
    @ObservedObject var installer: TextModelInstaller
    @ObservedObject var speechModels: LocalSpeechModelManager
    @ObservedObject var updater: AppUpdater
    let openText: () -> Void
    let openSpeech: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if installer.installing {
                Button(action: openText) {
                    job(symbol: "arrow.down.circle", title: "下載 \(installer.model)", detail: installer.status) {
                        ProgressView(value: installer.progress ?? 0)
                    }
                }.buttonStyle(.plain).pointingCursor().help("開啟文字整理設定")
            }
            if let downloading = speechModels.downloading {
                Button(action: openSpeech) {
                    job(symbol: "arrow.down.circle", title: "下載 \(downloading.title)",
                        detail: speechModels.progress.map { "\(speechModels.status) \(Int($0 * 100))%" } ?? speechModels.status) {
                        if let progress = speechModels.progress { ProgressView(value: progress) } else { ProgressView().progressViewStyle(.linear) }
                    }
                }.buttonStyle(.plain).pointingCursor().help("開啟語音辨識設定")
            }
            if let update = updater.update { updateJob(update) }
        }
    }

    @ViewBuilder private func updateJob(_ update: AppUpdate) -> some View {
        switch updater.state {
        case .idle: EmptyView()
        case .available:
            job(symbol: "sparkles", title: "有新版本 \(update.version)", detail: "目前是 \(AppUpdater.currentVersion)") {
                Button("下載更新", action: updater.startDownload).buttonStyle(AlignButtonStyle(kind: .primary)).controlSize(.small)
            }
        case .downloading(let fraction):
            job(symbol: "arrow.down.circle", title: "下載 \(update.version)", detail: "正在下載 \(Int(fraction * 100))%") {
                HStack(spacing: 8) {
                    ProgressView(value: fraction)
                    Button("取消", action: updater.cancelDownload).buttonStyle(.link).font(Typography.font(.caption))
                }
            }
        case .ready:
            if updater.canRestartToUpdate {
                job(symbol: "checkmark.circle", title: "\(update.version) 已下載", detail: "重新啟動後就會換成新版") {
                    Button("重新啟動並更新", action: updater.restartToUpdate).buttonStyle(AlignButtonStyle(kind: .primary)).controlSize(.small)
                }
            } else {
                job(symbol: "checkmark.circle", title: "\(update.version) 已下載", detail: "結束 Hyday Talk 後，把新版拖進應用程式資料夾") {
                    Button("打開安裝檔", action: updater.openInstaller).buttonStyle(AlignButtonStyle(kind: .primary)).controlSize(.small)
                }
            }
        case .installing:
            job(symbol: "arrow.triangle.2.circlepath", title: "正在更新 \(update.version)", detail: "正在檢查新版，完成後會自動重新啟動") {
                ProgressView().progressViewStyle(.linear)
            }
        case .failed(let message):
            job(symbol: "exclamationmark.circle", title: "有新版本 \(update.version)", detail: message) {
                Button("重新下載", action: updater.startDownload).buttonStyle(AlignButtonStyle()).controlSize(.small)
            }
        }
    }

    private func job<Accessory: View>(symbol: String, title: String, detail: String,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).font(IconToken.font(.regular)).foregroundStyle(Palette.action).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typography.font(.caption, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(Typography.font(.caption)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            accessory()
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
    }
}
