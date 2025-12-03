# EAIdentityKit

A Swift package for retrieving EA Player IDs (nucleus_id, pid, personaId) from EA's Identity API.

[![Swift](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Overview

EAIdentityKit provides a clean, Swift-native interface to EA's identity services. Use this package to:

- **Authenticate** with EA using web-based OAuth or email/password
- Retrieve a user's **nucleus ID** (pidId) - the master account identifier
- Retrieve a user's **persona ID** - the per-game/platform identifier  
- Retrieve a user's **EA ID** - the public username visible to other players

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

## Quick Start

The simplest way to get started is with `EAClient`:

```swift
import EAIdentityKit

let client = EAClient()

// Authenticate and get identity in one call
let identity = try await client.getIdentity()

print("EA ID: \(identity.eaId)")
print("Nucleus ID: \(identity.pidId)")
print("Persona ID: \(identity.personaId)")
```

## Authentication Methods

### 1. Web-Based OAuth (Recommended)

Opens EA's login page in a browser window:

```swift
let client = EAClient()

// macOS
let token = try await client.authenticate()

// iOS  
let token = try await client.authenticate(from: viewController)

// Then fetch identity
let identity = try await client.getIdentity()
```

### 2. Email/Password

Direct authentication with credentials:

```swift
let client = EAClient()

// Authenticate with credentials
try await client.authenticate(email: "user@example.com", password: "password")

// Fetch identity
let identity = try await client.getIdentity()
```

> **Note:** This method may fail if CAPTCHA or 2FA is required. Web-based authentication is recommended.

### 3. One-Line Lookup

Quick lookup using static method:

```swift
let identity = try await EAClient.lookup(email: "user@example.com", password: "password")
print("EA ID: \(identity.eaId)")
```

### 4. Manual Token

If you already have an access token:

```swift
let api = EAIdentityAPI(accessToken: "your_token_here")
let identity = try await api.getFullIdentity()
```

## Usage Examples

### Get Specific IDs

```swift
let client = EAClient()

// Get only nucleus ID
let nucleusId = try await client.getNucleusId()

// Get only persona ID
let personaId = try await client.getPersonaId()

// Get only EA ID (username)
let eaId = try await client.getEAId()
```

### SwiftUI Integration

```swift
import SwiftUI
import EAIdentityKit

struct ContentView: View {
    @StateObject private var viewModel = EAIdentityViewModel(api: EAIdentityAPI(accessToken: token))
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView()
            } else if let identity = viewModel.identity {
                Text("EA ID: \(identity.eaId)")
                Text("Nucleus ID: \(identity.pidId)")
            } else if let error = viewModel.errorMessage {
                Text("Error: \(error)")
            }
            
            Button("Fetch") { viewModel.fetchIdentity() }
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

### Token Management

Tokens are automatically stored in the Keychain:

```swift
let client = EAClient()

// Check if authenticated
if client.isAuthenticated {
    // Already have a valid token
}

// Logout and clear stored tokens
client.logout()
```

Manual token storage:

```swift
let storage = EATokenStorage()

// Save token
try storage.saveToken(token)

// Load token
if let savedToken = storage.loadToken() {
    let api = EAIdentityAPI(accessToken: savedToken)
}

// Delete token
try storage.deleteToken()
```

## API Reference

### EAClient

High-level client combining authentication and identity fetching.

| Method | Description |
|--------|-------------|
| `authenticate()` | Web-based OAuth authentication |
| `authenticate(email:password:)` | Credential-based authentication |
| `getIdentity()` | Get full identity (auto-authenticates if needed) |
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

### EAAuthenticator

Handles OAuth authentication flows.

| Method | Description |
|--------|-------------|
| `authenticate(window:)` | Web OAuth (macOS) |
| `authenticate(from:)` | Web OAuth (iOS) |
| `authenticate(email:password:)` | Credential authentication |
| `refreshAccessToken(_:)` | Refresh an expired token |
| `validateToken(_:)` | Check if token is valid |

### Models

| Model | Description |
|-------|-------------|
| `EAIdentity` | Complete identity with pidId, personaId, eaId |
| `PIDInfo` | Detailed account information |
| `PersonaInfo` | Persona information (userId, personaId, eaId) |
| `EACredentials` | Stored authentication credentials |

## Error Handling

```swift
do {
    let identity = try await client.getIdentity()
} catch EAAuthError.cancelled {
    // User cancelled authentication
} catch EAAuthError.invalidCredentials {
    // Wrong email or password
} catch EAAuthError.captchaRequired {
    // CAPTCHA required - use web authentication
} catch EAAuthError.twoFactorRequired {
    // 2FA required - use web authentication
} catch EAIdentityError.invalidToken {
    // Token expired - re-authenticate
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
- **Token Expiration**: Tokens are automatically refreshed when possible
- **Credentials**: Email/password are never stored - only tokens
- **Terms of Service**: Using undocumented APIs may violate EA's ToS

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This package is not affiliated with or endorsed by Electronic Arts Inc. Use at your own risk. EA's internal APIs may change without notice.
