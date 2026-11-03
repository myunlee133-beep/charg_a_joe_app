import SwiftUI

private enum AccountStyle {
    static let green = Color(hex: 0x356C56)
    static let ink = Color(hex: 0x15201C)
    static let muted = Color(hex: 0x63706A)
    static let line = Color(hex: 0xCAD2CD)
    static let canvas = Color(hex: 0xF5F7F4)
    static let field = Color(hex: 0xF3F6F3)
}

struct AccountLoginView: View {
    @EnvironmentObject private var account: AccountStore
    @Environment(\.scenePhase) private var scenePhase
    private enum Step { case credentials, confirmation, reset }
    private enum Field: Hashable { case email, password }
    @FocusState private var focusedField: Field?
    @State private var step = Step.credentials
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
    @State private var kakaoQR = false
    @State private var unavailableProvider: String?
    private var validEmail: Bool { email.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.caseInsensitive, .regularExpression]) != nil }
    private var signupReady: Bool { adult && account.policiesVerified && account.policies.filter { $0.context == "account" }.allSatisfy { agreed.contains($0.kind) } }
    private var continueTitle: String { step == .reset ? "재설정 메일 받기" : signup ? "동의하고 가입하기" : "로그인" }
    private var continueDisabled: Bool { working || !validEmail || (step == .credentials && (password.isEmpty || (signup && (password.count < 10 || !signupReady)))) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if step == .confirmation {
                        Text("메일함을 확인해 주세요").font(.title2.bold())
                        Text("\(email)로 인증 안내를 보냈어요. 메일의 링크로 이메일을 인증한 후 로그인해 주세요.")
                            .font(.subheadline).foregroundStyle(AccountStyle.muted).lineSpacing(5)
                        primary("인증했어요 · 로그인") { signup = false; step = .credentials; message = nil }
                        Button("인증 메일 다시 보내기") { perform { try await account.resendConfirmation(email: email); show("인증 안내를 다시 요청했어요. 메일함과 스팸함을 확인해 주세요.") } }
                            .disabled(working).font(.subheadline)
                    } else {
                        if step == .reset {
                            Text("가입한 이메일로 재설정 안내를 보내드려요.").font(.subheadline).foregroundStyle(AccountStyle.muted)
                        }
                        VStack(alignment: .leading, spacing: 20) {
                            emailForm
                            if step == .credentials && signup {
                                AccountConsentChecklist(context: "account", agreed: $agreed, adult: $adult, selectedPolicy: $selectedPolicy)
                            }
                            if focusedField == nil { primary(continueTitle, action: continueTapped).disabled(continueDisabled) }
                        }
                        .padding(22)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AccountStyle.line.opacity(0.45), lineWidth: 0.5))
                        .shadow(color: AccountStyle.ink.opacity(0.035), radius: 20, y: 8)
                        if step == .credentials { socialOptions }
                        if step == .reset {
                            Button("로그인으로 돌아가기") { step = .credentials; signup = false; message = nil }.font(.subheadline)
                        }
                    }
                    if let message {
                        Label(message, systemImage: failure ? "exclamationmark.circle" : "checkmark.circle")
                            .font(.footnote).foregroundStyle(failure ? .red : AccountStyle.green)
                            .accessibilityIdentifier("account-message")
                    }
                    policiesFooter
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 24).padding(.top, 36).padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .background(AccountStyle.canvas).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil && step != .confirmation {
                    primary(continueTitle, action: continueTapped).disabled(continueDisabled)
                        .padding(.horizontal, 24).padding(.vertical, 12).background(AccountStyle.canvas)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("완료") { focusedField = nil } }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(AccountStyle.green)
        .sheet(item: $selectedPolicy) { AccountPolicyView(document: $0) }
        .sheet(isPresented: Binding(get: { provider != nil }, set: { if !$0 { provider = nil } })) {
            if let provider { AccountProviderConsentView(provider: provider, preferKakaoQR: kakaoQR) }
        }
        .alert("로그인 안내", isPresented: Binding(get: { unavailableProvider != nil }, set: { if !$0 { unavailableProvider = nil } })) {
            Button("확인") { unavailableProvider = nil }
        } message: { Text("\(unavailableProvider ?? "") 로그인을 준비하고 있어요. 지금은 이메일로 이용해 주세요.") }
        .onChange(of: signup) { _, _ in password = ""; message = nil; focusedField = nil }
        .onChange(of: focusedField) { _, value in account.authFormFocused = value != nil }
        .onDisappear { account.authFormFocused = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await account.loadProviders() } }
        }
        .task {
            await account.loadProviders()
            do { try await account.loadPolicies() } catch { show(error.localizedDescription, failed: true) }
        }
    }

    private var header: some View {
        VStack(spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill").font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(AccountStyle.green, in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)
                Text("찾아줘").font(.system(size: 27, weight: .bold)).tracking(-1)
            }
            Text(step == .reset ? "비밀번호 재설정" : signup ? "회원가입" : "로그인")
                .font(.system(size: 21, weight: .semibold)).tracking(-0.6)
                .accessibilityIdentifier("account-entry-title")
        }.frame(maxWidth: .infinity).foregroundStyle(AccountStyle.ink)
    }

    private var socialOptions: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                Rectangle().fill(AccountStyle.line.opacity(0.65)).frame(height: 0.5)
                Text("간편 로그인").font(.system(size: 12, weight: .medium)).fixedSize()
                Rectangle().fill(AccountStyle.line.opacity(0.65)).frame(height: 0.5)
            }
            .foregroundStyle(AccountStyle.muted)
            HStack(spacing: 32) {
                providerButton("google", title: "Google")
                providerButton("apple", title: "Apple")
                providerButton("kakao", title: "카카오")
            }
            .frame(maxWidth: .infinity)
            Button { selectProvider("kakao", qr: true) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode").font(.system(size: 15, weight: .medium))
                    Text("카카오 QR 로그인").font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }.frame(minHeight: 44).frame(maxWidth: .infinity)
                    .foregroundStyle(AccountStyle.muted)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AccountStyle.line.opacity(0.6), lineWidth: 0.5))
            }.buttonStyle(.plain).disabled(working).accessibilityIdentifier("account-kakao-qr")
        }
    }

    private func selectProvider(_ value: String, qr: Bool = false) {
        focusedField = nil
        perform {
            await account.loadProviders()
            if account.providers.contains(value) { kakaoQR = qr; provider = value }
            else { unavailableProvider = value == "apple" ? "Apple" : value == "google" ? "Google" : "카카오" }
        }
    }

    private func providerButton(_ value: String, title: String) -> some View {
        Button { selectProvider(value) } label: {
            VStack(spacing: 9) {
                ZStack {
                    Circle().fill(value == "apple" ? Color.black : value == "kakao" ? Color(hex: 0xFEE500) : .white)
                    if value == "google" {
                        Image("AccountGoogle").resizable().frame(width: 44, height: 44).accessibilityHidden(true)
                    } else if value == "apple" {
                        Image(systemName: "apple.logo").font(.system(size: 25)).foregroundStyle(.white).accessibilityHidden(true)
                    } else {
                        Image("AccountKakao").resizable().scaledToFit().frame(width: 26, height: 26).accessibilityHidden(true)
                    }
                }.frame(width: 58, height: 58)
                    .overlay(Circle().stroke(value == "google" ? AccountStyle.line.opacity(0.65) : .clear, lineWidth: 0.5))
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(AccountStyle.muted)
            }.frame(minWidth: 64)
        }
        .buttonStyle(.plain).disabled(working)
        .accessibilityLabel("\(title)로 계속하기")
        .accessibilityIdentifier("account-provider-\(value)")
    }

    private var emailForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("이메일").font(.caption).foregroundStyle(AccountStyle.muted)
                TextField("이메일 주소", text: $email, prompt: Text("name@example.com").foregroundStyle(AccountStyle.muted))
                    .foregroundStyle(AccountStyle.ink).focused($focusedField, equals: .email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(step == .reset ? .go : .next)
                    .onSubmit { if step == .reset { if !continueDisabled { continueTapped() } } else { focusedField = .password } }
                    .font(.system(size: 15)).padding(.vertical, 17).padding(.horizontal, 16)
                    .background(AccountStyle.field, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("account-email")
            }
            if step == .credentials {
                VStack(alignment: .leading, spacing: 7) {
                    Text(signup ? "비밀번호 · 10자 이상" : "비밀번호").font(.caption).foregroundStyle(AccountStyle.muted)
                    SecureField(signup ? "새 비밀번호" : "비밀번호", text: $password)
                        .focused($focusedField, equals: .password).foregroundStyle(AccountStyle.ink)
                        .textContentType(signup ? .newPassword : .password)
                        .submitLabel(.go).onSubmit { if !continueDisabled { continueTapped() } }
                        .font(.system(size: 15)).padding(.vertical, 17).padding(.horizontal, 16)
                        .background(AccountStyle.field, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("account-password")
                }
                HStack(spacing: 14) {
                    Spacer(minLength: 0)
                    if signup {
                        Button { signup = false } label: {
                            Text("로그인으로 돌아가기").frame(minHeight: 44)
                        }
                            .accessibilityIdentifier("account-return-login")
                    } else {
                        Button { password = ""; step = .reset; focusedField = nil; message = nil } label: {
                            Text("비밀번호 찾기").frame(minHeight: 44)
                        }
                            .accessibilityIdentifier("account-forgot-password")
                        Rectangle().fill(AccountStyle.line).frame(width: 1, height: 12).accessibilityHidden(true)
                        Button { signup = true } label: {
                            Text("회원가입").fontWeight(.semibold).frame(minHeight: 44)
                        }
                            .accessibilityIdentifier("account-signup-link")
                    }
                }
                .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(AccountStyle.green)
                .frame(minHeight: 44).disabled(working)
            }
        }
    }

    private var policiesFooter: some View {
        VStack(spacing: 11) {
            HStack(spacing: 18) {
                ForEach(account.policies.filter { ["terms", "privacy"].contains($0.kind) }) { document in
                    Button(document.kind == "terms" ? "이용약관" : "개인정보 처리방침") { selectedPolicy = document }
                        .font(.system(size: 11)).foregroundStyle(AccountStyle.muted)
                }
            }
            Text("퀘스트 보상은 이용자끼리 직접 송금해요.")
                .font(.system(size: 11)).foregroundStyle(AccountStyle.muted.opacity(0.85))
        }.frame(maxWidth: .infinity)
    }

    private func continueTapped() {
        focusedField = nil
        if step == .reset { perform { try await account.sendPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines)); show("계정이 있다면 재설정 안내를 받을 수 있어요. 메일의 링크를 열어 주세요.") } }
        else { authenticate() }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Spacer(); if working { ProgressView().tint(.white) } else { Text(title).font(.system(size: 16, weight: .semibold)) }; Spacer() }
                .padding(.vertical, 16).foregroundStyle(.white)
                .background(AccountStyle.green.opacity(continueDisabled ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 14))
        }.accessibilityIdentifier("account-continue")
    }
    private func show(_ text: String, failed: Bool = false) { message = text; failure = failed }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        working = true; message = nil
        Task { @MainActor in
            defer { working = false }
            do { try await action() }
            catch is CancellationError { }
            catch { show(error.localizedDescription, failed: true) }
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
    var preferKakaoQR = false
    @State private var adult = false
    @State private var agreed = Set<String>()
    @State private var document: AccountPolicy?
    @State private var working = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if preferKakaoQR && provider == "kakao" {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "qrcode").accessibilityHidden(true)
                            Text("카카오 화면에서 ‘QR코드 로그인’을 선택해 주세요.")
                                .accessibilityIdentifier("account-kakao-qr-guide")
                        }.font(.subheadline.weight(.semibold))
                        Text("다른 기기의 카카오톡으로 QR을 스캔하면 이 기기에서 인증을 이어가요. QR 메뉴가 표시되지 않는 환경에서는 카카오계정으로 로그인할 수 있어요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section { Text("인증을 시작하기 전에 계정 정보 처리와 국외 저장 안내를 확인해 주세요. 신규 회원의 동의 이력은 인증 후 계정 설정에서 기록합니다.").font(.subheadline) }
                AccountConsentChecklist(context: "account", agreed: $agreed, adult: $adult, selectedPolicy: $document)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Button(working ? "인증 중…" : "동의하고 계속") {
                    working = true
                    Task {
                        defer { working = false }
                        do { try await account.signIn(provider: provider, preferKakaoQR: preferKakaoQR); dismiss() }
                        catch is CancellationError { }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(working || !adult || !account.policiesVerified || !account.policies.filter { $0.context == "account" }.allSatisfy { agreed.contains($0.kind) })
                    .accessibilityIdentifier("account-provider-continue")
            }
            .navigationTitle(preferKakaoQR && provider == "kakao" ? "카카오 QR 로그인" : "계정 정보 확인")
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
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소하고 로그아웃") { Task { await account.signOut() } } } }
        }.interactiveDismissDisabled()
    }
}
