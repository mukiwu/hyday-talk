import SwiftUI
import AppKit
import TalkCore

private final class NonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class VoicePanelPresentation: ObservableObject {
    @Published var expanded = false
}

@MainActor
final class VoicePanel {
    private let panel: NonactivatingPanel
    private let model: AppModel
    private let presentation = VoicePanelPresentation()
    private var lastPhase: CapturePhase = .idle
    init(model: AppModel) {
        self.model = model
        panel = NonactivatingPanel(contentRect: NSRect(x: 0, y: 0, width: LayoutToken.voicePanelWidth, height: LayoutToken.voicePanelHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: VoicePanelContent(model: model, presentation: presentation,
            onSizeChange: { [weak self] in self?.refresh() }))
        panel.isReleasedWhenClosed = false
    }
    func refresh() {
        if lastPhase != model.phase {
            lastPhase = model.phase
            presentation.expanded = model.phase == .failed || (model.phase == .done && (model.action == .ask || model.missedInsertion))
        }
        guard model.phase != .idle else { panel.orderOut(nil); return }
        let height = presentation.expanded ? LayoutToken.voiceDetailHeight : LayoutToken.voicePanelHeight
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(NSRect(x: frame.midX - LayoutToken.voicePanelWidth / 2, y: frame.minY + LayoutToken.voicePanelBottomInset,
            width: LayoutToken.voicePanelWidth, height: height), display: true)
        panel.orderFrontRegardless()
    }
}

private struct VoicePanelContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presentation: VoicePanelPresentation
    let onSizeChange: () -> Void
    var body: some View {
        VoiceBarView(state: VoiceBarState(model: model), expanded: $presentation.expanded,
            actions: VoiceBarActions(finish: model.finish, dismiss: model.dismissPanel, copy: model.copyResult,
                openMain: { model.dismissPanel(); model.showWindow?() }, resize: onSizeChange))
            .onChange(of: model.phase) { _, _ in onSizeChange() }
    }
}

struct VoiceBarState {
    let phase: CapturePhase
    var elapsed: TimeInterval = 0
    var level: Double = 0
    var transcript = ""
    var result = ""
    var notice = ""
    var action: VoiceAction = .dictate
    var destination = "結果區"
    var missedInsertion = false
    var actionTitle: String { action.title }
}

extension VoiceBarState {
    @MainActor init(model: AppModel) {
        self.init(phase: model.phase, elapsed: model.elapsed, level: model.level, transcript: model.transcript,
            result: model.result, notice: model.notice, action: model.action, destination: model.destination,
            missedInsertion: model.missedInsertion)
    }
}

struct VoiceBarActions {
    var finish: () -> Void = {}
    var dismiss: () -> Void = {}
    var copy: () -> Void = {}
    var openMain: () -> Void = {}
    var resize: () -> Void = {}
}

struct VoiceBarView: View {
    let state: VoiceBarState
    @Binding var expanded: Bool
    @State private var history: [Double] = []
    @State private var sampleCount = 0
    // Shared so the timer survives re-renders; one owned by the view restarted on every model update and never fired.
    private static let sampler = Timer.publish(every: 0.06, on: .main, in: .common).autoconnect()
    private static let historyLength = 26
    var actions = VoiceBarActions()
    private var terminal: Bool { state.phase == .done || state.phase == .failed }
    private var radius: CGFloat { expanded ? 16 : 26 }
    private var elapsedText: String { String(format: "%02d:%02d", Int(state.elapsed) / 60, Int(state.elapsed) % 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controls.frame(height: 32)
            if expanded { details }
        }.padding(LayoutToken.voicePanelPadding).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.voiceSurface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.border, lineWidth: 1))
            .padding(2).font(Typography.font(.caption)).lineSpacing(Typography.paragraphSpacing)
            .foregroundStyle(Palette.ink).tint(Palette.action).preferredColorScheme(.light).focusEffectDisabled()
            .onReceive(Self.sampler) { _ in
                MeterDiagnostics.shared.recordTick(recording: state.phase == .recording)
                guard state.phase == .recording else { if !history.isEmpty { history = [] }; return }
                sampleCount += 1
                let sample = VoiceMeter.display(level: state.level) * VoiceMeter.jitter(sample: sampleCount)
                history = Array((history + [sample]).suffix(Self.historyLength))
            }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if state.phase.busy && state.phase != .recording {
                ProgressView().controlSize(.regular).scaleEffect(0.5).frame(width: 16, height: 16)
            } else {
                Image(systemName: state.phase == .recording ? "waveform" : (state.phase == .failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill"))
                    .font(IconToken.font(.badge, weight: .semibold))
                    .foregroundStyle(state.phase == .recording ? Palette.accent : Palette.action)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            if state.phase == .recording {
                levelMeter.accessibilityHint(compactTitle)
                Text(elapsedText).font(Typography.font(.body, weight: .medium)).monospacedDigit()
                    .fixedSize().padding(.horizontal, 4).accessibilityLabel("錄音時間").accessibilityValue(elapsedText)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(compactTitle).font(Typography.font(.caption, weight: .semibold)).lineLimit(1)
                        .fixedSize(horizontal: state.missedInsertion, vertical: false)
                        .help(state.notice.isEmpty ? compactTitle : state.notice)
                    // A Hyday entry is not inserted anywhere, so preview what was written.
                    if state.phase == .done, state.action == .hyday, !state.result.isEmpty {
                        Text(state.result).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            if state.phase == .recording {
                control("stop.fill", label: "完成錄音 · fn", emphasized: true, action: actions.finish)
            } else if terminal && !state.result.isEmpty && !(expanded && state.missedInsertion) {
                // When expanded after a missed insertion, the copy button below takes over.
                control("doc.on.doc", label: "複製文字", emphasized: true, action: actions.copy)
            }
            if state.phase != .recording {
                control(expanded ? "chevron.up" : "chevron.down", label: expanded ? "收合詳情" : "展開詳情") {
                    expanded.toggle(); actions.resize()
                }
            }
            control("xmark", label: state.phase.busy ? "取消 · esc" : "關閉", action: actions.dismiss)
        }
    }

    private var compactTitle: String {
        switch state.phase {
        case .idle: return "待機"
        case .preparing: return "準備中"
        case .recording:
            switch state.action {
            case .dictate: return "錄音中"
            case .translate: return "翻譯錄音"
            case .ask: return "提問錄音"
            case .hyday: return "Hyday 錄音"
            }
        case .transcribing: return "辨識中"
        case .processing:
            switch state.action {
            case .dictate: return "整理中"
            case .translate: return "翻譯中"
            case .ask: return "回應中"
            case .hyday: return "寫入中"
            }
        case .done:
            if state.missedInsertion { return "沒有可插入的位置" }
            return state.action == .hyday ? "已記到 Hyday" : "已完成"
        case .failed: return "處理失敗"
        }
    }

    /// Scrolling level history: the newest sample enters on the right and
    /// older samples fade as they drift left, so the meter fills its width.
    private var levelMeter: some View {
        var samples = Array(repeating: 0.0, count: max(0, Self.historyLength - history.count)) + history
        // The newest bar follows the live level so the meter reacts the moment you speak.
        samples[samples.count - 1] = max(samples[samples.count - 1], VoiceMeter.display(level: state.level))
        return HStack(spacing: 2.5) {
            ForEach(samples.indices, id: \.self) { index in
                let age = Double(index) / Double(Self.historyLength - 1)
                Capsule().fill(Palette.accent.opacity(0.45 + 0.55 * age))
                    .frame(width: 2.5, height: 3 + CGFloat(min(1.1, samples[index])) * 19)
            }
        }.animation(.easeOut(duration: 0.08), value: samples)
            .frame(maxWidth: .infinity, maxHeight: 24)
            .accessibilityElement(children: .ignore).accessibilityLabel("麥克風音量")
            .accessibilityValue("\(Int(min(1, max(0, state.level)) * 100)) 百分比")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if state.phase == .recording {
                        Text(state.transcript.isEmpty ? "請開始說話" : state.transcript).font(Typography.font(.body)).textSelection(.enabled)
                    } else if terminal {
                        if !state.result.isEmpty { Text(state.result).font(Typography.font(.body)).textSelection(.enabled) }
                    } else {
                        Text(state.phase == .preparing ? "請允許麥克風與必要的辨識權限。" : "聽寫或翻譯送出文字後會關閉面板，其他結果保留供複製。")
                            .foregroundStyle(Palette.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: .infinity)
            // Outside the scroll view, so a long result cannot push it under the buttons.
            if terminal, !state.notice.isEmpty {
                Text(state.notice).foregroundStyle(Palette.muted).textSelection(.enabled)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).help(state.notice)
            }
            if terminal {
                HStack(spacing: 8) {
                    if state.missedInsertion, !state.result.isEmpty {
                        Button("複製文字", action: actions.copy).buttonStyle(AlignButtonStyle(kind: .primary)).controlSize(.regular)
                    }
                    Button("開啟主視窗", action: actions.openMain).buttonStyle(AlignButtonStyle()).controlSize(.regular)
                }
            } else {
                Text("\(state.actionTitle) · \(state.destination)").foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle).help("\(state.actionTitle) · \(state.destination)")
            }
        }
    }

    private func control(_ symbol: String, label: String, emphasized: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(IconToken.font(.small, weight: .semibold))
                .frame(width: LayoutToken.voiceControlSize, height: LayoutToken.voiceControlSize)
                .foregroundStyle(emphasized ? (state.phase == .recording ? Palette.danger : Palette.action) : Palette.muted)
                .background(emphasized ? (state.phase == .recording ? Palette.dangerSurface : Palette.actionSurface) : Color.clear, in: Circle())
                .contentShape(Rectangle())
        }.buttonStyle(.plain).pointingCursor().help(label).accessibilityLabel(label)
    }
}
