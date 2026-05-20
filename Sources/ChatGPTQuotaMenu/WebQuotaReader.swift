import Foundation
import WebKit

@MainActor
final class WebQuotaReader: NSObject, WKNavigationDelegate {
    private let parser = QuotaParser()
    private let store: QuotaStore
    private let webView: WKWebView
    private var continuation: CheckedContinuation<Result<[QuotaSnapshot], QuotaReaderError>, Never>?
    private var loginWindow: NSWindow?

    init(store: QuotaStore) {
        self.store = store

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()
        webView.navigationDelegate = self
    }

    func refresh() async -> Result<[QuotaSnapshot], QuotaReaderError> {
        if webView.url == nil {
            loadChatGPT()
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                await self.readVisibleText()
            }
        }
    }

    func openLoginWindow() {
        let window: NSWindow
        if let loginWindow {
            window = loginWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "ChatGPT 登录与额度读取"
            window.contentView = webView
            window.center()
            self.loginWindow = window
        }

        if webView.url == nil {
            loadChatGPT()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func loadChatGPT() {
        guard let url = URL(string: "https://chatgpt.com") else {
            return
        }
        webView.load(URLRequest(url: url))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            await readVisibleText()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            finish(.failure(.navigationFailed(error.localizedDescription)))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            finish(.failure(.navigationFailed(error.localizedDescription)))
        }
    }

    private func readVisibleText() async {
        let script = """
        return await (async () => {
          const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
          const visible = (el) => {
            const style = window.getComputedStyle(el);
            const rect = el.getBoundingClientRect();
            return style && style.visibility !== 'hidden' && style.display !== 'none' && (el === document.body || (rect.width > 0 && rect.height > 0));
          };
          const clean = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
          const parts = [];

          const textOf = (el) => [
            clean(el.innerText),
            clean(el.textContent),
            clean(el.getAttribute('aria-label')),
            clean(el.getAttribute('title')),
            clean(el.getAttribute('data-testid')),
            clean(el.getAttribute('aria-describedby')),
            clean(el.getAttribute('aria-controls'))
          ].filter(Boolean).join(' ');

          const collect = (label) => {
            parts.push(`\\n--- ${label} url=${location.href} title=${document.title} ---`);
            if (document.body && document.body.innerText) parts.push(document.body.innerText);
            const selector = [
              'button',
              '[role="button"]',
              '[role="menu"]',
              '[role="menuitem"]',
              '[role="option"]',
              '[role="tooltip"]',
              '[role="dialog"]',
              '[aria-label]',
              '[title]',
              '[data-testid]',
              '[id^="radix-"]'
            ].join(',');
            for (const el of Array.from(document.querySelectorAll(selector))) {
              if (!visible(el)) continue;
              const text = textOf(el);
              if (text) parts.push(text);
            }
          };

          const dispatchHover = (el) => {
            const rect = el.getBoundingClientRect();
            const opts = {
              bubbles: true,
              cancelable: true,
              clientX: rect.left + Math.max(1, rect.width / 2),
              clientY: rect.top + Math.max(1, rect.height / 2)
            };
            for (const name of ['pointerover', 'pointerenter', 'mouseover', 'mouseenter', 'mousemove']) {
              el.dispatchEvent(new MouseEvent(name, opts));
            }
            if (typeof el.focus === 'function') el.focus({ preventScroll: true });
          };

          const candidateSelectors = [
            '[data-testid="model-switcher-dropdown-button"]',
            '[data-testid*="model-switcher"]',
            '[data-testid*="model"]',
            'button[aria-haspopup="menu"]',
            'button[aria-haspopup="listbox"]',
            'button[aria-label*="model" i]',
            'button[aria-label*="模型"]',
            'button'
          ];

          const scoreModelButton = (el) => {
            const text = textOf(el).toLowerCase();
            let score = 0;
            if (text.includes('model-switcher')) score += 30;
            if (text.includes('gpt')) score += 20;
            if (text.includes('chatgpt')) score += 14;
            if (text.includes('model') || text.includes('模型')) score += 12;
            if (text.includes('thinking') || text.includes('思考')) score += 8;
            if (text.includes('new chat') || text.includes('新聊天')) score -= 30;
            if (text.includes('send') || text.includes('发送')) score -= 20;
            return score;
          };

          collect('initial');

          const modelButtons = Array.from(new Set(candidateSelectors.flatMap((selector) => Array.from(document.querySelectorAll(selector)))))
            .filter(visible)
            .map((el) => ({ el, score: scoreModelButton(el), text: textOf(el).slice(0, 220) }))
            .sort((a, b) => b.score - a.score);

          parts.push('\\n--- model button candidates ---');
          for (const item of modelButtons.slice(0, 12)) {
            parts.push(`[score=${item.score}] ${item.text}`);
          }

          const modelButton = modelButtons.find((item) => item.score > 0)?.el;
          if (modelButton) {
            dispatchHover(modelButton);
            modelButton.click();
            await sleep(900);
            collect('after model button click');
          }

          const moreButton = Array.from(document.querySelectorAll('button, [role="button"], [role="menuitem"]'))
            .filter(visible)
            .find((el) => {
              const text = textOf(el).toLowerCase();
              return text.includes('more models') || text.includes('all models') || text.includes('更多模型') || text.includes('所有模型');
            });
          if (moreButton) {
            dispatchHover(moreButton);
            moreButton.click();
            await sleep(700);
            collect('after more models click');
          }

          const quotaLike = (el) => {
            const text = textOf(el).toLowerCase();
            return text.includes('gpt') ||
              text.includes('thinking') ||
              text.includes('reasoning') ||
              text.includes('message') ||
              text.includes('limit') ||
              text.includes('reset') ||
              text.includes('remaining') ||
              text.includes('available') ||
              text.includes('模型') ||
              text.includes('思考') ||
              text.includes('消息') ||
              text.includes('额度') ||
              text.includes('限制') ||
              text.includes('重置') ||
              text.includes('剩余');
          };

          const menuItems = Array.from(new Set(Array.from(document.querySelectorAll('button, [role="button"], [role="menuitem"], [role="option"], [aria-label], [data-testid]'))))
            .filter(visible)
            .filter(quotaLike)
            .slice(0, 35);

          parts.push('\\n--- hovered quota/model items ---');
          for (const [index, item] of menuItems.entries()) {
            item.scrollIntoView({ block: 'nearest', inline: 'nearest' });
            dispatchHover(item);
            await sleep(250);
            parts.push(`\\n[item ${index + 1}] ${textOf(item)}`);
            collect(`after hover ${index + 1}`);
          }

          return parts.join('\\n');
        })();
        """

        do {
            let value = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
            let text = (value as? String) ?? ""
            await store.saveRawText(text)

            if looksLoggedOut(text: text, url: webView.url) {
                finish(.failure(.loggedOut))
                return
            }

            let snapshots = parser.parse(text)
            if snapshots.isEmpty {
                finish(.failure(.unreadable("页面已加载，但没有找到可解析的额度文本。已保存诊断文本；请点文档放大镜查看 last-page-text.txt。")))
                return
            }

            await store.save(snapshots)
            finish(.success(snapshots))
        } catch {
            finish(.failure(.scriptFailed(error.localizedDescription)))
        }
    }

    private func looksLoggedOut(text: String, url: URL?) -> Bool {
        let lower = text.lowercased()
        if url?.absoluteString.contains("/auth/") == true {
            return true
        }
        if lower.contains("log in") || lower.contains("sign up") || lower.contains("登录") || lower.contains("注册") {
            return lower.contains("message chatgpt") == false && lower.contains("new chat") == false
        }
        return false
    }

    private func finish(_ result: Result<[QuotaSnapshot], QuotaReaderError>) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(returning: result)
    }
}

enum QuotaReaderError: Error, Equatable {
    case loggedOut
    case navigationFailed(String)
    case scriptFailed(String)
    case unreadable(String)
}
