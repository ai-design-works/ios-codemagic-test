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

    func makeUIView(context: Context) -> PaymentWebContainer {

        let configuration = WKWebViewConfiguration()

        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let container = PaymentWebContainer(configuration: configuration)

        let webView = container.webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        context.coordinator.container = container

        // GOLFPAQ側の初回ページには決済用ヘッダーを追加しない。
        webView.load(URLRequest(url: myPageURL))

        return container
    }

    func updateUIView(
        _ uiView: PaymentWebContainer,
        context: Context
    ) {
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        weak var container: PaymentWebContainer?

        private let externalAcceptLanguage =
            "ja,en-US;q=0.9,en;q=0.8"

        private let paymentEntryHost =
            "www.golfpaq.net"

        private var paymentEntryNeedsPrimeReload = false
        private var paymentEntryPrimed = false
        private var paymentTransferErrorAutoBackDone = false

        private func isPaymentEntryURL(_ url: URL) -> Bool {
            guard url.host?.lowercased() == paymentEntryHost else {
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

        private func logNavigation(
            _ prefix: String,
            request: URLRequest
        ) {
            let url = request.url?.absoluteString ?? "(nil)"
            let method = request.httpMethod ?? "GET"
            let language =
                request.value(
                    forHTTPHeaderField: "Accept-Language"
                ) ?? "(default)"

            print(
                "[GOLFPAQ] \(prefix) | " +
                "method=\(method) | " +
                "url=\(url) | " +
                "language=\(language)"
            )
        }

        private func injectTapFeedback(
            into webView: WKWebView
        ) {
            let javaScript = """
            (function() {
                if (document.getElementById('golfpaq-ios-tap-feedback')) {
                    return;
                }

                var style = document.createElement('style');
                style.id = 'golfpaq-ios-tap-feedback';

                style.textContent = `
                    a, button, input[type="button"],
                    input[type="submit"],
                    [role="button"] {
                        -webkit-tap-highlight-color:
                            rgba(0, 0, 0, 0.10);
                    }

                    a:active, button:active,
                    input[type="button"]:active,
                    input[type="submit"]:active,
                    [role="button"]:active {
                        opacity: 0.72 !important;
                        transform: scale(0.985);
                    }
                `;

                (document.head || document.documentElement)
                    .appendChild(style);
            })();
            """

            webView.evaluateJavaScript(javaScript)
        }

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

            logNavigation(
                "window.open",
                request: navigationAction.request
            )

            let method =
                navigationAction.request.httpMethod?
                    .uppercased() ?? "GET"

            // POSTは絶対に作り直さない。
            if method == "POST" {
                webView.load(navigationAction.request)
                return nil
            }

            var request = navigationAction.request

            // Android完成版と同じく、
            // popup/外部決済GETには補正済み言語を使用。
            request.setValue(
                externalAcceptLanguage,
                forHTTPHeaderField: "Accept-Language"
            )

            webView.load(request)

            print(
                "[GOLFPAQ] popup moved to main WebView: " +
                url.absoluteString
            )

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

            logNavigation(
                "navigation",
                request: navigationAction.request
            )

            let scheme = url.scheme?.lowercased() ?? ""

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
                navigationAction.request.httpMethod?
                    .uppercased() ?? "GET"

            let isPost = method == "POST"

            // 外部ホストのGETだけAccept-Languageを補正。
            // POSTには介入しない。
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

                    print(
                        "[GOLFPAQ] external GET corrected: " +
                        url.absoluteString
                    )

                    decisionHandler(.cancel)

                    DispatchQueue.main.async {
                        webView.load(correctedRequest)
                    }

                    return
                }
            }

            // Android完成版と同じ考え方。
            // purchase.phpに入った瞬間から画面を覆い、
            // 一瞬の「転送エラー」を利用者へ見せない。
            if isMainFrame &&
               !isPost &&
               isPaymentEntryURL(url) {

                container?.showPaymentLoading()

                if !paymentEntryPrimed &&
                   !paymentEntryNeedsPrimeReload {

                    paymentEntryNeedsPrimeReload = true

                    print(
                        "[GOLFPAQ] payment entry first reach"
                    )
                }
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            print(
                "[GOLFPAQ] didStart: " +
                (webView.url?.absoluteString ?? "(nil)")
            )
        }

        func webView(
            _ webView: WKWebView,
            didCommit navigation: WKNavigation!
        ) {
            print(
                "[GOLFPAQ] didCommit: " +
                (webView.url?.absoluteString ?? "(nil)")
            )
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {

            guard let finishedURL = webView.url else {
                return
            }

            print(
                "[GOLFPAQ] didFinish: " +
                finishedURL.absoluteString
            )

            injectTapFeedback(into: webView)

            // 決済入口以外へ正常に進んだら
            // ローディングを解除。
            guard isPaymentEntryURL(finishedURL) else {
                container?.hidePaymentLoading()
                return
            }

            let errorCheckJavaScript = """
            (function() {
                var text =
                    (document.body &&
                     document.body.innerText) || '';

                return text.indexOf('転送エラー') !== -1;
            })();
            """

            webView.evaluateJavaScript(
                errorCheckJavaScript
            ) { [weak self, weak webView] result, error in

                guard
                    let self = self,
                    let webView = webView
                else {
                    return
                }

                if let error = error {
                    print(
                        "[GOLFPAQ] transfer-error check JS error: " +
                        error.localizedDescription
                    )
                }

                let hasTransferError =
                    (result as? Bool) == true

                print(
                    "[GOLFPAQ] purchase.php transferError=" +
                    String(hasTransferError)
                )

                if hasTransferError {

                    // 初回prime reloadがまだ必要なら、
                    // 先にreloadを実施する。
                    // エラー検出callbackから先に戻ってしまう競合を防止。
                    if self.paymentEntryNeedsPrimeReload &&
                       !self.paymentEntryPrimed {

                        self.paymentEntryPrimed = true
                        self.paymentEntryNeedsPrimeReload = false

                        print(
                            "[GOLFPAQ] prime reload after transfer error"
                        )

                        DispatchQueue.main.async {
                            webView.load(
                                URLRequest(url: finishedURL)
                            )
                        }

                        return
                    }

                    // prime reload後にも転送エラーなら、
                    // POST再送や自動クリックは行わず、
                    // Android完成版と同じ安全なgoBackだけ行う。
                    guard
                        self.paymentEntryPrimed,
                        !self.paymentTransferErrorAutoBackDone,
                        !webView.isLoading,
                        webView.canGoBack
                    else {
                        return
                    }

                    self.paymentTransferErrorAutoBackDone = true

                    print(
                        "[GOLFPAQ] transfer error after prime -> goBack"
                    )

                    DispatchQueue.main.async {
                        webView.goBack()
                    }

                    return
                }

                // purchase.phpがエラー無しで完了した場合。
                self.container?.hidePaymentLoading()
            }

            // 「転送エラー」が無い場合でも、
            // 初回purchase.phpならAndroid同様1回だけprime。
            if paymentEntryNeedsPrimeReload &&
               !paymentEntryPrimed {

                paymentEntryPrimed = true
                paymentEntryNeedsPrimeReload = false

                print(
                    "[GOLFPAQ] prime reload after normal purchase finish"
                )

                DispatchQueue.main.async {
                    webView.load(
                        URLRequest(url: finishedURL)
                    )
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            print(
                "[GOLFPAQ] navigation error: " +
                error.localizedDescription
            )

            container?.hidePaymentLoading()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            print(
                "[GOLFPAQ] provisional navigation error: " +
                error.localizedDescription
            )

            container?.hidePaymentLoading()
        }
    }
}


// MARK: - WebView + payment loading overlay

final class PaymentWebContainer: UIView {

    let webView: WKWebView

    private let paymentOverlay = UIView()
    private let spinner =
        UIActivityIndicatorView(style: .large)

    init(configuration: WKWebViewConfiguration) {

        webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        super.init(frame: .zero)

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(
                equalTo: leadingAnchor
            ),
            webView.trailingAnchor.constraint(
                equalTo: trailingAnchor
            ),
            webView.topAnchor.constraint(
                equalTo: topAnchor
            ),
            webView.bottomAnchor.constraint(
                equalTo: bottomAnchor
            )
        ])

        paymentOverlay.translatesAutoresizingMaskIntoConstraints = false
        paymentOverlay.backgroundColor =
            UIColor.systemBackground

        paymentOverlay.isHidden = true

        spinner.translatesAutoresizingMaskIntoConstraints = false
        paymentOverlay.addSubview(spinner)

        addSubview(paymentOverlay)

        NSLayoutConstraint.activate([
            paymentOverlay.leadingAnchor.constraint(
                equalTo: leadingAnchor
            ),
            paymentOverlay.trailingAnchor.constraint(
                equalTo: trailingAnchor
            ),
            paymentOverlay.topAnchor.constraint(
                equalTo: topAnchor
            ),
            paymentOverlay.bottomAnchor.constraint(
                equalTo: bottomAnchor
            ),

            spinner.centerXAnchor.constraint(
                equalTo: paymentOverlay.centerXAnchor
            ),
            spinner.centerYAnchor.constraint(
                equalTo: paymentOverlay.centerYAnchor
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPaymentLoading() {
        paymentOverlay.isHidden = false
        spinner.startAnimating()
        bringSubviewToFront(paymentOverlay)
    }

    func hidePaymentLoading() {
        spinner.stopAnimating()
        paymentOverlay.isHidden = true
    }
}

#Preview {
    ContentView()
}
