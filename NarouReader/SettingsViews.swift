import SwiftUI
import AVFoundation

/// 読み上げ・表示の設定(読む画面の設定シートと、設定タブで共通)
struct SettingsForm: View {
    @EnvironmentObject var store: AppStore
    var onSpeechSettingChanged: () -> Void = {}
    var showAccount: Bool = false

    private var voices: [AVSpeechSynthesisVoice] { Speaker.japaneseVoices() }

    var body: some View {
        Form {
            if showAccount {
                Section("アカウント") {
                    NavigationLink {
                        AccountView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.loggedIn ? (store.s.acctEmail ?? "") : "ログイン / 新規登録")
                            Text(store.loggedIn ? "複数の端末で履歴を共有中" : "複数の端末で履歴を共有できます")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section("読み上げ") {
                VStack(alignment: .leading) {
                    Text("速度 \(String(format: "%.1f", store.s.speed))x")
                    Slider(value: $store.s.speed, in: 0.6...2.0, step: 0.1) { editing in
                        if !editing { onSpeechSettingChanged() }
                    }
                }
                Picker("声", selection: $store.s.voiceID) {
                    Text("自動").tag("")
                    ForEach(voices, id: \.identifier) { v in
                        Text(Speaker.voiceLabel(v)).tag(v.identifier)
                    }
                }
                .onChange(of: store.s.voiceID) { _ in onSpeechSettingChanged() }
                Toggle("次の話へ続けて読む", isOn: $store.s.autoNext)
                Text("より自然な声は、iPhone の「設定」→「アクセシビリティ」→「読み上げコンテンツ」→「声」→「日本語」からダウンロードできます。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Section("表示") {
                VStack(alignment: .leading) {
                    Text("文字の大きさ \(Int(store.s.fontSize))")
                    Slider(value: $store.s.fontSize, in: 14...32, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("行間 \(Int(store.s.lineSpacing))")
                    Slider(value: $store.s.lineSpacing, in: 2...24, step: 1)
                }
                Picker("画面の色", selection: $store.s.theme) {
                    Text("端末の設定に合わせる").tag("system")
                    Text("白地").tag("light")
                    Text("黒地").tag("dark")
                }
            }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            SettingsForm(showAccount: true)
                .navigationTitle("設定")
        }
    }
}
