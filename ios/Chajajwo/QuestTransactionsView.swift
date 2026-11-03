import SwiftUI

struct QuestTransactionConsentView: View {
    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var agreed = false
    @State private var selectedPolicy: AccountPolicy?
    @State private var error: String?
    @State private var working = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("보상은 서로 직접 송금해요").font(.title2.bold())
                    Text("찾아줘는 돈을 보관하거나 이체하지 않아요. 결과 승인과 송금 신고, 실제 입금 확인을 따로 기록해요.")
                }
                if let document = account.policies.first(where: { $0.kind == "transaction" }) {
                    Section {
                        Button("퀘스트 거래 약관 전문 보기") { selectedPolicy = document }
                        Toggle("[필수] 거래 약관을 확인하고 동의합니다", isOn: $agreed)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                Button(working ? "저장 중…" : "동의 기록하고 돌아가기") {
                    working = true
                    Task {
                        defer { working = false }
                        do { try await account.acceptTransactionPolicies(); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(!agreed || !account.policiesVerified || working)
            }.navigationTitle("퀘스트 시작 전 확인")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .sheet(item: $selectedPolicy) { AccountPolicyView(document: $0) }
                .task { do { try await account.loadPolicies() } catch { self.error = error.localizedDescription } }
        }
    }
}

struct QuestTransactionsView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var records: [QuestTransaction] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            Section { Text("보상은 은행 앱에서 직접 송금해요. 아래 기록은 당사자의 신고·확인이며 은행의 이체 증빙은 아니에요.").font(.footnote).foregroundStyle(.secondary) }
            if loading && records.isEmpty { ProgressView("거래를 불러오는 중") }
            if records.isEmpty && !loading && error == nil { ContentUnavailableView("아직 보상 기록이 없어요", systemImage: "banknote", description: Text("의뢰자가 결과를 승인하면 보상 거래가 생겨요.")) }
            ForEach(records) { record in
                NavigationLink { QuestTransactionDetailView(transaction: record) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.title).font(.headline)
                        Text(record.amount.formatted() + "원 · " + (record.amPayer ? "보낼 보상" : "받을 보상"))
                        Text(record.statusTitle).font(.caption).foregroundStyle(Color.cjTealText)
                        Text("상대방 · \(record.counterparty)").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red); Button("다시 불러오기") { Task { await load() } } } }
        }.navigationTitle("보상·송금 기록").refreshable { await load() }.task { await load() }
            .onChange(of: account.userID) { _, _ in records = []; Task { await load() } }
    }
    private func load() async {
        guard account.authenticated else { records = []; return }
        let userID = account.userID
        loading = true; defer { loading = false }
        do {
            let fetched = try await QuestAccountAPI.transactions()
            guard userID == account.userID else { return }
            records = fetched; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct QuestTransactionDetailView: View {
    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    let transaction: QuestTransaction
    @State private var current: QuestTransaction?
    @State private var bank = ""
    @State private var holder = ""
    @State private var number = ""
    @State private var details: QuestTransferDetails?
    @State private var agreed = false
    @State private var working = false
    @State private var error: String?
    @State private var message: String?
    @State private var confirm: String?
    @State private var reason = ""
    @State private var selectedPolicy: AccountPolicy?
    private var record: QuestTransaction { current ?? transaction }
    var body: some View {
        Form {
            Section(record.title) {
                LabeledContent("보상", value: record.amount.formatted() + "원")
                LabeledContent("상대방", value: record.counterparty)
                Text(record.statusTitle).foregroundStyle(Color.cjTealText)
                Text("거래 번호 \(record.id.uuidString.lowercased())").font(.caption2).textSelection(.enabled)
            }
            if let details {
                Section("이 거래의 송금 계좌") {
                    LabeledContent("은행", value: details.bankName)
                    LabeledContent("예금주", value: details.holderName)
                    Text(details.accountNumber).font(.body.monospaced()).textSelection(.enabled)
                    Text("이 거래의 보상 지급에만 사용하고 지급 목적이 끝나면 불필요한 사본을 삭제해 주세요.").font(.caption)
                    if !record.amPayer { Button("계좌 제공 철회", role: .destructive) { action { let _: Bool = try await account.rpc("quest_remove_transfer_details", ["p_transaction_id": record.id.uuidString], as: Bool.self); message = "앱의 계좌 안내를 삭제했어요." } } }
                }
            }
            if !record.amPayer && record.status == "awaiting_transfer" {
                Section("보상 받을 계좌 안내 · 선택") {
                    Text("\(record.counterparty)님에게만 아래 계좌를 제공해요. 원치 않으면 별도로 합의한 지급 방법을 사용할 수 있어요.").font(.footnote)
                    TextField("은행명", text: $bank)
                    TextField("예금주", text: $holder).textContentType(.name)
                    TextField("계좌번호", text: $number).keyboardType(.numberPad)
                    if let document = account.policies.first(where: { $0.kind == "transfer_disclosure" }) {
                        Button("제공 항목·목적·보유 기간 보기") { selectedPolicy = document }
                        Toggle("이 거래의 \(record.counterparty)님에게 계좌 정보를 제공하는 데 동의합니다", isOn: $agreed).font(.footnote)
                        Button("동의하고 계좌 안내 저장") {
                            action {
                                let _: Bool = try await account.rpc("quest_save_transfer_details", ["p_transaction_id": record.id.uuidString,
                                    "p_bank": bank, "p_holder": holder, "p_account": number, "p_version": document.version, "p_agreed": agreed], as: Bool.self)
                                agreed = false; message = "이 거래 상대방에게 계좌 안내를 공유했어요."
                            }
                        }.disabled(working || !agreed || !account.policiesVerified || bank.count < 2 || holder.count < 2 || number.filter(\.isNumber).count < 6)
                    }
                }
            }
            if record.amPayer && record.status == "awaiting_transfer" {
                Section("직접 송금") {
                    Text("은행 앱에서 수취인과 금액을 확인해 직접 송금한 뒤 아래 버튼을 눌러 주세요. 이 버튼은 이체를 실행하지 않습니다.").font(.footnote)
                    Button("은행에서 송금했어요") { confirm = "report" }.disabled(working)
                }
            }
            if !record.amPayer && record.status == "transfer_reported" {
                Section("입금 확인") {
                    Text("은행에서 실제 \(record.amount.formatted())원 입금을 확인한 후 완료해 주세요. 상대방이 송금했다고 표시한 상태예요.").font(.footnote)
                    Button("실제 입금을 확인했어요") { confirm = "receive" }.disabled(working)
                }
            }
            if ["awaiting_transfer", "transfer_reported"].contains(record.status) {
                Section("문제가 있나요?") {
                    TextField("미입금·금액 오류 등 사유 10자 이상", text: $reason, axis: .vertical)
                    Button("거래에 이의 남기기", role: .destructive) {
                        action { let _: Bool = try await account.rpc("quest_dispute", ["p_transaction_id": record.id.uuidString, "p_reason": reason], as: Bool.self); message = "이의를 기록했어요. 거래 번호와 증빙을 운영자에게 보내 주세요." }
                    }.disabled(working || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Color.cjTealText) }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            Section { Link("운영자에게 거래 문의", destination: URL(string: "mailto:info@chargajoe.org?subject=\(record.id.uuidString)")!) }
        }
        .navigationTitle("직접 송금 확인").navigationBarTitleDisplayMode(.inline)
        .disabled(working)
        .confirmationDialog(confirm == "report" ? "실제로 송금했나요?" : "실제 입금을 확인했나요?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            if confirm == "report" { Button("송금 사실 기록") { action { let _: Bool = try await account.rpc("quest_transfer_report", ["p_transaction_id": record.id.uuidString], as: Bool.self) } } }
            else { Button("입금 확인하고 거래 완료") { action { let _: Bool = try await account.rpc("quest_transfer_confirm", ["p_transaction_id": record.id.uuidString], as: Bool.self) } } }
        } message: { Text("\(record.amount.formatted())원 · \(record.counterparty)님. 앱은 은행 이체 내역을 조회하지 않아요.") }
        .sheet(item: $selectedPolicy) { AccountPolicyView(document: $0) }
        .task { do { try await account.loadPolicies(); try await reload() } catch { self.error = error.localizedDescription } }
        .onChange(of: account.userID) { _, _ in details = nil; bank = ""; holder = ""; number = ""; dismiss() }
    }
    private func reload() async throws {
        let transactions = try await QuestAccountAPI.transactions()
        guard let value = transactions.first(where: { $0.id == transaction.id }) else { dismiss(); return }
        current = value
        details = try await account.rpc("quest_transfer_details", ["p_transaction_id": value.id.uuidString], as: QuestTransferDetails?.self)
        bank = details?.bankName ?? ""; holder = details?.holderName ?? ""; number = details?.accountNumber ?? ""
    }
    private func action(_ operation: @escaping @MainActor () async throws -> Void) {
        working = true; error = nil
        Task { @MainActor in
            defer { working = false }
            do { try await operation(); try await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
}
