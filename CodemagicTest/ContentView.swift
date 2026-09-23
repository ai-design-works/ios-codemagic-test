import SwiftUI
import WebKit

struct ContentView: View {
    var body: some View {
        GOLFPAQWebView()
            .ignoresSafeArea(edges: .bottom)
    }
}

struct GOLFPAQWebView: UIViewRepresentable {

    private let myPageURL =
        URL(string: "https://golfpaq.net/booking/mypage")!

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

        // Android版と同様、WebView特有の識別を弱める
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 " +
            "Mobile/15E148 Safari/604.1"

        var request = URLRequest(url: myPageURL)

        // GOLFPAQ通常ページ
        request.setValue(
            "ja,en-US;q=0.9,en;q=0.8",
            forHTTPHeaderField: "Accept-Language"
        )

        webView.load(request)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        // Android版で実機確認済みの値
        private let externalAcceptLanguage =
            "ja,en-US;q=0.9,en;q=0.8"

        // 決済入口ホスト
        private let paymentEntryHost =
            "www.golfpaq.net"

        // このWebViewで決済入口を初めて通ったか
        private var paymentEntryNeedsPrimeReload = false

        // 再読み込みを既に実施したか
        private var paymentEntryPrimed = false

        private func isPaymentEntryURL(_ url: URL) -> Bool {

            guard
                url.host?.lowercased() == paymentEntryHost
            else {
                return false
            }

            let path = url.path.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )

            return path.contains("/payment/") &&
                   path.hasSuffix("purchase.php")
        }

        // target="_blank" / window.open() を同じWebViewで開く
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {

            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url {

                var request = URLRequest(url: url)

                request.setValue(
                    externalAcceptLanguage,
                    forHTTPHeaderField: "Accept-Language"
                )

                webView.load(request)
            }

            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Android版と同じ考え方：
            // purchase.php への最初のGET到達だけを記録
            if navigationAction.targetFrame?.isMainFrame == true &&
               navigationAction.request.httpMethod?.uppercased() != "POST" &&
               isPaymentEntryURL(url) &&
               !paymentEntryPrimed &&
               !paymentEntryNeedsPrimeReload {

                paymentEntryNeedsPrimeReload = true
            }

            let scheme = url.scheme?.lowercased() ?? ""

            // HTTP / HTTPS はWebView内で処理
            if scheme == "http" || scheme == "https" {
                decisionHandler(.allow)
                return
            }

            // tel: / mailto: など
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {

            guard
                paymentEntryNeedsPrimeReload,
                !paymentEntryPrimed,
                let url = webView.url,
                isPaymentEntryURL(url)
            else {
                return
            }

            // Android版と同じく、この画面につき1回だけ実行
            paymentEntryPrimed = true
            paymentEntryNeedsPrimeReload = false

            // Cookieを確定させてから同じ決済入口を再GET
            webView.configuration.websiteDataStore.httpCookieStore
                .getAllCookies { [weak webView] _ in

                    guard let webView = webView else {
                        return
                    }

                    var request = URLRequest(url: url)

                    request.setValue(
                        self.externalAcceptLanguage,
                        forHTTPHeaderField: "Accept-Language"
                    )

                    DispatchQueue.main.async {
                        webView.load(request)
                    }
                }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            print(
                "GOLFPAQ navigation error: \(error.localizedDescription)"
            )
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            print(
                "GOLFPAQ provisional navigation error: \(error.localizedDescription)"
            )
        }
    }
}

#Preview {
    ContentView()
}
