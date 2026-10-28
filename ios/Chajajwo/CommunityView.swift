import SwiftUI

private enum CommunityPalette {
    static let ink = Color(hex: 0x1B302E)
    static let muted = Color(hex: 0x667774)
    static let bg = Color(hex: 0xF6F8F7)
    static let green = Color.cjTeal
    static let border = Color(hex: 0xE1E8E6)
}

private let communityTags = ["시험·수업", "대학원·연구", "취업·인턴", "학교생활", "기타"]

private func communityTime(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let days = Int(Date().timeIntervalSince(d) / 86400)
    if days < 1 { return "오늘" }
    if days < 7 { return "\(days)일 전" }
    return d.formatted(.dateTime.year().month().day())
}

struct CommunityView: View {
    @StateObject private var api = CommunityAPI()
    @State private var board: CommunityBoard = .all
    @State private var selectedTag: String?
    @State private var query = ""
    @State private var savedOnly = false
    @State private var posts: [CommunityPost] = []
    @State private var error: String?
    @State private var loading = false
    @State private var hasMore = true
    @State private var loadedAt = Date.distantPast
    @State private var showEditor = false
    @State private var showProfile = false
    @State private var showAdmin = false

    var body: some View {
        NavigationStack {
            Group {
                if api.configuration == nil {
                    ContentUnavailableView("커뮤니티 연결이 필요해요", systemImage: "network.slash",
                                           description: Text("Supabase 데이터베이스와 앱 연결 정보를 설정하면 사랑방을 이용할 수 있어요."))
                } else if !api.authenticated {
                    CommunityAuthView(api: api)
                } else {
                    feedView
                }
            }
            .navigationTitle("사랑방")
            .toolbar {
                if api.authenticated {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showProfile = true } label: { Image(systemName: "person.crop.circle") }
                            .accessibilityLabel("커뮤니티 프로필")
                    }
                    if api.profile?.isModerator == true {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showAdmin = true } label: { Image(systemName: "checkmark.shield") }
                                .accessibilityLabel("운영진 관리")
                        }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                CommunityPostDetailView(api: api, postID: id) { Task { await load(reset: true) } }
            }
            .sheet(isPresented: $showEditor, onDismiss: { Task { await load(reset: true) } }) {
                CommunityPostEditor(api: api)
            }
            .sheet(isPresented: $showProfile) {
                CommunityProfileView(api: api) {
                    posts.removeAll()
                    showProfile = false
                }
            }
            .sheet(isPresented: $showAdmin, onDismiss: { Task { await load(reset: true) } }) {
                CommunityModeratorView(api: api)
            }
            .onAppear {
                // 탭에 들어올 때마다 불린다. 로그인돼 있고 1분 안에 받은 목록이 있으면 다시 받지 않는다(새로고침은 그대로).
                // .task와 달리 탭을 넘겨도 받던 요청이 취소되지 않는다.
                Task {
                    if !api.authenticated { await api.restore() }
                    if api.authenticated, Date().timeIntervalSince(loadedAt) > 60 { await load(reset: true) }
                }
            }
            .onChange(of: api.authenticated) { _, loggedIn in
                if loggedIn { Task { await load(reset: true) } }
                else { posts = [] }
            }
        }
    }

    private var feedView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CommunityPalette.muted)
                    TextField("글 제목 또는 내용 검색", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await load(reset: true) } }
                    if !query.isEmpty {
                        Button { query = ""; Task { await load(reset: true) } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(CommunityPalette.muted)
                        }
                    }
                    Button { Task { await load(reset: true) } } label: {
                        Text("검색").font(.subheadline.weight(.semibold))
                    }
                }
                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(CommunityBoard.allCases) { option in
                            Button { board = option; selectedTag = nil; Task { await load(reset: true) } } label: {
                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(board == option ? Color.white : CommunityPalette.ink)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(board == option ? CommunityPalette.green : .white, in: Capsule())
                            }
                        }
                    }
                }
                if board == .goodwill || board == .all {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(communityTags, id: \.self) { tag in
                                Button { selectedTag = selectedTag == tag ? nil : tag; Task { await load(reset: true) } } label: {
                                    Text(tag)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(selectedTag == tag ? Color.white : CommunityPalette.muted)
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(selectedTag == tag ? CommunityPalette.green : .white, in: Capsule())
                                }
                            }
                        }
                    }
                }
                HStack {
                    Button {
                        savedOnly.toggle()
                        Task { await load(reset: true) }
                    } label: {
                        Label("스크랩한 글", systemImage: savedOnly ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(savedOnly ? CommunityPalette.green : CommunityPalette.muted)
                    }
                    Spacer()
                    Button { Task { await load(reset: true) } } label: {
                        Label("새로고침", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("게시글 새로고침")
                }
                .font(.caption.weight(.medium))
            }
            .padding(14)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if loading && posts.isEmpty { ProgressView().padding(30) }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote).padding() }
                    if !loading && posts.isEmpty && error == nil {
                        ContentUnavailableView("게시글이 없어요", systemImage: "text.bubble",
                                               description: Text("첫 이야기를 남겨 주세요."))
                    }
                    ForEach(posts) { post in
                        NavigationLink(value: post.id) { CommunityPostRow(post: post) }
                            .buttonStyle(.plain)
                    }
                    if hasMore && !posts.isEmpty {
                        Button("더 보기") { Task { await load(reset: false) } }
                            .disabled(loading).padding(16)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 90)
            }
            .refreshable { await load(reset: true) }
            .overlay(alignment: .bottomTrailing) {
                Button { showEditor = true } label: {
                    Label("글쓰기", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .background(CommunityPalette.green, in: Capsule())
                        .shadow(radius: 4)
                }
                .padding(.trailing, 20).padding(.bottom, 20)
            }
        }
        .background(CommunityPalette.bg)
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let more = try await api.feed(board: board, query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                                          tag: selectedTag, savedOnly: savedOnly, offset: reset ? 0 : posts.count)
            if reset { posts = more; loadedAt = Date() } else { posts += more }
            hasMore = more.count == 30
        } catch { self.error = error.localizedDescription }
    }
}

private struct CommunityPostRow: View {
    let post: CommunityPost
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(CommunityBoard(rawValue: post.board)?.title ?? post.board)
                    .font(.caption.weight(.bold)).foregroundStyle(CommunityPalette.green)
                ForEach(post.tags.prefix(2), id: \.self) { tag in
                    Text(tag).font(.caption2).foregroundStyle(CommunityPalette.muted)
                }
                Spacer()
                Text(communityTime(post.createdAt)).font(.caption2).foregroundStyle(CommunityPalette.muted)
            }
            Text(post.title).font(.body.weight(.semibold)).foregroundStyle(CommunityPalette.ink)
            Text(post.body).lineLimit(2).font(.subheadline).foregroundStyle(CommunityPalette.muted)
            HStack(spacing: 12) {
                Label(post.authorDisplay, systemImage: "person.crop.circle")
                Label("\(post.commentCount)", systemImage: "bubble.right")
                Label("\(post.likeCount)", systemImage: "hand.thumbsup")
                if post.isSaved { Image(systemName: "bookmark.fill") }
                Spacer()
                if post.reviewState == "source_checked" { Text("출처 확인") }
                if post.reviewState == "recommended" { Text("운영진 추천") }
            }
            .font(.caption2).foregroundStyle(CommunityPalette.muted)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(CommunityPalette.border, lineWidth: 0.6))
    }
}

private struct CommunityAuthView: View {
    @ObservedObject var api: CommunityAPI
    @State private var email = ""
    @State private var password = ""
    @State private var signup = false
    @State private var working = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "person.2.wave.2.fill").font(.largeTitle).foregroundStyle(CommunityPalette.green)
                Text("서울대 구성원의 이야기가 모이는 곳")
                    .font(.title2.weight(.bold))
                Text("글·댓글 작성과 익명 게시를 위해 계정이 필요해요. 학교 인증은 추후 도입할 예정입니다.")
                    .font(.subheadline).foregroundStyle(CommunityPalette.muted)
                TextField("이메일", text: $email).keyboardType(.emailAddress).textContentType(.username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("비밀번호 (6자 이상)", text: $password).textContentType(signup ? .newPassword : .password)
                    .textFieldStyle(.roundedBorder)
                if let message { Text(message).font(.footnote).foregroundStyle(CommunityPalette.ink) }
                Button {
                    Task {
                        working = true; defer { working = false }
                        do {
                            if signup {
                                let active = try await api.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password)
                                if !active { message = "인증 메일을 확인한 뒤 로그인해 주세요." }
                            } else { try await api.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
                        } catch { message = error.localizedDescription }
                    }
                } label: {
                    Text(signup ? "회원가입" : "로그인")
                        .font(.headline).frame(maxWidth: .infinity).padding(14)
                        .foregroundStyle(.white).background(CommunityPalette.green, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(working || !email.contains("@") || password.count < 6)
                Button(signup ? "이미 계정이 있나요? 로그인" : "처음이신가요? 회원가입") {
                    signup.toggle(); message = nil
                }
                .font(.subheadline)
            }
            .padding(24)
        }
        .background(CommunityPalette.bg)
    }
}

private struct CommunityPostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var api: CommunityAPI
    @State private var board: CommunityBoard = .goodwill
    @State private var title = ""
    @State private var bodyText = ""
    @State private var identity: CommunityIdentity = .anonymous
    @State private var tags: Set<String> = []
    @State private var kind: CommunityInfoKind = .experience
    @State private var sourceURL = ""
    @State private var hasExpiry = false
    @State private var expires = Date()
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("게시판") {
                    Picker("분류", selection: $board) {
                        ForEach(CommunityBoard.allCases.filter { $0 != .all }) { b in Text(b.title).tag(b) }
                    }
                    Picker("작성자 표시", selection: $identity) {
                        ForEach(CommunityIdentity.allCases) { i in Text(i.title).tag(i) }
                    }
                    .pickerStyle(.segmented)
                    Text(identity == .anonymous ? "다른 회원에게 작성자 정보가 공개되지 않아요." : "다른 회원에게 현재 닉네임이 보여요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("게시글") {
                    TextField("제목 (2~120자)", text: $title)
                    TextEditor(text: $bodyText).frame(minHeight: 160)
                }
                if board == .goodwill {
                    Section("정보 유형") {
                        Picker("자료 종류", selection: $kind) {
                            ForEach(CommunityInfoKind.allCases) { k in Text(k.title).tag(k) }
                        }
                        ForEach(communityTags, id: \.self) { tag in
                            Toggle(tag, isOn: Binding(get: { tags.contains(tag) }, set: { active in
                                if active { tags.insert(tag) } else { tags.remove(tag) }
                            }))
                        }
                        TextField("출처 URL (https://, 선택)", text: $sourceURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL)
                        Toggle("유효기간이 있는 정보", isOn: $hasExpiry)
                        if hasExpiry { DatePicker("유효기간", selection: $expires, in: Date()..., displayedComponents: .date) }
                        Text("개인 경험은 공식 사실 확인과 다릅니다. 무단 복제한 시험지·강의자료, 개인정보, 현재 시험 유출 자료는 게시할 수 없어요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("글쓰기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("등록") { Task { await save() } }
                        .disabled(working || !CommunityRules.validPost(title: title, body: bodyText))
                }
            }
        }
    }
    private func save() async {
        working = true; defer { working = false }
        do {
            if !CommunityRules.validSourceURL(sourceURL) {
                throw CommunityError.message("출처 URL은 https:// 주소를 사용해 주세요.")
            }
            _ = try await api.createPost(board: board, title: title, body: bodyText, identity: identity,
                                         tags: board == .goodwill ? CommunityRules.normalizedTags(communityTags.filter { tags.contains($0) }) : [],
                                         kind: board == .goodwill ? kind : nil,
                                         sourceURL: board == .goodwill ? sourceURL : nil,
                                         expires: board == .goodwill && hasExpiry ? expires : nil)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct CommunityReportTarget: Identifiable {
    let id = UUID()
    let postID: UUID?
    let commentID: UUID?
}

private struct CommunityReportForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var api: CommunityAPI
    let target: CommunityReportTarget
    @State private var reason = ""
    @State private var error: String?
    @State private var working = false
    var body: some View {
        NavigationStack {
            Form {
                Section("신고 사유") {
                    TextField("사유를 구체적으로 입력해 주세요", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                    Text("허위 자료, 개인정보 노출, 부적절한 콘텐츠 등을 신고할 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("콘텐츠 신고")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("신고하기") {
                        Task {
                            working = true; defer { working = false }
                            do { try await api.report(postID: target.postID, commentID: target.commentID, reason: reason); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(working || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
            }
        }
    }
}

private struct CommunityPostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var api: CommunityAPI
    let postID: UUID
    let onChange: () -> Void
    @State private var post: CommunityPost?
    @State private var comments: [CommunityComment] = []
    @State private var commentText = ""
    @State private var commentIdentity: CommunityIdentity = .anonymous
    @State private var reportTarget: CommunityReportTarget?
    @State private var error: String?
    @State private var busy = false
    @State private var showBlockConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let post {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(CommunityBoard(rawValue: post.board)?.title ?? "")
                                .foregroundStyle(CommunityPalette.green).font(.caption.weight(.bold))
                            Spacer()
                            Text(communityTime(post.createdAt)).foregroundStyle(.secondary).font(.caption)
                        }
                        Text(post.title).font(.title3.weight(.bold))
                        Text("\(post.authorDisplay) · \(post.displayMode == "anonymous" ? "익명 작성" : "닉네임 작성")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(post.body).font(.body).textSelection(.enabled)
                        if !post.tags.isEmpty {
                            Text(post.tags.map { "#" + $0 }.joined(separator: "  "))
                                .font(.caption).foregroundStyle(CommunityPalette.green)
                        }
                        if post.board == "goodwill" {
                            goodwillInfo(post)
                        }
                        Divider()
                        HStack(spacing: 18) {
                            Button { Task { await tryAction { try await api.toggleLike(postID) } } } label: {
                                Label("\(post.likeCount)", systemImage: post.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            }
                            Button { Task { await tryAction { try await api.toggleSave(postID) } } } label: {
                                Label("\(post.saveCount)", systemImage: post.isSaved ? "bookmark.fill" : "bookmark")
                            }
                            Spacer()
                            Menu {
                                Button("신고하기", systemImage: "flag") {
                                    reportTarget = CommunityReportTarget(postID: postID, commentID: nil)
                                }
                                if post.mine {
                                    Button("내 글 삭제", systemImage: "trash", role: .destructive) {
                                        Task {
                                            do { try await api.deletePost(postID); onChange(); dismiss() }
                                            catch { self.error = error.localizedDescription }
                                        }
                                    }
                                } else {
                                    Button("작성자 차단", systemImage: "person.crop.circle.badge.xmark") {
                                        showBlockConfirmation = true
                                    }
                                }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                        .font(.subheadline)
                    }
                    .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    Text("댓글 \(comments.count)개").font(.headline)
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(comment.authorDisplay).font(.subheadline.weight(.semibold))
                                Text(communityTime(comment.createdAt)).foregroundStyle(.secondary).font(.caption)
                                Spacer()
                                Menu {
                                    if comment.mine {
                                        Button("댓글 삭제", systemImage: "trash", role: .destructive) {
                                            Task { await tryAction { try await api.deleteComment(comment.id) } }
                                        }
                                    } else {
                                        Button("댓글 신고", systemImage: "flag") {
                                            reportTarget = CommunityReportTarget(postID: nil, commentID: comment.id)
                                        }
                                    }
                                } label: { Image(systemName: "ellipsis") }
                            }
                            Text(comment.body).font(.subheadline).textSelection(.enabled)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(spacing: 10) {
                        TextField("댓글 작성", text: $commentText, axis: .vertical).lineLimit(2...5)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Picker("댓글 표시", selection: $commentIdentity) {
                                ForEach(CommunityIdentity.allCases) { m in Text(m.title).tag(m) }
                            }
                            .pickerStyle(.segmented)
                            Button("등록") {
                                Task { await tryAction { try await api.addComment(postID: postID, body: commentText, identity: commentIdentity); commentText = "" } }
                            }
                            .disabled(busy || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
                } else if error == nil { ProgressView().padding(25) }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .padding(14)
        }
        .background(CommunityPalette.bg)
        .navigationTitle("게시글")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .sheet(item: $reportTarget) { target in CommunityReportForm(api: api, target: target) }
        .confirmationDialog("작성자를 차단할까요?", isPresented: $showBlockConfirmation) {
            Button("차단", role: .destructive) {
                Task {
                    do { try await api.blockAuthor(of: postID); onChange(); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        } message: { Text("차단한 사용자의 글과 댓글은 내 화면에서 숨겨져요.") }
    }

    private func goodwillInfo(_ post: CommunityPost) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let info = post.infoKind, let kind = CommunityInfoKind(rawValue: info) {
                Label(kind.title, systemImage: "doc.text").font(.caption.weight(.semibold))
            }
            if post.reviewState == "source_checked" { Label("출처 확인", systemImage: "checkmark.seal").foregroundStyle(.green) }
            if post.reviewState == "recommended" { Label("운영진 추천", systemImage: "star.fill").foregroundStyle(CommunityPalette.green) }
            if post.reviewState == "pending" { Text("운영진 검토 대기 · 공식 확인 전") }
            if let source = post.sourceUrl, let url = URL(string: source), url.scheme == "https" {
                Link("자료 출처 확인", destination: url)
            }
            if let expiry = post.expiresAt { Text("유효기간: \(expiry)") }
            Text("개인 후기의 내용 전체가 운영진에 의해 보증되는 것은 아닙니다.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .font(.caption).padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CommunityPalette.bg, in: RoundedRectangle(cornerRadius: 10))
    }

    private func refresh() async {
        do {
            post = try await api.post(postID)
            comments = try await api.comments(postID)
            onChange()
        } catch { self.error = error.localizedDescription }
    }
    private func tryAction(_ action: () async throws -> Void) async {
        busy = true; defer { busy = false }
        do { try await action(); await refresh() }
        catch { self.error = error.localizedDescription }
    }
}

private struct CommunityProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var api: CommunityAPI
    let onSignOut: () -> Void
    @State private var nickname = ""
    @State private var contributions: [CommunityContribution] = []
    @State private var blocks: [CommunityBlock] = []
    @State private var error: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("공개 닉네임") {
                    TextField("닉네임 (2~20자)", text: $nickname)
                        .textInputAutocapitalization(.never)
                    Button("닉네임 변경") {
                        Task {
                            do { try await api.setNickname(nickname); error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(!CommunityRules.validNickname(nickname))
                    Text("익명으로 작성한 게시글은 닉네임이 공개되지 않아요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("인정된 정보 기여") {
                    if contributions.isEmpty { Text("아직 인정된 정보 기여가 없어요.").foregroundStyle(.secondary) }
                    ForEach(contributions) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.title).font(.subheadline.weight(.semibold))
                            Text(communityTime(c.recordedAt)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("차단한 회원") {
                    if blocks.isEmpty { Text("차단된 회원이 없어요.").foregroundStyle(.secondary) }
                    ForEach(blocks) { block in
                        HStack {
                            Text("차단된 회원 · \(communityTime(block.createdAt))")
                            Spacer()
                            Button("차단 해제") {
                                Task {
                                    do { try await api.unblock(block.id); blocks = try await api.myBlocks() }
                                    catch { self.error = error.localizedDescription }
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("로그아웃") {
                        Task { await api.signOut(); onSignOut(); dismiss() }
                    }
                    Button("사랑방 계정 삭제", role: .destructive) { showDeleteConfirmation = true }
                } footer: {
                    Text("계정 삭제 시 사랑방 게시물·댓글·스크랩·기여 기록이 삭제됩니다. 기존 분실 신고의 기기 저장 데이터는 별도로 관리됩니다.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("내 커뮤니티 정보")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .task {
                nickname = api.profile?.nickname ?? ""
                contributions = (try? await api.myContributions()) ?? []
                blocks = (try? await api.myBlocks()) ?? []
            }
            .confirmationDialog("사랑방 계정을 영구 삭제할까요?", isPresented: $showDeleteConfirmation) {
                Button("계정과 커뮤니티 기록 삭제", role: .destructive) {
                    Task {
                        do { try await api.deleteAccount(); onSignOut(); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            } message: { Text("게시글, 댓글, 기여 기록을 복원할 수 없습니다. 기존 지도·식단 기능은 유지됩니다.") }
        }
    }
}

private struct CommunityModeratorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var api: CommunityAPI
    @State private var pending: [CommunityPost] = []
    @State private var reports: [CommunityReport] = []
    @State private var reviewNote = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("정보 검토 대기 · \(pending.count)건") {
                    if pending.isEmpty { Text("대기 중인 정보가 없습니다.") }
                    ForEach(pending) { p in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(p.title).font(.headline)
                            Text(p.body).font(.footnote).lineLimit(3)
                            if let url = p.sourceUrl, let link = URL(string: url), link.scheme == "https" {
                                Link("출처 보기", destination: link).font(.caption)
                            }
                            HStack {
                                Button("출처 확인") { Task { await review(p.id, "source_checked") } }
                                Button("추천") { Task { await review(p.id, "recommended") } }
                                Button("반려", role: .destructive) { Task { await review(p.id, "rejected") } }
                            }.buttonStyle(.bordered).font(.caption)
                        }.padding(.vertical, 6)
                    }
                }
                Section("신고 접수 · \(reports.count)건") {
                    if reports.isEmpty { Text("미처리 신고가 없습니다.") }
                    ForEach(reports) { r in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(r.reason).font(.subheadline)
                            Text("대상: \(r.postId != nil ? "게시글" : "댓글") · \(communityTime(r.createdAt))")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("숨기기") { Task { await resolve(r.id, hide: true, dismiss: false) } }
                                Button("기각") { Task { await resolve(r.id, hide: false, dismiss: true) } }
                            }.buttonStyle(.bordered).font(.caption)
                        }.padding(.vertical, 6)
                    }
                }
                Section("검토 기록") {
                    TextField("검토 메모 (선택)", text: $reviewNote)
                    Text("출처 확인은 개인 후기 전체를 사실로 보증하지 않습니다. 승인 전 저작권과 개인정보를 확인하세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("사랑방 운영진")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }
    private func reload() async {
        do {
            async let a = api.pending()
            async let b = api.reports()
            pending = try await a; reports = try await b
        } catch { self.error = error.localizedDescription }
    }
    private func review(_ id: UUID, _ state: String) async {
        do { try await api.review(postID: id, state: state, note: reviewNote); await reload() }
        catch { self.error = error.localizedDescription }
    }
    private func resolve(_ id: UUID, hide: Bool, dismiss: Bool) async {
        do { try await api.resolveReport(id, hide: hide, dismiss: dismiss); await reload() }
        catch { self.error = error.localizedDescription }
    }
}
