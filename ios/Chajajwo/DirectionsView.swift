import SwiftUI
import UIKit
import WebKit

/// Own the presentation at the button so directions also work from an existing sheet.
struct DirectionsButton<Content: View>: View {
    let destination: URL?
    let name: String
    @ViewBuilder var label: () -> Content
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { label() }
            .disabled(destination == nil)
            .fullScreenCover(isPresented: $isPresented) {
                if let destination {
                    DirectionsView(destination: destination, name: name)
                }
            }
    }
}

struct DirectionsView: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser: DirectionsBrowser

    init(destination: URL, name: String) {
        self.name = name
        _browser = StateObject(wrappedValue: DirectionsBrowser(destination: destination))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if browser.isShowingLanding {
                    Text("‘설치없이 지도보기’를 선택하면 이 화면에서 경로를 확인할 수 있어요.")
                        .font(.subheadline)
                        .foregroundStyle(Color.cjTealText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cjSuccessFill)
                }
                if browser.showBlockedLinkNotice {
                    HStack {
                        Text("외부 앱으로 연결되는 기능이에요. 이 화면에서 길찾기를 계속할 수 있어요.")
                            .font(.footnote)
                        Spacer(minLength: 8)
                        Button { browser.showBlockedLinkNotice = false } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("안내 닫기")
                    }
                    .padding(.leading, 16)
                    .background(Color.cjInset)
                }
                ZStack {
                    DirectionsWebView(browser: browser)
                        .accessibilityIdentifier("directions.web")
                        .opacity(browser.errorMessage == nil ? 1 : 0)
                        .accessibilityHidden(browser.errorMessage != nil)
                    if let message = browser.errorMessage {
                        ContentUnavailableView {
                            Label("길찾기를 불러오지 못했어요", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("다시 시도") { browser.reload() }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("directions.retry")
                        }
                    } else if browser.isLoading {
                        ProgressView("길찾기 불러오는 중")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .allowsHitTesting(false)
                    }
                }
            }
            .navigationTitle("길찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("길찾기").font(.headline)
                        Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!browser.canGoBack)
                        .accessibilityLabel("길찾기 뒤로 가기")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("길찾기 새로고침")
                    Button("닫기") { dismiss() }
                        .accessibilityIdentifier("directions.close")
                }
            }
        }
        .onAppear { browser.start() }
    }
}

@MainActor
private final class DirectionsBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var isLoading = true
    @Published private(set) var canGoBack = false
    @Published private(set) var isShowingLanding = false
    @Published private(set) var errorMessage: String?
    @Published var showBlockedLinkNotice = false

    let webView: WKWebView
    private let destination: URL
    private var started = false
    private var navigationObservations: [NSKeyValueObservation] = []

    init(destination: URL) {
        self.destination = destination
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        // The mobile map also changes its URL/history without a full page load.
        navigationObservations = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateNavigation() }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateNavigation() }
            }
        ]
    }

    func start() {
        guard !started else { return }
        started = true
        load(destination)
    }

    func reload() {
        errorMessage = nil
        showBlockedLinkNotice = false
        // A provisional failure may leave webView.url empty or at the bridge page.
        if let url = webView.url, DirectionsURL.inAppURL(url) != nil {
            webView.reload()
        } else {
            load(destination)
        }
    }

    func goBack() {
        guard webView.canGoBack else { return }
        errorMessage = nil
        showBlockedLinkNotice = false
        webView.goBack()
    }

    private func load(_ url: URL) {
        guard let url = DirectionsURL.inAppURL(url) else { return }
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let inAppURL = DirectionsURL.inAppURL(url) else {
            // Kakao's mobile landing page tries its app scheme automatically. Keep
            // that page and its "설치없이 지도보기" option visible instead.
            if action.navigationType == .linkActivated { showBlockedLinkNotice = true }
            decisionHandler(.cancel)
            return
        }
        if action.targetFrame == nil || action.navigationType == .linkActivated || url != inAppURL {
            // Load clicked links and target=_blank in this web view ourselves.
            // This also keeps universal links from being handed to an installed app.
            decisionHandler(.cancel)
            var request = action.request
            request.url = inAppURL
            webView.load(request)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
        showBlockedLinkNotice = false
        updateNavigation()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateNavigation()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        updateNavigation()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failed(URLError(.networkConnectionLost))
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           let inAppURL = DirectionsURL.inAppURL(url) {
            var request = navigationAction.request
            request.url = inAppURL
            webView.load(request)
        }
        return nil
    }

    // Prevent link context menus from offering an external browser or app.
    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        completionHandler(nil)
    }

    private func updateNavigation() {
        canGoBack = webView.canGoBack
        isShowingLanding = webView.url?.host?.lowercased() == "applink.map.kakao.com"
    }

    private func failed(_ error: Error) {
        let error = error as NSError
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else { return }
        isLoading = false
        errorMessage = "인터넷 연결을 확인하고 다시 시도해주세요."
        updateNavigation()
    }
}

private struct DirectionsWebView: UIViewRepresentable {
    let browser: DirectionsBrowser

    func makeUIView(context: Context) -> WKWebView { browser.webView }

    // SwiftUI updates must not reload the page or clear the entered starting point.
    func updateUIView(_ uiView: WKWebView, context: Context) { }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }
}
