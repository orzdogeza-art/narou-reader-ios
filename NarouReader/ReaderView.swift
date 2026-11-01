import SwiftUI

/// 各段落の位置(スクロールで見えている段落を調べる用)
struct ParaFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ReaderView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var speaker: Speaker
    @StateObject private var model: ReaderModel
    @State private var showSettings = false

    let startEp: Int
    let startPara: Int

    init(ncode: String, title: String, episodes: [EpisodeInfo], isShort: Bool,
         startEp: Int, startPara: Int, store: AppStore) {
        self.startEp = startEp
        self.startPara = startPara
        _speaker = ObservedObject(wrappedValue: store.speaker)
        _model = StateObject(wrappedValue: ReaderModel(ncode: ncode, novelTitle: title, episodes: episodes, isShort: isShort, store: store))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.canLoadPrevious {
                            Button("↑ 前の話を読み込む") { Task { await model.loadPrevious() } }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        ForEach(model.loaded) { ep in
                            episodeBlock(ep)
                        }
                        Color.clear.frame(height: store.s.hideControls ? 80 : 170)
                    }
                    .padding(.horizontal, 16)
                }
                .coordinateSpace(name: "reader")
                .onPreferenceChange(ParaFramesKey.self) { frames in
                    Task { @MainActor in model.handleFrames(frames) }
                }
                .onChange(of: model.scrollKey) { key in
                    if let k = key {
                        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(k, anchor: .center) }
                    }
                }
            }
            if store.s.hideControls {
                HStack {
                    Spacer()
                    Button { store.s.hideControls = false } label: {
                        Image(systemName: "slider.horizontal.3")
                            .padding(12)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
                }
            } else {
                controls
            }
            if model.isLoading { ProgressView().padding(.bottom, 200) }
        }
        .navigationTitle(model.novelTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { store.s.hideControls.toggle() } label: {
                    Image(systemName: store.s.hideControls ? "eye" : "eye.slash")
                }
                Button { showSettings = true } label: { Image(systemName: "textformat.size") }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsForm(onSpeechSettingChanged: { model.restartIfPlaying() })
                    .navigationTitle("読み上げ・表示の設定")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showSettings = false } }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("エラー", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.open(ep: startEp, para: startPara) }
        .onDisappear { model.stopAll() }
    }

    // MARK: 本文

    private func episodeBlock(_ ep: LoadedEpisode) -> some View {
        let active = speaker.isPlaying || speaker.isPaused
        return VStack(alignment: .leading, spacing: 0) {
            if !model.isShort {
                Text("第\(ep.n)話").font(.footnote).foregroundColor(.secondary).padding(.top, 22)
            }
            Text(ep.title).font(.title2.bold()).padding(.top, 2).padding(.bottom, 10)
            ForEach(Array(ep.paragraphs.enumerated()), id: \.offset) { idx, text in
                paragraphRow(ep: ep.n, idx: idx, text: text, highlighted: active && model.cursorEp == ep.n && model.cursorPara == idx)
            }
            endBar(ep)
        }
    }

    private func paragraphRow(ep: Int, idx: Int, text: String, highlighted: Bool) -> some View {
        let key = ReaderModel.key(ep, idx)
        return Text(text.isEmpty ? " " : text)
            .font(.system(size: store.s.fontSize))
            .lineSpacing(store.s.lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, text.isEmpty ? 2 : 5)
            .padding(.horizontal, 6)
            .background(highlighted ? Color.yellow.opacity(0.32) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: ParaFramesKey.self, value: [key: g.frame(in: .named("reader")).minY])
                }
            )
            .id(key)
            .onTapGesture { model.tap(ep: ep, para: idx) }
    }

    private func endBar(_ ep: LoadedEpisode) -> some View {
        let nextN = model.neighbor(of: ep.n, 1)
        return VStack(spacing: 2) {
            Text(model.isShort ? "おわり" : "第\(ep.n)話 おわり").font(.subheadline.bold())
            if let nx = nextN {
                Text("▼ 第\(nx)話 \(model.title(of: nx))").font(.footnote)
            }
        }
        .foregroundColor(.accentColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.accentColor.opacity(0.12))
        .overlay(alignment: .top) { Rectangle().fill(Color.accentColor).frame(height: 4) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.accentColor).frame(height: 4) }
        .padding(.vertical, 26)
        .onAppear { model.reachedEnd(of: ep.n) }
    }

    // MARK: 操作バー

    private var controls: some View {
        HStack(spacing: 34) {
            Button { Task { await model.previous() } } label: {
                Image(systemName: "backward.end.fill").font(.title2)
            }
            Button {
                if speaker.isPlaying { model.pause() } else { model.play() }
            } label: {
                Image(systemName: speaker.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 58))
            }
            Button { Task { await model.next() } } label: {
                Image(systemName: "forward.end.fill").font(.title2)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}
