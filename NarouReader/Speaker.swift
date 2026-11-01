import AVFoundation
import MediaPlayer

/// 読み上げエンジン。
/// 1話ぶんの文を、最初から全部まとめて iPhone の読み上げキューに積む。
/// (1文ごとにアプリが「次を読んで」と指示する方式だと、画面を消したときに指示が止まるため)
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentEp: Int = 0
    @Published private(set) var currentPara: Int = 0

    var onProgress: ((Int, Int) -> Void)?       // (話, 段落) を読み始めた
    var onSectionFinished: ((Int) -> Void)?     // 1話ぶんを読み終えた
    var onAllFinished: (() -> Void)?            // 積んだものをすべて読み終えた
    var onNext: (() -> Void)?                   // ロック画面の「次へ」
    var onPrev: (() -> Void)?                   // ロック画面の「前へ」
    var onPlayRequest: (() -> Void)?            // ロック画面の「再生」(止まった状態から)

    var voiceID: String = ""
    var speed: Double = 1.2
    var nowPlayingTitle: String = ""
    var nowPlayingSubtitle: String = ""

    private struct Meta {
        let ep: Int
        let para: Int
        let isLastOfSection: Bool
    }

    private let synth = AVSpeechSynthesizer()
    private var metas: [ObjectIdentifier: Meta] = [:]
    private var utterances: [AVSpeechUtterance] = []
    private var pendingEps: [Int] = []

    override init() {
        super.init()
        synth.delegate = self
        setupRemote()
        observeInterruptions()
    }

    // MARK: 操作

    /// 1話ぶんを、fromPara 段落目から読み始める(読んでいたものは止める)
    func start(_ section: SpeakSection, fromPara: Int) {
        stop()
        activateSession()
        isPlaying = true
        isPaused = false
        enqueue(section, fromPara: fromPara)
        updateNowPlaying()
    }

    /// すでに読んでいるものの後ろに、続きの話を積む
    func enqueue(_ section: SpeakSection, fromPara: Int = 0) {
        let list = section.chunks.filter { $0.para >= fromPara }
        if list.isEmpty {
            DispatchQueue.main.async { self.onSectionFinished?(section.ep) }
            return
        }
        pendingEps.append(section.ep)
        let rate = speechRate()
        let voice = pickVoice()
        for (i, c) in list.enumerated() {
            let u = AVSpeechUtterance(string: c.text)
            u.rate = rate
            u.voice = voice
            u.postUtteranceDelay = 0.05
            metas[ObjectIdentifier(u)] = Meta(ep: section.ep, para: c.para, isLastOfSection: i == list.count - 1)
            utterances.append(u)
            synth.speak(u)
        }
    }

    func pause() {
        if synth.isSpeaking && !synth.isPaused {
            synth.pauseSpeaking(at: .immediate)
            isPlaying = false
            isPaused = true
            updateNowPlaying()
        }
    }

    func resume() {
        if synth.isPaused {
            activateSession()
            synth.continueSpeaking()
            isPlaying = true
            isPaused = false
            updateNowPlaying()
        }
    }

    func stop() {
        metas.removeAll()
        utterances.removeAll()
        pendingEps.removeAll()
        synth.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
        updateNowPlaying()
    }

    // MARK: 設定

    private func speechRate() -> Float {
        let r = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        return min(max(r, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    private func pickVoice() -> AVSpeechSynthesisVoice? {
        if !voiceID.isEmpty, let v = AVSpeechSynthesisVoice(identifier: voiceID) { return v }
        return Speaker.japaneseVoices().first ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }

    static func japaneseVoices() -> [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ja-JP" }
        return all.sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    static func voiceLabel(_ v: AVSpeechSynthesisVoice) -> String {
        var label = v.name
        if v.quality == .premium { label += "(プレミアム)" }
        else if v.quality == .enhanced { label += "(高品質)" }
        return label
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async {
            guard let m = self.metas[id] else { return }
            self.currentEp = m.ep
            self.currentPara = m.para
            self.onProgress?(m.ep, m.para)
            self.updateNowPlaying()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async {
            guard let m = self.metas[id] else { return }
            self.metas.removeValue(forKey: id)
            self.utterances.removeAll { ObjectIdentifier($0) == id }
            if m.isLastOfSection {
                if let i = self.pendingEps.firstIndex(of: m.ep) { self.pendingEps.remove(at: i) }
                self.onSectionFinished?(m.ep)
                if self.pendingEps.isEmpty && self.metas.isEmpty {
                    self.isPlaying = false
                    self.isPaused = false
                    self.updateNowPlaying()
                    self.onAllFinished?()
                }
            }
        }
    }

    // MARK: 音声セッション・ロック画面

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPaused { self.resume() } else { self.onPlayRequest?() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPlaying { self.pause() } else if self.isPaused { self.resume() } else { self.onPlayRequest?() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNext?()
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPrev?()
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle,
            MPMediaItemPropertyArtist: nowPlayingSubtitle,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let info = note.userInfo else { return }
            guard let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            guard let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.pause()
            } else if let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let opts = AVAudioSession.InterruptionOptions(rawValue: optRaw)
                if opts.contains(.shouldResume) { self.resume() }
            }
        }
    }
}
