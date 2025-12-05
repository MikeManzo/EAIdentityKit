//
//  EAWebAuthenticator.swift
//  EAIdentityKit
//
//  Web-based token capture using WKWebView
//
//  This provides a programmatic way to authenticate with EA by:
//  1. Loading EA's login page in a WKWebView
//  2. Letting the user sign in normally
//  3. Intercepting requests to gateway.ea.com after login
//  4. Extracting the Bearer token from the Authorization header
//

import Foundation
import WebKit

#if canImport(AppKit)
import AppKit
public typealias ViewControllerType = NSViewController
public typealias WindowType = NSWindow
#elseif canImport(UIKit)
import UIKit
public typealias ViewControllerType = UIViewController
public typealias WindowType = UIWindow
#endif

// MARK: - Web Authenticator Delegate

/// Delegate protocol for EAWebAuthenticator events
public protocol EAWebAuthenticatorDelegate: AnyObject {
    /// Called when a token is successfully captured
    func webAuthenticator(_ authenticator: EAWebAuthenticator, didCaptureToken token: String)
    
    /// Called when authentication fails
    func webAuthenticator(_ authenticator: EAWebAuthenticator, didFailWithError error: Error)
    
    /// Called when the user cancels authentication
    func webAuthenticatorDidCancel(_ authenticator: EAWebAuthenticator)
}

// MARK: - Web Authenticator

/// Authenticator that uses WKWebView to capture EA OAuth tokens
///
/// This class presents a web view with EA's login page and intercepts
/// the Authorization header from requests to gateway.ea.com after login.
///
/// ## Usage
///
/// ```swift
/// let webAuth = EAWebAuthenticator()
/// webAuth.delegate = self
///
/// // macOS
/// webAuth.present(from: window)
///
/// // iOS
/// webAuth.present(from: viewController)
///
/// // Or use async/await
/// let token = try await webAuth.authenticate(from: window)
/// ```
@available(macOS 10.15, iOS 13.0, *)
public final class EAWebAuthenticator: NSObject {
    
    // MARK: - Types
    
    public enum WebAuthError: Error, LocalizedError {
        case cancelled
        case noToken
        case timeout
        case webViewError(String)
        
        public var errorDescription: String? {
            switch self {
            case .cancelled:
                return "Authentication was cancelled"
            case .noToken:
                return "No token was captured"
            case .timeout:
                return "Authentication timed out"
            case .webViewError(let message):
                return "Web view error: \(message)"
            }
        }
    }
    
    // MARK: - Properties
    
    public weak var delegate: EAWebAuthenticatorDelegate?
    
    private var webView: WKWebView?
    private var tokenContinuation: CheckedContinuation<String, Error>?
    private var capturedToken: String?
    private var isPresented = false
    
    #if os(macOS)
    private var authWindow: NSWindow?
    private var windowDelegate: WebAuthWindowDelegate?
    #elseif os(iOS)
    private var navigationController: UINavigationController?
    #endif
    
    private let storage: EATokenStorage
    
    // MARK: - Constants
    
    private enum URLs {
        static let login = "https://www.ea.com/login"
        static let eaHome = "https://www.ea.com"
        static let gatewayPattern = "gateway.ea.com"
    }
    
    // MARK: - Initialization
    
    public init(storage: EATokenStorage = EATokenStorage()) {
        self.storage = storage
        super.init()
    }
    
    // MARK: - Public Methods
    
    #if os(macOS)
    /// Present the authentication web view (macOS)
    /// - Parameter window: The parent window to present from
    @MainActor
    public func present(from window: NSWindow) {
        guard !isPresented else { return }
        isPresented = true
        
        let webView = createWebView()
        self.webView = webView
        
        // Create auth window
        let authWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        authWindow.title = "Sign in with EA"
        authWindow.contentView = webView
        authWindow.center()
        
        // Set up window delegate to handle close
        let windowDelegate = WebAuthWindowDelegate { [weak self] in
            self?.handleCancel()
        }
        authWindow.delegate = windowDelegate
        self.windowDelegate = windowDelegate
        self.authWindow = authWindow
        
        // Add toolbar with cancel button
        let toolbar = NSToolbar(identifier: "EAAuthToolbar")
        toolbar.displayMode = .iconOnly
        authWindow.toolbar = toolbar
        
        // Show as sheet or window
        if window.isVisible {
            window.beginSheet(authWindow) { _ in }
        } else {
            authWindow.makeKeyAndOrderFront(nil)
        }
        
        // Load login page
        if let url = URL(string: URLs.login) {
            webView.load(URLRequest(url: url))
        }
    }
    
    /// Authenticate using async/await (macOS)
    /// - Parameter window: The parent window
    /// - Returns: The captured access token
    @MainActor
    public func authenticate(from window: NSWindow) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.tokenContinuation = continuation
            self.present(from: window)
        }
    }
    #endif
    
    #if os(iOS)
    /// Present the authentication web view (iOS)
    /// - Parameter viewController: The view controller to present from
    @MainActor
    public func present(from viewController: UIViewController) {
        guard !isPresented else { return }
        isPresented = true
        
        let webView = createWebView()
        self.webView = webView
        
        // Create view controller for web view
        let webVC = WebAuthViewController(webView: webView) { [weak self] in
            self?.handleCancel()
        }
        webVC.title = "Sign in with EA"
        
        let navController = UINavigationController(rootViewController: webVC)
        navController.modalPresentationStyle = .formSheet
        self.navigationController = navController
        
        viewController.present(navController, animated: true)
        
        // Load login page
        if let url = URL(string: URLs.login) {
            webView.load(URLRequest(url: url))
        }
    }
    
    /// Authenticate using async/await (iOS)
    /// - Parameter viewController: The view controller to present from
    /// - Returns: The captured access token
    @MainActor
    public func authenticate(from viewController: UIViewController) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.tokenContinuation = continuation
            self.present(from: viewController)
        }
    }
    #endif
    
    /// Dismiss the authentication view
    @MainActor
    public func dismiss() {
        #if os(macOS)
        if let authWindow = authWindow {
            if let parent = authWindow.sheetParent {
                parent.endSheet(authWindow)
            } else {
                authWindow.close()
            }
        }
        authWindow = nil
        windowDelegate = nil
        #elseif os(iOS)
        navigationController?.dismiss(animated: true)
        navigationController = nil
        #endif
        
        webView?.stopLoading()
        webView = nil
        isPresented = false
    }
    
    // MARK: - Private Methods
    
    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Set up custom URL scheme handler to intercept requests
        let schemeHandler = TokenInterceptSchemeHandler { [weak self] token in
            self?.handleTokenCapture(token)
        }
        
        // We can't intercept https directly, so we use a different approach:
        // Inject JavaScript to monitor fetch/XHR requests
        let userContentController = WKUserContentController()
        
        // Script to intercept fetch requests and capture Authorization headers
        let interceptScript = WKUserScript(
            source: Self.tokenInterceptScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(interceptScript)
        
        // Add message handler for captured tokens
        let messageHandler = TokenMessageHandler { [weak self] token in
            self?.handleTokenCapture(token)
        }
        userContentController.add(messageHandler, name: "tokenCapture")
        
        config.userContentController = userContentController
        
        // Enable developer extras for debugging if needed
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        
        // Custom user agent to appear as a regular browser
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        
        return webView
    }
    
    private func handleTokenCapture(_ token: String) {
        guard capturedToken == nil else { return } // Only capture once
        guard !token.isEmpty else { return }
        
        capturedToken = token
        
        // Store the token
        try? storage.saveCredentials(EACredentials(
            accessToken: token,
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600),
            userId: nil
        ))
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.delegate?.webAuthenticator(self, didCaptureToken: token)
            self.tokenContinuation?.resume(returning: token)
            self.tokenContinuation = nil
            self.dismiss()
        }
    }
    
    /// Try to extract token by making a direct API call using the webview's cookies
    private func tryDirectAPICall() {
        guard let webView = webView, capturedToken == nil else { return }
        
        print("[EAWebAuth] Attempting direct API call to get token...")
        
        // Get all cookies from the webview
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self, self.capturedToken == nil else { return }
            
            // Print cookies for debugging
            let eaCookies = cookies.filter { $0.domain.contains("ea.com") }
            print("[EAWebAuth] Found \(eaCookies.count) EA cookies")
            
            // Look for specific auth cookies
            for cookie in eaCookies {
                print("[EAWebAuth] Cookie: \(cookie.name) = \(String(cookie.value.prefix(20)))... (domain: \(cookie.domain))")
                
                // Check if this looks like a token cookie
                if cookie.name.lowercased().contains("token") ||
                   cookie.name.lowercased().contains("access") ||
                   cookie.name == "sid" {
                    let value = cookie.value
                    // EA tokens are typically long alphanumeric strings
                    if value.count > 50 && !value.contains("=") {
                        print("[EAWebAuth] Found potential token in cookie: \(cookie.name)")
                        self.handleTokenCapture(value)
                        return
                    }
                }
            }
            
            // If no token cookie found, try making an API call with cookies
            self.makeAuthenticatedAPICall(cookies: eaCookies)
        }
    }
    
    /// Make an API call using cookies to try to get a token response
    private func makeAuthenticatedAPICall(cookies: [HTTPCookie]) {
        guard capturedToken == nil else { return }
        
        print("[EAWebAuth] Making authenticated API call...")
        
        // Create a URL session with the cookies
        let config = URLSessionConfiguration.default
        config.httpCookieStorage?.setCookies(cookies, for: URL(string: "https://www.ea.com")!, mainDocumentURL: nil)
        config.httpCookieStorage?.setCookies(cookies, for: URL(string: "https://accounts.ea.com")!, mainDocumentURL: nil)
        
        let session = URLSession(configuration: config)
        
        // Try the token endpoint that might return a token
        guard let url = URL(string: "https://accounts.ea.com/connect/auth?client_id=ORIGIN_JS_SDK&response_type=token&redirect_uri=nucleus:rest&prompt=none") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, self.capturedToken == nil else { return }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("[EAWebAuth] API response status: \(httpResponse.statusCode)")
                
                // Check if we got redirected to a URL with the token
                if let responseURL = httpResponse.url?.absoluteString {
                    print("[EAWebAuth] Response URL: \(responseURL)")
                    
                    if responseURL.contains("access_token=") {
                        // Extract token from URL
                        if let range = responseURL.range(of: "access_token=") {
                            let afterToken = responseURL[range.upperBound...]
                            let token: String
                            if let endIndex = afterToken.firstIndex(where: { $0 == "&" || $0 == "#" }) {
                                token = String(afterToken[..<endIndex])
                            } else {
                                token = String(afterToken)
                            }
                            print("[EAWebAuth] Extracted token from redirect URL!")
                            DispatchQueue.main.async {
                                self.handleTokenCapture(token)
                            }
                            return
                        }
                    }
                }
                
                // Check response body
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    print("[EAWebAuth] Response body preview: \(String(body.prefix(200)))")
                    
                    // Try to parse as JSON
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let token = json["access_token"] as? String {
                            print("[EAWebAuth] Found token in JSON response!")
                            DispatchQueue.main.async {
                                self.handleTokenCapture(token)
                            }
                            return
                        }
                    }
                }
            }
            
            // If that didn't work, try using JavaScript to check for tokens in the page
            DispatchQueue.main.async {
                self.tryJavaScriptExtraction()
            }
        }
        task.resume()
    }
    
    /// Try to extract token using JavaScript evaluation
    private func tryJavaScriptExtraction() {
        guard let webView = webView, capturedToken == nil else { return }
        
        print("[EAWebAuth] Trying JavaScript token extraction...")
        
        // JavaScript to search for tokens in various places
        let script = """
        (function() {
            var result = { found: false, token: null, source: null };
            
            // Check localStorage
            for (var i = 0; i < localStorage.length; i++) {
                var key = localStorage.key(i);
                var value = localStorage.getItem(key);
                if (value && value.length > 50 && value.length < 500) {
                    if (key.toLowerCase().includes('token') || key.toLowerCase().includes('access')) {
                        result.found = true;
                        result.token = value;
                        result.source = 'localStorage: ' + key;
                        return JSON.stringify(result);
                    }
                    // Check if it's JSON with a token
                    try {
                        var parsed = JSON.parse(value);
                        if (parsed.access_token) {
                            result.found = true;
                            result.token = parsed.access_token;
                            result.source = 'localStorage JSON: ' + key;
                            return JSON.stringify(result);
                        }
                    } catch(e) {}
                }
            }
            
            // Check sessionStorage
            for (var i = 0; i < sessionStorage.length; i++) {
                var key = sessionStorage.key(i);
                var value = sessionStorage.getItem(key);
                if (value && value.length > 50 && value.length < 500) {
                    if (key.toLowerCase().includes('token') || key.toLowerCase().includes('access')) {
                        result.found = true;
                        result.token = value;
                        result.source = 'sessionStorage: ' + key;
                        return JSON.stringify(result);
                    }
                }
            }
            
            // Check window object
            if (window.ea && window.ea.token) {
                result.found = true;
                result.token = window.ea.token;
                result.source = 'window.ea.token';
                return JSON.stringify(result);
            }
            
            // Check for __NEXT_DATA__ or similar
            var scripts = document.querySelectorAll('script');
            for (var s of scripts) {
                var text = s.textContent;
                if (text && text.includes('access_token')) {
                    var match = text.match(/"access_token"\\s*:\\s*"([^"]+)"/);
                    if (match) {
                        result.found = true;
                        result.token = match[1];
                        result.source = 'inline script';
                        return JSON.stringify(result);
                    }
                }
            }
            
            return JSON.stringify(result);
        })();
        """
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self, self.capturedToken == nil else { return }
            
            if let error = error {
                print("[EAWebAuth] JavaScript error: \(error)")
                return
            }
            
            if let resultString = result as? String,
               let data = resultString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                print("[EAWebAuth] JS extraction result: \(json)")
                
                if let found = json["found"] as? Bool, found,
                   let token = json["token"] as? String {
                    let source = json["source"] as? String ?? "unknown"
                    print("[EAWebAuth] Found token via JS from: \(source)")
                    self.handleTokenCapture(token)
                }
            }
        }
    }
    
    /// Try to get token from stored cookies/session
    private func tryExtractFromCookies() {
        guard capturedToken == nil else { return }
        print("[EAWebAuth] Trying cookie extraction...")
        tryDirectAPICall()
    }
    
    private func handleCancel() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.delegate?.webAuthenticatorDidCancel(self)
            self.tokenContinuation?.resume(throwing: WebAuthError.cancelled)
            self.tokenContinuation = nil
            self.dismiss()
        }
    }
    
    private func handleError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.delegate?.webAuthenticator(self, didFailWithError: error)
            self.tokenContinuation?.resume(throwing: error)
            self.tokenContinuation = nil
            self.dismiss()
        }
    }
    
    // MARK: - JavaScript Intercept Script
    
    /// JavaScript that intercepts fetch/XHR requests and captures Authorization headers
    /// Also checks localStorage and sessionStorage for EA tokens
    private static let tokenInterceptScript = """
    (function() {
        let tokenSent = false;
        
        function sendToken(token) {
            if (tokenSent || !token) return;
            tokenSent = true;
            try {
                window.webkit.messageHandlers.tokenCapture.postMessage(token);
            } catch(e) {
                console.log('Failed to send token:', e);
            }
        }
        
        // Check localStorage and sessionStorage for EA tokens
        function checkStorage() {
            try {
                // Check various known EA token storage keys
                const storageKeys = [
                    'access_token', 'accessToken', 'token', 
                    'ea_access_token', 'eaAccessToken',
                    'bearer_token', 'bearerToken',
                    'auth_token', 'authToken'
                ];
                
                for (const key of storageKeys) {
                    let value = localStorage.getItem(key) || sessionStorage.getItem(key);
                    if (value) {
                        // Clean up the token if it has Bearer prefix
                        if (value.startsWith('Bearer ')) {
                            value = value.substring(7);
                        }
                        // Basic validation - EA tokens are usually long alphanumeric strings
                        if (value.length > 20 && /^[A-Za-z0-9_-]+$/.test(value)) {
                            sendToken(value);
                            return;
                        }
                    }
                }
                
                // Also check for JSON stored auth data
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    if (key && (key.toLowerCase().includes('auth') || key.toLowerCase().includes('token'))) {
                        try {
                            const data = JSON.parse(localStorage.getItem(key));
                            if (data && (data.access_token || data.accessToken || data.token)) {
                                let token = data.access_token || data.accessToken || data.token;
                                if (token.startsWith('Bearer ')) token = token.substring(7);
                                if (token.length > 20) {
                                    sendToken(token);
                                    return;
                                }
                            }
                        } catch(e) {}
                    }
                }
            } catch(e) {
                console.log('Storage check error:', e);
            }
        }
        
        // Store original fetch
        const originalFetch = window.fetch;
        
        // Override fetch
        window.fetch = function(input, init) {
            let url = '';
            if (typeof input === 'string') {
                url = input;
            } else if (input instanceof Request) {
                url = input.url;
            }
            
            // Check any request for Authorization header (not just gateway.ea.com)
            // EA might use the token on various domains
            let authHeader = null;
            
            if (init && init.headers) {
                if (init.headers instanceof Headers) {
                    authHeader = init.headers.get('Authorization');
                } else if (typeof init.headers === 'object') {
                    authHeader = init.headers['Authorization'] || init.headers['authorization'];
                }
            }
            
            if (input instanceof Request) {
                authHeader = authHeader || input.headers.get('Authorization');
            }
            
            if (authHeader && authHeader.startsWith('Bearer ')) {
                const token = authHeader.substring(7);
                if (token.length > 20) {
                    sendToken(token);
                }
            }
            
            return originalFetch.apply(this, arguments);
        };
        
        // Store original XMLHttpRequest methods
        const originalXHROpen = XMLHttpRequest.prototype.open;
        const originalXHRSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
        const originalXHRSend = XMLHttpRequest.prototype.send;
        
        // Track headers per XHR instance
        const xhrHeaders = new WeakMap();
        
        XMLHttpRequest.prototype.open = function(method, url) {
            this._url = url;
            xhrHeaders.set(this, {});
            return originalXHROpen.apply(this, arguments);
        };
        
        XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
            const headers = xhrHeaders.get(this) || {};
            headers[name.toLowerCase()] = value;
            xhrHeaders.set(this, headers);
            return originalXHRSetRequestHeader.apply(this, arguments);
        };
        
        XMLHttpRequest.prototype.send = function() {
            const headers = xhrHeaders.get(this) || {};
            const authHeader = headers['authorization'];
            
            if (authHeader && authHeader.startsWith('Bearer ')) {
                const token = authHeader.substring(7);
                if (token.length > 20) {
                    sendToken(token);
                }
            }
            
            return originalXHRSend.apply(this, arguments);
        };
        
        // Check storage periodically and on page events
        checkStorage();
        
        // Poll for token in storage every 2 seconds
        const pollInterval = setInterval(function() {
            if (tokenSent) {
                clearInterval(pollInterval);
                return;
            }
            checkStorage();
        }, 2000);
        
        // Also check when DOM is ready
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', checkStorage);
        }
        
        // And when page is fully loaded
        window.addEventListener('load', function() {
            setTimeout(checkStorage, 1000);
        });
        
        console.log('EA Token interceptor installed');
    })();
    """
}

// MARK: - WKNavigationDelegate

@available(macOS 10.15, iOS 13.0, *)
extension EAWebAuthenticator: WKNavigationDelegate {
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        let urlString = url.absoluteString.lowercased()
        
        print("[EAWebAuth] Page loaded: \(urlString)")
        
        // Check if we've completed login (redirected away from login page)
        let isLoginPage = urlString.contains("signin.ea.com") ||
                          urlString.contains("/login") ||
                          urlString.contains("accounts.ea.com/connect")
        
        let isEAPage = urlString.contains("ea.com")
        let isLoggedInPage = isEAPage && !isLoginPage
        
        print("[EAWebAuth] isLoginPage: \(isLoginPage), isLoggedInPage: \(isLoggedInPage), tokenCaptured: \(capturedToken != nil)")
        
        // If we're on the account page, try extraction methods
        if urlString.contains("myaccount.ea.com") {
            print("[EAWebAuth] On account page, waiting then trying extraction...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard self?.capturedToken == nil else { return }
                self?.tryExtractFromCookies()
            }
        } else if isLoggedInPage && capturedToken == nil {
            // User appears to be logged in, navigate to account page
            print("[EAWebAuth] User logged in, redirecting to account page...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard self?.capturedToken == nil else { return }
                
                // Navigate to account page which should make API calls
                if let accountURL = URL(string: "https://myaccount.ea.com/cp-ui/aboutme/index") {
                    webView.load(URLRequest(url: accountURL))
                }
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        print("[EAWebAuth] Navigation error: \(error.localizedDescription)")
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            print("[EAWebAuth] Navigation to: \(url.absoluteString)")
            
            // Check if this is a redirect with an access token in the URL
            let urlString = url.absoluteString
            if urlString.contains("access_token=") {
                print("[EAWebAuth] Found access_token in URL!")
                if let range = urlString.range(of: "access_token=") {
                    let afterToken = urlString[range.upperBound...]
                    let token: String
                    if let endIndex = afterToken.firstIndex(where: { $0 == "&" || $0 == "#" }) {
                        token = String(afterToken[..<endIndex])
                    } else {
                        token = String(afterToken)
                    }
                    if !token.isEmpty {
                        print("[EAWebAuth] Extracted token from URL redirect!")
                        handleTokenCapture(token)
                    }
                }
            }
        }
        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Check response headers for tokens
        if let response = navigationResponse.response as? HTTPURLResponse {
            if let authHeader = response.allHeaderFields["Authorization"] as? String,
               authHeader.hasPrefix("Bearer ") {
                let token = String(authHeader.dropFirst(7))
                print("[EAWebAuth] Found token in response header!")
                handleTokenCapture(token)
            }
        }
        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url {
            print("[EAWebAuth] Redirect to: \(url.absoluteString)")
        }
    }
}

// MARK: - Token Message Handler

@available(macOS 10.15, iOS 13.0, *)
private class TokenMessageHandler: NSObject, WKScriptMessageHandler {
    private let onTokenCapture: (String) -> Void
    
    init(onTokenCapture: @escaping (String) -> Void) {
        self.onTokenCapture = onTokenCapture
        super.init()
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let token = message.body as? String, !token.isEmpty {
            onTokenCapture(token)
        }
    }
}

// MARK: - Scheme Handler (Placeholder)

@available(macOS 10.15, iOS 13.0, *)
private class TokenInterceptSchemeHandler: NSObject, WKURLSchemeHandler {
    private let onTokenCapture: (String) -> Void
    
    init(onTokenCapture: @escaping (String) -> Void) {
        self.onTokenCapture = onTokenCapture
        super.init()
    }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // Not used for https interception
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Not used
    }
}

// MARK: - macOS Window Delegate

#if os(macOS)
@available(macOS 10.15, *)
private class WebAuthWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose()
        return true
    }
}
#endif

// MARK: - iOS View Controller

#if os(iOS)
@available(iOS 13.0, *)
private class WebAuthViewController: UIViewController {
    private let webView: WKWebView
    private let onCancel: () -> Void
    
    init(webView: WKWebView, onCancel: @escaping () -> Void) {
        self.webView = webView
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }
    
    @objc private func cancelTapped() {
        onCancel()
    }
}
#endif

// MARK: - EAClient Extension

@available(macOS 10.15, iOS 13.0, *)
public extension EAClient {
    
    #if os(macOS)
    /// Authenticate using web-based login (macOS)
    ///
    /// This presents a web view where the user can sign in to EA.
    /// The token is automatically captured and stored.
    ///
    /// - Parameter window: The window to present from
    /// - Returns: The captured access token
    @MainActor
    func authenticateWithWeb(from window: NSWindow) async throws -> String {
        let webAuth = EAWebAuthenticator(storage: EATokenStorage())
        let token = try await webAuth.authenticate(from: window)
        try await setToken(token)
        return token
    }
    #endif
    
    #if os(iOS)
    /// Authenticate using web-based login (iOS)
    ///
    /// This presents a web view where the user can sign in to EA.
    /// The token is automatically captured and stored.
    ///
    /// - Parameter viewController: The view controller to present from
    /// - Returns: The captured access token
    @MainActor
    func authenticateWithWeb(from viewController: UIViewController) async throws -> String {
        let webAuth = EAWebAuthenticator(storage: EATokenStorage())
        let token = try await webAuth.authenticate(from: viewController)
        try await setToken(token)
        return token
    }
    #endif
}
