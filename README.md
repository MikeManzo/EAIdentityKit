# EAIdentityKit

A Swift package for retrieving EA Player IDs (nucleus_id, pid, personaId) from EA's Identity API.

[![Swift](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> **⚠️ Note:** Origin was officially shut down by EA in April 2025. This package uses EA gateway endpoints (`gateway.ea.com`).

## Overview

EAIdentityKit provides a clean, Swift-native interface to EA's identity services. Use this package to:

- Retrieve a user's **nucleus ID** (pidId) - the master account identifier
- Retrieve a user's **persona ID** - the per-game/platform identifier  
- Retrieve a user's **EA ID** - the public username visible to other players
- **Validate** and **store** EA OAuth access tokens securely

## Requirements

- macOS 12.0+ / iOS 15.0+ / tvOS 15.0+ / watchOS 8.0+
- Swift 5.7+
- Xcode 14.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/EAIdentityKit.git", from: "1.0.0")
]
```

Or in Xcode:

1. Go to **File → Add Packages...**
2. Enter the repository URL
3. Select the version and click **Add Package**

## Getting an Access Token

### Method 1: Web-Based Login (Recommended)

The package includes `EAWebAuthenticator` which presents EA's login page in a web view and automatically captures the token:

```swift
// macOS
let webAuth = EAWebAuthenticator()
let token = try await webAuth.authenticate(from: window)

// iOS
let token = try await webAuth.authenticate(from: viewController)

// Or use the EAClient convenience method
let client = EAClient()
let token = try await client.authenticateWithWeb(from: window)
let identity = try await client.getIdentity()
```

### Method 2: Manual Token Entry

If the web-based approach doesn't work, you can get a token manually:

**From Browser:**
1. Go to [ea.com](https://www.ea.com) and sign in
2. Open Developer Tools (F12)
3. Go to the **Network** tab
4. Filter requests by `gateway.ea.com`
5. Look for the `Authorization` header in any request
6. Copy the token value (remove the `Bearer ` prefix)

**From EA App (Windows):**
Use a network inspection tool like Fiddler or Wireshark to capture network traffic and find requests with Bearer tokens to EA's gateway.

## Quick Start

```swift
import EAIdentityKit

// Initialize client with your token
let client = EAClient()
try await client.setToken("your_access_token_here")

// Get identity
let identity = try await client.getIdentity()

print("EA ID: \(identity.eaId)")
print("Nucleus ID: \(identity.pidId)")
print("Persona ID: \(identity.personaId)")
```

## Usage Examples

### Using EAClient (Recommended)

```swift
let client = EAClient()

// Set and validate token
try await client.setToken("your_token")

// Get full identity
let identity = try await client.getIdentity()

// Or get specific IDs
let nucleusId = try await client.getNucleusId()
let personaId = try await client.getPersonaId()
let eaId = try await client.getEAId()
```

### Using EAIdentityAPI Directly

```swift
let api = EAIdentityAPI(accessToken: "your_token_here")

// Get full identity
let identity = try await api.getFullIdentity()

// Or get specific data
let pidInfo = try await api.getPIDInfo()
let personaInfo = try await api.getPersonaInfo(pidId: pidInfo.pidId)
```

### Token Validation

```swift
let authenticator = EAAuthenticator()

// Validate and store a token
let isValid = try await authenticator.validateAndStore(token: "your_token")

// Test if token works
let works = try await authenticator.testToken("your_token")

// Get stored token later
if let token = authenticator.getStoredToken() {
    let api = EAIdentityAPI(accessToken: token)
}
```

### Using Cached Token

```swift
// Check if there's a valid cached token
if let api = EAIdentityAPI.fromCache() {
    let identity = try await api.getFullIdentity()
}
```

### SwiftUI Integration

```swift
import SwiftUI
import EAIdentityKit

struct ContentView: View {
    @State private var identity: EAIdentity?
    @State private var token = ""
    
    var body: some View {
        VStack {
            if let identity = identity {
                Text("EA ID: \(identity.eaId)")
                Text("Nucleus ID: \(identity.pidId)")
            } else {
                SecureField("Access Token", text: $token)
                Button("Fetch Identity") {
                    Task {
                        let api = EAIdentityAPI(accessToken: token)
                        identity = try? await api.getFullIdentity()
                    }
                }
            }
        }
    }
}
```

### Combine Support

```swift
import Combine

var cancellables = Set<AnyCancellable>()

let api = EAIdentityAPI(accessToken: token)

api.getFullIdentityPublisher()
    .receive(on: DispatchQueue.main)
    .sink(
        receiveCompletion: { completion in
            if case .failure(let error) = completion {
                print("Error: \(error)")
            }
        },
        receiveValue: { identity in
            print("EA ID: \(identity.eaId)")
        }
    )
    .store(in: &cancellables)
```

## API Reference

### EAClient

High-level client combining token management and identity fetching.

| Method | Description |
|--------|-------------|
| `setToken(_:)` | Validate and store a token |
| `setTokenWithoutValidation(_:expiresIn:)` | Store token without validation |
| `testCurrentToken()` | Test if stored token works |
| `getIdentity()` | Get full identity |
| `getNucleusId()` | Get only nucleus ID |
| `getPersonaId()` | Get only persona ID |
| `getEAId()` | Get only EA ID (username) |
| `logout()` | Clear stored credentials |

### EAIdentityAPI

Lower-level API client for direct API access.

| Method | Description |
|--------|-------------|
| `getPIDInfo()` | Get nucleus ID and account details |
| `getPersonaInfo(pidId:)` | Get persona ID and EA ID |
| `getFullIdentity()` | Get complete identity information |
| `fromCache()` | Create API from cached token |

### EAWebAuthenticator

Web-based authenticator that captures tokens from EA's login flow.

| Method | Description |
|--------|-------------|
| `authenticate(from:)` | Present login and capture token |
| `present(from:)` | Present login (delegate-based) |
| `dismiss()` | Dismiss the login view |

### EAAuthenticator

Handles token validation and storage.

| Method | Description |
|--------|-------------|
| `validateAndStore(token:)` | Validate and store a token |
| `validateToken(_:)` | Check if token is valid |
| `testToken(_:)` | Test token against API |
| `getStoredToken()` | Get stored token |
| `storeToken(_:expiresIn:)` | Store token directly |
| `logout()` | Clear stored credentials |

### Models

| Model | Description |
|-------|-------------|
| `EAIdentity` | Complete identity with pidId, personaId, eaId |
| `PIDInfo` | Detailed account information |
| `PersonaInfo` | Persona information (userId, personaId, eaId) |
| `TokenInfo` | Token validation response |
| `EACredentials` | Stored authentication credentials |

## Error Handling

```swift
do {
    let identity = try await client.getIdentity()
} catch EAAuthError.noToken {
    // No token set - call setToken() first
} catch EAAuthError.invalidToken {
    // Token is invalid or expired
} catch EAIdentityError.invalidToken {
    // Token expired - get a new one
} catch EAIdentityError.rateLimited {
    // Too many requests - wait and retry
} catch {
    print("Error: \(error)")
}
```

## Terminology

| Term | Description |
|------|-------------|
| **pidId / nucleus_id** | Master account identifier at EA's backend |
| **personaId** | Per-game or per-platform identifier |
| **EAID / EA ID** | Public username visible to other players |

A single EA account (pidId) can have multiple personas (personaId) across different platforms (PC, PlayStation, Xbox) or games.

## Security Considerations

- **Token Security**: Tokens are stored securely in the Keychain
- **No Credentials Stored**: The package never stores email/password
- **Token Expiration**: Tokens typically expire in 1 hour
- **Terms of Service**: Using undocumented APIs may violate EA's ToS

## Origin Shutdown Notice

As of April 2025, EA has officially shut down the Origin client and its associated APIs. This package uses EA's gateway endpoints (`gateway.ea.com`). Automated OAuth authentication is not supported due to EA's strict redirect URI requirements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This package is not affiliated with or endorsed by Electronic Arts Inc. Use at your own risk. EA's APIs may change without notice.
