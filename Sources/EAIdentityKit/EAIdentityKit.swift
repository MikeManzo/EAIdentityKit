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
/// EA's OAuth system has strict redirect URI requirements that make automated
/// web-based authentication from native apps challenging. To get a token:
///
/// 1. **From the EA App (Windows)**: Use a network inspector to capture the access token
/// 2. **From Browser Dev Tools**: Login to ea.com, open dev tools, look for requests
///    to gateway.ea.com and copy the Authorization header (remove "Bearer " prefix)
/// 3. **From Game Auth**: Some EA games expose their auth tokens that can be reused
///
/// Once you have a token, validate and store it:
///
/// ```swift
/// let authenticator = EAAuthenticator()
/// try await authenticator.validateAndStore(token: "your_token_here")
///
/// // Later, use the stored token
/// if let token = authenticator.getStoredToken() {
///     let api = EAIdentityAPI(accessToken: token)
/// }
/// ```
///
/// ## Using EAClient (Recommended)
///
/// For simpler usage, use ``EAClient`` which handles token storage:
///
/// ```swift
/// let client = EAClient()
/// try await client.setToken("your_token_here")
/// let identity = try await client.getIdentity()
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
/// - ``EAClient``
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

// Re-export all public types
@_exported import Foundation
