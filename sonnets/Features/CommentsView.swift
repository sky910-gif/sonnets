import SwiftUI

struct CommentsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PluginManager.self) private var plugins

    let track: MusicItem
    @State private var comments: [MusicComment] = []
    @State private var page = 0
    @State private var isEnd = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                content
            }
            .navigationTitle("音乐评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: track.stableID) { await loadFirstPage() }
    }

    @ViewBuilder
    private var content: some View {
        if !plugins.supportsComments(for: track) {
            ContentUnavailableView(
                "该平台暂不支持评论",
                systemImage: "bubble.left.and.exclamationmark.bubble.right",
                description: Text("\(track.platform) 插件没有提供评论接口")
            )
        } else if isLoading && comments.isEmpty {
            ProgressView("正在读取评论…")
        } else if let errorMessage, comments.isEmpty {
            ContentUnavailableView {
                Label("评论加载失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试") { Task { await load(page: 1, replacing: true) } }
                    .buttonStyle(.borderedProminent)
            }
        } else if comments.isEmpty {
            ContentUnavailableView("暂无评论", systemImage: "bubble.left", description: Text("这首音乐还没有可展示的评论"))
        } else {
            commentsList
        }
    }

    private var commentsList: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    RemoteArtwork(urlString: track.artwork, cornerRadius: 10)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.headline).lineLimit(1)
                        Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("评论 · \(track.platform)") {
                ForEach(comments) { comment in
                    MusicCommentRow(comment: comment)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if !isEnd {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Button("加载更多") { Task { await load(page: page + 1) } }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .onAppear {
                        if !isLoading { Task { await load(page: page + 1) } }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load(page: 1, replacing: true) }
    }

    private func loadFirstPage() async {
        comments = []
        page = 0
        isEnd = false
        errorMessage = nil
        guard plugins.supportsComments(for: track) else { return }
        await load(page: 1, replacing: true)
    }

    private func load(page targetPage: Int, replacing: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await plugins.comments(for: track, page: targetPage)
            let existing = replacing ? Set<String>() : Set(comments.map(\.id))
            let newComments = result.comments.filter { !existing.contains($0.id) }
            comments = replacing ? newComments : comments + newComments
            page = targetPage
            isEnd = result.isEnd || newComments.isEmpty
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MusicCommentRow: View {
    let comment: MusicComment
    var isReply = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            RemoteArtwork(urlString: comment.avatar, cornerRadius: isReply ? 17 : 21, symbol: "person.fill")
                .frame(width: isReply ? 34 : 42, height: isReply ? 34 : 42)

            VStack(alignment: .leading, spacing: 7) {
                Text(comment.nickname)
                    .font(isReply ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(comment.content.isEmpty ? "…" : comment.content)
                    .font(isReply ? .subheadline : .body)
                    .textSelection(.enabled)

                if !metadata.isEmpty {
                    Text(metadata.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !isReply, !comment.replies.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(comment.replies.prefix(3))) { reply in
                            MusicCommentRow(comment: reply, isReply: true)
                        }
                        if comment.replies.count > 3 {
                            Text("另有 \(comment.replies.count - 3) 条回复")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, isReply ? 1 : 6)
    }

    private var metadata: [String] {
        var values: [String] = []
        if let date = comment.createdAt {
            values.append(date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
        }
        if !comment.location.isEmpty { values.append(comment.location) }
        if comment.likes > 0 { values.append("\(comment.likes) 赞") }
        return values
    }
}
