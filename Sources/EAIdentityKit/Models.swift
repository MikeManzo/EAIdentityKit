//
//  Models.swift
//  EAIdentityKit
//
//  Data models for EA Identity API responses
//

import Foundation

// MARK: - PID Response Models

/// Response from the /proxy/identity/pids/me endpoint
public struct PIDResponse: Codable, Sendable {
    public let pid: PIDInfo
}

/// Detailed PID (Player ID) information from EA's identity service
public struct PIDInfo: Codable, Sendable {
    /// The nucleus ID - this is the primary account identifier
    public let pidId: String
    
    /// External reference type (typically "NUCLEUS")
    public let externalRefType: String?
    
    /// External reference value
    public let externalRefValue: String?
    
    /// User's country code (e.g., "US")
    public let country: String?
    
    /// User's language code (e.g., "en")
    public let language: String?
    
    /// User's locale (e.g., "en_US")
    public let locale: String?
    
    /// Account status (e.g., "ACTIVE")
    public let status: String?
    
    /// Stop process status
    public let stopProcessStatus: String?
    
    /// Reason code for any account restrictions
    public let reasonCode: String?
    
    /// Terms of service version accepted
    public let tosVersion: String?
    
    /// Parental email for child accounts
    public let parentalEmail: String?
    
    /// Third-party opt-in status
    public let thirdPartyOptin: String?
    
    /// Global opt-in status
    public let globalOptin: String?
    
    /// Account creation date
    public let dateCreated: String?
    
    /// Source of account registration (e.g., "eadm-origin")
    public let registrationSource: String?
    
    /// Authentication source identifier
    public let authenticationSource: String?
    
    /// Email visibility setting
    public let showEmail: String?
    
    /// Email discoverability setting
    public let discoverableEmail: String?
    
    /// Whether this is an anonymous PID
    public let anonymousPid: String?
    
    /// Whether this is an underage PID
    public let underagePid: String?
    
    /// Teen to adult transition flag
    public let teenToAdultFlag: Bool?
    
    /// Default billing address URI
    public let defaultBillingAddressUri: String?
    
    /// Default shipping address URI
    public let defaultShippingAddressUri: String?
    
    /// Password signature for validation
    public let passwordSignature: String?
}

// MARK: - Persona Models

/// Persona information from the atom/users endpoint
public struct PersonaInfo: Sendable, Equatable {
    /// User ID (same as pidId in most cases)
    public let userId: String
    
    /// Persona ID - per-game/platform identifier
    public let personaId: String
    
    /// EA ID - the public username visible to other players
    public let eaId: String
    
    public init(userId: String, personaId: String, eaId: String) {
        self.userId = userId
        self.personaId = personaId
        self.eaId = eaId
    }
}

// MARK: - Combined Identity Model

/// Complete EA identity information combining PID and persona data
public struct EAIdentity: Sendable, Equatable {
    /// Nucleus ID (pidId) - the master account identifier
    public let pidId: String
    
    /// Persona ID - per-game/platform identifier
    public let personaId: String
    
    /// EA ID - the public username visible to other players
    public let eaId: String
    
    /// Account status (e.g., "ACTIVE")
    public let status: String?
    
    /// User's country code
    public let country: String?
    
    /// User's locale
    public let locale: String?
    
    /// Account creation date
    public let dateCreated: String?
    
    /// Registration source
    public let registrationSource: String?
    
    public init(
        pidId: String,
        personaId: String,
        eaId: String,
        status: String? = nil,
        country: String? = nil,
        locale: String? = nil,
        dateCreated: String? = nil,
        registrationSource: String? = nil
    ) {
        self.pidId = pidId
        self.personaId = personaId
        self.eaId = eaId
        self.status = status
        self.country = country
        self.locale = locale
        self.dateCreated = dateCreated
        self.registrationSource = registrationSource
    }
}

// MARK: - Subscription Models

/// EA Play / Origin Access subscription information
public struct SubscriptionInfo: Codable, Sendable {
    public let subscriptionStatus: String?
    public let tier: String?
    public let startDate: String?
    public let endDate: String?
}
