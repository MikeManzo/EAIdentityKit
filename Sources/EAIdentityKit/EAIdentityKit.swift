//
//  EAIdentityKit.swift
//  EAIdentityKit
//
//  A Swift package for retrieving EA Player IDs (nucleus_id/pid/personaId)
//
//  Copyright © 2024. MIT License.
//

/// # EAIdentityKit
///
/// A Swift package for interacting with EA's Identity API to retrieve player IDs.
///
/// ## Overview
///
/// EAIdentityKit provides a clean, Swift-native interface to EA's internal identity services.
/// Use this package to:
///
/// - Retrieve a user's **nucleus ID** (also known as pidId) - the master account identifier
/// - Retrieve a user's **persona ID** - the per-game/platform identifier
/// - Retrieve a user's **EA ID** - the public username visible to other players
///
/// ## Quick Start
///
/// ```swift
/// import EAIdentityKit
///
/// // Initialize with an OAuth access token
/// let api = EAIdentityAPI(accessToken: "your_token_here")
///
/// // Fetch identity using async/await
/// let identity = try await api.getFullIdentity()
/// print("Nucleus ID: \(identity.pidId)")
/// print("Persona ID: \(identity.personaId)")
/// print("EA ID: \(identity.eaId)")
/// ```
///
/// ## Authentication
///
/// To use this package, you need an EA OAuth access token. You can obtain one using:
///
/// 1. The built-in ``EAAuthenticator`` class
/// 2. Intercepting tokens from the EA App/Origin client
/// 3. Implementing your own OAuth flow
///
/// ```swift
/// let authenticator = EAAuthenticator()
/// let token = try await authenticator.authenticate(anchor: window)
/// let api = EAIdentityAPI(accessToken: token)
/// ```
///
/// ## Token Storage
///
/// Use ``EATokenStorage`` to securely store tokens in the Keychain:
///
/// ```swift
/// let storage = EATokenStorage()
/// try storage.saveToken(token)
/// let savedToken = storage.loadToken()
/// ```
///
/// ## Terminology
///
/// | Term | Description |
/// |------|-------------|
/// | **pidId / nucleus_id** | The master account identifier at EA's backend level |
/// | **personaId** | A per-game or per-platform identifier for a "persona" |
/// | **EAID / EA ID** | The public-facing username visible to other players |
///
/// A single EA account (pidId) can have multiple personas (personaId) across
/// different platforms (PC, PlayStation, Xbox) or games.
///
/// ## Topics
///
/// ### Essentials
/// - ``EAIdentityAPI``
/// - ``EAIdentity``
/// - ``EAIdentityError``
///
/// ### Authentication
/// - ``EAAuthenticator``
/// - ``EATokenStorage``
///
/// ### Models
/// - ``PIDInfo``
/// - ``PersonaInfo``
/// - ``TokenInfo``
///
/// ### SwiftUI Integration
/// - ``EAIdentityViewModel``

// Re-export all public types
@_exported import Foundation
