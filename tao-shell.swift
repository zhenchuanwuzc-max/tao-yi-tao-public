// 套一套 · 原生独立窗口壳（macOS 自带 swift + WKWebView，零第三方依赖）
// 只做一件事：开一个独立窗口，加载本机 launchd 跑的 http://localhost:8774。
// server 生命周期不归这里管（归 launchd com.ocean.tao）。壳启动可能早于 server
// 自启，所以加载失败会自动重试，重试穷尽后显示本地兜底页（不是 WKWebView 默认错误页）。
import Cocoa
import WebKit

let PORT = ProcessInfo.processInfo.environment["TAO_PORT"] ?? "8774"
let URL_STR = "http://localhost:\(PORT)/"

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var retries = 0
    let maxRetries = 8          // launchd 自启秒级窗口，~8 次×0.8s 足够覆盖

    func applicationDidFinishLaunching(_ note: Notification) {
        let rect = NSRect(x: 0, y: 0, width: 900, height: 680)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "套一套"
        window.minSize = NSSize(width: 600, height: 460)   // 可拉伸，给个下限
        window.center()
        window.setFrameAutosaveName("TaoMainWindow")        // 记住上次窗口大小/位置

        webView = WKWebView(frame: rect)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        buildMenu()
        load()
    }

    // 原生 app 要有主菜单，键盘快捷键(Cmd+R/W/Q)才生效。
    func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "刷新", action: #selector(reload), keyEquivalent: "r")
        appMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出套一套", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = mainMenu
    }

    @objc func reload() { retries = 0; load() }   // 重新拉服务器(不是 webView.reload,避免卡在兜底页)

    func load() {
        webView.load(URLRequest(url: URL(string: URL_STR)!))
    }

    // 加载失败（多半是 server 还没起来）→ 退避重试，穷尽则兜底页
    func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) { onFail() }
    func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError e: Error) { onFail() }

    func onFail() {
        if retries < maxRetries {
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.load() }
        } else {
            showFallback()
        }
    }

    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) { retries = 0 }

    func showFallback() {
        let html = """
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font-family:-apple-system,sans-serif;background:#1c1c1e;color:#eee;
        display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center}
        h2{font-weight:600}p{color:#999;font-size:14px;line-height:1.6}
        button{margin-top:20px;padding:10px 28px;font-size:15px;border:0;border-radius:8px;
        background:#0a84ff;color:#fff;cursor:pointer}</style></head>
        <body><h2>套一套 server 没响应</h2>
        <p>本机服务（localhost:\(PORT)）暂时连不上。<br>它由 launchd 守护，通常几秒内会自启。</p>
        <button onclick="location.href='\(URL_STR)'">重试</button>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)          // 出现在 Dock + Cmd+Tab
let delegate = AppDelegate()
app.delegate = delegate
app.run()
