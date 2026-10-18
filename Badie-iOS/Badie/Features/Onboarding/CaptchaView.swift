import SwiftUI
import WebKit

/// 人机验证（Cloudflare Turnstile）的状态。令牌只能用一次，发完验证码就重新取。
/// token 为空字符串表示网站没开启人机验证，直接发就行
@MainActor
final class CaptchaModel: ObservableObject {
    @Published private(set) var token: String?
    /// Cloudflare 觉得可疑、需要点一下时为 true，这时把验证框露出来
    @Published private(set) var needsInteraction = false
    @Published private(set) var failed = false
    /// 每重置一次加一，网页视图据此重新加载
    @Published private(set) var attempt = 0

    var isReady: Bool { token != nil }

    func reset() {
        token = nil
        needsInteraction = false
        failed = false
        attempt += 1
    }

    fileprivate func receive(_ message: [String: Any]) {
        if let token = message["token"] as? String {
            self.token = token
            needsInteraction = false
        } else if message["interactive"] as? Bool == true {
            needsInteraction = true
        } else if message["error"] as? String == "expired" {
            reset()
        } else if message["error"] != nil {
            failed = true
        }
    }

    fileprivate func loadFailed() {
        failed = true
    }
}

/// 打开网站上的 /captcha/ 页面（站点密钥只配在网站上），页面通过 messageHandlers.captcha 把令牌交回来。
/// 平时看不见，需要点的时候由外面把高度放开
struct CaptchaView: UIViewRepresentable {
    @ObservedObject var model: CaptchaModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "captcha")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        context.coordinator.load(in: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if context.coordinator.loadedAttempt != model.attempt { context.coordinator.load(in: view) }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "captcha")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let model: CaptchaModel
        private(set) var loadedAttempt = -1

        init(model: CaptchaModel) {
            self.model = model
        }

        func load(in view: WKWebView) {
            loadedAttempt = model.attempt
            view.load(URLRequest(url: SupabaseConfig.captchaPage, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            model.receive(body)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.loadFailed()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.loadFailed()
        }
    }
}
