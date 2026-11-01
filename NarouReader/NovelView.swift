import SwiftUI

/// 作品ページ: 続きから / 最初から、話数の一覧(既読・途中の表示)
struct NovelView: View {
    let ncode: String
    @EnvironmentObject var store: AppStore

    @State private var title = ""
    @State private var episodes: [EpisodeInfo] = []
    @State private var isShort = false
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    @State private var showReader = false
    @State private var startEp = 0
    @State private var startPara = 0
    @State private var pendingEp: Int? = nil
    @State private var showEpisodeChoice = false
    @State private var showStartConfirm = false
    @State private var showResetConfirm = false

    private var total: Int { isShort ? 1 : episodes.count }

    var body: some View {
        List {
            if let msg = errorMessage {
                Text(msg).foregroundColor(.red)
            }
            if !isLoading && errorMessage == nil {
                Section {
                    Text(title).font(.title3.bold())
                    Text(summaryLine).font(.footnote).foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        Button { resume() } label: {
                            VStack(spacing: 2) {
                                Text(resumeTitle).bold()
                                if !resumeSubtitle.isEmpty { Text(resumeSubtitle).font(.caption2) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        Button { startFromBeginning() } label: {
                            VStack(spacing: 2) {
                                Text("最初から")
                                if !firstSubtitle.isEmpty { Text(firstSubtitle).font(.caption2) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    .buttonStyle(.borderless)
                }
                if !isShort {
                    Section("話数") {
                        ForEach(episodes) { e in
                            episodeRow(e)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if !isShort && !episodes.isEmpty {
                        Menu {
                            Button("全話を既読にする") { markAll(true) }
                            Button("既読をリセット", role: .destructive) { showResetConfirm = true }
                        } label: { Image(systemName: "checkmark.circle") }
                    }
                    Button {
                        store.toggleFav(ncode: ncode, title: title, total: total)
                    } label: {
                        Image(systemName: store.isFav(ncode) ? "star.fill" : "star")
                            .foregroundColor(store.isFav(ncode) ? .yellow : .accentColor)
                    }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationDestination(isPresented: $showReader) {
            ReaderView(ncode: ncode, title: title, episodes: episodes, isShort: isShort,
                       startEp: startEp, startPara: startPara, store: store)
        }
        .confirmationDialog("第\(pendingEp ?? 0)話は途中まで読んでいます", isPresented: $showEpisodeChoice, titleVisibility: .visible) {
            Button("続きから読む") { if let n = pendingEp { openReader(n, store.pos(ncode, n) ?? 0) } }
            Button("最初から読む") { if let n = pendingEp { openReader(n, 0) } }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("最初の話から読み始めます(既読の記録は残ります)", isPresented: $showStartConfirm, titleVisibility: .visible) {
            Button("最初から読む") { openReader(isShort ? 0 : (episodes.first?.n ?? 1), 0) }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("既読の記録をすべて消しますか?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("リセット", role: .destructive) { store.resetProgress(ncode) }
            Button("キャンセル", role: .cancel) {}
        }
        .task { await load() }
    }

    // MARK: 表示

    private var summaryLine: String {
        if isShort { return "\(ncode) ・ 短編" }
        let read = store.readCount(ncode)
        return "\(ncode) ・ 全\(total)話 ・ 既読\(read)話 ・ 未読\(max(0, total - read))話"
    }

    private func episodeRow(_ e: EpisodeInfo) -> some View {
        let read = store.isRead(ncode, e.n)
        let mid = store.pos(ncode, e.n) != nil && !read
        return HStack {
            Button {
                tapEpisode(e.n)
            } label: {
                HStack {
                    Text("\(e.n). \(e.title)")
                        .foregroundColor(read ? .secondary : .primary)
                        .fontWeight(read ? .regular : .semibold)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if read {
                        Text("既読").font(.caption2).foregroundColor(.secondary)
                    } else if mid {
                        Text("途中").font(.caption2.bold()).foregroundColor(.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            Button {
                store.setRead(ncode, e.n, !read)
            } label: {
                Image(systemName: read ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundColor(read ? .accentColor : .gray)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: 続きから / 最初から

    private func resumeTarget() -> (ep: Int, para: Int, fresh: Bool)? {
        if isShort { return (0, store.pos(ncode, 0) ?? 0, false) }
        guard let first = episodes.first else { return nil }
        guard let n = store.s.last[ncode], episodes.contains(where: { $0.n == n }) else {
            return (first.n, 0, true)
        }
        if let p = store.pos(ncode, n) { return (n, p, false) }
        if store.isRead(ncode, n), let nx = episodes.first(where: { $0.n > n }) { return (nx.n, 0, false) }
        return (n, 0, false)
    }

    private var resumeTitle: String {
        guard let t = resumeTarget() else { return "読む" }
        return t.fresh ? "読み始める" : "続きから"
    }

    private var resumeSubtitle: String {
        guard let t = resumeTarget(), !t.fresh, !isShort else { return "" }
        return "第\(t.ep)話" + (t.para > 0 ? "・途中から" : "")
    }

    private var firstSubtitle: String {
        if isShort { return "" }
        return "第\(episodes.first?.n ?? 1)話"
    }

    private func resume() {
        if let t = resumeTarget() { openReader(t.ep, t.para) }
    }

    private func startFromBeginning() {
        if store.readCount(ncode) > 0 || store.s.last[ncode] != nil {
            showStartConfirm = true
        } else {
            openReader(isShort ? 0 : (episodes.first?.n ?? 1), 0)
        }
    }

    private func tapEpisode(_ n: Int) {
        if store.pos(ncode, n) != nil && !store.isRead(ncode, n) {
            pendingEp = n
            showEpisodeChoice = true
        } else {
            openReader(n, 0)
        }
    }

    private func openReader(_ ep: Int, _ para: Int) {
        startEp = ep
        startPara = para
        showReader = true
    }

    private func markAll(_ value: Bool) {
        for e in episodes { store.setRead(ncode, e.n, value) }
    }

    // MARK: 読み込み

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let r = try await NarouClient.index(ncode)
            title = r.title
            episodes = r.episodes
            isShort = r.episodes.isEmpty
            store.markSeen(ncode, title: r.title, total: isShort ? 1 : r.episodes.count)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
