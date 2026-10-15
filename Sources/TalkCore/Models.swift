import Foundation

public enum SpeechBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, whisper, cli, api
    public static let availableSources: [SpeechBackend] = [.system, .whisper, .api]
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return "系統辨識"
        case .whisper: return "本機模型"
        case .cli: return "CLI"
        case .api: return "API Key"
        }
    }
    public var symbol: String {
        switch self {
        case .system: return "apple.logo"
        case .whisper: return "desktopcomputer"
        case .cli: return "terminal"
        case .api: return "network"
        }
    }
    public var detail: String {
        switch self {
        case .system: return "使用 macOS 語音辨識"
        case .whisper: return "在這台 Mac 離線辨識"
        case .cli: return "自訂辨識工具與執行參數"
        case .api: return "連接 OpenAI 相容的服務"
        }
    }
}

public enum TextBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case basic, local, cli, api, claude
    public static let availableSources: [TextBackend] = [.basic, .local, .claude, .api]
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .basic: return "基礎整理"
        case .local: return "本機 AI"
        case .cli: return "CLI"
        case .api: return "API Key"
        case .claude: return "Claude"
        }
    }
}

public enum DictationLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, paragraph, list
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: return "自動整理"
        case .paragraph: return "段落"
        case .list: return "列表"
        }
    }
    public var detail: String {
        switch self {
        case .automatic: return "依內容決定排版，一般敘述使用段落，明確列舉多個事項時使用列表，適合日常聽寫。"
        case .paragraph: return "以完整句子連成段落，列舉事項也不轉成列表，適合訊息、郵件與文件。"
        case .list: return "將獨立事項逐項分行並加上編號，只有一件事時保留單項，適合待辦清單與工作步驟。"
        }
    }
    public static let singleExampleInput = "請先確認麥克風權限"
    public static let enumerationExampleInput = "第一確認權限第二測試錄音第三檢查文字插入"
    public var singleExampleOutput: String {
        self == .list ? "1. 請先確認麥克風權限。" : "請先確認麥克風權限。"
    }
    public var enumerationExampleOutput: String {
        self == .paragraph ? "先確認權限，接著測試錄音，最後檢查文字插入。"
            : "1. 確認權限。\n2. 測試錄音。\n3. 檢查文字插入。"
    }
    public var instruction: String {
        switch self {
        case .automatic: return "依內容自動排版，同一段輸出可同時包含段落與編號列表：一般敘述保留為段落，話題轉換時換段，超過三句的敘述依意思分成數段，每段二到三句，段落之間空一行，絕對不要把四句以上的敘述擠成一整段；遇到第一、第二、第三等連續列舉，或用「再來」「然後」「接著」「還有」「另外」「最後」串起的多個並列事項、步驟或修改項目，改用編號列表，並刪掉這些串接詞，每項獨立一行並完整保留該項內容，行首使用阿拉伯數字與句點，例如1. 內容，不以第一、第二作為行首；列表前後的敘述仍保留為段落，不要為一般敘述強行條列。範例：逐字稿「這次改了兩個地方然後第一個是按鈕改成藍色再來是標題字變大了」應輸出「這次改了兩個地方：\n1. 按鈕改成藍色。\n2. 標題字變大。」；逐字稿「新版首頁上線了速度比之前快很多大家反應都不錯不過手機版還有跑版的問題按鈕會疊在一起我們下週要先修這個」應分兩段輸出「新版首頁上線了，速度比之前快很多，大家反應都不錯。\n\n不過手機版還有跑版的問題，按鈕會疊在一起，我們下週要先修這個。」"
        case .paragraph: return "以完整句子與段落呈現，不使用列表。"
        case .list: return "輸出必須為編號列表，每個獨立事項各佔一行，依序以1.、2.、3.開頭；依語意將原文中的多個事項分開，每項保留完整資訊。只有一個事項就輸出單項列表，禁止虛構事項。"
        }
    }
}

public enum VoiceAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case dictate, translate, ask, hyday
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .dictate: return "聽寫"
        case .translate: return "翻譯"
        case .ask: return "提問 / 編輯"
        case .hyday: return "記到 Hyday"
        }
    }
    public var shortcut: String {
        switch self {
        case .dictate: return "fn"
        case .translate: return "fn + 左 ⇧"
        case .ask: return "fn + Control"
        case .hyday: return "fn + Space"
        }
    }
}

public enum WritingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case verbatim, natural, professional
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .natural: return "自然"
        case .verbatim: return "保留原話"
        case .professional: return "正式"
        }
    }
    public var detail: String {
        switch self {
        case .natural: return "保留口語語氣與情緒並補上標點，刪除多餘的贅詞與思考片段，適合日常訊息。"
        case .verbatim: return "保留辨識原文的字句，僅套用字形、既有標點與個人辭典，不使用 AI 改寫。"
        case .professional: return "刪除所有贅詞，改用清楚簡潔的書面用語並補上標點，適合工作郵件與文件。"
        }
    }
    public static let exampleInput = "呃明天下午3點要開會，然後再麻煩Amy把API文件帶過來這樣"
    public var exampleOutput: String {
        switch self {
        case .natural: return "明天下午3點要開會，再麻煩Amy把API文件帶過來。"
        case .verbatim: return Self.exampleInput
        case .professional: return "明天下午3點開會，請Amy攜帶API文件。"
        }
    }
    public var instruction: String {
        switch self {
        case .natural: return "保留說話者自己的用詞，只刪不換，不把口語詞換成意思相同的書面詞，例如我覺得就保持我覺得；自行判斷哪些簡單口語能帶出說話者的情緒與語氣轉折，感受、強調、遲疑、句首的嘆氣聲、無奈或勉強答應的語氣都算情緒要保留，其餘不帶意思的贅詞與說到一半的思考片段都刪除。"
        case .verbatim: return "保留辨識原文，不改寫字句。"
        case .professional: return "贅詞、語助詞、口頭禪與思考過程的片段全部刪除，一個都不保留；將口語用詞換成簡潔書面用詞，可調整句構並保留原意；使用「請」取代「麻煩」等口語請求詞，不疊加客套詞，不要加入原文沒有的「請問」「能否」「是否」等問句，保留「可能」「應該」等原有的確定程度；正式風格也必須保留原文的阿拉伯數字，不改成國字數字。"
        }
    }
}

public struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    /// Stored under the original keys so older settings still decode: `replacement` is the term,
    /// `heard` the optional misheard spelling (empty when there is none).
    public var heard: String
    public var replacement: String
    /// Absent in settings saved before automatic learning existed.
    var automatic: Bool?
    public var isAutomatic: Bool { automatic == true }
    /// The correct spelling, given to recognition and the text AI as a hint.
    public var term: String {
        get { replacement }
        set { replacement = newValue }
    }
    /// Only manual entries may name a misheard spelling, which is then replaced by the term.
    /// Learned entries saved by older versions still carry the misheard text; it is ignored, so they never replace.
    public var misheard: String? { heard.isEmpty || isAutomatic ? nil : heard }
    /// A term can be misheard several ways; they are entered separated by 、 or commas.
    public var misheardSpellings: [String] {
        (misheard ?? "").components(separatedBy: CharacterSet(charactersIn: "、,，"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    public init(term: String, misheard: String? = nil, isAutomatic: Bool = false) {
        heard = misheard ?? ""; replacement = term; automatic = isAutomatic ? true : nil
    }
    public init(heard: String, replacement: String, isAutomatic: Bool = false) {
        self.init(term: replacement, misheard: heard, isAutomatic: isAutomatic)
    }
}

public struct APISettings: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public init(baseURL: String = "https://api.openai.com/v1", model: String) {
        self.baseURL = baseURL; self.model = model
    }
}

public struct TalkSettings: Codable, Equatable, Sendable {
    public var speechBackend: SpeechBackend = .whisper
    public var textBackend: TextBackend = .basic
    public var localTextModel: String?
    public var dictationLayout: DictationLayout?
    public var locale: String = "zh-TW"
    public var targetLanguage: String = "英文"
    public var writingStyle: WritingStyle = .natural
    public var systemOfflineOnly = false
    public var autoInsert = true
    public var saveHistory = true
    public var interactionSounds = true
    public var whisperExecutable = "/opt/homebrew/bin/whisper-cli"
    public var whisperModel = ""
    public var speechCLIExecutable = ""
    public var speechCLIArguments = "{audio}"
    public var textCLIExecutable = ""
    public var textCLIArguments = ""
    public var speechAPI = APISettings(model: "gpt-transcribe")
    public var textAPI = APISettings(model: "gpt-4.1-mini")
    public var dictionary: [DictionaryEntry] = []
    /// Optional so settings saved by earlier versions still decode; nil means on.
    var learnFromCorrections: Bool?
    var blockedCorrections: [DictionaryEntry]?
    var typingSpeed: Int?
    var claudeTextModel: String?
    /// A folder chosen in the Hyday page; nil follows Hyday's own `vault.root`.
    public var hydayFolder: String?
    var askHydayNotes: Bool?
    var readScreenContext: Bool?
    var screenContextExcluded: [String]?
    /// Text questions answer from notes found in the Hyday folder; off by default.
    public var asksHydayNotes: Bool {
        get { askHydayNotes ?? false }
        set { askHydayNotes = newValue }
    }
    /// Used to estimate time saved; 40 sits in the common 20–50 range for Taiwanese Zhuyin typists.
    public var typingWordsPerMinute: Int {
        get { typingSpeed ?? 40 }
        set { typingSpeed = newValue }
    }
    /// Formats text through the user's own Claude Code login; Haiku unless chosen otherwise.
    public var claudeModel: ClaudeTextModel {
        get { claudeTextModel.flatMap(ClaudeTextModel.init(rawValue:)) ?? .recommended }
        set { claudeTextModel = newValue.rawValue }
    }
    public var learnsFromCorrections: Bool {
        get { learnFromCorrections ?? true }
        set { learnFromCorrections = newValue }
    }
    public init() {}
    public var languageCode: String { String(locale.prefix(2)) }
    public func requiresTextModel(for action: VoiceAction) -> Bool {
        // Without a text AI, Hyday entries are stored as one cleaned list item.
        if action == .hyday { return textBackend != .basic }
        return action != .dictate || (textBackend != .basic && writingStyle != .verbatim)
    }
}

public struct DictationRecord: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date: Date
    public var rawText: String
    public var text: String
    public var action: VoiceAction
    public var backend: SpeechBackend
    public var duration: TimeInterval
    public var destination: String
    public init(date: Date = Date(), rawText: String, text: String, action: VoiceAction,
                backend: SpeechBackend, duration: TimeInterval, destination: String) {
        self.date = date; self.rawText = rawText; self.text = text; self.action = action
        self.backend = backend; self.duration = duration; self.destination = destination
    }
}

public struct TalkError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
