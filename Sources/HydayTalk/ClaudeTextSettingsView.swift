import SwiftUI
import TalkCore

struct ClaudeTextSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var executable = ClaudeSession.discoverExecutable()

    var body: some View {
        SettingsGroup(title: "Claude", detail: "透過這台 Mac 上已登入的 Claude Code 整理文字，用的是你自己的 Claude 訂閱額度。") {
            SettingsRow(title: "Claude 模型", detail: model.settings.claudeModel.detail) {
                AlignMenuPicker(title: "Claude 模型", values: ClaudeTextModel.allCases, selection: $model.settings.claudeModel,
                                label: { $0.title }, showsTitle: false).frame(width: 200)
            }
            SettingsRow(title: "Claude Code", detail: executable == nil
                        ? "找不到 Claude Code，安裝並登入後按重新檢查。" : "已找到 Claude Code，錄音時會先在背景啟動，整理會比較快。") {
                HStack(spacing: 8) {
                    if executable == nil {
                        Link("安裝說明", destination: URL(string: "https://docs.claude.com/en/docs/claude-code/setup")!)
                            .font(Typography.font(.caption)).pointingCursor()
                    }
                    Button("重新檢查") { executable = ClaudeSession.discoverExecutable() }.buttonStyle(AlignButtonStyle())
                }
            }
            SettingsBlock {
                Text("逐字稿會送到 Anthropic 處理。Hyday Talk 不經手你的登入資料，額度用完時請改用其他整理方式。")
                    .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            }
        }
    }
}
