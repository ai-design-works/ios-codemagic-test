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

        // Build 8: 通信エラー画面の「再読み込み」はCoordinator側の
        // 安全なURL判定（retryAfterCommunicationError）に委譲する。
        container.onCommunicationErrorRetryTapped = {
            [weak coordinator = context.coordinator, weak webView] in
            coordinator?.retryAfterCommunicationError(webView: webView)
        }

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

        // 本番Releaseでは詳細ログを出力しない。
        // DEBUG時の診断能力のみ維持し、navigationロジックには一切影響しない。
        private func debugLog(_ message: String) {
            #if DEBUG
            print(message)
            #endif
        }

        // MARK: - Build 8 追加機能用の独立State
        // 上記3つの決済用Stateとは完全に分離している。

        private var hasCompletedInitialLoad = false
        private var initialLoadRetried = false

        private var pendingMainFrameNavigationIsPost = false
        private var pendingMainFrameNavigationIsPaymentEntry = false
        private var pendingMainFrameNavigationURL: URL?

        // 自分自身が発生させたdecisionHandler(.cancel)による
        // didFail/didFailProvisionalNavigationを、本物の通信障害として
        // 誤検知しないためのフラグ。cancelを呼ぶ直前に必ずtrueにする。
        private var pendingSelfInitiatedCancel = false

        // 通信エラー画面の「再読み込み」で安全に使える、
        // 直近に確認済みの非POST・非決済GET URL。
        private var lastSafeRetryURL: URL?

        private var awaitingPostSigninNavigation = false

        private let signinURL =
            URL(string: "https://golfpaq.net/booking/signin")!

        private let myPageDestinationURL =
            URL(string: "https://golfpaq.net/booking/mypage")!

        private func matchesExactURL(_ url: URL, _ target: URL) -> Bool {
            return url.host?.lowercased() == target.host?.lowercased() &&
                   url.path.lowercased() == target.path.lowercased()
        }

        private func isNoticeTopPageURL(_ url: URL) -> Bool {
            guard url.host?.lowercased() == "www.golfpaq.net" else {
                return false
            }

            let path = url.path
            return path.isEmpty || path == "/"
        }

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

            debugLog(
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

        // MARK: - Build 8: Android完成版パリティ機能
        // 決済コード（isPaymentEntryURL / paymentEntryHost / externalAcceptLanguage /
        // isExternalHost / prime reload / transfer error検出 / safe goBack /
        // POST処理 / window.openの既存決済処理）は一切変更しない。
        // 以下はすべて独立した追加関数・追加Stateのみで構成する。

        private func injectAndroidParityCSS(
            into webView: WKWebView
        ) {
            let javaScript = """
            (function() {
                if (document.getElementById('golfpaq_app_wrapper_fix')) {
                    return;
                }

                var style = document.createElement('style');
                style.id = 'golfpaq_app_wrapper_fix';

                style.textContent = `
                    .card-body p.mb-0 {
                        word-break: keep-all;
                        overflow-wrap: break-word;
                    }

                    .cover {
                        background-size: contain !important;
                        background-position: center top !important;
                        background-repeat: no-repeat !important;
                        background-color: #dff1fb !important;
                    }

                    @media (max-width: 767.98px) {
                        .cover h1.display-5 {
                            font-size: 1.375rem !important;
                        }
                    }
                `;

                (document.head || document.documentElement)
                    .appendChild(style);
            })();
            """

            webView.evaluateJavaScript(javaScript)
        }

        private func injectPlanColumnNowrapFix(
            into webView: WKWebView
        ) {
            let javaScript = """
            (function() {
                var tables = document.querySelectorAll('table');

                for (var t = 0; t < tables.length; t++) {
                    var table = tables[t];

                    if (table.getAttribute('data-golfpaq-plan-fix') === '1') {
                        continue;
                    }

                    var firstRow = table.querySelector('tr');
                    if (!firstRow) {
                        continue;
                    }

                    var cells = firstRow.children;
                    var planIndex = -1;

                    for (var i = 0; i < cells.length; i++) {
                        var text = (cells[i].textContent || '').trim();
                        if (text === 'プラン') {
                            planIndex = i;
                            break;
                        }
                    }

                    if (planIndex === -1) {
                        continue;
                    }

                    table.setAttribute('data-golfpaq-plan-fix', '1');

                    var rows = table.querySelectorAll('tr');
                    for (var r = 0; r < rows.length; r++) {
                        var rowCells = rows[r].children;
                        if (rowCells.length > planIndex) {
                            rowCells[planIndex].style.whiteSpace = 'nowrap';
                        }
                    }
                }
            })();
            """

            webView.evaluateJavaScript(javaScript)
        }

        private func injectPaymentButtonDisplayFix(
            into webView: WKWebView
        ) {
            let javaScript = """
            (function() {
                var targetText = 'クレジットカードで決済';
                var candidates = document.querySelectorAll(
                    'button, a, input[type="submit"], input[type="button"]'
                );

                for (var i = 0; i < candidates.length; i++) {
                    var el = candidates[i];

                    if (el.getAttribute('data-golfpaq-cc-button-fix') === '1') {
                        continue;
                    }

                    var text =
                        (el.tagName === 'INPUT'
                            ? (el.value || '')
                            : (el.textContent || '')).trim();

                    if (text !== targetText) {
                        continue;
                    }

                    el.setAttribute('data-golfpaq-cc-button-fix', '1');

                    el.style.whiteSpace = 'nowrap';
                    el.style.overflow = 'hidden';
                    el.style.textOverflow = 'ellipsis';
                    el.style.paddingLeft = '12px';
                    el.style.paddingRight = '12px';
                    el.style.minHeight = '44px';
                    el.style.boxSizing = 'border-box';
                    el.style.display = 'inline-flex';
                    el.style.alignItems = 'center';
                    el.style.justifyContent = 'center';
                }
            })();
            """

            webView.evaluateJavaScript(javaScript)
        }

        private func injectNoticeAutoScroll(
            into webView: WKWebView
        ) {
            let javaScript = """
            (function() {
                if (window.__golfpaqNoticeScrollDone__) {
                    return;
                }
                window.__golfpaqNoticeScrollDone__ = true;

                var attempts = 0;
                var maxAttempts = 5;

                function scrollToNotice() {
                    attempts++;

                    var heading = null;
                    var candidates =
                        document.querySelectorAll('h1, h2, h3, h4, h5, h6');

                    for (var i = 0; i < candidates.length; i++) {
                        var text = (candidates[i].textContent || '').trim();
                        if (text === '最新情報') {
                            heading = candidates[i];
                            break;
                        }
                    }

                    if (heading) {
                        var rect = heading.getBoundingClientRect();
                        var targetY =
                            rect.top + window.pageYOffset - 4;

                        window.scrollTo({
                            top: targetY,
                            behavior: 'auto'
                        });
                    }

                    if (attempts < maxAttempts) {
                        setTimeout(scrollToNotice, attempts * 400);
                    }
                }

                scrollToNotice();
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

            debugLog(
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

            // isMainFrameは非httpスキーム分岐より前に判定する。
            // didFail/didFailProvisionalNavigationはmain-frameのナビゲーションにしか
            // 発火しないため、サブフレーム（埋め込みiframe内のtel:リンク等）のcancelで
            // pendingSelfInitiatedCancelを立てると、対応する失敗通知が来ず
            // フラグが残留し、後続の本物のmain-frame障害を誤って握り潰す恐れがある。
            let isMainFrame =
                navigationAction.targetFrame?.isMainFrame == true

            let scheme = url.scheme?.lowercased() ?? ""

            if scheme != "http" && scheme != "https" {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)

                    if isMainFrame {
                        pendingSelfInitiatedCancel = true
                    }

                    decisionHandler(.cancel)
                    return
                }

                decisionHandler(.allow)
                return
            }

            let method =
                navigationAction.request.httpMethod?
                    .uppercased() ?? "GET"

            let isPost = method == "POST"

            // Build 8: 初回ロード失敗時の自動再試行・通信エラー画面用に、
            // 直近のmainFrameナビゲーションの種別・URLのみを読み取り専用で記録する。
            // 既存のdecisionHandler分岐・判定条件は一切変更しない。
            if isMainFrame {
                pendingMainFrameNavigationIsPost = isPost
                pendingMainFrameNavigationIsPaymentEntry = isPaymentEntryURL(url)
                pendingMainFrameNavigationURL = url
            }

            // Build 8: MY PAGEログイン後の誤遷移補正のarming。
            // 「signinページを開いただけ」ではarmedにしない
            // （パスワード再発行等の通常GET遷移を誤ってログイン試行と判定しないため）。
            // 「signinページから実際にPOSTが送信された（ログイン試行そのもの）」
            // ことを条件にする。POST自体の扱いは一切変更しない（読み取り専用の観測のみ）。
            if isMainFrame,
               isPost,
               let currentURL = webView.url,
               matchesExactURL(currentURL, signinURL) {
                awaitingPostSigninNavigation = true
            }

            // Build 8: MY PAGEログイン後の誤遷移補正は【保留】。
            // 複数回のレビューで、ログイン失敗時のCSRF確認ページ・
            // パスワード再発行誘導・エラーページ等への正規のリダイレクトを
            // 「誤遷移」と誤判定し、正規のページを見せずにMY PAGEへ強制的に
            // 差し戻してしまう恐れがあると指摘された。GOLFPAQ側の実際の
            // ログイン成功/失敗時のリダイレクト仕様がソースコードからは
            // 確認できず、安全性を保証できないため、推測によるナビゲーション
            // 介入（decisionHandler(.cancel) + 強制load）は実装しない。
            // 検知（いつ・どこへ遷移したか）のみdebugLogで観測し、
            // ナビゲーションそのものには一切介入しない。
            // 実機ログでGOLFPAQの実際のリダイレクト仕様（成功時・失敗時とも）
            // を確認できるまで、この機能は保留とする。
            if awaitingPostSigninNavigation &&
               isMainFrame &&
               !isPost {

                awaitingPostSigninNavigation = false

                let isSignin = matchesExactURL(url, signinURL)
                let isMyPage = matchesExactURL(url, myPageDestinationURL)

                if !isSignin &&
                   !isMyPage &&
                   !isPaymentEntryURL(url) {

                    debugLog(
                        "[GOLFPAQ] post-signin navigation observed " +
                        "(correction held pending device verification): " +
                        url.absoluteString
                    )
                }
            }

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

                    debugLog(
                        "[GOLFPAQ] external GET corrected: " +
                        url.absoluteString
                    )

                    pendingSelfInitiatedCancel = true
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

                    debugLog(
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
            debugLog(
                "[GOLFPAQ] didStart: " +
                (webView.url?.absoluteString ?? "(nil)")
            )
        }

        func webView(
            _ webView: WKWebView,
            didCommit navigation: WKNavigation!
        ) {
            debugLog(
                "[GOLFPAQ] didCommit: " +
                (webView.url?.absoluteString ?? "(nil)")
            )

            // Build 8: レイアウト崩れ・ちらつき軽減のため、
            // didCommit相当の早い段階でもCSS補正を適用する（決済ページは除外）。
            if let committedURL = webView.url,
               !isPaymentEntryURL(committedURL) {
                injectAndroidParityCSS(into: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {

            guard let finishedURL = webView.url else {
                return
            }

            debugLog(
                "[GOLFPAQ] didFinish: " +
                finishedURL.absoluteString
            )

            hasCompletedInitialLoad = true
            pendingSelfInitiatedCancel = false
            container?.hideCommunicationError()

            injectTapFeedback(into: webView)

            // Build 8: Android完成版パリティ機能。決済ページ(purchase.php)では実行しない。
            if !isPaymentEntryURL(finishedURL) {
                injectAndroidParityCSS(into: webView)
                injectPlanColumnNowrapFix(into: webView)
                injectPaymentButtonDisplayFix(into: webView)

                if isNoticeTopPageURL(finishedURL) {
                    injectNoticeAutoScroll(into: webView)
                }
            }

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
                    self.debugLog(
                        "[GOLFPAQ] transfer-error check JS error: " +
                        error.localizedDescription
                    )
                }

                let hasTransferError =
                    (result as? Bool) == true

                self.debugLog(
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

                        self.debugLog(
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

                    self.debugLog(
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

                debugLog(
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
            debugLog(
                "[GOLFPAQ] navigation error: " +
                error.localizedDescription
            )

            container?.hidePaymentLoading()

            handleLoadFailure(webView: webView, error: error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            debugLog(
                "[GOLFPAQ] provisional navigation error: " +
                error.localizedDescription
            )

            container?.hidePaymentLoading()

            handleLoadFailure(webView: webView, error: error)
        }

        // Build 8: 通常ページの初回ロード失敗時の1回限定自動再試行、および
        // 通信エラー画面の表示。決済POST・購入ページ(purchase.php)には
        // 絶対に適用しない。既存の`container?.hidePaymentLoading()`（上記）は
        // これまで通り無条件で先に実行され、本関数はそれに追加するだけである。
        private func handleLoadFailure(
            webView: WKWebView,
            error: Error
        ) {
            // 自分自身が直前にdecisionHandler(.cancel)を呼んだ結果の失敗通知は、
            // エラーコードを推測で判定せず、明示的フラグで確実に無視する。
            // （WKWebViewはポリシーによるcancelをWebKitErrorDomain/102等で
            //   通知することがあり、NSURLErrorCancelledのみのチェックでは
            //   検知漏れが起こり得るため、専用フラグ方式に変更した）
            if pendingSelfInitiatedCancel {
                pendingSelfInitiatedCancel = false
                return
            }

            // 念のため、他要因によるナビゲーション取り消し
            // （新しいナビゲーションによる差し替え等）も通信障害として扱わない。
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                return
            }

            // 決済POST・決済ページ関連の失敗には一切介入しない。
            guard
                !pendingMainFrameNavigationIsPost,
                !pendingMainFrameNavigationIsPaymentEntry
            else {
                return
            }

            if !hasCompletedInitialLoad && !initialLoadRetried {
                initialLoadRetried = true

                debugLog(
                    "[GOLFPAQ] initial load failed, retrying once"
                )

                DispatchQueue.main.async {
                    webView.load(
                        URLRequest(url: self.myPageDestinationURL)
                    )
                }

                return
            }

            // 通信エラー画面の「再読み込み」で使う安全なURL。
            // ここに到達する時点で、直近のmain-frameナビゲーションが
            // 非POST・非決済ページであることは上のguardで確認済み。
            lastSafeRetryURL = pendingMainFrameNavigationURL ?? myPageDestinationURL

            debugLog(
                "[GOLFPAQ] showing communication error screen"
            )

            container?.showCommunicationError()
        }

        // Build 8: 通信エラー画面の「再読み込み」ボタンから呼ばれる。
        // 安全なGET URLが判明している場合はそのURLへ明示的にload()し、
        // 不明な場合のみwebView.reload()にフォールバックする。
        // いずれの経路でもPOSTの再構築・再送は絶対に行わない。
        func retryAfterCommunicationError(webView: WKWebView?) {
            guard let webView = webView else {
                return
            }

            if let retryURL = lastSafeRetryURL {
                debugLog(
                    "[GOLFPAQ] communication error retry: load(" +
                    retryURL.absoluteString + ")"
                )
                webView.load(URLRequest(url: retryURL))
            } else {
                debugLog(
                    "[GOLFPAQ] communication error retry: reload()"
                )
                webView.reload()
            }
        }
    }
}


// MARK: - WebView + payment loading overlay

final class PaymentWebContainer: UIView {

    let webView: WKWebView

    private let paymentOverlay = UIView()
    private let spinner =
        UIActivityIndicatorView(style: .large)
    private let paymentLoadingLabel = UILabel()

    // Build 8: 通常ページの通信エラー表示用。決済オーバーレイとは別UI・別state。
    private let communicationErrorOverlay = UIView()
    private let communicationErrorLabel = UILabel()
    private let communicationErrorRetryButton = UIButton(type: .system)

    // 再読み込みの実処理はCoordinator側（安全なURL判定）に委譲する。
    var onCommunicationErrorRetryTapped: (() -> Void)?

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

        paymentLoadingLabel.translatesAutoresizingMaskIntoConstraints = false
        paymentLoadingLabel.text = "ページに移動中"
        paymentLoadingLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        paymentLoadingLabel.textColor = UIColor.secondaryLabel
        paymentLoadingLabel.textAlignment = .center
        paymentOverlay.addSubview(paymentLoadingLabel)

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
            ),

            paymentLoadingLabel.topAnchor.constraint(
                equalTo: spinner.bottomAnchor,
                constant: 12
            ),
            paymentLoadingLabel.centerXAnchor.constraint(
                equalTo: paymentOverlay.centerXAnchor
            )
        ])

        // Build 8: 通常ページの通信エラーオーバーレイ（決済オーバーレイとは独立）。
        communicationErrorOverlay.translatesAutoresizingMaskIntoConstraints = false
        communicationErrorOverlay.backgroundColor =
            UIColor.systemBackground
        communicationErrorOverlay.isHidden = true

        communicationErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        communicationErrorLabel.text = "通信エラーが発生しました"
        communicationErrorLabel.font = UIFont.preferredFont(forTextStyle: .body)
        communicationErrorLabel.textColor = UIColor.label
        communicationErrorLabel.textAlignment = .center
        communicationErrorLabel.numberOfLines = 0
        communicationErrorOverlay.addSubview(communicationErrorLabel)

        communicationErrorRetryButton.translatesAutoresizingMaskIntoConstraints = false
        communicationErrorRetryButton.setTitle("再読み込み", for: .normal)
        communicationErrorRetryButton.addTarget(
            self,
            action: #selector(handleCommunicationErrorRetryTapped),
            for: .touchUpInside
        )
        communicationErrorOverlay.addSubview(communicationErrorRetryButton)

        addSubview(communicationErrorOverlay)

        NSLayoutConstraint.activate([
            communicationErrorOverlay.leadingAnchor.constraint(
                equalTo: leadingAnchor
            ),
            communicationErrorOverlay.trailingAnchor.constraint(
                equalTo: trailingAnchor
            ),
            communicationErrorOverlay.topAnchor.constraint(
                equalTo: topAnchor
            ),
            communicationErrorOverlay.bottomAnchor.constraint(
                equalTo: bottomAnchor
            ),

            communicationErrorLabel.centerXAnchor.constraint(
                equalTo: communicationErrorOverlay.centerXAnchor
            ),
            communicationErrorLabel.centerYAnchor.constraint(
                equalTo: communicationErrorOverlay.centerYAnchor,
                constant: -24
            ),
            communicationErrorLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: communicationErrorOverlay.leadingAnchor,
                constant: 24
            ),
            communicationErrorLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: communicationErrorOverlay.trailingAnchor,
                constant: -24
            ),

            communicationErrorRetryButton.topAnchor.constraint(
                equalTo: communicationErrorLabel.bottomAnchor,
                constant: 16
            ),
            communicationErrorRetryButton.centerXAnchor.constraint(
                equalTo: communicationErrorOverlay.centerXAnchor
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

    func showCommunicationError() {
        communicationErrorOverlay.isHidden = false
        bringSubviewToFront(communicationErrorOverlay)
    }

    func hideCommunicationError() {
        communicationErrorOverlay.isHidden = true
    }

    @objc private func handleCommunicationErrorRetryTapped() {
        hideCommunicationError()
        onCommunicationErrorRetryTapped?()
    }
}

#Preview {
    ContentView()
}
