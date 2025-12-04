//
//  EAClient.swift
//  EAIdentityKit
//
//  High-level client that combines token management and identity fetching
//

import Foundation

/// A high-level client that handles token management and identity fetching
///
/// ## Usage
///
/// ```swift
/// let client = EAClient()
///
/// // Set token obtained from EA App or browser
/// try await client.setToken("your_access_token_here")
///
/// // Get identity
/// let identity = try await client.getIdentity()
/// print("EA ID: \(identity.eaId)")
/// print("Nucleus ID: \(identity.pidId)")
/// ```
@available(macOS 10.15, iOS 13.0, *)
public final class EAClient: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let authenticator: EAAuthenticator
    private let storage: EATokenStorage
    private var api: EAIdentityAPI?
    
    /// Whether the client has a valid authentication token
    public var isAuthenticated: Bool {
        authenticator.hasValidToken
    }
    
    /// The current access token, if available
    public var currentToken: String? {
        authenticator.getStoredToken()
    }
    
    // MARK: - Initialization
    
    /// Initialize the EA client
    public init() {
        self.storage = EATokenStorage()
        self.authenticator = EAAuthenticator(storage: storage)
        
        // Initialize API with cached token if available
        if let token = authenticator.getStoredToken() {
            self.api = EAIdentityAPI(accessToken: token)
        }
    }
    
    /// Initialize with a token
    /// - Parameter token: The EA access token
    public init(token: String) {
        self.storage = EATokenStorage()
        self.authenticator = EAAuthenticator(storage: storage)
        self.api = EAIdentityAPI(accessToken: token)
        
        // Store the token
        try? authenticator.storeToken(token)
    }
    
    // MARK: - Token Management
    
    /// Set the access token (validates and stores it)
    /// - Parameter token: The EA access token
    /// - Returns: True if the token is valid
    @discardableResult
    public func setToken(_ token: String) async throws -> Bool {
        let isValid = try await authenticator.validateAndStore(token: token)
        if isValid {
            self.api = EAIdentityAPI(accessToken: token)
        }
        return isValid
    }
    
    /// Set the access token without validation
    /// - Parameters:
    ///   - token: The EA access token
    ///   - expiresIn: Seconds until expiration (default 1 hour)
    public func setTokenWithoutValidation(_ token: String, expiresIn: Int = 3600) throws {
        try authenticator.storeToken(token, expiresIn: expiresIn)
        self.api = EAIdentityAPI(accessToken: token)
    }
    
    /// Test if the current token works
    /// - Returns: True if the token is valid
    public func testCurrentToken() async throws -> Bool {
        guard let token = currentToken else {
            return false
        }
        return try await authenticator.testToken(token)
    }
    
    /// Logout and clear stored credentials
    public func logout() {
        authenticator.logout()
        api = nil
    }
    
    // MARK: - Identity Methods
    
    /// Get the full EA identity
    /// - Returns: The user's EA identity
    /// - Throws: EAAuthError.noToken if no token is set
    public func getIdentity() async throws -> EAIdentity {
        let api = try ensureAPI()
        return try await api.getFullIdentity()
    }
    
    /// Get only the nucleus ID (pidId)
    /// - Returns: The nucleus ID
    public func getNucleusId() async throws -> String {
        let api = try ensureAPI()
        return try await api.getNucleusId()
    }
    
    /// Get only the persona ID
    /// - Returns: The persona ID
    public func getPersonaId() async throws -> String {
        let api = try ensureAPI()
        let pidInfo = try await api.getPIDInfo()
        let personaInfo = try await api.getPersonaInfo(pidId: pidInfo.pidId)
        return personaInfo.personaId
    }
    
    /// Get only the EA ID (public username)
    /// - Returns: The EA ID
    public func getEAId() async throws -> String {
        let api = try ensureAPI()
        let identity = try await api.getFullIdentity()
        return identity.eaId
    }
    
    /// Get detailed PID information
    /// - Returns: Detailed PID info
    public func getPIDInfo() async throws -> PIDInfo {
        let api = try ensureAPI()
        return try await api.getPIDInfo()
    }
    
    // MARK: - Private Methods
    
    private func ensureAPI() throws -> EAIdentityAPI {
        // Check for stored token first
        if let token = authenticator.getStoredToken() {
            if api == nil {
                api = EAIdentityAPI(accessToken: token)
            }
            return api!
        }
        
        // No token available
        throw EAAuthError.noToken
    }
}

// MARK: - Convenience Extensions

@available(macOS 10.15, iOS 13.0, *)
public extension EAClient {
    
    /// Get all identity information as a dictionary
    /// - Returns: Dictionary with identity information
    func getIdentityDictionary() async throws -> [String: String] {
        let identity = try await getIdentity()
        
        var dict: [String: String] = [
            "pidId": identity.pidId,
            "nucleusId": identity.pidId,
            "personaId": identity.personaId,
            "eaId": identity.eaId
        ]
        
        if let status = identity.status {
            dict["status"] = status
        }
        if let country = identity.country {
            dict["country"] = country
        }
        if let locale = identity.locale {
            dict["locale"] = locale
        }
        if let dateCreated = identity.dateCreated {
            dict["dateCreated"] = dateCreated
        }
        
        return dict
    }
}

// MARK: - Static Convenience Methods

@available(macOS 10.15, iOS 13.0, *)
public extension EAClient {
    
    /// Shared client instance for convenience
    static let shared = EAClient()
    
    /// Quick lookup of EA identity using a token
    /// - Parameter token: EA access token
    /// - Returns: The EA identity
    static func lookup(token: String) async throws -> EAIdentity {
        let client = EAClient(token: token)
        return try await client.getIdentity()
    }
}
