import SwiftUI
import WebKit
import UIKit

// MARK: - Build 9: ホーム画面のentry point

// Android完成版のMainActivity.kt / Config.ktを根拠とする。
// MY PAGE: Config.MY_PAGE_URL、ヘッダータイトルはstrings.xmlのtitle_my_page。
// ツアー予約: Config.TOUR_RESERVATION_URL、ヘッダータイトルはtitle_tour_reservation
// （ホームボタンの文言「ツアーを予約する」とヘッダーの文言「ツアー予約」は
// Android側でも別の文字列であり、意図的にそのまま踏襲する）。
enum EntryPoint: Equatable {
    case myPage
    case tourReservation

    var url: URL {
        switch self {
        case .myPage:
            return URL(string: "https://golfpaq.net/booking/mypage")!
        case .tourReservation:
            return URL(string: "https://golfpaq.net/booking/")!
        }
    }

    var headerTitle: String {
        switch self {
        case .myPage:
            return "MY PAGE"
        case .tourReservation:
            return "ツアー予約"
        }
    }
}

private enum GOLFPAQBrand {
    static let green = Color(red: 0x1B / 255.0, green: 0x5E / 255.0, blue: 0x20 / 255.0)
    static let textSecondary = Color(red: 0x5F / 255.0, green: 0x63 / 255.0, blue: 0x68 / 255.0)
    static let background = Color(red: 0xF5 / 255.0, green: 0xF7 / 255.0, blue: 0xF5 / 255.0)
}

struct ContentView: View {

    // Build 9: nilならホーム画面、値があればそのentry pointでWeb画面を表示する。
    // 単一のGOLFPAQWebView（単一WKWebView・単一Coordinator）はZStack内に常時
    // 配置し続け、opacity/allowsHitTestingで表示/非表示を切り替えるだけで、
    // ホーム⇔Web画面の遷移のたびにWKWebViewを再生成することは絶対にしない。
    @State private var activeEntryPoint: EntryPoint?
    @State private var pendingEntryPoint: EntryPoint?

    @Environment(\.openURL) private var openURL

    // Android完成版 Config.INFO_URL。
    // 「お知らせ・緊急告知」はアプリ内WebViewを経由せず、端末の既定ブラウザで
    // 開く（MainActivity.kt: openInExternalBrowser）。WebView側の状態
    // （Cookie・session・決済state）には一切触れない。
    private let infoURL =
        URL(string: "https://www.golfpaq.net/info.html")!

    var body: some View {
        VStack(spacing: 0) {
            if let entryPoint = activeEntryPoint {
                AppHeaderView(title: entryPoint.headerTitle) {
                    // Build 9: ×はホーム画面へ戻る純粋なSwiftUI state変更のみ。
                    // webView.goBack() / reload() / Cookie・session操作は
                    // 一切行わない（WebViewActivity.kt: setupToolbar の
                    // finish()と同じ「戻り先を切り替えるだけ」という考え方）。
                    activeEntryPoint = nil
                }
            }

            ZStack {
                GOLFPAQWebView(pendingEntryPoint: $pendingEntryPoint)
                    .opacity(activeEntryPoint == nil ? 0 : 1)
                    .allowsHitTesting(activeEntryPoint != nil)

                if activeEntryPoint == nil {
                    HomeView(
                        onSelectMyPage: { navigate(to: .myPage) },
                        onSelectTourReservation: { navigate(to: .tourReservation) },
                        onSelectInfo: { openURL(infoURL) }
                    )
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func navigate(to entryPoint: EntryPoint) {
        activeEntryPoint = entryPoint
        pendingEntryPoint = entryPoint
    }
}

// MARK: - Build 9: ホーム画面

// Android完成版 activity_main.xml / strings.xml を根拠に、文言・配置を
// 可能な限り忠実に再現する。
struct HomeView: View {

    let onSelectMyPage: () -> Void
    let onSelectTourReservation: () -> Void
    let onSelectInfo: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("GOLFPAQ")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(GOLFPAQBrand.green)
                    .tracking(2)

                Text("ようこそ GOLFPAQ へ")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .padding(.top, 12)

                Text("下のボタンから、マイページやツアー予約ページをすぐに開けます。")
                    .font(.system(size: 14))
                    .foregroundColor(GOLFPAQBrand.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                HomeMenuButton(title: "MY PAGE", action: onSelectMyPage)
                    .padding(.top, 48)

                HomeMenuButton(title: "ツアーを予約する", action: onSelectTourReservation)
                    .padding(.top, 20)

                HomeMenuButton(title: "お知らせ・緊急告知", action: onSelectInfo)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .background(GOLFPAQBrand.background)
    }
}

private struct HomeMenuButton: View {

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
        .background(GOLFPAQBrand.green)
        .cornerRadius(14)
    }
}

// MARK: - Build 9: アプリ側ヘッダー（Web画面表示時のみ）

// Android完成版 activity_web_view.xml（MaterialToolbar、緑背景・白文字・
// ×アイコン）を根拠とする。
struct AppHeaderView: View {

    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("戻る")

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.leading, 4)
        .padding(.trailing, 16)
        .background(GOLFPAQBrand.green)
    }
}

struct GOLFPAQWebView: UIViewRepresentable {

    // Build 9: ホーム画面のボタンで選択されたentry pointを一度だけ消費し、
    // 既存の単一WKWebViewへ明示的にload()する。新規WKWebViewは生成しない。
    @Binding var pendingEntryPoint: EntryPoint?

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

        // Build 9: 起動直後は自動ロードしない（ホーム画面を先に表示する）。
        // ホームでボタンが選択された時点でupdateUIViewがpendingEntryPointを
        // 検知し、このWKWebViewへ明示的にload()する。

        return container
    }

    func updateUIView(
        _ uiView: PaymentWebContainer,
        context: Context
    ) {
        guard let entryPoint = pendingEntryPoint else {
            return
        }

        context.coordinator.loadEntryPoint(entryPoint, into: uiView.webView)

        // SwiftUIのView更新サイクル中にstateを直接書き換えないよう、
        // 次のrunloopで消費済みのpendingEntryPointをリセットする。
        DispatchQueue.main.async {
            pendingEntryPoint = nil
        }
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

        // Build 9: 会員有効期限切れ警告（Android完成版 WebViewActivity.kt
        // MEMBER_ACCOUNT_URLを根拠とする。パスのみの一致判定で、
        // Android側のnormalizedPath()（ホストは見ず、クエリ・フラグメント除去、
        // 末尾"/"除去）と同じ挙動にする）。
        private let memberAccountURL =
            URL(string: "https://golfpaq.net/booking/mypage/account/show")!

        private func matchesExactURL(_ url: URL, _ target: URL) -> Bool {
            return url.host?.lowercased() == target.host?.lowercased() &&
                   url.path.lowercased() == target.path.lowercased()
        }

        // Android完成版 WebViewActivity.kt normalizedPath() と同じ挙動：
        // クエリ・フラグメントを除いたパスを取り出し、末尾の"/"をすべて除去する。
        private func normalizedPath(_ url: URL) -> String {
            var path = url.path
            while path.hasSuffix("/") {
                path.removeLast()
            }
            return path
        }

        // Android完成版 isMemberAccountUrl() と同じ、パスのみの一致判定。
        private func isMemberAccountURL(_ url: URL) -> Bool {
            return normalizedPath(url) == normalizedPath(memberAccountURL)
        }

        // Android完成版 isMyPageTopUrl() と同じ、パスのみの一致判定。
        private func isMyPageTopURL(_ url: URL) -> Bool {
            return normalizedPath(url) == normalizedPath(myPageDestinationURL)
        }

        // Android完成版 isMembershipExpiryTargetUrl() と同じ。
        // 会員情報画面とMY PAGEトップの2画面だけが対象。
        private func isMembershipExpiryTargetURL(_ url: URL) -> Bool {
            return isMemberAccountURL(url) || isMyPageTopURL(url)
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

        // Build 9: 会員有効期限切れ警告。
        // Android完成版 WebViewActivity.kt の injectMembershipExpiryNotice() を
        // 忠実に移植したもの。DOM構造・class名には依存せず、「有効期限」という
        // 表示文字列そのものをテキストノードとして探す方式（Android側と同じ）。
        // 対象は会員情報画面・MY PAGEトップの2画面のみ（isMembershipExpiryTargetURL
        // で判定済みの場合のみ呼び出される）。フォーム・Cookie・通信・
        // 決済コードには一切触れない。読み取りと警告要素の追加・削除のみ。
        private func injectMembershipExpiryNotice(
            into webView: WKWebView,
            isMyPageTop: Bool
        ) {
            let javaScript = """
            (function() {
                var NOTICE_ID = 'golfpaq_membership_expiry_notice';
                var IS_MY_PAGE_TOP = \(isMyPageTop ? "true" : "false");
                var existing = document.getElementById(NOTICE_ID);

                function findExpiryDateNode() {
                    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
                    var textNodes = [];
                    var node;
                    while ((node = walker.nextNode())) { textNodes.push(node); }
                    for (var i = 0; i < textNodes.length; i++) {
                        var label = textNodes[i].nodeValue.trim().replace(/[:：]$/, '');
                        if (label === '有効期限') {
                            for (var j = i + 1; j < textNodes.length; j++) {
                                var t = textNodes[j].nodeValue.trim();
                                if (t === '') continue;
                                var m = t.match(/^(\\d{4})年(\\d{1,2})月(\\d{1,2})日$/);
                                return m ? { node: textNodes[j], match: m } : null;
                            }
                            return null;
                        }
                    }
                    return null;
                }

                var found = findExpiryDateNode();
                if (!found) {
                    return;
                }

                var y = parseInt(found.match[1], 10);
                var mo = parseInt(found.match[2], 10);
                var d = parseInt(found.match[3], 10);
                var expiry = new Date(y, mo - 1, d);
                expiry.setHours(0, 0, 0, 0);
                var today = new Date();
                today.setHours(0, 0, 0, 0);
                var expired = expiry.getTime() < today.getTime();

                if (!expired) {
                    if (existing && existing.parentNode) { existing.parentNode.removeChild(existing); }
                    return;
                }
                if (existing) {
                    return;
                }

                var dateParent = found.node.parentNode;
                var anchor = (dateParent && dateParent.nodeType === 1) ? dateParent : found.node;
                var noticeTag = 'div';
                var noticeClassName = '';

                if (IS_MY_PAGE_TOP) {
                    var row = anchor;
                    while (row && row.nodeType === 1 && row.tagName !== 'LI') {
                        row = row.parentElement;
                    }
                    if (row && row.tagName === 'LI' && row.parentNode) {
                        anchor = row;
                        noticeTag = 'li';
                        noticeClassName = row.className;
                    }
                }

                var notice = document.createElement(noticeTag);
                notice.id = NOTICE_ID;
                notice.textContent = '年度会員を更新してください';
                notice.style.color = '#D32F2F';
                notice.style.fontWeight = 'bold';
                notice.style.margin = '4px 0';
                notice.style.whiteSpace = 'nowrap';
                if (noticeClassName) { notice.className = noticeClassName; }

                if (anchor.parentNode) {
                    anchor.parentNode.insertBefore(notice, anchor.nextSibling);
                }
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

                // Build 9: 会員有効期限切れ警告も、Android完成版の
                // onPageCommitVisible相当の早い段階で適用する。
                if isMembershipExpiryTargetURL(committedURL) {
                    injectMembershipExpiryNotice(
                        into: webView,
                        isMyPageTop: isMyPageTopURL(committedURL)
                    )
                }
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

                // Build 9: 会員有効期限切れ警告（Android完成版の
                // onPageFinished相当）。対象外URLでは関数内で即returnする。
                if isMembershipExpiryTargetURL(finishedURL) {
                    injectMembershipExpiryNotice(
                        into: webView,
                        isMyPageTop: isMyPageTopURL(finishedURL)
                    )
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

                // Build 9: ホーム画面からの入口はMY PAGEとは限らない
                // （ツアー予約から始まる場合もある）ため、常にmypageへ
                // 再試行するのではなく、実際に読み込もうとしていたURL
                // （pendingMainFrameNavigationURL）を優先して再試行する。
                // 不明な場合のみ従来通りmyPageDestinationURLへフォールバックする。
                DispatchQueue.main.async {
                    webView.load(
                        URLRequest(
                            url: self.pendingMainFrameNavigationURL ??
                                self.myPageDestinationURL
                        )
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

        // Build 9: ホーム画面のボタンから選択されたentry pointを、
        // 既存の単一WKWebViewへ明示的にload()する。新規WKWebViewは生成しない。
        // isPaymentEntryURL・prime reload・POST処理・Accept-Language・
        // window.open・isExternalHost・transfer error検知・safe goBack等の
        // 決済関連ロジックには一切触れない（通常のURL読み込みのみ）。
        func loadEntryPoint(_ entryPoint: EntryPoint, into webView: WKWebView) {
            debugLog(
                "[GOLFPAQ] loading entry point: " +
                entryPoint.url.absoluteString
            )
            webView.load(URLRequest(url: entryPoint.url))
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
