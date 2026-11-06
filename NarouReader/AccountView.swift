import SwiftUI

/// アカウント(メールアドレスとパスワード)で、複数の端末の履歴を共有する画面
struct AccountView: View {
    @EnvironmentObject var store: AppStore
    @State private var mode = 0          // 0: ログイン / 1: 新規登録
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorText = ""

    private var lastSyncText: String {
        guard let t = store.s.lastSync else { return "まだ同期していません" }
        let d = Date(timeIntervalSince1970: t / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d HH:mm"
        return "最後の同期: " + f.string(from: d)
    }

    var body: some View {
        Form {
            if store.loggedIn {
                Section("ログイン中") {
                    Text(store.s.acctEmail ?? "")
                    Text(store.syncMessage.isEmpty ? lastSyncText : store.syncMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button("今すぐ同期") {
                        Task { await store.syncNow() }
                    }
                    .disabled(store.syncing)
                    Button("ログアウト", role: .destructive) {
                        Task { await store.logout() }
                    }
                }
            } else {
                Section("サーバー") {
                    TextField("Web版のアドレス(https://…)", text: $store.s.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("Web 版を開いているときのアドレスを入れてください。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Section {
                    Picker("", selection: $mode) {
                        Text("ログイン").tag(0)
                        Text("新規登録").tag(1)
                    }
                    .pickerStyle(.segmented)
                    TextField("メールアドレス", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                    SecureField("パスワード(8文字以上)", text: $password)
                        .textContentType(mode == 0 ? .password : .newPassword)
                    if !store.syncMessage.isEmpty && errorText.isEmpty {
                        Text(store.syncMessage).font(.footnote).foregroundColor(.red)
                    }
                    if !errorText.isEmpty {
                        Text(errorText).font(.footnote).foregroundColor(.red)
                    }
                    Button(mode == 0 ? "ログイン" : "登録してはじめる") {
                        submit()
                    }
                    .disabled(busy || email.isEmpty || password.count < 8 || store.s.serverURL.isEmpty)
                }
            }
            Section {
                Text("お気に入り・既読と読んだ位置・最近読んだ小説・文字の大きさ/行間/画面の色・次の話へ続けて読む・操作ボタンの表示を、ログインした端末どうしで共有します。読み上げの声と速さは、端末ごとのままです。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("アカウント")
    }

    private func submit() {
        busy = true
        errorText = ""
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password
        let register = (mode == 1)
        Task {
            do {
                try await store.authenticate(email: e, password: p, register: register)
                password = ""
            } catch let f as SyncFailure {
                errorText = f.message
            } catch {
                errorText = "通信できませんでした。アドレスと通信状態を確認してください"
            }
            busy = false
        }
    }
}
