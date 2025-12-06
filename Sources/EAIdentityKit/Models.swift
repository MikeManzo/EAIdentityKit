//
//  Models.swift
//  EAIdentityKit
//
//  Data models for EA Identity API responses
//
// Copyright (c) 2025 CitizenCoder.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
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
    
    /// User's email (may be masked)
    public let email: String?
    
    /// Email verification status
    public let emailStatus: String?
    
    /// Password strength
    public let strength: String?
    
    /// Date of birth (may be masked)
    public let dob: String?
    
    /// User's age
    public let age: Int?
    
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
    
    /// Account last modified date
    public let dateModified: String?
    
    /// Last authentication date
    public let lastAuthDate: String?
    
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
    public let passwordSignature: Int?
    
    /// Whether two-factor authentication is enabled
    public let tfaEnabled: Bool?
    
    /// Custom decoder to handle pidId as Int or String
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle pidId as either Int or String
        if let intId = try? container.decode(Int.self, forKey: .pidId) {
            pidId = String(intId)
        } else {
            pidId = try container.decode(String.self, forKey: .pidId)
        }
        
        externalRefType = try container.decodeIfPresent(String.self, forKey: .externalRefType)
        externalRefValue = try container.decodeIfPresent(String.self, forKey: .externalRefValue)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        emailStatus = try container.decodeIfPresent(String.self, forKey: .emailStatus)
        strength = try container.decodeIfPresent(String.self, forKey: .strength)
        dob = try container.decodeIfPresent(String.self, forKey: .dob)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        stopProcessStatus = try container.decodeIfPresent(String.self, forKey: .stopProcessStatus)
        reasonCode = try container.decodeIfPresent(String.self, forKey: .reasonCode)
        tosVersion = try container.decodeIfPresent(String.self, forKey: .tosVersion)
        parentalEmail = try container.decodeIfPresent(String.self, forKey: .parentalEmail)
        thirdPartyOptin = try container.decodeIfPresent(String.self, forKey: .thirdPartyOptin)
        globalOptin = try container.decodeIfPresent(String.self, forKey: .globalOptin)
        dateCreated = try container.decodeIfPresent(String.self, forKey: .dateCreated)
        dateModified = try container.decodeIfPresent(String.self, forKey: .dateModified)
        lastAuthDate = try container.decodeIfPresent(String.self, forKey: .lastAuthDate)
        registrationSource = try container.decodeIfPresent(String.self, forKey: .registrationSource)
        authenticationSource = try container.decodeIfPresent(String.self, forKey: .authenticationSource)
        showEmail = try container.decodeIfPresent(String.self, forKey: .showEmail)
        discoverableEmail = try container.decodeIfPresent(String.self, forKey: .discoverableEmail)
        anonymousPid = try container.decodeIfPresent(String.self, forKey: .anonymousPid)
        underagePid = try container.decodeIfPresent(String.self, forKey: .underagePid)
        teenToAdultFlag = try container.decodeIfPresent(Bool.self, forKey: .teenToAdultFlag)
        defaultBillingAddressUri = try container.decodeIfPresent(String.self, forKey: .defaultBillingAddressUri)
        defaultShippingAddressUri = try container.decodeIfPresent(String.self, forKey: .defaultShippingAddressUri)
        passwordSignature = try container.decodeIfPresent(Int.self, forKey: .passwordSignature)
        tfaEnabled = try container.decodeIfPresent(Bool.self, forKey: .tfaEnabled)
    }
    
    private enum CodingKeys: String, CodingKey {
        case pidId, externalRefType, externalRefValue, email, emailStatus, strength, dob, age
        case country, language, locale, status, stopProcessStatus, reasonCode, tosVersion
        case parentalEmail, thirdPartyOptin, globalOptin, dateCreated, dateModified, lastAuthDate
        case registrationSource, authenticationSource, showEmail, discoverableEmail
        case anonymousPid, underagePid, teenToAdultFlag, defaultBillingAddressUri
        case defaultShippingAddressUri, passwordSignature, tfaEnabled
    }
    
    /// Manual initializer for flexible parsing
    public init(
        pidId: String,
        externalRefType: String? = nil,
        externalRefValue: String? = nil,
        email: String? = nil,
        emailStatus: String? = nil,
        strength: String? = nil,
        dob: String? = nil,
        age: Int? = nil,
        country: String? = nil,
        language: String? = nil,
        locale: String? = nil,
        status: String? = nil,
        stopProcessStatus: String? = nil,
        reasonCode: String? = nil,
        tosVersion: String? = nil,
        parentalEmail: String? = nil,
        thirdPartyOptin: String? = nil,
        globalOptin: String? = nil,
        dateCreated: String? = nil,
        dateModified: String? = nil,
        lastAuthDate: String? = nil,
        registrationSource: String? = nil,
        authenticationSource: String? = nil,
        showEmail: String? = nil,
        discoverableEmail: String? = nil,
        anonymousPid: String? = nil,
        underagePid: String? = nil,
        teenToAdultFlag: Bool? = nil,
        defaultBillingAddressUri: String? = nil,
        defaultShippingAddressUri: String? = nil,
        passwordSignature: Int? = nil,
        tfaEnabled: Bool? = nil
    ) {
        self.pidId = pidId
        self.externalRefType = externalRefType
        self.externalRefValue = externalRefValue
        self.email = email
        self.emailStatus = emailStatus
        self.strength = strength
        self.dob = dob
        self.age = age
        self.country = country
        self.language = language
        self.locale = locale
        self.status = status
        self.stopProcessStatus = stopProcessStatus
        self.reasonCode = reasonCode
        self.tosVersion = tosVersion
        self.parentalEmail = parentalEmail
        self.thirdPartyOptin = thirdPartyOptin
        self.globalOptin = globalOptin
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.lastAuthDate = lastAuthDate
        self.registrationSource = registrationSource
        self.authenticationSource = authenticationSource
        self.showEmail = showEmail
        self.discoverableEmail = discoverableEmail
        self.anonymousPid = anonymousPid
        self.underagePid = underagePid
        self.teenToAdultFlag = teenToAdultFlag
        self.defaultBillingAddressUri = defaultBillingAddressUri
        self.defaultShippingAddressUri = defaultShippingAddressUri
        self.passwordSignature = passwordSignature
        self.tfaEnabled = tfaEnabled
    }
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
