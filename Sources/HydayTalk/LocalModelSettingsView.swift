import SwiftUI
import TalkCore

struct LocalModelSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var manager: LocalSpeechModelManager

    var body: some View {
        SettingsGroup(title: "選擇本機語音模型", detail: "模型在這台 Mac 辨識語音，錄音不會上傳。") {
            if !manager.engineReady {
                SettingsBlock {
                    Label("辨識引擎尚未就緒，請重新安裝 Hyday Talk。", systemImage: "exclamationmark.circle")
                        .font(Typography.font(.caption)).foregroundStyle(Palette.ink)
                }
            }
            ForEach(LocalSpeechModel.all) { candidate in
                let url = manager.installed[candidate.id]
                let selected = url?.path == model.settings.whisperModel
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(title: candidate.title, detail: "\(candidate.detail) \(candidate.sizeLabel)",
                                badge: candidate.isRecommended ? "推薦" : nil) {
                        if selected {
                            Label("使用中", systemImage: "checkmark.circle.fill")
                                .font(Typography.font(.caption, weight: .medium)).foregroundStyle(Palette.action).fixedSize()
                        } else if let url {
                            Button("使用此模型") { select(url) }.buttonStyle(AlignButtonStyle())
                                .accessibilityLabel("使用 \(candidate.title)")
                                .disabled(manager.busyModelID != nil || !manager.engineReady(for: candidate.filename))
                        } else {
                            Button("下載並使用") { manager.download(candidate, onSelect: select) }.buttonStyle(AlignButtonStyle(kind: .primary))
                                .accessibilityLabel("下載並使用 \(candidate.title)")
                                .disabled(manager.busyModelID != nil || !manager.engineReady(for: candidate.filename))
                        }
                    }
                    if manager.busyModelID == candidate.id {
                        HStack(spacing: 10) {
                            if let progress = manager.progress {
                                ProgressView(value: progress).frame(width: 160)
                                Text("\(manager.status) \(Int(progress * 100))%").font(Typography.font(.caption))
                                    .foregroundStyle(Palette.muted).monospacedDigit()
                            } else {
                                ProgressView().controlSize(.small)
                                Text(manager.status).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button("取消", action: manager.cancel).buttonStyle(AlignButtonStyle())
                        }.padding(.bottom, 14)
                    } else if url != nil && !selected {
                        Label("已可使用", systemImage: "checkmark.circle").font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                            .padding(.bottom, 14)
                    }
                }
            }
            if !manager.issue.isEmpty {
                SettingsBlock {
                    Label(manager.issue, systemImage: "exclamationmark.circle")
                        .font(Typography.font(.caption)).foregroundStyle(Palette.ink)
                }
            }
        }
    }
    private func select(_ url: URL) {
        model.settings.whisperModel = url.path
        model.settings.whisperExecutable = LocalSpeechModelManager.enginePath
        model.settings.speechBackend = .whisper
    }
}
