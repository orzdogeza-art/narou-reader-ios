import Foundation

// MARK: - サーバーとやり取りする JSON(Web 版と同じ形)

struct SyncFav: Codable {
    var title: String?
    var total: Int?
    var seen: Int?
    var del: Bool?
    var t: Double
}

struct SyncProg: Codable {
    var read: [Int]
    var pos: [String: Int]
    var last: Int?
    var t: Double
}

struct SyncRecent: Codable {
    var ncode: String
    var title: String
    var total: Int
    var t: Double
}

struct SyncSettings: Codable {
    var fs: Double
    var lh: Double
    var theme: String      // auto / light / dark
    var auto: Bool
    var hideBar: Bool
    var t: Double
}

struct SyncDoc: Codable {
    var favs: [String: SyncFav] = [:]
    var prog: [String: SyncProg] = [:]
    var recent: [SyncRecent] = []
    var settings: SyncSettings? = nil

    init() {}

    enum CodingKeys: String, CodingKey { case favs, prog, recent, settings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favs = try c.decodeIfPresent([String: SyncFav].self, forKey: .favs) ?? [:]
        prog = try c.decodeIfPresent([String: SyncProg].self, forKey: .prog) ?? [:]
        recent = try c.decodeIfPresent([SyncRecent].self, forKey: .recent) ?? []
        settings = try c.decodeIfPresent(SyncSettings.self, forKey: .settings)
    }
}

struct SyncEnvelope: Codable {
    var data: SyncDoc
}

struct SyncPushBody: Codable {
    var data: SyncDoc
}

struct AuthBody: Codable {
    var email: String
    var password: String
}

struct AuthResult: Codable {
    var token: String
    var email: String?
}

struct ServerError: Codable {
    var error: String?
}

struct SyncFailure: LocalizedError {
    let message: String
    let status: Int
    var errorDescription: String? { message }
}

// MARK: - 通信

enum SyncClient {
    static func normalize(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if !t.lowercased().hasPrefix("http://") && !t.lowercased().hasPrefix("https://") {
            t = "https://" + t
        }
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }

    static func request(base: String, path: String, method: String, body: Data?, token: String?) async throws -> Data {
        let b = normalize(base)
        guard !b.isEmpty, let url = URL(string: b + path) else {
            throw SyncFailure(message: "サーバーのアドレスを入力してください", status: 0)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        if let body = body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = token {
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 200 && status < 300 { return data }
        let msg = (try? JSONDecoder().decode(ServerError.self, from: data))?.error ?? "サーバーがエラーを返しました(\(status))"
        throw SyncFailure(message: msg, status: status)
    }
}

// MARK: - AppStore に同期の処理を追加

@MainActor
extension AppStore {
    var loggedIn: Bool { s.acctEmail != nil && s.acctToken != nil }

    private static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

    private func settingsKey(_ p: PersistedState) -> String {
        return "\(p.fontSize)|\(p.lineSpacing)|\(p.theme)|\(p.autoNext)|\(p.hideControls)"
    }

    /// 変更のあった作品・設定に、更新時刻を付ける
    func trackChanges(old: PersistedState) {
        let now = AppStore.nowMs()
        var tm = s.tm
        var changed = false

        if old.favs != s.favs {
            for c in Set(old.favs.keys).union(s.favs.keys) where old.favs[c] != s.favs[c] {
                tm.f[c] = now
                changed = true
            }
        }
        if old.read != s.read || old.pos != s.pos || old.last != s.last {
            var codes = Set(old.read.keys)
            codes.formUnion(s.read.keys)
            codes.formUnion(old.pos.keys)
            codes.formUnion(s.pos.keys)
            codes.formUnion(old.last.keys)
            codes.formUnion(s.last.keys)
            for c in codes {
                let a = old.read[c] ?? []
                let b = s.read[c] ?? []
                let pa = old.pos[c] ?? [:]
                let pb = s.pos[c] ?? [:]
                if a != b || pa != pb || old.last[c] != s.last[c] {
                    tm.p[c] = now
                    changed = true
                }
            }
        }
        if settingsKey(old) != settingsKey(s) {
            tm.s = now
            changed = true
        }
        if changed { s.tm = tm }
    }

    func buildSyncDoc() -> SyncDoc {
        var doc = SyncDoc()
        for c in Set(s.favs.keys).union(s.tm.f.keys) {
            let t = s.tm.f[c] ?? 0
            if let f = s.favs[c] {
                doc.favs[c] = SyncFav(title: f.title, total: f.total, seen: f.seen, del: nil, t: t)
            } else {
                doc.favs[c] = SyncFav(title: nil, total: nil, seen: nil, del: true, t: t)
            }
        }
        var codes = Set(s.read.keys)
        codes.formUnion(s.pos.keys)
        codes.formUnion(s.last.keys)
        codes.formUnion(s.tm.p.keys)
        for c in codes {
            doc.prog[c] = SyncProg(read: (s.read[c] ?? []).sorted(), pos: s.pos[c] ?? [:], last: s.last[c], t: s.tm.p[c] ?? 0)
        }
        doc.recent = s.recent.map { SyncRecent(ncode: $0.ncode, title: $0.title, total: $0.total, t: $0.t ?? 0) }
        let fs = max(1, s.fontSize)
        let lh = (1 + s.lineSpacing / fs * 100).rounded() / 100
        doc.settings = SyncSettings(
            fs: s.fontSize,
            lh: lh,
            theme: s.theme == "system" ? "auto" : s.theme,
            auto: s.autoNext,
            hideBar: s.hideControls,
            t: s.tm.s
        )
        return doc
    }

    func applySyncDoc(_ d: SyncDoc) {
        applyingRemote = true
        defer { applyingRemote = false }
        var n = s
        for (c, f) in d.favs {
            n.tm.f[c] = f.t
            if f.del == true {
                n.favs.removeValue(forKey: c)
            } else if let title = f.title {
                n.favs[c] = FavoriteNovel(ncode: c, title: title, total: f.total ?? 0, seen: f.seen ?? 0)
            }
        }
        for (c, p) in d.prog {
            n.tm.p[c] = p.t
            n.read[c] = p.read
            n.pos[c] = p.pos
            if let l = p.last { n.last[c] = l } else { n.last.removeValue(forKey: c) }
        }
        n.recent = d.recent.map { RecentNovel(ncode: $0.ncode, title: $0.title, total: $0.total, t: $0.t) }
        if let st = d.settings, st.t > n.tm.s {
            n.fontSize = min(32, max(14, st.fs.rounded()))
            let ls = (st.lh - 1) * n.fontSize
            n.lineSpacing = min(24, max(2, ls.rounded()))
            n.theme = st.theme == "auto" ? "system" : (st.theme == "light" || st.theme == "dark" ? st.theme : "system")
            n.autoNext = st.auto
            n.hideControls = st.hideBar
            n.tm.s = st.t
        }
        s = n
    }

    // MARK: ログイン・登録・ログアウト

    func authenticate(email: String, password: String, register: Bool) async throws {
        let body = try JSONEncoder().encode(AuthBody(email: email, password: password))
        let data = try await SyncClient.request(base: s.serverURL, path: register ? "/api/auth/register" : "/api/auth/login", method: "POST", body: body, token: nil)
        let r = try JSONDecoder().decode(AuthResult.self, from: data)
        s.acctToken = r.token
        s.acctEmail = r.email ?? email.lowercased()
        s.lastSync = nil
        await syncNow()
    }

    func logout() async {
        let token = s.acctToken
        let base = s.serverURL
        s.acctToken = nil
        s.acctEmail = nil
        s.lastSync = nil
        syncMessage = ""
        syncTask?.cancel()
        if let token = token {
            _ = try? await SyncClient.request(base: base, path: "/api/auth/logout", method: "POST", body: nil, token: token)
        }
    }

    // MARK: 同期

    func scheduleSync(after seconds: Double = 20) {
        guard loggedIn else { return }
        if syncing { syncDirty = true; return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.syncNow()
        }
    }

    func syncIfStale() async {
        guard loggedIn else { return }
        if let t = s.lastSync, AppStore.nowMs() - t < 30_000 { return }
        await syncNow()
    }

    func syncNow() async {
        guard loggedIn, let token = s.acctToken else { return }
        if syncing { syncDirty = true; return }
        syncing = true
        syncDirty = false
        syncMessage = "同期中…"
        defer {
            syncing = false
            if syncDirty && loggedIn { scheduleSync() }
        }
        do {
            let body = try JSONEncoder().encode(SyncPushBody(data: buildSyncDoc()))
            let data = try await SyncClient.request(base: s.serverURL, path: "/api/sync", method: "POST", body: body, token: token)
            let env = try JSONDecoder().decode(SyncEnvelope.self, from: data)
            applySyncDoc(env.data)
            applyingRemote = true
            s.lastSync = AppStore.nowMs()
            applyingRemote = false
            syncMessage = ""
        } catch let e as SyncFailure {
            if e.status == 401 {
                s.acctToken = nil
                s.acctEmail = nil
                syncMessage = "ログインの期限が切れました。もう一度ログインしてください"
            } else {
                syncMessage = "同期できませんでした(\(e.message))"
            }
        } catch {
            syncMessage = "同期できませんでした(通信を確認してください)"
        }
    }
}
