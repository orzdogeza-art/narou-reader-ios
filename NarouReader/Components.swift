import SwiftUI

/// 検索・ランキングに出す、作品1件ぶんの表示
struct NovelCard: View {
    @EnvironmentObject var store: AppStore
    let novel: NovelSummary
    var rank: Int? = nil
    var periodLabel: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let r = rank {
                RankBadge(rank: r)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(novel.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Text(metaLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(pointLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !novel.story.isEmpty {
                    Text(novel.story.replacingOccurrences(of: "\n", with: " "))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button {
                store.toggleFav(ncode: novel.ncode, title: novel.title, total: novel.totalEpisodes)
            } label: {
                Image(systemName: store.isFav(novel.ncode) ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundColor(store.isFav(novel.ncode) ? .yellow : .gray)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var metaLine: String {
        var kind = "短編"
        if !novel.isShort {
            kind = (novel.isEnded ? "完結" : "連載中") + " 全\(novel.totalEpisodes)話"
        }
        var parts: [String] = [novel.writer, kind]
        if let g = Genres.names[novel.genre] { parts.append(g) }
        return parts.joined(separator: " ・ ")
    }

    private var pointLine: String {
        let len = "\(novel.length)文字"
        if let p = novel.periodPoint {
            return "\(periodLabel) \(p)pt ・ \(len)"
        }
        return "\(novel.globalPoint)pt ・ \(len)"
    }
}

struct RankBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.system(size: 13, weight: .bold))
            .frame(width: 30, height: 30)
            .background(color)
            .foregroundColor(rank <= 3 ? Color.black.opacity(0.75) : Color.secondary)
            .clipShape(Circle())
    }

    private var color: Color {
        switch rank {
        case 1: return Color(red: 0.95, green: 0.76, blue: 0.19)
        case 2: return Color(red: 0.78, green: 0.80, blue: 0.83)
        case 3: return Color(red: 0.85, green: 0.63, blue: 0.40)
        default: return Color.gray.opacity(0.2)
        }
    }
}

/// お気に入り・履歴の1行
struct StoredNovelRow: View {
    @EnvironmentObject var store: AppStore
    let ncode: String
    let title: String
    let total: Int
    var showBadges: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title.isEmpty ? ncode : title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                if showBadges && store.newCount(ncode) > 0 {
                    Text("更新 +\(store.newCount(ncode))話")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            Text(metaText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var metaText: String {
        let unread = max(0, total - store.readCount(ncode))
        if showBadges {
            return "\(ncode) ・ 全\(total)話 ・ 未読\(unread)話"
        }
        return "\(ncode) ・ 全\(total)話"
    }
}
