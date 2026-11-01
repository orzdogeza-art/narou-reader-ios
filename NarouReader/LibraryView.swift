import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: AppStore
    @State private var path = NavigationPath()
    @State private var query = ""

    @State private var results: [NovelSummary] = []
    @State private var total = 0
    @State private var searchedWord = ""
    @State private var showResults = false
    @State private var isSearching = false
    @State private var errorMessage: String? = nil

    @State private var scopeTitle = true
    @State private var scopeStory = false
    @State private var scopeKeyword = false
    @State private var scopeWriter = false
    @State private var order = "hyoka"
    @State private var type = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let msg = errorMessage {
                    Text(msg).foregroundColor(.red).font(.footnote)
                }
                if showResults {
                    searchSection
                }
                favoritesSection
                recentSection
                if store.s.favs.isEmpty && store.s.recent.isEmpty && !showResults {
                    Text("作品名を検索するか、Nコード・URL を入力して始めてください。")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
            }
            .navigationTitle("なろう読み上げ")
            .searchable(text: $query, prompt: "作品名 / Nコード / URL")
            .onSubmit(of: .search) { submit() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { optionsMenu }
            }
            .navigationDestination(for: NovelRoute.self) { route in
                NovelView(ncode: route.ncode)
            }
            .refreshable { await store.refreshFavorites() }
            .task { await store.refreshFavorites() }
            .overlay {
                if isSearching { ProgressView() }
            }
        }
    }

    // MARK: 一覧

    @ViewBuilder
    private var searchSection: some View {
        Section {
            ForEach(results) { n in
                NavigationLink(value: NovelRoute(ncode: n.ncode)) {
                    NovelCard(novel: n)
                }
            }
            if results.count < total && results.count < 2000 {
                Button("もっと見る") { Task { await search(more: true) } }
            }
        } header: {
            HStack {
                Text("「\(searchedWord)」の検索結果 \(total)件")
                Spacer()
                Button("閉じる") { showResults = false }.font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        let codes = sortedFavorites()
        if !codes.isEmpty {
            Section("お気に入り") {
                ForEach(codes) { f in
                    NavigationLink(value: NovelRoute(ncode: f.ncode)) {
                        StoredNovelRow(ncode: f.ncode, title: f.title, total: f.total)
                    }
                }
                .onDelete { idx in
                    for i in idx { store.s.favs.removeValue(forKey: codes[i].ncode) }
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !store.s.recent.isEmpty {
            Section("最近読んだ作品") {
                ForEach(store.s.recent) { r in
                    NavigationLink(value: NovelRoute(ncode: r.ncode)) {
                        StoredNovelRow(ncode: r.ncode, title: r.title, total: r.total, showBadges: false)
                    }
                }
            }
        }
    }

    private func sortedFavorites() -> [FavoriteNovel] {
        let list = Array(store.s.favs.values)
        return list.sorted { a, b in
            let na = store.newCount(a.ncode)
            let nb = store.newCount(b.ncode)
            if na != nb { return na > nb }
            return a.title.localizedCompare(b.title) == .orderedAscending
        }
    }

    // MARK: 検索

    private var optionsMenu: some View {
        Menu {
            Section("検索範囲") {
                Toggle("タイトル", isOn: $scopeTitle)
                Toggle("あらすじ", isOn: $scopeStory)
                Toggle("キーワード", isOn: $scopeKeyword)
                Toggle("作者名", isOn: $scopeWriter)
            }
            Picker("並び順", selection: $order) {
                Text("総合ポイント順").tag("hyoka")
                Text("最新掲載順").tag("new")
                Text("週間ポイント順").tag("weeklypoint")
                Text("月間ポイント順").tag("monthlypoint")
                Text("ブックマーク順").tag("favnovelcnt")
                Text("レビュー順").tag("reviewcnt")
                Text("文字数順").tag("lengthdesc")
            }
            Picker("種別", selection: $type) {
                Text("すべて").tag("")
                Text("連載中").tag("r")
                Text("完結済").tag("er")
                Text("短編").tag("t")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
    }

    private func submit() {
        let v = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return }
        if let code = Self.parseNcode(v) {
            path.append(NovelRoute(ncode: code))
            return
        }
        Task { await search(more: false, word: v) }
    }

    private func search(more: Bool, word: String? = nil) async {
        if !more {
            searchedWord = word ?? searchedWord
            results = []
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let r = try await NarouClient.search(
                word: searchedWord, title: scopeTitle, story: scopeStory, keyword: scopeKeyword, writer: scopeWriter,
                order: order, type: type, start: results.count + 1)
            total = r.total
            results.append(contentsOf: r.items)
            showResults = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func parseNcode(_ s: String) -> String? {
        let pattern = "^(?:https?://)?(?:ncode\\.syosetu\\.com/)?(n\\d{1,6}[a-z]{1,3})(?:/\\d+)?/?$"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1)).lowercased()
    }
}
