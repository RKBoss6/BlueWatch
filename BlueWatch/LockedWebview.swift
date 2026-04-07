// LockedWebView.swift

import SwiftUI
import WebKit

struct LockedWebView: UIViewRepresentable {

    let url: URL
    
    
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

        func userContentController(_ ucc: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            // BLE bridge messages
            if message.name == "bluetooth" {
                guard let body   = message.body as? [String: Any],
                      let id     = body["id"]     as? Int,
                      let method = body["method"] as? String,
                      let args   = body["args"]   as? [String: Any]
                else { return }
                BLEManager.instance.handleWebBluetoothMessage(id: id, method: method, args: args)
                return
            }

            // Console log bridge
            if message.name == "consoleLog" {
                if let body = message.body as? [String: Any] {
                    let level = body["level"] as? String ?? "log"
                    let text  = body["text"]  as? String ?? String(describing: message.body)
                    print("[JS:\(level)] \(text)")
                }
                return
            }
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
            print("[LockedWebView] Page loaded: \(webView.url?.absoluteString ?? "?")")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[LockedWebView] Navigation error: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[LockedWebView] Provisional navigation error: \(error.localizedDescription)")
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let ucc    = WKUserContentController()

        // 1. Inject Web Bluetooth polyfill
        if let jsURL = Bundle.main.url(forResource: "WebBluetooth", withExtension: "js"),
           let src   = try? String(contentsOf: jsURL, encoding: .utf8) {
            ucc.addUserScript(WKUserScript(
                source: src, injectionTime: .atDocumentStart, forMainFrameOnly: false
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
                        try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
                        catch(e) { return String(a); }
                    }).join(' ');
                    _handler.postMessage({ level: level, text: text });
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
                _handler.postMessage({ level: 'UNHANDLED_REJECTION', text: msg });
            });

            // Catch uncaught errors
            window.addEventListener('error', function(e) {
                _handler.postMessage({ level: 'UNCAUGHT_ERROR', text: e.message + ' at ' + e.filename + ':' + e.lineno });
            });
        })();
        """
        ucc.addUserScript(WKUserScript(
            source: consoleBridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false
        ))

        // 3. CSS overflow fix
        ucc.addUserScript(WKUserScript(
            source: "var s=document.createElement('style');s.innerHTML='html,body{overflow-x:hidden!important}';document.documentElement.appendChild(s);",
            injectionTime: .atDocumentStart, forMainFrameOnly: false
        ))

        // 4. Register message handlers
        ucc.add(context.coordinator, name: "bluetooth")
        ucc.add(context.coordinator, name: "consoleLog")

        config.userContentController = ucc
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.isDirectionalLockEnabled = true

        BLEManager.instance.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

// MARK: - ContentView

struct WebView: View {

    private let lockedURL = URL(string: "https://"+Settings.instance.webURL)
                            ?? URL(string: "https://banglejs.com/apps")!
    @ObservedObject private var ble = BLEManager.instance
    @ObservedObject private var vm = ViewModel.instance
    var body: some View {
        
        VStack() {
            
            LockedWebView(url: lockedURL)
                .ignoresSafeArea()
                .padding(.bottom,70)
                
            
            
                
                
            
        }
        
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
