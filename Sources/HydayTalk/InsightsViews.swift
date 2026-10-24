import SwiftUI
import TalkCore

enum InsightFormat {
    static func number(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)) }
    static func duration(_ minutes: Double) -> (String, String) {
        let total = Int(minutes.rounded())
        if total < 60 { return ("\(total)", "分鐘") }
        return ("\(total / 60)", total % 60 == 0 ? "小時" : "小時 \(total % 60) 分鐘")
    }
}

/// Past or estimated values are hatched; the current value is solid.
struct HatchedShape: View {
    var color: Color
    var line: Color
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
            var x: CGFloat = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height)); path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(line), lineWidth: 1)
                x += 4
            }
        }
    }
}

struct MetricValue: View {
    let value: String
    let unit: String
    var size: CGFloat = 34
    var color: Color = Palette.ink
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: size, weight: .regular)).monospacedDigit().tracking(-size * 0.03).foregroundStyle(color)
            Text(unit).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
        }.lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// A white capsule comparing a value with an earlier period.
struct ChangePill: View {
    let change: Double
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 7))
                .foregroundStyle(change >= 0 ? Palette.success : Palette.danger)
            Text(text).font(Typography.font(.caption, weight: .medium)).monospacedDigit()
        }.padding(.horizontal, 7).padding(.vertical, 2)
            .background(Palette.surface, in: Capsule()).shadow(color: Color.black.opacity(0.08), radius: 1.5, y: 1)
    }
}

struct Metric: Identifiable {
    let title: String
    let value: String
    let unit: String
    var color: Color = Palette.ink
    var change: (Double, String)? = nil
    let caption: String
    var id: String { title }
}

/// Columns on one surface, split by hairlines: label, large light number, then a comparison or note.
struct MetricStrip: View {
    let metrics: [Metric]
    var size: CGFloat = 32
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                if index > 0 { Rectangle().fill(Palette.border).frame(width: 1) }
                VStack(alignment: .leading, spacing: 8) {
                    Text(metric.title).font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineLimit(1)
                    MetricValue(value: metric.value, unit: metric.unit, size: size, color: metric.color)
                    HStack(spacing: 6) {
                        if let change = metric.change { ChangePill(change: change.0, text: change.1) }
                        Text(metric.caption).font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, index == 0 ? 0 : 20).padding(.trailing, 12)
                    .accessibilityElement(children: .combine)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct HomeSummary: View {
    let insights: UsageInsights
    let typingSpeed: Int
    var body: some View {
        let saved = InsightFormat.duration(insights.weekSavedMinutes)
        let wordChange = insights.todayWords - insights.yesterdayWords
        let savedChange = insights.weekSavedMinutes - insights.previousWeekSavedMinutes
        MetricStrip(metrics: [
            Metric(title: "今日字詞", value: InsightFormat.number(insights.todayWords), unit: "字",
                   change: (Double(wordChange), InsightFormat.number(abs(wordChange))), caption: "與昨天相比"),
            Metric(title: "目前連續天數", value: "\(insights.currentStreak)", unit: "天", caption: "最長 \(insights.longestStreak) 天"),
            Metric(title: "近 7 日節省時間", value: saved.0, unit: saved.1, color: insights.weekSavedMinutes > 0 ? Palette.success : Palette.ink,
                   change: (savedChange, InsightFormat.duration(abs(savedChange)).0 + " " + InsightFormat.duration(abs(savedChange)).1), caption: "與前 7 日相比"),
            Metric(title: "平均口述速度", value: insights.wordsPerMinute.map(String.init) ?? "—", unit: "字／分",
                   caption: "打字約每分鐘 \(typingSpeed) 字"),
        ]).surface()
    }
}

struct InsightsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let insights = UsageInsights(ledger: model.usage, typingSpeed: model.settings.typingWordsPerMinute)
        let saved = InsightFormat.duration(insights.savedMinutes)
        let spoken = InsightFormat.duration(insights.totalMinutes)
        VStack(alignment: .leading, spacing: 16) {
            MetricStrip(metrics: [
                Metric(title: "口述字數", value: InsightFormat.number(insights.totalWords), unit: "字", caption: "累計"),
                Metric(title: "節省時間", value: saved.0, unit: saved.1, color: insights.savedMinutes > 0 ? Palette.success : Palette.ink, caption: "估算"),
                Metric(title: "平均口述速度", value: insights.wordsPerMinute.map(String.init) ?? "—", unit: "每分鐘字數", caption: "累計平均"),
                Metric(title: "總口述時間", value: spoken.0, unit: spoken.1, caption: "累計"),
            ], size: 38).surface()
            HStack(alignment: .top, spacing: 16) {
                InsightCard(title: "近 12 週", detail: "每週口述字數，本週以實色標示") { WeeklyBars(weeks: insights.weekly(weeks: 12)) }
                HighlightCard(insights: insights).frame(width: 300)
            }.fixedSize(horizontal: false, vertical: true)
            InsightCard(title: "口述速度趨勢", detail: "近 12 週的每分鐘字數") { SpeedLine(weeks: insights.weekly(weeks: 12)) }
            HStack(alignment: .top, spacing: 16) {
                InsightCard(title: "使用時段", detail: "一天中各時段的聽寫筆數") { HourGrid(counts: insights.hourCounts) }
                InsightCard(title: "功能使用比例", detail: "聽寫、翻譯與提問的筆數") { ActionShare(counts: insights.actionCounts) }
                    .frame(width: 300)
            }.fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                InsightCard(title: "常用 App", detail: "插入文字的目的地，依筆數排序") { AppRanking(apps: insights.apps) }
                InsightCard(title: "每筆口述長度", detail: "最近的聽寫紀錄，每個點代表一筆") { SessionDots(history: model.history) }
            }.fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                InsightCard(title: "個人紀錄") {
                    VStack(spacing: 0) {
                        recordRow("單日最多字詞", insights.bestDay.map { "\(InsightFormat.number($0.words)) 字" } ?? "尚無資料",
                                  insights.bestDay.map { $0.day.replacingOccurrences(of: "-", with: "/") })
                        Divider()
                        recordRow("最長一次口述", insights.longestSession > 0 ? String(format: "%.0f 秒", insights.longestSession) : "尚無資料", nil)
                    }
                }
                InsightCard(title: "連續使用") {
                    VStack(spacing: 0) {
                        recordRow("活躍天數", "\(insights.activeDays) 天", nil)
                        Divider()
                        recordRow("目前連續天數", "\(insights.currentStreak) 天", nil)
                        Divider()
                        recordRow("最長連續天數", "\(insights.longestStreak) 天", nil)
                    }
                }
                dictionaryCard
            }.fixedSize(horizontal: false, vertical: true)
            Text("節省時間以每分鐘打字 \(model.settings.typingWordsPerMinute) 字估算，扣除實際口述時間，可於一般設定調整打字速度。")
                .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
        }
    }
    private func recordRow(_ title: String, _ value: String, _ note: String?) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.muted)
            Spacer()
            if let note { Text(note).foregroundStyle(Palette.faint).monospacedDigit() }
            Text(value).monospacedDigit()
        }.font(Typography.font(.caption)).padding(.vertical, 10)
    }
    private var dictionaryCard: some View {
        let total = model.settings.dictionary.count
        let learned = model.settings.dictionary.filter(\.isAutomatic).count
        return InsightCard(title: "個人辭典", detail: "自動學習的詞彙佔比") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        MetricValue(value: "\(total)", unit: "個詞彙", size: 30)
                        Text("全部").font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        MetricValue(value: "\(learned)", unit: "個詞彙", size: 30, color: Palette.action)
                        Text("自動學習").font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                    }
                }
                GeometryReader { proxy in
                    HatchedShape(color: Palette.actionSurface, line: Palette.action.opacity(0.35)).clipShape(Capsule())
                        .overlay(alignment: .leading) {
                            Capsule().fill(Palette.action).frame(width: total == 0 ? 0 : proxy.size.width * CGFloat(learned) / CGFloat(total))
                        }
                }.frame(height: 8).accessibilityHidden(true)
            }
        }
    }
}

struct InsightCard<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typography.font(.section, weight: .medium)).singleLineHeading()
                if let detail { Text(detail).font(Typography.font(.caption)).foregroundStyle(Palette.muted) }
            }
            content
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).surface()
    }
}

/// A floating white label for a chart value.
struct ChartTag: View {
    let text: String
    var body: some View {
        Text(text).font(Typography.font(.caption, weight: .medium)).monospacedDigit().fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Palette.surface, in: Capsule()).shadow(color: Color.black.opacity(0.08), radius: 1.5, y: 1)
    }
}

struct WeeklyBars: View {
    let weeks: [WeekUsage]
    var body: some View {
        let peak = max(1, weeks.map(\.words).max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    let current = index == weeks.count - 1
                    VStack(spacing: 6) {
                        if current { ChartTag(text: InsightFormat.number(week.words)) }
                        else if week.words > 0 {
                            Text(InsightFormat.number(week.words)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.muted)
                                .fixedSize()
                        }
                        Group {
                            if current { Palette.action } else { HatchedShape(color: Palette.actionSurface, line: Palette.action.opacity(0.45)) }
                        }.frame(height: max(4, 120 * CGFloat(week.words) / CGFloat(peak))).clipShape(RoundedRectangle(cornerRadius: 3))
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 150, alignment: .bottom)
            HStack {
                Text(weeks.first.map { $0.start.formatted(.dateTime.month(.defaultDigits).day()) } ?? "")
                Spacer()
                Text("本週")
            }.font(Typography.font(.caption)).foregroundStyle(Palette.muted)
        }.accessibilityElement(children: .ignore).accessibilityLabel("近 12 週口述字數")
            .accessibilityValue(weeks.map { "\($0.words)" }.joined(separator: "、"))
    }
}

struct SpeedLine: View {
    let weeks: [WeekUsage]
    var body: some View {
        let values = weeks.map { $0.wordsPerMinute.map(Double.init) }
        let known = values.compactMap { $0 }
        let top = (known.max() ?? 100) * 1.2, bottom = max(0, (known.min() ?? 0) * 0.8)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width, height = proxy.size.height
                let point = { (index: Int, value: Double) -> CGPoint in
                    CGPoint(x: weeks.count > 1 ? width * CGFloat(index) / CGFloat(weeks.count - 1) : width / 2,
                            y: height * (1 - CGFloat((value - bottom) / max(1, top - bottom))))
                }
                let points = values.enumerated().compactMap { index, value in value.map { point(index, $0) } }
                ZStack(alignment: .topLeading) {
                    ForEach(0..<4, id: \.self) { line in
                        Path { path in
                            let y = height * CGFloat(line) / 3
                            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: width, y: y))
                        }.stroke(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                    if points.count > 1 {
                        Path { path in
                            path.move(to: CGPoint(x: points[0].x, y: height)); points.forEach { path.addLine(to: $0) }
                            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: height)); path.closeSubpath()
                        }.fill(LinearGradient(colors: [Palette.action.opacity(0.18), Palette.action.opacity(0)], startPoint: .top, endPoint: .bottom))
                        Path { path in path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) } }
                            .stroke(Palette.action, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { index, p in
                        Circle().fill(index == points.count - 1 ? Palette.surface : Palette.action).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Palette.action, lineWidth: 2)).position(p)
                    }
                    if let last = points.last, let value = known.last {
                        ChartTag(text: "\(Int(value)) 字／分").position(x: min(max(last.x, 50), width - 50), y: max(12, last.y - 20))
                    }
                }
            }.frame(height: 150)
            if known.isEmpty { Text("尚無資料").font(Typography.font(.caption)).foregroundStyle(Palette.muted) }
        }.accessibilityElement(children: .ignore).accessibilityLabel("近 12 週口述速度")
            .accessibilityValue(values.map { $0.map { "\(Int($0))" } ?? "無" }.joined(separator: "、"))
    }
}

struct HourGrid: View {
    let counts: [Int]
    var body: some View {
        let peak = max(1, counts.max() ?? 1)
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 12), spacing: 6) {
                ForEach(0..<24, id: \.self) { hour in
                    let level = Double(counts[hour]) / Double(peak)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(counts[hour] == 0 ? Palette.subtleSurface : Palette.accent.opacity(0.18 + 0.82 * level))
                        .frame(height: 34)
                        .overlay(Text("\(hour)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(level > 0.55 ? Color.white : Palette.muted))
                        .help("\(hour):00 至 \(hour + 1):00，\(counts[hour]) 筆")
                }
            }
            HStack(spacing: 4) {
                Text("較少").font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                ForEach([0.0, 0.3, 0.6, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3).fill(level == 0 ? Palette.subtleSurface : Palette.accent.opacity(0.18 + 0.82 * level)).frame(width: 12, height: 12)
                }
                Text("較多").font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("各時段聽寫筆數")
            .accessibilityValue(counts.enumerated().map { "\($0.offset) 點 \($0.element) 筆" }.joined(separator: "、"))
    }
}

struct ActionShare: View {
    let counts: [VoiceAction: Int]
    private func tint(_ action: VoiceAction) -> Color {
        switch action {
        case .dictate: return Palette.accent
        case .translate: return Palette.action
        case .ask: return Palette.ai
        case .hyday: return Palette.success
        }
    }
    var body: some View {
        let total = max(1, counts.values.reduce(0, +))
        VStack(alignment: .leading, spacing: 16) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(VoiceAction.allCases) { action in
                        let share = CGFloat(counts[action] ?? 0) / CGFloat(total)
                        if share > 0 { RoundedRectangle(cornerRadius: 4).fill(tint(action)).frame(width: max(4, (proxy.size.width - 6) * share)) }
                    }
                }
            }.frame(height: 12)
            VStack(spacing: 0) {
                ForEach(VoiceAction.allCases) { action in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(tint(action)).frame(width: 10, height: 10)
                        Text(action.title)
                        Spacer()
                        Text("\(counts[action] ?? 0) 筆").foregroundStyle(Palette.muted).monospacedDigit()
                        Text("\(Int((Double(counts[action] ?? 0) / Double(total) * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }.font(Typography.font(.caption)).padding(.vertical, 8)
                    if action != VoiceAction.allCases.last { Divider() }
                }
            }
        }
    }
}

struct AppRanking: View {
    let apps: [AppUsage]
    var body: some View {
        let top = max(1, apps.first?.count ?? 1)
        VStack(spacing: 0) {
            if apps.isEmpty { Text("尚無資料").font(Typography.font(.caption)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(Array(apps.prefix(6).enumerated()), id: \.offset) { index, app in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(app.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(InsightFormat.number(app.words)) 字").foregroundStyle(Palette.muted).monospacedDigit()
                        Text("\(app.count) 筆").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }.font(Typography.font(.caption))
                    GeometryReader { proxy in
                        Group {
                            if index == 0 { Palette.action } else { HatchedShape(color: Palette.actionSurface, line: Palette.action.opacity(0.45)) }
                        }.frame(width: max(6, proxy.size.width * CGFloat(app.count) / CGFloat(top))).clipShape(Capsule())
                    }.frame(height: 5)
                }.padding(.vertical, 8)
            }
        }
    }
}

struct SessionDots: View {
    let history: [DictationRecord]
    var body: some View {
        let sessions = Array(history.prefix(120).map(\.duration))
        let limit = max(30, (sessions.max() ?? 30).rounded(.up))
        let average = sessions.isEmpty ? 0 : sessions.reduce(0, +) / Double(sessions.count)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width, height = proxy.size.height
                let top: CGFloat = 26 // room for the average tag above the tallest stack
                let count = max(1, Int(width / 9))
                // Stack dots that land in the same column, like a dot plot.
                let columns = Dictionary(grouping: sessions.indices) { min(count - 1, Int(sessions[$0] / limit * Double(count))) }
                let tallest = CGFloat(columns.values.map(\.count).max() ?? 1)
                // Shrink the vertical step when a column would otherwise rise past the chart.
                let step = min(9, (height - top) / tallest)
                let dot = max(2, min(7, step - 1.5))
                let pitch = width / CGFloat(count)
                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(columns.keys), id: \.self) { column in
                        ForEach(Array(columns[column, default: []].enumerated()), id: \.offset) { stack, _ in
                            Circle().fill(Palette.action.opacity(0.75)).frame(width: dot, height: dot)
                                .position(x: CGFloat(column) * pitch + pitch / 2, y: height - CGFloat(stack) * step - step / 2)
                        }
                    }
                    if !sessions.isEmpty {
                        let x = width * CGFloat(average / limit)
                        Path { path in path.move(to: CGPoint(x: x, y: top)); path.addLine(to: CGPoint(x: x, y: height)) }
                            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        ChartTag(text: String(format: "平均 %.0f 秒", average)).position(x: min(max(x, 44), width - 44), y: top / 2)
                    }
                }
            }.frame(height: 160)
            HStack {
                Text("0 秒"); Spacer(); Text(String(format: "%.0f 秒", limit))
            }.font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            if sessions.isEmpty { Text("尚無資料").font(Typography.font(.caption)).foregroundStyle(Palette.muted) }
        }.accessibilityElement(children: .ignore).accessibilityLabel("每筆口述長度")
            .accessibilityValue(String(format: "共 %d 筆，平均 %.0f 秒", sessions.count, average))
    }
}

/// One finding drawn from the data, set apart on a gradient like a callout.
struct HighlightCard: View {
    let insights: UsageInsights
    var body: some View {
        let hour = insights.peakHour
        let totalHours = max(1, insights.hourCounts.reduce(0, +))
        VStack(alignment: .leading, spacing: 14) {
            Label("使用習慣", systemImage: "sparkles").font(Typography.font(.caption, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4).background(Color.white.opacity(0.18), in: Capsule())
            if let hour {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(hour):00").font(.system(size: 42, weight: .light)).monospacedDigit().tracking(-1)
                    Text("最常口述的時段").font(Typography.font(.caption)).opacity(0.85)
                }
                Text("\(Int((Double(insights.hourCounts[hour]) / Double(totalHours) * 100).rounded()))% 的聽寫發生在 \(hour):00 至 \(hour + 1):00")
                    .font(Typography.font(.body, weight: .medium))
                if let app = insights.apps.first {
                    Text("最常插入 \(app.name)，共 \(app.count) 筆、\(InsightFormat.number(app.words)) 字。").font(Typography.font(.caption)).opacity(0.85)
                }
            } else {
                Text("累積更多聽寫後，這裡會顯示你的使用習慣。").font(Typography.font(.body, weight: .medium))
            }
            Spacer(minLength: 0)
        }.foregroundStyle(Color.white).padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [Color(red: 0.24, green: 0.40, blue: 0.86), Color(red: 0.44, green: 0.56, blue: 0.86), Color(red: 0.96, green: 0.62, blue: 0.42)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius))
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
    }
}
