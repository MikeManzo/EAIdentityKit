//
//  EAIdentityAPI.swift
//  EAIdentityKit
//
//  Main API client for interacting with EA's identity services
//

import Foundation
import AuthenticationServices

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Client for interacting with EA's Identity API to retrieve player IDs
///
/// Use this client to:
/// - Get the authenticated user's nucleus ID (pidId)
/// - Get persona information (personaId, EA ID/username)
/// - Get complete identity information
///
/// ## Usage with Access Token
///
/// ```swift
/// let api = EAIdentityAPI(accessToken: "your_oauth_token")
/// let identity = try await api.getFullIdentity()
/// ```
///
/// ## Usage with Cached Token
///
/// ```swift
/// if let api = EAIdentityAPI.fromCache() {
///     let identity = try await api.getFullIdentity()
/// }
/// ```
public final class EAIdentityAPI: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let accessToken: String
    private let session: URLSession
    
    // MARK: - Constants
    
    /// API endpoint URLs
    /// Note: Origin was shut down in April 2025. All endpoints now use EA gateway services.
    public enum Endpoints {
        /// Identity PID endpoint
        public static let identityPids = "https://gateway.ea.com/proxy/identity/pids/me"
        
        /// Token info endpoint
        public static let tokenInfo = "https://accounts.ea.com/connect/tokeninfo"
        
        /// Personas endpoint - get persona info for a pidId
        public static func personas(pidId: String) -> String {
            return "https://gateway.ea.com/proxy/identity/pids/\(pidId)/personas"
        }
        
        /// Achievements endpoint
        public static func achievements(personaId: String, achievementSet: String? = nil) -> String {
            let setPath = achievementSet.map { "/\($0)" } ?? ""
            return "https://achievements.gameservices.ea.com/achievements/personas/\(personaId)\(setPath)/all"
        }
        
        /// EA Play subscriptions endpoint
        public static func subscriptions(pidId: String) -> String {
            return "https://gateway.ea.com/proxy/subscription/pids/\(pidId)/subscriptionsv2/groups/EA%20Play"
        }
        
        /// Entitlements endpoint
        public static func entitlements(pidId: String) -> String {
            return "https://gateway.ea.com/proxy/identity/pids/\(pidId)/entitlements"
        }
    }
    
    private enum Headers {
        static let authorization = "Authorization"
        static let extendedPids = "X-Extended-Pids"
        static let includeNamespace = "X-Include-Namespace"
        static let accept = "Accept"
        static let contentType = "Content-Type"
    }
    
    // MARK: - Initialization
    
    /// Initialize the EA Identity API client
    /// - Parameters:
    ///   - accessToken: OAuth 2.0 access token from EA authentication
    ///   - session: URLSession to use for requests (defaults to shared)
    public init(
        accessToken: String,
        session: URLSession = .shared
    ) {
        self.accessToken = accessToken
        self.session = session
    }
    
    /// Initialize with a custom URLSession configuration
    /// - Parameters:
    ///   - accessToken: OAuth 2.0 access token from EA authentication
    ///   - configuration: URLSession configuration
    public convenience init(
        accessToken: String,
        configuration: URLSessionConfiguration
    ) {
        let session = URLSession(configuration: configuration)
        self.init(accessToken: accessToken, session: session)
    }
    
    // MARK: - Factory Methods
    
    /// Create an API instance using a cached token if available
    ///
    /// Returns nil if no valid cached token exists.
    ///
    /// - Parameter storage: Token storage to check
    /// - Returns: EAIdentityAPI instance if cached token exists, nil otherwise
    public static func fromCache(
        storage: EATokenStorage = EATokenStorage()
    ) -> EAIdentityAPI? {
        guard let credentials = storage.loadCredentials(),
              !credentials.isExpired else {
            return nil
        }
        return EAIdentityAPI(accessToken: credentials.accessToken)
    }
    
    /// Create an API instance from the EAAuthenticator's stored token
    ///
    /// Returns nil if no valid token is stored.
    ///
    /// - Parameter authenticator: The authenticator to get the token from
    /// - Returns: EAIdentityAPI instance if token exists, nil otherwise
    public static func fromAuthenticator(_ authenticator: EAAuthenticator) -> EAIdentityAPI? {
        guard let token = authenticator.getStoredToken() else {
            return nil
        }
        return EAIdentityAPI(accessToken: token)
    }
    
    // MARK: - Private Helpers
    
    private func createRequest(url: URL, additionalHeaders: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: Headers.authorization)
        request.setValue("true", forHTTPHeaderField: Headers.extendedPids)
        request.setValue("application/json", forHTTPHeaderField: Headers.accept)
        request.timeoutInterval = 30
        
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        return request
    }
    
    private func handleHTTPResponse(_ response: URLResponse?, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return // Success
        case 401:
            throw EAIdentityError.invalidToken
        case 429:
            throw EAIdentityError.rateLimited
        default:
            let message = data.flatMap { String(data: $0, encoding: .utf8) }
            throw EAIdentityError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }
    
    // MARK: - Public API Methods (Async/Await)
    
    /// Get the authenticated user's nucleus ID (pidId) and account info
    /// - Returns: PIDInfo containing the nucleus ID and account details
    /// - Throws: EAIdentityError if the request fails
    public func getPIDInfo() async throws -> PIDInfo {
        guard let url = URL(string: Endpoints.identityPids) else {
            throw EAIdentityError.invalidURL
        }
        
        let request = createRequest(url: url)
        
        do {
            let (data, response) = try await session.data(for: request)
            try handleHTTPResponse(response, data: data)
            
            let decoder = JSONDecoder()
            let pidResponse = try decoder.decode(PIDResponse.self, from: data)
            return pidResponse.pid
            
        } catch let error as EAIdentityError {
            throw error
        } catch let error as DecodingError {
            throw EAIdentityError.decodingError(error.localizedDescription)
        } catch {
            throw EAIdentityError.networkError(error.localizedDescription)
        }
    }
    
    /// Get persona information (personaId, EAID/username) for a given pidId
    /// - Parameter pidId: The nucleus ID obtained from getPIDInfo()
    /// - Returns: PersonaInfo containing userId, personaId, and EA ID (username)
    /// - Throws: EAIdentityError if the request fails
    public func getPersonaInfo(pidId: String) async throws -> PersonaInfo {
        // Use EA gateway personas endpoint (Origin has been shut down)
        guard let url = URL(string: Endpoints.personas(pidId: pidId)) else {
            throw EAIdentityError.invalidURL
        }
        
        let request = createRequest(url: url)
        
        do {
            let (data, response) = try await session.data(for: request)
            try handleHTTPResponse(response, data: data)
            
            // Parse the JSON response from EA gateway
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Handle {"personas": {"persona": [...]}} format
                if let personasWrapper = json["personas"] as? [String: Any],
                   let personaArray = personasWrapper["persona"] as? [[String: Any]],
                   let firstPersona = personaArray.first {
                    return try parsePersonaJSON(firstPersona, userId: pidId)
                }
                
                // Handle {"personas": [...]} format
                if let personas = json["personas"] as? [[String: Any]],
                   let firstPersona = personas.first {
                    return try parsePersonaJSON(firstPersona, userId: pidId)
                }
                
                // Handle single persona object
                if let personaId = json["personaId"] {
                    return try parsePersonaJSON(json, userId: pidId)
                }
            }
            
            throw EAIdentityError.decodingError("Failed to parse persona response from EA gateway")
            
        } catch let error as EAIdentityError {
            throw error
        } catch {
            throw EAIdentityError.networkError(error.localizedDescription)
        }
    }
    
    /// Parse persona JSON into PersonaInfo
    private func parsePersonaJSON(_ json: [String: Any], userId: String) throws -> PersonaInfo {
        // Extract personaId (can be Int or String)
        let personaIdValue: String
        if let intId = json["personaId"] as? Int {
            personaIdValue = String(intId)
        } else if let stringId = json["personaId"] as? String {
            personaIdValue = stringId
        } else {
            throw EAIdentityError.missingField("personaId")
        }
        
        // Extract display name (try multiple possible field names)
        let displayName = json["displayName"] as? String
            ?? json["name"] as? String
            ?? json["pidId"] as? String
            ?? userId
        
        return PersonaInfo(
            userId: userId,
            personaId: personaIdValue,
            eaId: displayName
        )
    }
    
    /// Get complete identity information including both pidId and personaId
    /// - Returns: EAIdentity with all identity information
    /// - Throws: EAIdentityError if the request fails
    public func getFullIdentity() async throws -> EAIdentity {
        // Step 1: Get nucleus ID
        let pidInfo = try await getPIDInfo()
        
        // Step 2: Get persona information
        let personaInfo = try await getPersonaInfo(pidId: pidInfo.pidId)
        
        return EAIdentity(
            pidId: pidInfo.pidId,
            personaId: personaInfo.personaId,
            eaId: personaInfo.eaId,
            status: pidInfo.status,
            country: pidInfo.country,
            locale: pidInfo.locale,
            dateCreated: pidInfo.dateCreated,
            registrationSource: pidInfo.registrationSource
        )
    }
    
    /// Get only the nucleus ID (pidId) without additional account details
    /// - Returns: The nucleus ID string
    /// - Throws: EAIdentityError if the request fails
    public func getNucleusId() async throws -> String {
        let pidInfo = try await getPIDInfo()
        return pidInfo.pidId
    }
    
    /// Get only the persona ID for a given nucleus ID
    /// - Parameter pidId: The nucleus ID
    /// - Returns: The persona ID string
    /// - Throws: EAIdentityError if the request fails
    public func getPersonaId(for pidId: String) async throws -> String {
        let personaInfo = try await getPersonaInfo(pidId: pidId)
        return personaInfo.personaId
    }
    
    // MARK: - Public API Methods (Completion Handler)
    
    /// Get the authenticated user's nucleus ID (pidId) and account info
    /// - Parameter completion: Completion handler with Result containing PIDInfo or error
    public func getPIDInfo(completion: @escaping @Sendable (Result<PIDInfo, EAIdentityError>) -> Void) {
        guard let url = URL(string: Endpoints.identityPids) else {
            completion(.failure(.invalidURL))
            return
        }
        
        let request = createRequest(url: url)
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            
            do {
                try self?.handleHTTPResponse(response, data: data)
            } catch let error as EAIdentityError {
                completion(.failure(error))
                return
            } catch {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.noData))
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let pidResponse = try decoder.decode(PIDResponse.self, from: data)
                completion(.success(pidResponse.pid))
            } catch {
                completion(.failure(.decodingError(error.localizedDescription)))
            }
        }.resume()
    }
    
    /// Get persona information (personaId, EAID/username) for a given pidId
    /// - Parameters:
    ///   - pidId: The nucleus ID obtained from getPIDInfo()
    ///   - completion: Completion handler with Result containing PersonaInfo or error
    public func getPersonaInfo(pidId: String, completion: @escaping @Sendable (Result<PersonaInfo, EAIdentityError>) -> Void) {
        guard let url = URL(string: Endpoints.personas(pidId: pidId)) else {
            completion(.failure(.invalidURL))
            return
        }
        
        let request = createRequest(url: url)
        
        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            
            do {
                try self?.handleHTTPResponse(response, data: data)
            } catch let error as EAIdentityError {
                completion(.failure(error))
                return
            } catch {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.noData))
                return
            }
            
            // Parse JSON response from EA gateway
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Handle {"personas": {"persona": [...]}} format
                    if let personasWrapper = json["personas"] as? [String: Any],
                       let personaArray = personasWrapper["persona"] as? [[String: Any]],
                       let firstPersona = personaArray.first,
                       let personaInfo = self?.parsePersonaJSONSync(firstPersona, userId: pidId) {
                        completion(.success(personaInfo))
                        return
                    }
                    
                    // Handle {"personas": [...]} format
                    if let personas = json["personas"] as? [[String: Any]],
                       let firstPersona = personas.first,
                       let personaInfo = self?.parsePersonaJSONSync(firstPersona, userId: pidId) {
                        completion(.success(personaInfo))
                        return
                    }
                    
                    // Handle single persona object
                    if json["personaId"] != nil,
                       let personaInfo = self?.parsePersonaJSONSync(json, userId: pidId) {
                        completion(.success(personaInfo))
                        return
                    }
                }
                completion(.failure(.decodingError("Failed to parse persona response")))
            } catch {
                completion(.failure(.decodingError(error.localizedDescription)))
            }
        }.resume()
    }
    
    /// Sync version of parsePersonaJSON for completion handler use
    private func parsePersonaJSONSync(_ json: [String: Any], userId: String) -> PersonaInfo? {
        let personaIdValue: String
        if let intId = json["personaId"] as? Int {
            personaIdValue = String(intId)
        } else if let stringId = json["personaId"] as? String {
            personaIdValue = stringId
        } else {
            return nil
        }
        
        let displayName = json["displayName"] as? String
            ?? json["name"] as? String
            ?? json["pidId"] as? String
            ?? userId
        
        return PersonaInfo(
            userId: userId,
            personaId: personaIdValue,
            eaId: displayName
        )
    }
    
    /// Get complete identity information including both pidId and personaId
    /// - Parameter completion: Completion handler with Result containing EAIdentity or error
    public func getFullIdentity(completion: @escaping @Sendable (Result<EAIdentity, EAIdentityError>) -> Void) {
        getPIDInfo { [weak self] result in
            switch result {
            case .success(let pidInfo):
                self?.getPersonaInfo(pidId: pidInfo.pidId) { personaResult in
                    switch personaResult {
                    case .success(let personaInfo):
                        let identity = EAIdentity(
                            pidId: pidInfo.pidId,
                            personaId: personaInfo.personaId,
                            eaId: personaInfo.eaId,
                            status: pidInfo.status,
                            country: pidInfo.country,
                            locale: pidInfo.locale,
                            dateCreated: pidInfo.dateCreated,
                            registrationSource: pidInfo.registrationSource
                        )
                        completion(.success(identity))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
