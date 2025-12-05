//
//  EAAuthenticator.swift
//  EAIdentityKit
//
//  Authentication helpers for EA OAuth tokens
//
//  Note: EA's OAuth system has strict redirect URI requirements that make
//  automated web-based authentication from native apps challenging.
//  The recommended approach is to obtain a token manually.
//

import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Authentication Errors

/// Errors that can occur during EA authentication
public enum EAAuthError: Error, LocalizedError, Sendable {
    case cancelled
    case noToken
    case invalidResponse
    case invalidCredentials
    case invalidToken
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
        case .invalidToken:
            return "The provided token is invalid or expired"
        case .networkError(let message):
            return "Network error: \(message)"
        case .sessionExpired:
            return "Session has expired"
        case .captchaRequired:
            return "CAPTCHA verification required"
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

// MARK: - Token Info

/// Information about a validated token
public struct TokenInfo: Codable, Sendable {
    public let accessToken: String?
    public let tokenType: String?
    public let clientId: String?
    public let expiresIn: Int?
    public let scope: String?
    public let userId: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case clientId = "client_id"
        case expiresIn = "expires_in"
        case scope
        case userId = "user_id"
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

/// Helper for managing EA OAuth access tokens
///
/// EA's OAuth system has strict redirect URI requirements that make automated
/// web-based authentication from native apps challenging. This class provides
/// utilities for:
/// - Validating tokens obtained manually
/// - Storing tokens securely in the Keychain
/// - Checking token expiration
///
/// ## How to Get a Token
///
/// 1. **From the EA App (Windows)**: Use a network inspector to capture the access token
/// 2. **From Browser Dev Tools**: Login to ea.com, open dev tools, look for requests
///    to gateway.ea.com and copy the Authorization header (remove "Bearer " prefix)
/// 3. **From Game Auth**: Some EA games expose their auth tokens that can be reused
///
/// ## Usage
///
/// ```swift
/// // Validate and store a manually obtained token
/// let authenticator = EAAuthenticator()
/// let isValid = try await authenticator.validateAndStore(token: "your_token_here")
///
/// // Later, retrieve the stored token
/// if let token = authenticator.getStoredToken() {
///     let api = EAIdentityAPI(accessToken: token)
/// }
/// ```
@available(macOS 10.15, iOS 13.0, *)
public final class EAAuthenticator: @unchecked Sendable {
    
    // MARK: - Constants
    
    private enum URLs {
        static let tokenInfo = "https://accounts.ea.com/connect/tokeninfo"
        static let identity = "https://gateway.ea.com/proxy/identity/pids/me"
    }
    
    // MARK: - Properties
    
    private let session: URLSession
    private let storage: EATokenStorage
    
    // MARK: - Initialization
    
    /// Initialize the authenticator
    /// - Parameter storage: Token storage instance (defaults to Keychain storage)
    public init(storage: EATokenStorage = EATokenStorage()) {
        self.storage = storage
        
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Token Validation
    
    /// Validate a token and store it if valid
    /// - Parameter token: The access token to validate
    /// - Returns: True if the token is valid
    @discardableResult
    public func validateAndStore(token: String) async throws -> Bool {
        // First, validate the token
        let tokenInfo = try await validateToken(token)
        
        // Determine expiration
        let expiresIn = tokenInfo.expiresIn ?? 3600
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        
        // Store the credentials
        let credentials = EACredentials(
            accessToken: token,
            refreshToken: nil,
            expiresAt: expiresAt,
            userId: tokenInfo.userId
        )
        try storage.saveCredentials(credentials)
        
        return true
    }
    
    /// Validate an existing token
    /// - Parameter token: The access token to validate
    /// - Returns: Token info if valid
    /// - Throws: EAAuthError.invalidToken if the token is invalid
    public func validateToken(_ token: String) async throws -> TokenInfo {
        guard let url = URL(string: "\(URLs.tokenInfo)?access_token=\(token)") else {
            throw EAAuthError.invalidResponse
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EAAuthError.invalidResponse
        }
        
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            throw EAAuthError.invalidToken
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw EAAuthError.serverError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(TokenInfo.self, from: data)
    }
    
    /// Test if a token works by making an API call
    /// - Parameter token: The access token to test
    /// - Returns: True if the token is valid and can access EA's API
    public func testToken(_ token: String) async throws -> Bool {
        guard let url = URL(string: URLs.identity) else {
            throw EAAuthError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return (200...299).contains(httpResponse.statusCode)
    }
    
    // MARK: - Token Storage
    
    /// Get the stored token if available and not expired
    /// - Returns: The stored access token, or nil if not available or expired
    public func getStoredToken() -> String? {
        guard let credentials = storage.loadCredentials(),
              !credentials.isExpired else {
            return nil
        }
        return credentials.accessToken
    }
    
    /// Get stored credentials
    /// - Returns: The stored credentials, or nil if not available
    public func getStoredCredentials() -> EACredentials? {
        return storage.loadCredentials()
    }
    
    /// Check if user has a valid stored token
    public var hasValidToken: Bool {
        return getStoredToken() != nil
    }
    
    /// Clear all stored credentials
    public func logout() {
        storage.clearCredentials()
    }
    
    /// Store a token directly (without validation)
    /// - Parameters:
    ///   - token: The access token
    ///   - expiresIn: Seconds until expiration (default 1 hour)
    public func storeToken(_ token: String, expiresIn: Int = 3600) throws {
        let credentials = EACredentials(
            accessToken: token,
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            userId: nil
        )
        try storage.saveCredentials(credentials)
    }
}

// MARK: - Token Storage

/// Secure storage for EA access tokens and credentials using the Keychain
public final class EATokenStorage: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let service: String
    private let credentialsAccount: String
    
    // MARK: - Initialization
    
    /// Initialize token storage
    /// - Parameters:
    ///   - service: Keychain service identifier
    ///   - account: Account name for credentials storage
    public init(
        service: String = "com.eaidentitykit.auth",
        account: String = "ea_credentials"
    ) {
        self.service = service
        self.credentialsAccount = account
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
