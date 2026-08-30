// 对味 · 原生独立窗口壳（macOS 自带 swift + WKWebView，零第三方依赖）
// 只做一件事：开一个独立窗口，加载本机 launchd 跑的 http://localhost:8774。
// server 生命周期不归这里管（归 launchd com.ocean.tao）。壳启动可能早于 server
// 自启，所以加载失败会自动重试，重试穷尽后显示本地兜底页（不是 WKWebView 默认错误页）。
import Cocoa
import WebKit

let PORT = ProcessInfo.processInfo.environment["TAO_PORT"] ?? "8774"
let URL_STR = "http://localhost:\(PORT)/"

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var retries = 0
    var downloadDest: URL?      // 本次下载的落点，downloadDidFinish 时在 Finder 里选中
    let maxRetries = 8          // launchd 自启秒级窗口，~8 次×0.8s 足够覆盖

    func applicationDidFinishLaunching(_ note: Notification) {
        let rect = NSRect(x: 0, y: 0, width: 900, height: 680)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "对味"
        window.minSize = NSSize(width: 600, height: 460)   // 可拉伸，给个下限
        window.center()
        window.setFrameAutosaveName("TaoMainWindow")        // 记住上次窗口大小/位置

        webView = WKWebView(frame: rect)
        webView.navigationDelegate = self
        webView.uiDelegate = self          // 不接这个，页面里 confirm()/alert() 会被 WKWebView 静默吞掉（直接返回 false）
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        buildMenu()
        load()
    }

    // 原生 app 要有主菜单，键盘快捷键(Cmd+R/W/Q)才生效。
    // 编辑菜单(剪切/复制/粘贴/全选)必须存在，WKWebView 里的 Cmd+C/V/X/A 才会绑定。
    func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "检查更新…", action: #selector(checkUpdate), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "刷新", action: #selector(reload), keyEquivalent: "r")
        appMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出对味", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 编辑菜单：撤销/重做/剪切/复制/粘贴/全选 —— 文本框的复制粘贴靠这些 selector 生效
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc func reload() { retries = 0; load() }   // 重新拉服务器(不是 webView.reload,避免卡在兜底页)

    // 菜单「检查更新…」→ 触发页面里的 checkUpdate(true)，逻辑全在 index.html/server.py。
    @objc func checkUpdate() {
        webView.evaluateJavaScript("if(typeof checkUpdate==='function')checkUpdate(true)", completionHandler: nil)
    }

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

    // MARK: - 下载：页面里「导出备份(JSON)」是 blob: + <a download>，WKWebView 默认把它当
    // 一次普通导航、既不显示也不落盘 —— 点了完全没反应（跟上面 alert/confirm 是同一类静默吞）。
    // 实测：不接本段时该导航带 shouldPerformDownload=true 但被丢弃；接上后文件正常存盘。
    func webView(_ wv: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, *), action.shouldPerformDownload {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    @available(macOS 11.3, *)
    func webView(_ wv: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    @available(macOS 11.3, *)
    func webView(_ wv: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: - WKUIDelegate：把 JS 的 alert/confirm 桥到原生 NSAlert。
    // WKWebView 默认不实现这些面板——没有本段时 confirm() 直接返回 false，
    // 页面里所有「删除配方 / 导入替换 / 立即更新」确认框会静默失败（点了没反应）。
    func webView(_ wv: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = "对味"
        a.informativeText = message
        a.addButton(withTitle: "好")
        a.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ wv: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = "对味"
        a.informativeText = message
        a.addButton(withTitle: "确定")
        a.addButton(withTitle: "取消")
        a.beginSheetModal(for: window) { resp in
            completionHandler(resp == .alertFirstButtonReturn)
        }
    }

    func showFallback() {
        let html = """
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font-family:-apple-system,sans-serif;background:#1c1c1e;color:#eee;
        display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center}
        h2{font-weight:600}p{color:#999;font-size:14px;line-height:1.6}
        button{margin-top:20px;padding:10px 28px;font-size:15px;border:0;border-radius:8px;
        background:#0a84ff;color:#fff;cursor:pointer}</style></head>
        <body><h2>对味 server 没响应</h2>
        <p>本机服务（localhost:\(PORT)）暂时连不上。<br>它由 launchd 守护，通常几秒内会自启。</p>
        <button onclick="location.href='\(URL_STR)'">重试</button>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - WKDownloadDelegate：出存储位置面板 → 落盘 → 在 Finder 里选中。
// macOS 11.3 才有 WKDownload；LSMinimumSystemVersion 是 11.0，所以整段带可用性门。
@available(macOS 11.3, *)
extension AppDelegate: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url else {
                self?.downloadDest = nil
                completionHandler(nil)      // 用户取消：必须回 nil，不能不调
                return
            }
            // WKDownload 要求目标不存在，同名旧备份先删掉（面板已让用户确认过覆盖）
            try? FileManager.default.removeItem(at: url)
            self?.downloadDest = url
            completionHandler(url)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadDest else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        downloadDest = nil
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDest = nil
        let a = NSAlert()
        a.messageText = "导出失败"
        a.informativeText = error.localizedDescription
        a.addButton(withTitle: "好")
        a.beginSheetModal(for: window, completionHandler: nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)          // 出现在 Dock + Cmd+Tab
let delegate = AppDelegate()
app.delegate = delegate
app.run()
