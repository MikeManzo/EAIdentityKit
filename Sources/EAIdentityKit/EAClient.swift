//
//  EAClient.swift
//  EAIdentityKit
//
//  High-level client that combines authentication and identity fetching
//

import Foundation
import AuthenticationServices

/// A high-level client that handles authentication and identity fetching
///
/// This is the recommended entry point for most use cases. It automatically
/// handles token management, caching, and refresh.
///
/// ## Usage
///
/// ```swift
/// let client = EAClient()
///
/// // Authenticate and get identity in one call
/// let identity = try await client.getIdentity()
/// print("EA ID: \(identity.eaId)")
/// print("Nucleus ID: \(identity.pidId)")
///
/// // Or authenticate first, then make multiple calls
/// try await client.authenticate()
/// let nucleusId = try await client.getNucleusId()
/// let personaId = try await client.getPersonaId()
/// ```
@available(macOS 10.15, iOS 13.0, *)
public final class EAClient: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let authenticator: EAAuthenticator
    private let storage: EATokenStorage
    private var api: EAIdentityAPI?
    
    /// Whether the client has a valid authentication token
    public var isAuthenticated: Bool {
        authenticator.isAuthenticated
    }
    
    // MARK: - Initialization
    
    /// Initialize the EA client
    /// - Parameter clientId: The OAuth client ID to use
    public init(clientId: EAAuthenticator.ClientID = .default) {
        self.storage = EATokenStorage()
        self.authenticator = EAAuthenticator(clientId: clientId, storage: storage)
        
        // Initialize API with cached token if available
        if let credentials = storage.loadCredentials(), !credentials.isExpired {
            self.api = EAIdentityAPI(accessToken: credentials.accessToken)
        }
    }
    
    // MARK: - Authentication
    
    #if os(macOS)
    /// Authenticate with EA (macOS)
    /// - Parameter window: The window to present auth UI from (optional)
    /// - Returns: The access token
    @MainActor
    @discardableResult
    public func authenticate(window: NSWindow? = nil) async throws -> String {
        let token = try await authenticator.authenticate(window: window)
        self.api = EAIdentityAPI(accessToken: token)
        return token
    }
    #endif
    
    #if os(iOS)
    /// Authenticate with EA (iOS)
    /// - Parameter viewController: The view controller to present from
    /// - Returns: The access token
    @MainActor
    @discardableResult
    public func authenticate(from viewController: UIViewController) async throws -> String {
        let token = try await authenticator.authenticate(from: viewController)
        self.api = EAIdentityAPI(accessToken: token)
        return token
    }
    #endif
    
    /// Authenticate with EA using email and password
    /// - Parameters:
    ///   - email: EA account email
    ///   - password: EA account password
    /// - Returns: The access token
    @discardableResult
    public func authenticate(email: String, password: String) async throws -> String {
        let token = try await authenticator.authenticate(email: email, password: password)
        self.api = EAIdentityAPI(accessToken: token)
        return token
    }
    
    /// Logout and clear stored credentials
    public func logout() {
        authenticator.logout()
        api = nil
    }
    
    // MARK: - Identity Methods
    
    /// Get the full EA identity, authenticating if necessary
    ///
    /// This method will:
    /// 1. Check for a cached valid token
    /// 2. If no valid token, prompt for authentication
    /// 3. Fetch and return the identity
    ///
    /// - Parameter anchor: Presentation anchor for auth UI (macOS/iOS)
    /// - Returns: The user's EA identity
    public func getIdentity(anchor: ASPresentationAnchor? = nil) async throws -> EAIdentity {
        let api = try await ensureAuthenticated(anchor: anchor)
        return try await api.getFullIdentity()
    }
    
    /// Get only the nucleus ID (pidId)
    /// - Parameter anchor: Presentation anchor for auth UI
    /// - Returns: The nucleus ID
    public func getNucleusId(anchor: ASPresentationAnchor? = nil) async throws -> String {
        let api = try await ensureAuthenticated(anchor: anchor)
        return try await api.getNucleusId()
    }
    
    /// Get only the persona ID
    /// - Parameter anchor: Presentation anchor for auth UI
    /// - Returns: The persona ID
    public func getPersonaId(anchor: ASPresentationAnchor? = nil) async throws -> String {
        let api = try await ensureAuthenticated(anchor: anchor)
        let pidInfo = try await api.getPIDInfo()
        let personaInfo = try await api.getPersonaInfo(pidId: pidInfo.pidId)
        return personaInfo.personaId
    }
    
    /// Get only the EA ID (public username)
    /// - Parameter anchor: Presentation anchor for auth UI
    /// - Returns: The EA ID
    public func getEAId(anchor: ASPresentationAnchor? = nil) async throws -> String {
        let api = try await ensureAuthenticated(anchor: anchor)
        let identity = try await api.getFullIdentity()
        return identity.eaId
    }
    
    /// Get detailed PID information
    /// - Parameter anchor: Presentation anchor for auth UI
    /// - Returns: Detailed PID info
    public func getPIDInfo(anchor: ASPresentationAnchor? = nil) async throws -> PIDInfo {
        let api = try await ensureAuthenticated(anchor: anchor)
        return try await api.getPIDInfo()
    }
    
    // MARK: - Private Methods
    
    private func ensureAuthenticated(anchor: ASPresentationAnchor?) async throws -> EAIdentityAPI {
        // If we have a valid API instance, use it
        if let api = self.api {
            // Verify token is still valid
            do {
                let _ = try await authenticator.getValidToken()
                return api
            } catch {
                // Token expired, need to re-authenticate
            }
        }
        
        // Need to authenticate
        let token: String
        
        // Try to get a valid token (may refresh if needed)
        do {
            token = try await authenticator.getValidToken()
        } catch {
            // Need interactive authentication
            #if os(macOS)
            // Hop to the main actor to safely access NSApplication.shared.keyWindow
            let keyWindow: ASPresentationAnchor? = await MainActor.run { () -> ASPresentationAnchor? in
                return NSApplication.shared.keyWindow
            }
            if let anchor = anchor ?? keyWindow {
                token = try await authenticator.authenticateWithWeb(anchor: anchor)
            } else {
                throw EAAuthError.noToken
            }
            #elseif os(iOS)
            if let anchor = anchor {
                token = try await authenticator.authenticateWithWeb(anchor: anchor)
            } else {
                throw EAAuthError.noToken
            }
            #else
            throw EAAuthError.noToken
            #endif
        }
        
        let newApi = EAIdentityAPI(accessToken: token)
        self.api = newApi
        return newApi
    }
}

// MARK: - Convenience Extensions

@available(macOS 10.15, iOS 13.0, *)
public extension EAClient {
    
    /// Get all identity information as a dictionary
    /// - Parameter anchor: Presentation anchor for auth UI
    /// - Returns: Dictionary with identity information
    func getIdentityDictionary(anchor: ASPresentationAnchor? = nil) async throws -> [String: String] {
        let identity = try await getIdentity(anchor: anchor)
        
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
    
    /// Quick lookup of EA identity using credentials
    /// - Parameters:
    ///   - email: EA account email
    ///   - password: EA account password
    /// - Returns: The EA identity
    static func lookup(email: String, password: String) async throws -> EAIdentity {
        let client = EAClient()
        try await client.authenticate(email: email, password: password)
        return try await client.getIdentity()
    }
}

