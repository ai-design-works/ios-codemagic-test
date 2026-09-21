import SwiftUI
import WebKit

struct ContentView: View {
    var body: some View {
        GOLFPAQWebView()
            .ignoresSafeArea(edges: .bottom)
    }
}

struct GOLFPAQWebView: UIViewRepresentable {

    private let myPageURL = URL(string: "https://golfpaq.net/booking/mypage")!

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {

        let configuration = WKWebViewConfiguration()

        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Android版の決済ページ対策に合わせ、
        // WebView特有のUser-Agent識別を弱める
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 " +
            "Mobile/15E148 Safari/604.1"

        var request = URLRequest(url: myPageURL)
        request.setValue(
            "ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7",
            forHTTPHeaderField: "Accept-Language"
        )

        webView.load(request)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        // target="_blank" / window.open() を同じWebViewで開く
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {

            if navigationAction.targetFrame == nil {
                var request = navigationAction.request
                request.setValue(
                    "ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7",
                    forHTTPHeaderField: "Accept-Language"
                )
                webView.load(request)
            }

            return nil
        }

        // 通常のページ遷移にもAccept-Languageを付与
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let host = url.host?.lowercased() ?? ""

            // GOLFPAQおよびVeriTrans決済ページはWebView内で許可
            if host.contains("golfpaq.net") ||
               host.contains("veritrans.co.jp") {
                decisionHandler(.allow)
                return
            }

            // その他のHTTP/HTTPSページも基本的にWebView内で処理
            if url.scheme == "http" || url.scheme == "https" {
                decisionHandler(.allow)
                return
            }

            // tel:, mailto: 等はiOS側へ渡す
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            print("GOLFPAQ navigation error: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            print("GOLFPAQ provisional navigation error: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
}
