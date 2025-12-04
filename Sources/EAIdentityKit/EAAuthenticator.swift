//
//  EAAuthenticator.swift
//  EAIdentityKit
//
//  Authentication helpers for obtaining EA OAuth tokens
//

import Foundation
import AuthenticationServices

// MARK: - Authentication Errors

/// Errors that can occur during EA authentication
public enum EAAuthError: Error, LocalizedError, Sendable {
    case cancelled
    case noToken
    case invalidResponse
    case invalidCredentials
    case networkError(String)
    case sessionExpired
    case captchaRequired
    case twoFactorRequired
    case accountLocked
    case serverError(Int)
    
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Authentication was cancelled"
        case .noToken:
            return "No access token received"
        case .invalidResponse:
            return "Invalid response from EA servers"
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError(let message):
            return "Network error: \(message)"
        case .sessionExpired:
            return "Session has expired"
        case .captchaRequired:
            return "CAPTCHA verification required - please use web authentication"
        case .twoFactorRequired:
            return "Two-factor authentication required"
        case .accountLocked:
            return "Account is locked"
        case .serverError(let code):
            return "Server error (code: \(code))"
        }
    }
}

// MARK: - Token Response

/// Response containing OAuth token information
public struct EATokenResponse: Codable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int
    public let refreshToken: String?
    public let idToken: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

// MARK: - Stored Credentials

/// Stored authentication credentials
public struct EACredentials: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let userId: String?
    
    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date, userId: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
    }
    
    public var isExpired: Bool {
        Date() >= expiresAt
    }
    
    public var isExpiringSoon: Bool {
        Date().addingTimeInterval(300) >= expiresAt // 5 minutes
    }
}

// MARK: - EA Authenticator

/// Authenticator for obtaining EA OAuth access tokens
///
/// Supports multiple authentication methods:
/// - Web-based OAuth flow (recommended)
/// - Direct credential authentication
/// - Token refresh
///
/// ## Usage
///
/// ```swift
/// let auth = EAAuthenticator()
///
/// // Web-based authentication (recommended)
/// let token = try await auth.authenticate()
///
/// // Or with credentials
/// let token = try await auth.authenticate(email: "user@example.com", password: "pass")
/// ```
@available(macOS 10.15, iOS 13.0, *)
public final class EAAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    
    // MARK: - Types
    
    /// Known EA OAuth client IDs
    public enum ClientID: String, Sendable, CaseIterable {
        /// Battlefield/Sparta client - works with localhost redirect
        case battlefield = "sparta-backend-as-user-pc"
        
        /// Default client ID for general use
        public static let `default`: ClientID = .battlefield
        
        var redirectUri: String {
            switch self {
            case .battlefield:
                return "http://127.0.0.1:8085/callback"
            }
        }
        
        /// The URL scheme to listen for in ASWebAuthenticationSession
        var callbackScheme: String {
            return "http"
        }
    }
    
    // MARK: - Properties
    
    private var authSession: ASWebAuthenticationSession?
    private var presentingWindow: ASPresentationAnchor?
    
    private let clientId: ClientID
    private let session: URLSession
    private let storage: EATokenStorage
    
    // MARK: - Constants
    
    private enum URLs {
        // EA App authentication endpoints (post-Origin shutdown)
        static let authBase = "https://accounts.ea.com/connect"
        static let auth = "\(authBase)/auth"
        static let token = "\(authBase)/token"
        static let tokenInfo = "\(authBase)/tokeninfo"
        
        // EA App login portal
        static let eaLogin = "https://signin.ea.com/p/juno/login"
        static let eaLoginSubmit = "https://signin.ea.com/p/juno/login"
        
        // Alternative: EA web login
        static let webLogin = "https://www.ea.com/login"
    }
    
    // MARK: - Initialization
    
    /// Initialize the authenticator
    /// - Parameters:
    ///   - clientId: The EA OAuth client ID to use
    ///   - storage: Token storage instance (defaults to Keychain storage)
    public init(
        clientId: ClientID = .default,
        storage: EATokenStorage = EATokenStorage()
    ) {
        self.clientId = clientId
        self.storage = storage
        
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Accept": "application/json",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        self.session = URLSession(configuration: config)
        
        super.init()
    }
    
    // MARK: - Web Authentication (Recommended)
    
    #if os(macOS)
    /// Authenticate with EA using web-based OAuth flow (macOS)
    /// - Parameter window: The window to present the authentication UI from (optional, uses key window)
    /// - Returns: The access token
    @MainActor
    public func authenticate(window: NSWindow? = nil) async throws -> String {
        let anchor = window ?? NSApplication.shared.keyWindow ?? NSWindow()
        return try await authenticateWithWeb(anchor: anchor)
    }
    #endif
    
    #if os(iOS)
    /// Authenticate with EA using web-based OAuth flow (iOS)
    /// - Parameter viewController: The view controller to present from
    /// - Returns: The access token
    @MainActor
    public func authenticate(from viewController: UIViewController) async throws -> String {
        guard let window = viewController.view.window else {
            throw EAAuthError.invalidResponse
        }
        return try await authenticateWithWeb(anchor: window)
    }
    #endif
    
    /// Authenticate with EA using web-based OAuth flow
    /// - Parameter anchor: The presentation anchor for the authentication UI
    /// - Returns: The access token
    public func authenticateWithWeb(anchor: ASPresentationAnchor) async throws -> String {
        // Check for valid cached token first
        if let cached = try? await getValidToken() {
            return cached
        }
        
        self.presentingWindow = anchor
        
        return try await withCheckedThrowingContinuation { continuation in
            performWebAuthentication { result in
                continuation.resume(with: result)
            }
        }
    }
    
    private func performWebAuthentication(completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        var components = URLComponents(string: URLs.auth)!
        
        // Use code flow with battlefield client which accepts localhost redirect
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId.rawValue),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: clientId.redirectUri)
        ]
        
        guard let authURL = components.url else {
            completion(.failure(EAAuthError.invalidResponse))
            return
        }
        
        // Use http scheme for localhost callback
        let callbackScheme = clientId.callbackScheme
        
        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            if let error = error as? ASWebAuthenticationSessionError {
                if error.code == .canceledLogin {
                    completion(.failure(EAAuthError.cancelled))
                } else {
                    completion(.failure(EAAuthError.networkError(error.localizedDescription)))
                }
                return
            }
            
            if let error = error {
                completion(.failure(EAAuthError.networkError(error.localizedDescription)))
                return
            }
            
            guard let callbackURL = callbackURL else {
                completion(.failure(EAAuthError.noToken))
                return
            }
            
            // Try to extract access token from fragment (implicit flow)
            if let tokenData = self?.extractTokenData(from: callbackURL) {
                Task {
                    try? await self?.storeCredentials(tokenData)
                }
                completion(.success(tokenData.accessToken))
                return
            }
            
            // Try to extract authorization code from query (code flow)
            if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                // Exchange code for token
                Task {
                    do {
                        let tokenResponse = try await self?.exchangeCodeForToken(code)
                        if let token = tokenResponse?.accessToken {
                            try? await self?.storeCredentials(tokenResponse!)
                            completion(.success(token))
                        } else {
                            completion(.failure(EAAuthError.noToken))
                        }
                    } catch {
                        completion(.failure(error))
                    }
                }
                return
            }
            
            completion(.failure(EAAuthError.noToken))
        }
        
        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }
    
    // MARK: - Direct Credential Authentication
    
    /// Authenticate with EA using email and password
    ///
    /// Note: This method may fail if CAPTCHA or 2FA is required.
    /// Web-based authentication is recommended for most cases.
    ///
    /// - Parameters:
    ///   - email: EA account email
    ///   - password: EA account password
    /// - Returns: The access token
    public func authenticate(email: String, password: String) async throws -> String {
        // Step 1: Initialize login session and get CSRF token
        let (fid, csrfToken) = try await initializeLoginSession()
        
        // Step 2: Submit credentials
        let authCode = try await submitCredentials(
            email: email,
            password: password,
            fid: fid,
            csrfToken: csrfToken
        )
        
        // Step 3: Exchange auth code for token
        let tokenResponse = try await exchangeCodeForToken(authCode)
        
        // Store credentials
        try await storeCredentials(tokenResponse)
        
        return tokenResponse.accessToken
    }
    
    private func initializeLoginSession() async throws -> (fid: String, csrfToken: String) {
        var components = URLComponents(string: URLs.eaLogin)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId.rawValue),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: clientId.redirectUri),
            URLQueryItem(name: "locale", value: "en_US")
        ]
        
        guard let url = components.url else {
            throw EAAuthError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...399).contains(httpResponse.statusCode) else {
            throw EAAuthError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let html = String(data: data, encoding: .utf8) ?? ""
        
        // Extract fid from URL or response
        guard let fid = extractValue(from: html, pattern: "name=\"_eventId\"\\s+value=\"([^\"]+)\"") ??
                        extractValue(from: httpResponse.url?.absoluteString ?? "", pattern: "fid=([^&]+)") else {
            throw EAAuthError.invalidResponse
        }
        
        // Extract CSRF token
        guard let csrfToken = extractValue(from: html, pattern: "name=\"_csrf\"\\s+value=\"([^\"]+)\"") else {
            throw EAAuthError.invalidResponse
        }
        
        return (fid, csrfToken)
    }
    
    private func submitCredentials(email: String, password: String, fid: String, csrfToken: String) async throws -> String {
        guard let url = URL(string: URLs.eaLoginSubmit) else {
            throw EAAuthError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "email": email,
            "password": password,
            "_eventId": "submit",
            "_csrf": csrfToken,
            "fid": fid
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EAAuthError.invalidResponse
        }
        
        // Check for error responses
        let html = String(data: data, encoding: .utf8) ?? ""
        
        if html.contains("captcha") || html.contains("CAPTCHA") {
            throw EAAuthError.captchaRequired
        }
        
        if html.contains("two-factor") || html.contains("2FA") || html.contains("verification code") {
            throw EAAuthError.twoFactorRequired
        }
        
        if html.contains("locked") || html.contains("suspended") {
            throw EAAuthError.accountLocked
        }
        
        if html.contains("incorrect") || html.contains("invalid") {
            throw EAAuthError.invalidCredentials
        }
        
        // Look for redirect with auth code
        if let location = httpResponse.value(forHTTPHeaderField: "Location"),
           let code = extractValue(from: location, pattern: "code=([^&]+)") {
            return code
        }
        
        // Try to find code in response
        if let code = extractValue(from: html, pattern: "code=([^&\"]+)") {
            return code
        }
        
        throw EAAuthError.noToken
    }
    
    private func exchangeCodeForToken(_ code: String) async throws -> EATokenResponse {
        guard let url = URL(string: URLs.token) else {
            throw EAAuthError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientId.rawValue,
            "redirect_uri": clientId.redirectUri
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EAAuthError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return try JSONDecoder().decode(EATokenResponse.self, from: data)
    }
    
    // MARK: - Token Management
    
    /// Get a valid token, refreshing if necessary
    /// - Returns: A valid access token
    public func getValidToken() async throws -> String {
        guard let credentials = storage.loadCredentials() else {
            throw EAAuthError.noToken
        }
        
        if !credentials.isExpired && !credentials.isExpiringSoon {
            return credentials.accessToken
        }
        
        // Try to refresh
        if let refreshToken = credentials.refreshToken {
            do {
                let newToken = try await refreshAccessToken(refreshToken)
                return newToken.accessToken
            } catch {
                // Refresh failed, need to re-authenticate
                throw EAAuthError.sessionExpired
            }
        }
        
        throw EAAuthError.sessionExpired
    }
    
    /// Refresh an access token using a refresh token
    /// - Parameter refreshToken: The refresh token
    /// - Returns: New token response
    public func refreshAccessToken(_ refreshToken: String) async throws -> EATokenResponse {
        guard let url = URL(string: URLs.token) else {
            throw EAAuthError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId.rawValue
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EAAuthError.sessionExpired
        }
        
        let tokenResponse = try JSONDecoder().decode(EATokenResponse.self, from: data)
        try await storeCredentials(tokenResponse)
        
        return tokenResponse
    }
    
    /// Validate an existing token
    /// - Parameter token: The access token to validate
    /// - Returns: Token info if valid
    public func validateToken(_ token: String) async throws -> TokenInfo {
        guard let url = URL(string: "\(URLs.tokenInfo)?access_token=\(token)") else {
            throw EAAuthError.invalidResponse
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EAIdentityError.invalidToken
        }
        
        return try JSONDecoder().decode(TokenInfo.self, from: data)
    }
    
    /// Check if user is currently authenticated with a valid token
    public var isAuthenticated: Bool {
        guard let credentials = storage.loadCredentials() else {
            return false
        }
        return !credentials.isExpired
    }
    
    /// Logout and clear stored credentials
    public func logout() {
        storage.clearCredentials()
    }
    
    // MARK: - Private Helpers
    
    private func extractTokenData(from url: URL) -> EATokenResponse? {
        // Token can be in fragment (#access_token=...) or query (?access_token=...)
        let string = url.fragment ?? url.query ?? url.absoluteString
        
        guard let accessToken = extractValue(from: string, pattern: "access_token=([^&]+)") else {
            return nil
        }
        
        let expiresIn = extractValue(from: string, pattern: "expires_in=([^&]+)").flatMap { Int($0) } ?? 3600
        let tokenType = extractValue(from: string, pattern: "token_type=([^&]+)") ?? "Bearer"
        let refreshToken = extractValue(from: string, pattern: "refresh_token=([^&]+)")
        
        return EATokenResponse(
            accessToken: accessToken,
            tokenType: tokenType,
            expiresIn: expiresIn,
            refreshToken: refreshToken,
            idToken: nil
        )
    }
    
    private func extractValue(from string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range])
    }
    
    private func storeCredentials(_ tokenResponse: EATokenResponse) async throws {
        let credentials = EACredentials(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            userId: nil
        )
        try storage.saveCredentials(credentials)
    }
    
    // MARK: - ASWebAuthenticationPresentationContextProviding
    
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return presentingWindow ?? NSApplication.shared.keyWindow ?? NSWindow()
        #else
        return presentingWindow ?? UIWindow()
        #endif
    }
}

// MARK: - Token Storage

/// Secure storage for EA access tokens and credentials using the Keychain
public final class EATokenStorage: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let service: String
    private let tokenAccount: String
    private let credentialsAccount: String
    
    // MARK: - Initialization
    
    /// Initialize token storage
    /// - Parameters:
    ///   - service: Keychain service identifier
    ///   - tokenAccount: Account name for token storage
    ///   - credentialsAccount: Account name for credentials storage
    public init(
        service: String = "com.eaidentitykit.auth",
        tokenAccount: String = "ea_access_token",
        credentialsAccount: String = "ea_credentials"
    ) {
        self.service = service
        self.tokenAccount = tokenAccount
        self.credentialsAccount = credentialsAccount
    }
    
    // MARK: - Token Methods
    
    /// Save an access token to the Keychain
    public func saveToken(_ token: String) throws {
        try saveData(token.data(using: .utf8)!, account: tokenAccount)
    }
    
    /// Load the stored access token
    public func loadToken() -> String? {
        guard let data = loadData(account: tokenAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Delete the stored token
    public func deleteToken() throws {
        try deleteData(account: tokenAccount)
    }
    
    /// Check if a token is stored
    public var hasToken: Bool {
        loadToken() != nil
    }
    
    // MARK: - Credentials Methods
    
    /// Save credentials to the Keychain
    public func saveCredentials(_ credentials: EACredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try saveData(data, account: credentialsAccount)
    }
    
    /// Load stored credentials
    public func loadCredentials() -> EACredentials? {
        guard let data = loadData(account: credentialsAccount) else { return nil }
        return try? JSONDecoder().decode(EACredentials.self, from: data)
    }
    
    /// Clear all stored credentials
    public func clearCredentials() {
        try? deleteData(account: tokenAccount)
        try? deleteData(account: credentialsAccount)
    }
    
    // MARK: - Private Methods
    
    private func saveData(_ data: Data, account: String) throws {
        try? deleteData(account: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to save to Keychain"]
            )
        }
    }
    
    private func loadData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    private func deleteData(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete from Keychain"]
            )
        }
    }
}
