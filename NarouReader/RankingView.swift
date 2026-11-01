import SwiftUI

struct RankingView: View {
    @State private var period = "d"
    @State private var genre: Int = 0          // 0 = 全ジャンル
    @State private var type = ""
    @State private var items: [NovelSummary] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private var periodLabel: String {
        return NarouClient.periods.first(where: { $0.key == period })?.label ?? ""
    }

    private var filterKey: String { "\(period)-\(genre)-\(type)" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("期間", selection: $period) {
                        ForEach(NarouClient.periods) { p in
                            Text(p.label).tag(p.key)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Picker("ジャンル", selection: $genre) {
                            Text("全ジャンル").tag(0)
                            ForEach(Genres.pickerList) { g in
                                Text(g.name).tag(g.id)
                            }
                        }
                        Spacer()
                        Picker("種別", selection: $type) {
                            Text("すべて").tag("")
                            Text("連載中").tag("r")
                            Text("完結済").tag("er")
                            Text("短編").tag("t")
                        }
                    }
                }
                if let msg = errorMessage {
                    Text(msg).foregroundColor(.red).font(.footnote)
                }
                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, n in
                        NavigationLink(value: NovelRoute(ncode: n.ncode)) {
                            NovelCard(novel: n, rank: idx + 1, periodLabel: periodLabel)
                        }
                    }
                    if items.count < total && items.count < 2000 {
                        Button("もっと見る") { Task { await load(more: true) } }
                    }
                } header: {
                    Text("\(periodLabel)ポイント順")
                }
            }
            .navigationTitle("ランキング")
            .navigationDestination(for: NovelRoute.self) { route in
                NovelView(ncode: route.ncode)
            }
            .overlay {
                if isLoading && items.isEmpty { ProgressView() }
            }
            .task(id: filterKey) { await load(more: false) }
            .refreshable { await load(more: false) }
        }
    }

    private func load(more: Bool) async {
        if !more { items = [] }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let r = try await NarouClient.rank(period: period, genre: genre == 0 ? nil : genre, type: type, start: items.count + 1)
            total = r.total
            items.append(contentsOf: r.items)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
