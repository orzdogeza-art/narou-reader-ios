import Foundation

struct EpisodeInfo: Identifiable, Hashable, Codable {
    let n: Int
    let title: String
    var id: Int { n }
}

/// 検索・ランキングで返ってくる作品の情報
struct NovelSummary: Identifiable, Hashable {
    let ncode: String
    let title: String
    let writer: String
    let story: String
    let isShort: Bool
    let isEnded: Bool
    let totalEpisodes: Int
    let length: Int
    let globalPoint: Int
    let genre: Int
    let periodPoint: Int?
    var id: String { ncode }
}

struct FavoriteNovel: Codable, Identifiable, Hashable {
    let ncode: String
    var title: String
    var total: Int      // 最新の話数
    var seen: Int       // 最後に開いたときの話数(増えていたら「更新あり」)
    var id: String { ncode }
}

struct RecentNovel: Codable, Identifiable, Hashable {
    let ncode: String
    var title: String
    var total: Int
    var id: String { ncode }
}

struct Episode {
    var title: String
    var paragraphs: [String]
}

struct NovelRoute: Hashable {
    let ncode: String
}

enum Genres {
    static let names: [Int: String] = [
        101: "異世界恋愛", 102: "現実世界恋愛", 201: "ハイファンタジー", 202: "ローファンタジー",
        301: "純文学", 302: "ヒューマンドラマ", 303: "歴史", 304: "推理", 305: "ホラー",
        306: "アクション", 307: "コメディー", 401: "VRゲーム", 402: "宇宙", 403: "空想科学",
        404: "パニック", 9901: "童話", 9902: "詩", 9903: "エッセイ", 9904: "リプレイ",
        9999: "その他", 9801: "ノンジャンル",
    ]
    static let pickerList: [GenreOption] = [
        GenreOption(id: 101, name: "異世界恋愛"), GenreOption(id: 102, name: "現実世界恋愛"),
        GenreOption(id: 201, name: "ハイファンタジー"), GenreOption(id: 202, name: "ローファンタジー"),
        GenreOption(id: 301, name: "純文学"), GenreOption(id: 302, name: "ヒューマンドラマ"),
        GenreOption(id: 303, name: "歴史"), GenreOption(id: 304, name: "推理"), GenreOption(id: 305, name: "ホラー"),
        GenreOption(id: 306, name: "アクション"), GenreOption(id: 307, name: "コメディー"),
        GenreOption(id: 401, name: "VRゲーム"), GenreOption(id: 402, name: "宇宙"),
        GenreOption(id: 403, name: "空想科学"), GenreOption(id: 404, name: "パニック"),
        GenreOption(id: 9901, name: "童話"), GenreOption(id: 9902, name: "詩"),
        GenreOption(id: 9903, name: "エッセイ"), GenreOption(id: 9904, name: "リプレイ"),
        GenreOption(id: 9999, name: "その他"), GenreOption(id: 9801, name: "ノンジャンル"),
    ]
}

struct GenreOption: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct PeriodOption: Identifiable, Hashable {
    let key: String
    let label: String
    let order: String
    let field: String
    var id: String { key }
}
