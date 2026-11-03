import SwiftUI

struct MeView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var policy: AccountPolicy?
    @State private var nickname = ""
    @State private var editing = false
    @State private var deleting = false
    @State private var working = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            if !account.authenticated {
                AccountLoginView().toolbar(.hidden, for: .navigationBar)
            } else {
                List {
                    Section {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(Color.cjTeal)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(account.details?.nickname ?? "내 계정").font(.title3.bold())
                                Text(account.email ?? "").font(.footnote).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8)
                        Button("닉네임 수정") { nickname = account.details?.nickname ?? ""; editing = true }
                        Text("이 계정으로 퀘스트·분실물·사랑방을 함께 이용해요.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("나의 활동") {
                        NavigationLink { MyQuestsView() } label: { Label("내 의뢰·수행 퀘스트", systemImage: "bolt") }
                        NavigationLink { QuestTransactionsView() } label: { Label("보상·송금 기록", systemImage: "banknote") }
                    }
                    Section("약관과 개인정보") {
                        ForEach(account.policies) { document in Button(document.title) { policy = document } }
                        Link("운영자·개인정보 문의", destination: URL(string: "mailto:info@chargajoe.org")!)
                        Text("운영자·개인정보 보호책임자 이경록\ninfo@chargajoe.org").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("로그아웃") { Task { await account.signOut() } }.disabled(working)
                        Button("찾아줘 계정 삭제", role: .destructive) { deleting = true }.disabled(working)
                        Text("프로필과 계정은 삭제되며, 법정 보존 대상 거래 기록은 별도로 보관돼요. 진행 중인 의뢰·미확인 송금·분쟁이 있으면 먼저 정리하거나 운영자에게 삭제 지원을 요청해 주세요.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                .navigationTitle("내 정보")
                .alert("닉네임 수정", isPresented: $editing) {
                    TextField("2~20자", text: $nickname)
                    Button("취소", role: .cancel) { }
                    Button("저장") { perform { try await account.setNickname(nickname) } }
                } message: { Text("한글·영문·숫자·밑줄을 사용할 수 있어요.") }
                .confirmationDialog("찾아줘 계정을 삭제할까요?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("계정과 회원 데이터 삭제", role: .destructive) { perform { try await account.deleteAccount() } }
                } message: { Text("퀘스트·분실물·사랑방에 함께 사용하는 계정이에요. 진행 중인 거래는 먼저 정리해야 하며, 법정 보존 거래 기록은 즉시 삭제되지 않아요.") }
            }
        }
        .sheet(item: $policy) { AccountPolicyView(document: $0) }
        .task { do { try await account.loadPolicies() } catch { self.error = error.localizedDescription } }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        working = true
        Task { @MainActor in
            defer { working = false }
            do { try await action(); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
}
