import Foundation

struct SpeakChunk {
    let text: String
    let para: Int
}

struct SpeakSection {
    let ep: Int
    let chunks: [SpeakChunk]
}

/// 段落を、読み上げやすい長さ(約60文字、最大約100文字)の文に分ける
enum Chunker {
    static func chunks(from paragraphs: [String]) -> [SpeakChunk] {
        var out: [SpeakChunk] = []
        for (pi, raw) in paragraphs.enumerated() {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            var parts: [String] = []
            for sentence in sentences(text) {
                var t = sentence
                while t.count > 100 {
                    let cut = cutIndex(t)
                    parts.append(String(t.prefix(cut)))
                    t = String(t.dropFirst(cut))
                }
                if !t.isEmpty { parts.append(t) }
            }
            var buf = ""
            for s in parts {
                if !buf.isEmpty && (buf.count + s.count) > 60 {
                    out.append(SpeakChunk(text: buf, para: pi))
                    buf = s
                } else {
                    buf += s
                }
            }
            if !buf.isEmpty { out.append(SpeakChunk(text: buf, para: pi)) }
        }
        return out
    }

    private static func sentences(_ text: String) -> [String] {
        let terminators: Set<Character> = ["。", "！", "？", "!", "?"]
        let closers: Set<Character> = ["」", "』", "）", ")", "”"]
        var result: [String] = []
        var buf = ""
        var prevTerm = false
        for ch in text {
            if prevTerm && !closers.contains(ch) && !terminators.contains(ch) {
                result.append(buf)
                buf = ""
            }
            buf.append(ch)
            prevTerm = terminators.contains(ch) || (prevTerm && closers.contains(ch))
        }
        if !buf.isEmpty { result.append(buf) }
        return result
    }

    /// 100文字以内で、最後の「、」の直後(なければ100文字目)
    private static func cutIndex(_ t: String) -> Int {
        let chars = Array(t)
        var k = -1
        let limit = min(100, chars.count)
        for i in 0..<limit where chars[i] == "、" { k = i }
        return k >= 20 ? k + 1 : 100
    }
}
