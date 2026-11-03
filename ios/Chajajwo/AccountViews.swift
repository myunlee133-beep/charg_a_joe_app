import SwiftUI

private enum AccountStyle {
    static let green = Color(hex: 0x356C56)
    static let ink = Color(hex: 0x15201C)
    static let muted = Color(hex: 0x63706A)
    static let line = Color(hex: 0xCAD2CD)
}

struct AccountLoginView: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    private enum Step { case email, credentials, confirmation, reset }
    @State private var step = Step.email
    @State private var email = ""
    @State private var password = ""
    @State private var signup = false
    @State private var working = false
    @State private var message: String?
    @State private var failure = false
    @State private var agreed = Set<String>()
    @State private var adult = false
    @State private var selectedPolicy: AccountPolicy?
    @State private var provider: String?
    private var validEmail: Bool { email.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: .caseInsensitive) != nil }
    private var signupReady: Bool { adult && account.policiesVerified && account.policies.filter { $0.context == "account" }.allSatisfy { agreed.contains($0.kind) } }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image("AccountCampus").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: min(260, geometry.size.width * 0.66)).clipped()
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(step == .confirmation ? "메일함을 확인해 주세요" : step == .reset ? "비밀번호를 잊으셨나요?" : "찾아줘에 오신 걸\n환영해요")
                                .font(.system(size: 30, weight: .semibold)).tracking(-1).foregroundStyle(AccountStyle.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("캠퍼스의 작은 부탁, 서로의 도움이 되도록.")
                                .font(.subheadline).foregroundStyle(AccountStyle.muted)
                        }
                        if step == .confirmation {
                            Text("\(email)로 인증 안내를 보냈어요. 메일의 링크로 이메일을 인증한 후 로그인해 주세요.")
                                .font(.subheadline).lineSpacing(5)
                            primary("인증했어요 · 로그인") { signup = false; step = .credentials; message = nil }
                            Button("인증 메일 다시 보내기") { perform { try await account.resendConfirmation(email: email); show("인증 안내를 다시 요청했어요. 메일함과 스팸함을 확인해 주세요.") } }
                                .disabled(working).font(.subheadline)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("이메일 주소").font(.caption).foregroundStyle(AccountStyle.muted)
                                TextField("name@example.com", text: $email)
                                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .submitLabel(step == .email ? .continue : .next)
                                    .onSubmit { if validEmail && step == .email { step = .credentials } }
                                    .padding(.vertical, 15).padding(.horizontal, 14)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 9))
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(AccountStyle.line))
                                    .accessibilityIdentifier("account-email")
                            }
                            if step == .credentials {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(signup ? "비밀번호 만들기 · 10자 이상" : "비밀번호").font(.caption).foregroundStyle(AccountStyle.muted)
                                    SecureField(signup ? "새 비밀번호" : "비밀번호", text: $password)
                                        .textContentType(signup ? .newPassword : .password)
                                        .padding(14).overlay(RoundedRectangle(cornerRadius: 9).stroke(AccountStyle.line))
                                        .accessibilityIdentifier("account-password")
                                    if !signup { Button("비밀번호 찾기") { password = ""; step = .reset; message = nil }.font(.footnote) }
                                }
                                if signup {
                                    AccountConsentChecklist(context: "account", agreed: $agreed, adult: $adult, selectedPolicy: $selectedPolicy)
                                }
                            }
                            primary(step == .email ? "이메일로 계속하기" : step == .reset ? "재설정 메일 받기" : signup ? "동의하고 가입하기" : "로그인") {
                                if step == .email { step = .credentials; message = nil }
                                else if step == .reset { perform { try await account.sendPasswordReset(email: email); show("계정이 있다면 재설정 안내를 받을 수 있어요. 메일의 링크를 열어 주세요.") } }
                                else { authenticate() }
                            }
                            .disabled(working || !validEmail || (step == .credentials && (password.isEmpty || (signup && (password.count < 10 || !signupReady)))))
                            if step == .credentials {
                                Button(signup ? "이미 가입했어요 · 로그인" : "처음이신가요? 회원가입") { signup.toggle(); password = ""; message = nil }
                                    .font(.subheadline).frame(maxWidth: .infinity)
                            } else if step == .reset {
                                Button("로그인으로 돌아가기") { step = .credentials; message = nil }.font(.subheadline)
                            }
                        }
                        if let message {
                            Label(message, systemImage: failure ? "exclamationmark.circle" : "checkmark.circle")
                                .font(.footnote).foregroundStyle(failure ? .red : AccountStyle.green)
                                .accessibilityIdentifier("account-message")
                        }
                        if step == .email && !account.providers.isEmpty {
                            HStack { Rectangle().frame(height: 1); Text("또는").font(.caption).fixedSize(); Rectangle().frame(height: 1) }.foregroundStyle(AccountStyle.line)
                            HStack(spacing: 12) {
                                ForEach(account.providers, id: \.self) { value in
                                    Button { provider = value } label: {
                                        Text(value == "apple" ? "Apple" : value == "google" ? "Google" : "카카오")
                                            .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 48)
                                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AccountStyle.line))
                                    }.disabled(working)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 16) {
                                ForEach(account.policies.filter { ["terms", "privacy"].contains($0.kind) }) { document in
                                    Button(document.kind == "terms" ? "이용약관" : "개인정보 처리방침") { selectedPolicy = document }
                                        .font(.caption).underline()
                                }
                            }
                            Text("퀘스트 보상은 이용자끼리 직접 송금해요.\n찾아줘는 보상금을 보관하거나 자동 이체하지 않아요.")
                                .font(.caption).foregroundStyle(AccountStyle.muted).lineSpacing(4)
                            Button("먼저 둘러볼게요") { store.tab = .home; dismiss() }
                                .font(.subheadline).padding(.top, 4)
                        }
                    }.padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 32)
                }.frame(width: geometry.size.width)
            }.background(.white).scrollDismissesKeyboard(.interactively)
        }
        .tint(AccountStyle.green)
        .sheet(item: $selectedPolicy) { AccountPolicyView(document: $0) }
        .sheet(isPresented: Binding(get: { provider != nil }, set: { if !$0 { provider = nil } })) {
            if let provider { AccountProviderConsentView(provider: provider) }
        }
        .onChange(of: account.authenticated) { _, value in if value { store.showAccountLogin = false } }
        .task {
            do { try await account.loadPolicies() } catch { show(error.localizedDescription, failed: true) }
            await account.loadProviders()
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Spacer(); if working { ProgressView().tint(.white) } else { Text(title).font(.system(size: 16, weight: .semibold)) }; Spacer() }
                .padding(.vertical, 16).foregroundStyle(.white).background(AccountStyle.green, in: RoundedRectangle(cornerRadius: 9))
        }.accessibilityIdentifier("account-continue")
    }
    private func show(_ text: String, failed: Bool = false) { message = text; failure = failed }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        working = true; message = nil
        Task { @MainActor in
            defer { working = false }
            do { try await action() } catch { show(error.localizedDescription, failed: true) }
        }
    }
    private func authenticate() {
        email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        perform {
            if signup {
                let active = try await account.signUp(email: email, password: password)
                password = ""
                if !active { step = .confirmation }
            } else { try await account.signIn(email: email, password: password); password = "" }
        }
    }
}

struct AccountPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    let document: AccountPolicy
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(document.title).font(.title2.bold())
                    Text("문서 버전 \(document.version)").font(.caption).foregroundStyle(.secondary)
                    Text(document.body).font(.body).lineSpacing(7).textSelection(.enabled)
                    Link("운영자에게 문의", destination: URL(string: "mailto:info@chargajoe.org")!)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            .navigationTitle("약관 및 개인정보").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

private struct AccountConsentChecklist: View {
    @EnvironmentObject private var account: AccountStore
    let context: String
    @Binding var agreed: Set<String>
    @Binding var adult: Bool
    @Binding var selectedPolicy: AccountPolicy?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if context == "account" { Toggle("[필수] 만 19세 이상입니다", isOn: $adult).font(.footnote) }
            ForEach(account.policies.filter { $0.context == context }) { document in
                HStack(alignment: .top, spacing: 8) {
                    Toggle(isOn: Binding(get: { agreed.contains(document.kind) }, set: { value in
                        if value { agreed.insert(document.kind) } else { agreed.remove(document.kind) }
                    })) { Text("[필수] " + document.title).font(.footnote) }
                    Button { selectedPolicy = document } label: { Image(systemName: "chevron.right").font(.caption).padding(8) }
                        .accessibilityLabel(document.title + " 전문 보기")
                }
            }
            if !account.policiesVerified {
                Button("약관 다시 불러오기") { Task { try? await account.loadPolicies() } }.font(.footnote)
            }
        }.toggleStyle(.switch).tint(AccountStyle.green)
    }
}

struct AccountOnboardingView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var nickname = ""
    @State private var adult = false
    @State private var agreed = Set<String>()
    @State private var selectedPolicy: AccountPolicy?
    @State private var error: String?
    @State private var working = false
    private var ready: Bool { !working && adult && account.policiesVerified && nickname.range(of: #"^[가-힣A-Za-z0-9_]{2,20}$"#, options: .regularExpression) != nil && account.policies.filter { $0.context == "account" }.allSatisfy { agreed.contains($0.kind) } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("서로를 부를 이름을 알려주세요").font(.title2.bold())
                    Text("닉네임은 커뮤니티와 퀘스트에 보여요. 이메일·내부 계정 ID는 다른 회원에게 공개하지 않아요.").font(.subheadline)
                }
                Section("닉네임") {
                    TextField("한글·영문·숫자·밑줄 2~20자", text: $nickname).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("계정과 개인정보") { AccountConsentChecklist(context: "account", agreed: $agreed, adult: $adult, selectedPolicy: $selectedPolicy) }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
                Section {
                    Button(working ? "설정 중…" : "동의하고 시작하기") {
                        working = true
                        Task {
                            defer { working = false }
                            do { try await account.completeOnboarding(nickname: nickname, adult: adult) }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(!ready)
                    Button("로그아웃", role: .cancel) { Task { await account.signOut() } }
                }
            }
            .navigationTitle("처음 만나는 찾아줘").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedPolicy) { AccountPolicyView(document: $0) }
            .task {
                nickname = account.details?.nickname ?? ""
                do { try await account.loadPolicies() } catch { self.error = error.localizedDescription }
            }
        }.interactiveDismissDisabled()
    }
}

private struct AccountProviderConsentView: View {
    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    let provider: String
    @State private var adult = false
    @State private var agreed = Set<String>()
    @State private var document: AccountPolicy?
    @State private var working = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("인증을 시작하기 전에 계정 정보 처리와 국외 저장 안내를 확인해 주세요. 신규 회원의 동의 이력은 인증 후 계정 설정에서 기록합니다.").font(.subheadline) }
                AccountConsentChecklist(context: "account", agreed: $agreed, adult: $adult, selectedPolicy: $document)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Button(working ? "인증 중…" : "동의하고 계속") {
                    working = true
                    Task {
                        defer { working = false }
                        do { try await account.signIn(provider: provider); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(working || !adult || !account.policiesVerified || !account.policies.filter { $0.context == "account" }.allSatisfy { agreed.contains($0.kind) })
            }
            .navigationTitle("계정 정보 확인")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
            .sheet(item: $document) { AccountPolicyView(document: $0) }
        }
    }
}

struct AccountRecoveryView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var password = ""
    @State private var confirmation = ""
    @State private var working = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("새 비밀번호 · 10자 이상") {
                    SecureField("새 비밀번호", text: $password).textContentType(.newPassword)
                    SecureField("다시 입력", text: $confirmation).textContentType(.newPassword)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button(working ? "변경 중…" : "비밀번호 변경") {
                    working = true
                    Task {
                        defer { working = false }
                        do { try await account.updatePassword(password); password = ""; confirmation = "" }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(working || password.count < 10 || password != confirmation)
            }.navigationTitle("비밀번호 재설정")
        }.interactiveDismissDisabled()
    }
}
