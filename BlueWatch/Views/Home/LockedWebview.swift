// LockedWebView.swift

import SwiftUI
import WebKit
@Observable
class WebRefreshManager {
    static let shared = WebRefreshManager()
    private init() {
        //nthing
    }
    var refreshID = UUID()
    var currentThemeColor: Color = Color(uiColor: .systemBackground)
    func forceRefresh() {
        refreshID = UUID()
    }
}
struct LockedWebView: UIViewRepresentable {
    let refreshManager:WebRefreshManager = .shared
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler , UIScrollViewDelegate {

        weak var webView: WKWebView?
        var topThemeView: UIView?
        private var themeObservation: NSKeyValueObservation?
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if scrollView.contentOffset.x != 0 {
                    scrollView.contentOffset.x = 0
                }
            // Incorporate the bottom inset into the max scroll calculation
            let maxScrollableOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
            
            // Hard-lock the elastic bounce at the new extended boundary
            if scrollView.contentOffset.y > maxScrollableOffset {
                if maxScrollableOffset > 0 {
                    scrollView.contentOffset.y = maxScrollableOffset
                } else {
                    scrollView.contentOffset.y = 0
                }
            }
        }

        func setupThemeObservation(for webView: WKWebView) {
            self.webView = webView
            
            // KVO listens to Apple's native .themeColor updates
            themeObservation = webView.observe(\.themeColor, options: [.new]) { _, change in
                DispatchQueue.main.async {
                    if let uiColor = change.newValue as? UIColor {
                        // Instantly push the parsed web meta color into SwiftUI state
                        WebRefreshManager.shared.currentThemeColor = Color(uiColor: uiColor)
                    }
                }
            }
        }
        func userContentController(_ ucc: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            // BLE bridge messages
            if message.name == "bluetooth" {
                guard let body   = message.body as? [String: Any],
                      let id     = body["id"]     as? Int,
                      let method = body["method"] as? String,
                      let args   = body["args"]   as? [String: Any]
                else { return }
                BLEManager.shared.handleWebBluetoothMessage(id: id, method: method, args: args)
                return
            }

            // Console log bridge
            if message.name == "consoleLog" {
                if let body = message.body as? [String: Any] {
                    let level = body["level"] as? String ?? "log"
                    let text  = body["text"]  as? String ?? String(describing: message.body)
                    // LockedWebview.swift
                    logger.log("[JS:\(level, privacy: .public)] \(text, privacy: .public)")
                }
                return
            }
        }

        @objc func refreshWebView(_ sender: UIRefreshControl) {
            webView?.reload()
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            switch action.navigationType {
            case .linkActivated, .formSubmitted, .formResubmitted:
                decisionHandler(.cancel)
            default:
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            logger.log("[LockedWebView] Page loaded: \(webView.url?.absoluteString ?? "?")")
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            logger.log("[LockedWebView] Navigation error: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            logger.log("[LockedWebView] Provisional navigation error: \(error.localizedDescription)")
        }
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Dynamically update the color when the observable property changes
        context.coordinator.topThemeView?.backgroundColor = UIColor(refreshManager.currentThemeColor)
    }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()

        // 1. Inject Web Bluetooth polyfill
        if let jsURL = Bundle.main.url(forResource: "WebBluetooth", withExtension: "js"),
           let src = try? String(contentsOf: jsURL, encoding: .utf8) {
            ucc.addUserScript(WKUserScript(
                source: src,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        } else {
            assertionFailure("WebBluetooth.js not found — add to Copy Bundle Resources")
        }

        // 2. Inject console → Xcode bridge so JS errors show in your logs
        let consoleBridgeJS = """
        (function() {
            var _handler = window.webkit.messageHandlers.consoleLog;

            function _wrap(level, orig) {
                return function() {
                    var args = Array.prototype.slice.call(arguments);
                    var text = args.map(function(a) {
                        if (a instanceof Error) return a.message + '\\n' + a.stack;
                        try {
                            return typeof a === 'object' ? JSON.stringify(a) : String(a);
                        }
                        catch(e) {
                            return String(e);
                        }
                    }).join(' ');

                    _handler.postMessage({
                        level: level,
                        text: text
                    });

                    orig.apply(console, arguments);
                };
            }

            console.log   = _wrap('log',   console.log);
            console.warn  = _wrap('warn',  console.warn);
            console.error = _wrap('error', console.error);
            console.info  = _wrap('info',  console.info);

            // Catch unhandled promise rejections
            window.addEventListener('unhandledrejection', function(e) {
                var msg = e.reason instanceof Error
                    ? e.reason.message + '\\n' + e.reason.stack
                    : String(e.reason);

                _handler.postMessage({
                    level: 'UNHANDLED_REJECTION',
                    text: msg
                });
            });

            // Catch uncaught errors
            window.addEventListener('error', function(e) {
                _handler.postMessage({
                    level: 'UNCAUGHT_ERROR',
                    text: e.message + ' at ' + e.filename + ':' + e.lineno
                });
            });
        })();
        """

        ucc.addUserScript(WKUserScript(
            source: consoleBridgeJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let performanceCSS = """
        html, body {
            overflow-x: hidden !important;
            margin: 0 !important;
            padding: 0 !important;
            -webkit-overflow-scrolling: touch !important;
        }
        body {
            /* Adds extra empty space at the absolute bottom when fully scrolled */
            padding-bottom: 1000px !important; 
            box-sizing: border-box !important;
        }
        * {
            -webkit-backface-visibility: hidden;
            backface-visibility: hidden;
        }
        """
        let jsSource = "var s=document.createElement('style');s.innerHTML='\(performanceCSS)';document.documentElement.appendChild(s);"
        ucc.addUserScript(WKUserScript(
            source: jsSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        // 4. Register message handlers
        ucc.add(context.coordinator, name: "bluetooth")
        ucc.add(context.coordinator, name: "consoleLog")

        config.userContentController = ucc
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView
        context.coordinator.setupThemeObservation(for: webView)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.isDirectionalLockEnabled = true
        if(Settings.shared.pullToRefreshWebView){
            // 5. Native pull-to-refresh
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(
                context.coordinator,
                action: #selector(Coordinator.refreshWebView(_:)),
                for: .valueChanged
            )
            webView.scrollView.refreshControl = refreshControl
        }
        webView.scrollView.delegate = context.coordinator
        webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 80, right: 0)
        BLEManager.shared.webView = webView
        webView.load(URLRequest(url: url))
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // 1. Create a background container view that matches the scroll view's size
                let bgView = UIView(frame: webView.scrollView.bounds)
                bgView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                bgView.backgroundColor = .white // The default background color for the body/bottom bounce
                
        // 2. Create a top header slice for the pull-down area
        let topThemeView = UIView()
        topThemeView.frame = CGRect(x: 0, y: -1000, width: UIScreen.main.bounds.width, height: 1000)
        topThemeView.autoresizingMask = [.flexibleWidth]
        topThemeView.backgroundColor = UIColor(refreshManager.currentThemeColor)

        // Save it to the coordinator so we can reach it later
        context.coordinator.topThemeView = topThemeView

        bgView.addSubview(topThemeView)
                
                // 4. Insert the container at index 0 behind the web view's internal components
                webView.scrollView.insertSubview(bgView, at: 0)
        return webView
        
    }

}

// MARK: - ContentView

struct WebView: View {
    @State private var refreshManager = WebRefreshManager.shared
    private var lockedURL: URL {
        let base = !Settings.shared.webURL.isEmpty ? Settings.shared.webURL : "banglejs.com/apps"
        let candidate = URL(string: "https://" + base)
        if let url = candidate {
            return url
        }
        //assertionFailure("Invalid URL constructed from settings: \(base)")
        return URL(string: "https://banglejs.com/apps")!
    }

    @ObservedObject private var ble = BLEManager.shared
    @ObservedObject private var vm = ViewModel.shared

    var body: some View {
        ZStack{
            /*
            Rectangle().frame(maxHeight:.infinity)
               
                .foregroundStyle(LinearGradient(colors: [refreshManager.currentThemeColor,refreshManager.currentThemeColor,.white,.white], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges:.all)
             */
            VStack() {
                Rectangle()
                    .frame(width:.infinity, height:60)
                    .foregroundStyle(refreshManager.currentThemeColor)
                //            Button{
                //
                //            }label:{
                //                Image(systemName: "arrow.clockwise")
                //            }
                    .padding(.bottom,-10)
                LockedWebView(url: lockedURL)
                    .id(refreshManager.refreshID)
                    
            }
            
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .ignoresSafeArea(edges:.all)
            .padding(.top,-5)
            
        }
        .background(.white)
    }
}

#Preview {
    WebView()
}
