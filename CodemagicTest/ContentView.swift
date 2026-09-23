import SwiftUI
import WebKit
import UIKit

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

        // 初回のGOLFPAQページには余計な決済用ヘッダーを付けない。
        // Android完成版と同じ考え方。
        webView.load(URLRequest(url: myPageURL))

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        private let externalAcceptLanguage =
            "ja,en-US;q=0.9,en;q=0.8"

        private let paymentEntryHost =
            "www.golfpaq.net"

        private var paymentEntryNeedsPrimeReload = false
        private var paymentEntryPrimed = false
        private var paymentTransferErrorAutoBackDone = false

        // MARK: - URL判定

        private func isPaymentEntryURL(_ url: URL) -> Bool {

            guard
                url.host?.lowercased() == paymentEntryHost
            else {
                return false
            }

            let path = url.path.lowercased()

            return path.contains("/payment/") &&
                   path.hasSuffix("/purchase.php")
        }

        private func isExternalHost(_ url: URL) -> Bool {

            guard let host = url.host?.lowercased() else {
                return false
            }

            return host != "golfpaq.net" &&
                   !host.hasSuffix(".golfpaq.net")
        }

        // MARK: - target="_blank" / window.open()

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {

            guard
                navigationAction.targetFrame == nil,
                let url = navigationAction.request.url
            else {
                return nil
            }

            let method =
                navigationAction.request.httpMethod?.uppercased() ?? "GET"

            // POSTは絶対にGETへ変換しない。
            if method == "POST" {
                webView.load(navigationAction.request)
                return nil
            }

            var request = navigationAction.request

            request.setValue(
                externalAcceptLanguage,
                forHTTPHeaderField: "Accept-Language"
            )

            webView.load(request)

            return nil
        }

        // MARK: - ナビゲーション制御

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""

            // tel: / mailto: 等
            if scheme != "http" && scheme != "https" {

                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }

                decisionHandler(.allow)
                return
            }

            let isMainFrame =
                navigationAction.targetFrame?.isMainFrame == true

            let method =
                navigationAction.request.httpMethod?.uppercased() ?? "GET"

            let isPost = method == "POST"

            // ---------------------------------------------------------
            // Android完成版と同じ重要処理
            //
            // golfpaq.net以外へのメインフレームGET
            // （VeriTrans等）にAccept-Languageを付け直す。
            //
            // POSTには絶対に触れない。
            //
            // すでに正しいヘッダーが入っている場合はallowすることで
            // 無限リロードを防止。
            // ---------------------------------------------------------

            if isMainFrame &&
               !isPost &&
               isExternalHost(url) {

                let currentLanguage =
                    navigationAction.request.value(
                        forHTTPHeaderField: "Accept-Language"
                    )

                if currentLanguage != externalAcceptLanguage {

                    var correctedRequest =
                        navigationAction.request

                    correctedRequest.setValue(
                        externalAcceptLanguage,
                        forHTTPHeaderField: "Accept-Language"
                    )

                    decisionHandler(.cancel)

                    DispatchQueue.main.async {
                        webView.load(correctedRequest)
                    }

                    return
                }
            }

            // ---------------------------------------------------------
            // purchase.php 初回到達を記録
            // ---------------------------------------------------------

            if isMainFrame &&
               !isPost &&
               isPaymentEntryURL(url) &&
               !paymentEntryPrimed &&
               !paymentEntryNeedsPrimeReload {

                paymentEntryNeedsPrimeReload = true
            }

            decisionHandler(.allow)
        }

        // MARK: - 読み込み完了

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {

            guard let finishedURL = webView.url else {
                return
            }

            // purchase.php以外なら通常処理
            guard isPaymentEntryURL(finishedURL) else {
                return
            }

            // ---------------------------------------------------------
            // Android版と同じ転送エラー検出
            // DOMは変更せず本文を読むだけ。
            // ---------------------------------------------------------

            let errorCheckJavaScript = """
            (function() {
                var text =
                    (document.body && document.body.innerText) || '';
                return text.indexOf('転送エラー') !== -1;
            })();
            """

            webView.evaluateJavaScript(
                errorCheckJavaScript
            ) { [weak self, weak webView] result, _ in

                guard
                    let self = self,
                    let webView = webView
                else {
                    return
                }

                let hasTransferError =
                    (result as? Bool) == true

                guard hasTransferError else {
                    return
                }

                // 再読み込み中には戻らない。
                // Android版のprogressBar判定に相当。
                guard !webView.isLoading else {
                    return
                }

                guard
                    self.paymentEntryPrimed,
                    !self.paymentTransferErrorAutoBackDone,
                    webView.canGoBack
                else {
                    return
                }

                self.paymentTransferErrorAutoBackDone = true

                webView.goBack()
            }

            // ---------------------------------------------------------
            // purchase.php 初回到達時のみ1回再GET
            //
            // Android版:
            // CookieManager.flush()
            // ↓
            // loadUrl(finishedUrl)
            //
            // WKWebViewにはAndroidと同じflush APIは存在しないため、
            // 永続WKWebsiteDataStore上で同じURLを1回だけ再GETする。
            //
            // ここではAccept-Languageを追加しない。
            // Android完成版のloadUrl(finishedUrl)と合わせる。
            // ---------------------------------------------------------

            guard
                paymentEntryNeedsPrimeReload,
                !paymentEntryPrimed
            else {
                return
            }

            paymentEntryPrimed = true
            paymentEntryNeedsPrimeReload = false

            DispatchQueue.main.async {
                webView.load(
                    URLRequest(url: finishedURL)
                )
            }
        }

        // MARK: - エラー

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
