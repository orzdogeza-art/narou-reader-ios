import SwiftUI

/// この iPhone の中に保存するデータ(お気に入り・既読・読んだ位置・設定)
struct PersistedState: Codable {
    var favs: [String: FavoriteNovel] = [:]
    var read: [String: [Int]] = [:]            // 作品 -> 既読の話番号
    var pos: [String: [String: Int]] = [:]     // 作品 -> (話番号 -> 読んだ段落番号)
    var last: [String: Int] = [:]              // 作品 -> 最後に開いた話
    var recent: [RecentNovel] = []
    var speed: Double = 1.2
    var voiceID: String = ""
    var fontSize: Double = 18
    var lineSpacing: Double = 8
    var theme: String = "system"               // system / light / dark
    var autoNext: Bool = true
    var hideControls: Bool = false
}

@MainActor
final class AppStore: ObservableObject {
    @Published var s: PersistedState {
        didSet { save() }
    }
    private let key = "narou-native-v1"
    let speaker = Speaker()   // 読み上げエンジンは、アプリ全体で1つだけ

    init() {
        if let d = UserDefaults.standard.data(forKey: "narou-native-v1"),
           let v = try? JSONDecoder().decode(PersistedState.self, from: d) {
            s = v
        } else {
            s = PersistedState()
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    var colorScheme: ColorScheme? {
        switch s.theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // MARK: 既読・位置

    func isRead(_ ncode: String, _ n: Int) -> Bool {
        return s.read[ncode]?.contains(n) ?? false
    }

    func setRead(_ ncode: String, _ n: Int, _ value: Bool) {
        var set = Set(s.read[ncode] ?? [])
        if value { set.insert(n) } else { set.remove(n) }
        s.read[ncode] = Array(set).sorted()
        if value { clearPos(ncode, n) }
    }

    func readCount(_ ncode: String) -> Int {
        return s.read[ncode]?.count ?? 0
    }

    func pos(_ ncode: String, _ n: Int) -> Int? {
        return s.pos[ncode]?[String(n)]
    }

    func setPos(_ ncode: String, _ n: Int, _ para: Int) {
        var d = s.pos[ncode] ?? [:]
        if para > 0 { d[String(n)] = para } else { d.removeValue(forKey: String(n)) }
        s.pos[ncode] = d
        s.last[ncode] = n
    }

    func clearPos(_ ncode: String, _ n: Int) {
        var d = s.pos[ncode] ?? [:]
        d.removeValue(forKey: String(n))
        s.pos[ncode] = d
    }

    func resetProgress(_ ncode: String) {
        s.read[ncode] = []
        s.pos[ncode] = [:]
        s.last.removeValue(forKey: ncode)
    }

    // MARK: お気に入り・履歴

    func isFav(_ ncode: String) -> Bool { s.favs[ncode] != nil }

    func toggleFav(ncode: String, title: String, total: Int) {
        if s.favs[ncode] != nil {
            s.favs.removeValue(forKey: ncode)
        } else {
            s.favs[ncode] = FavoriteNovel(ncode: ncode, title: title, total: total, seen: total)
        }
    }

    func newCount(_ ncode: String) -> Int {
        guard let f = s.favs[ncode] else { return 0 }
        return max(0, f.total - f.seen)
    }

    func markSeen(_ ncode: String, title: String, total: Int) {
        if var f = s.favs[ncode] {
            f.title = title
            f.total = total
            f.seen = total
            s.favs[ncode] = f
        }
        var list = s.recent.filter { $0.ncode != ncode }
        list.insert(RecentNovel(ncode: ncode, title: title, total: total), at: 0)
        s.recent = Array(list.prefix(30))
    }

    func refreshFavorites() async {
        let codes = Array(s.favs.keys)
        if codes.isEmpty { return }
        var start = 0
        while start < codes.count {
            let chunk = Array(codes[start..<min(start + 40, codes.count)])
            start += 40
            if let result = try? await NarouClient.info(ncodes: chunk) {
                for (code, v) in result {
                    if var f = s.favs[code] {
                        f.total = v.total
                        f.title = v.title
                        s.favs[code] = f
                    }
                }
            }
        }
    }
}
