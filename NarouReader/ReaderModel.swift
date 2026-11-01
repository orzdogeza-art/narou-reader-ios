import SwiftUI

struct LoadedEpisode: Identifiable {
    let n: Int
    let title: String
    let paragraphs: [String]
    var id: Int { n }
}

/// 読む画面の状態。読み上げ位置・読み込み済みの話・既読の記録をまとめて扱う
@MainActor
final class ReaderModel: ObservableObject {
    let ncode: String
    let novelTitle: String
    let episodes: [EpisodeInfo]
    let isShort: Bool
    let store: AppStore
    let speaker: Speaker

    @Published var loaded: [LoadedEpisode] = []
    @Published var cursorEp: Int = 0
    @Published var cursorPara: Int = 0
    @Published var errorMessage: String? = nil
    @Published var scrollKey: Int? = nil
    @Published var isLoading: Bool = false

    private var loading = false
    private var userScrolled = false
    private var saveTask: Task<Void, Never>? = nil
    private var queuedLast: Int = 0

    static func key(_ ep: Int, _ para: Int) -> Int { return ep * 100000 + para }

    init(ncode: String, novelTitle: String, episodes: [EpisodeInfo], isShort: Bool, store: AppStore) {
        self.ncode = ncode
        self.novelTitle = novelTitle
        self.episodes = episodes
        self.isShort = isShort
        self.store = store
        self.speaker = store.speaker
        bindSpeaker()
    }

    private func bindSpeaker() {
        speaker.onProgress = { [weak self] ep, para in
            self?.handleProgress(ep, para)
        }
        speaker.onSectionFinished = { [weak self] ep in
            guard let self = self else { return }
            self.store.setRead(self.ncode, ep, true)
        }
        speaker.onNext = { [weak self] in
            guard let self = self else { return }
            Task { await self.next() }
        }
        speaker.onPrev = { [weak self] in
            guard let self = self else { return }
            Task { await self.previous() }
        }
        speaker.onPlayRequest = { [weak self] in
            self?.play()
        }
    }

    // MARK: 話の並び

    private func episodeNumbers() -> [Int] {
        return isShort ? [0] : episodes.map { $0.n }
    }

    func neighbor(of n: Int, _ dir: Int) -> Int? {
        if isShort { return nil }
        guard let i = episodes.firstIndex(where: { $0.n == n }) else { return nil }
        let j = i + dir
        return episodes.indices.contains(j) ? episodes[j].n : nil
    }

    func title(of n: Int) -> String {
        if isShort { return novelTitle }
        return episodes.first(where: { $0.n == n })?.title ?? ""
    }

    var canLoadPrevious: Bool {
        guard let first = loaded.first else { return false }
        return neighbor(of: first.n, -1) != nil
    }

    // MARK: 読み込み

    private func load(_ n: Int) async -> LoadedEpisode? {
        do {
            let e = try await NarouClient.episode(ncode, n)
            return LoadedEpisode(n: n, title: e.title, paragraphs: e.paragraphs)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// 指定した話の、指定した段落から開く
    func open(ep: Int, para: Int) async {
        speaker.stop()
        isLoading = true
        defer { isLoading = false }
        guard let e = await load(ep) else { return }
        loaded = [e]
        let p = min(max(para, 0), max(0, e.paragraphs.count - 1))
        cursorEp = ep
        cursorPara = p
        userScrolled = false
        store.setPos(ncode, ep, p)
        try? await Task.sleep(nanoseconds: 250_000_000)
        scrollKey = ReaderModel.key(ep, p)
    }

    @discardableResult
    func loadNext() async -> Bool {
        if loading { return false }
        guard let last = loaded.last, let nx = neighbor(of: last.n, 1) else { return false }
        loading = true
        defer { loading = false }
        guard let e = await load(nx) else { return false }
        loaded.append(e)
        return true
    }

    @discardableResult
    func loadPrevious() async -> Bool {
        if loading { return false }
        guard let first = loaded.first, let pv = neighbor(of: first.n, -1) else { return false }
        loading = true
        defer { loading = false }
        guard let e = await load(pv) else { return false }
        loaded.insert(e, at: 0)
        return true
    }

    // MARK: 読み上げ

    private func applySettings() {
        speaker.speed = store.s.speed
        speaker.voiceID = store.s.voiceID
        speaker.nowPlayingTitle = novelTitle
        speaker.nowPlayingSubtitle = isShort ? "" : "第\(cursorEp)話 \(title(of: cursorEp))"
    }

    func play() {
        if speaker.isPaused {
            speaker.resume()
            return
        }
        guard let ep = loaded.first(where: { $0.n == cursorEp }) else { return }
        applySettings()
        let section = SpeakSection(ep: ep.n, chunks: Chunker.chunks(from: ep.paragraphs))
        speaker.start(section, fromPara: cursorPara)
        queuedLast = ep.n
        Task { await topUp() }
    }

    func pause() { speaker.pause() }

    func stopAll() { speaker.stop() }

    /// 「続けて読む」のとき、次の話以降も先に読み上げキューへ積む(画面を消す前に済ませる)
    private func topUp() async {
        if !store.s.autoNext { return }
        var rounds = 0
        while rounds < 4 && (speaker.isPlaying || speaker.isPaused) {
            rounds += 1
            let nums = episodeNumbers()
            guard let curIdx = nums.firstIndex(of: cursorEp), let lastIdx = nums.firstIndex(of: queuedLast) else { break }
            if lastIdx - curIdx >= 2 { break }
            guard let nx = neighbor(of: queuedLast, 1) else { break }
            var found = loaded.first(where: { $0.n == nx })
            if found == nil {
                _ = await loadNext()
                found = loaded.first(where: { $0.n == nx })
            }
            guard let e = found else { break }
            speaker.enqueue(SpeakSection(ep: e.n, chunks: Chunker.chunks(from: e.paragraphs)))
            queuedLast = e.n
        }
    }

    private func handleProgress(_ ep: Int, _ para: Int) {
        if ep > cursorEp {
            for n in episodeNumbers() where n >= cursorEp && n < ep {
                store.setRead(ncode, n, true)
            }
        }
        cursorEp = ep
        cursorPara = para
        scrollKey = ReaderModel.key(ep, para)
        store.setPos(ncode, ep, para)
        Task { await topUp() }
    }

    /// 指定位置へ移動。読み上げ中(または一時停止中)なら、そこから読み直す
    func jump(ep: Int, para: Int) {
        let wasActive = speaker.isPlaying || speaker.isPaused
        speaker.stop()
        cursorEp = ep
        cursorPara = para
        scrollKey = ReaderModel.key(ep, para)
        store.setPos(ncode, ep, para)
        if wasActive { play() }
    }

    func next() async {
        guard let nx = neighbor(of: cursorEp, 1) else { return }
        if !loaded.contains(where: { $0.n == nx }) { _ = await loadNext() }
        guard loaded.contains(where: { $0.n == nx }) else { return }
        if let cur = loaded.first(where: { $0.n == cursorEp }), cur.paragraphs.count > 0,
           Double(cursorPara) / Double(cur.paragraphs.count) >= 0.8 {
            store.setRead(ncode, cursorEp, true)     // 8割以上読んでいれば、既読にして次へ
        }
        jump(ep: nx, para: 0)
    }

    func previous() async {
        if cursorPara > 0 {                           // 話の途中なら、その話の頭へ
            jump(ep: cursorEp, para: 0)
            return
        }
        guard let pv = neighbor(of: cursorEp, -1) else { return }
        if !loaded.contains(where: { $0.n == pv }) { _ = await loadPrevious() }
        guard loaded.contains(where: { $0.n == pv }) else { return }
        jump(ep: pv, para: 0)
    }

    func restartIfPlaying() {
        if speaker.isPlaying || speaker.isPaused { jump(ep: cursorEp, para: cursorPara) }
    }

    func tap(ep: Int, para: Int) {
        jump(ep: ep, para: para)
    }

    // MARK: 自分で読むとき(スクロール)

    func handleFrames(_ frames: [Int: CGFloat]) {
        if speaker.isPlaying || speaker.isPaused { return }
        var best: Int? = nil
        var bestY: CGFloat = -CGFloat.greatestFiniteMagnitude
        for (k, y) in frames where y <= 120 && y > bestY {
            best = k
            bestY = y
        }
        if best == nil { best = frames.min(by: { $0.value < $1.value })?.key }
        guard let k = best else { return }
        let ep = k / 100000
        let para = k % 100000
        if ep == cursorEp && para == cursorPara { return }
        cursorEp = ep
        cursorPara = para
        userScrolled = true
        saveTask?.cancel()
        let ncode = self.ncode
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            self?.store.setPos(ncode, ep, para)
        }
    }

    /// 話の終わりまでスクロールしてきた
    func reachedEnd(of ep: Int) {
        if userScrolled || speaker.isPlaying {
            store.setRead(ncode, ep, true)
        }
        if ep == loaded.last?.n {
            Task { await loadNext() }
        }
    }
}
