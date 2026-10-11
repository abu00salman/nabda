import SwiftUI
import WebKit

// Same design as android-app/ and desktop-app/: the app loads the real deployed site
// instead of a bundled copy, so every web deploy reaches iPhone users without a new
// App Store build. The native layer only adds what Safari can't: its own icon and
// launch screen, edge-to-edge layout, navigation that stays on the game's domain,
// and a native retry screen for when the first load fails.
enum AppConfig {
    static let url = URL(string: "https://playnabda.com/")!
    static let host = "playnabda.com"
    static let background = UIColor(red: 0x0E / 255, green: 0x14 / 255, blue: 0x1B / 255, alpha: 1)
}

// Shared state between the web view and the SwiftUI overlay.
final class WebModel: ObservableObject {
    @Published var loadFailed = false
    weak var webView: WKWebView?

    func retry() {
        loadFailed = false
        webView?.load(URLRequest(url: AppConfig.url))
    }
}

struct GameWebView: UIViewRepresentable {
    @ObservedObject var model: WebModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Game audio and the page's own state (localStorage) need nothing special here:
        // WKWebView's default data store already persists across launches.
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Dark background everywhere, so no white flash shows around the game
        // while the page loads, and so the page's own safe-area handling is used.
        webView.isOpaque = false
        webView.backgroundColor = AppConfig.background
        webView.scrollView.backgroundColor = AppConfig.background
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false

        model.webView = webView
        webView.load(URLRequest(url: AppConfig.url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: WebModel

        init(model: WebModel) {
            self.model = model
        }

        // Main-frame link taps to other sites open in Safari, not inside the game.
        // Sub-frames (for example ad or embed frames) and in-site navigation are left alone.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard
                navigationAction.targetFrame?.isMainFrame == true,
                navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url,
                url.host != AppConfig.host
            else {
                decisionHandler(.allow)
                return
            }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        // target="_blank" links would otherwise need a second web view. Open them in Safari.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                UIApplication.shared.open(url)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.loadFailed = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showFailureUnlessCancelled(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showFailureUnlessCancelled(error)
        }

        // A user-cancelled load (-999) is normal, for example after a quick second tap.
        // Only real failures show the retry screen.
        private func showFailureUnlessCancelled(_ error: Error) {
            if (error as NSError).code != NSURLErrorCancelled {
                model.loadFailed = true
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var model = WebModel()

    var body: some View {
        ZStack {
            Color(uiColor: AppConfig.background)
                .ignoresSafeArea()

            GameWebView(model: model)
                .ignoresSafeArea()

            if model.loadFailed {
                OfflineView(onRetry: model.retry)
            }
        }
    }
}

struct OfflineView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("تعذّر الاتصال بنبضة")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("تحقّق من الإنترنت ثم حاول مرة أخرى.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
            Button(action: onRetry) {
                Text("إعادة المحاولة")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x5A / 255))
            .foregroundStyle(Color(uiColor: AppConfig.background))
            .padding(.top, 8)
        }
        .padding(24)
        .environment(\.layoutDirection, .rightToLeft)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: AppConfig.background))
    }
}

#Preview {
    ContentView()
}
