//
//  ExampleApp.swift
//  EAIdentityKit Example
//
//  Example macOS application demonstrating EAIdentityKit usage
//  Updated for EA App (Origin has been shut down as of April 2025)
//

/*
 
 To use this example:
 
 1. Create a new macOS App project in Xcode (macOS 12.0+ deployment target)
 2. Add EAIdentityKit as a package dependency:
    - File → Add Package Dependencies
    - Enter the repository URL or add local package
 3. Copy this entire file content into your ContentView.swift
    (or create a new Swift file and set it as @main)
 4. Build and run
 
 Note: Make sure your project's deployment target is macOS 12.0 or later.
 
 */

import SwiftUI
import WebKit
import EAIdentityKit

// MARK: - App Entry Point

@main
struct EAIdentityExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var viewModel = IdentityViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("EA Identity Lookup")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Retrieve your EA Player ID (nucleus_id)")
                .foregroundColor(.secondary)
            
            Divider()
            
            // Status
            if viewModel.isLoading {
                LoadingView(statusMessage: viewModel.statusMessage)
            } else if let identity = viewModel.identity {
                IdentityDisplayView(identity: identity)
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error) {
                    viewModel.login()
                }
            } else {
                WelcomeView(viewModel: viewModel)
            }
            
            Spacer()
            
            // Footer actions
            if viewModel.identity != nil {
                HStack {
                    Button("Refresh") {
                        viewModel.refresh()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Logout") {
                        viewModel.logout()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .padding(30)
        .frame(minWidth: 500, minHeight: 450)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @ObservedObject var viewModel: IdentityViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Sign in with your EA Account")
                .font(.headline)
            
            Text("Click below to open EA's login page. Your token will be captured automatically after you sign in.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            
            Button(action: { viewModel.login() }) {
                HStack {
                    Image(systemName: "person.badge.key.fill")
                    Text("Sign In with EA")
                }
                .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Divider()
                .frame(width: 300)
            
            // Manual token entry (alternative option)
            DisclosureGroup("Alternative: Enter Token Manually") {
                VStack(spacing: 12) {
                    SecureField("Paste your access token here", text: $viewModel.manualToken)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Use Token") {
                        viewModel.useManualToken()
                    }
                    .disabled(viewModel.manualToken.isEmpty)
                }
                .padding()
            }
            .frame(width: 350)
            
            // Instructions
            DisclosureGroup("How to get a token manually") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("**From Browser:**")
                    Text("1. Go to ea.com and sign in")
                    Text("2. Open Developer Tools (F12)")
                    Text("3. Go to Network tab, filter by 'gateway'")
                    Text("4. Look for requests to gateway.ea.com")
                    Text("5. Copy the Authorization header")
                    Text("6. Remove the 'Bearer ' prefix")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            }
            .frame(width: 350)
        }
    }
}

// MARK: - Identity Display View

struct IdentityDisplayView: View {
    let identity: EAIdentity
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Authenticated")
                    .font(.headline)
            }
            
            GroupBox("Account Information") {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(label: "EA ID (Username)", value: identity.eaId, copyable: true)
                    InfoRow(label: "Nucleus ID (pidId)", value: identity.pidId, copyable: true)
                    InfoRow(label: "Persona ID", value: identity.personaId, copyable: true)
                    
                    Divider()
                    
                    InfoRow(label: "Status", value: identity.status ?? "Unknown")
                    InfoRow(label: "Country", value: identity.country ?? "Unknown")
                    InfoRow(label: "Locale", value: identity.locale ?? "Unknown")
                    
                    if let dateCreated = identity.dateCreated {
                        InfoRow(label: "Created", value: formatDate(dateCreated))
                    }
                }
                .padding()
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String
    var copyable: Bool = false
    
    @State private var copied = false
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
            
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
            
            Spacer()
            
            if copyable {
                Button(action: copyToClipboard) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copied ? .green : .blue)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
        }
    }
    
    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
        
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var statusMessage: String?
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(statusMessage ?? "Authenticating with EA...")
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("Authentication Failed")
                .font(.headline)
            
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            Button("Try Again") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - View Model

@MainActor
class IdentityViewModel: ObservableObject {
    @Published var identity: EAIdentity?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var manualToken = ""
    
    private var api: EAIdentityAPI?
    
    init() {
        // Try to use cached credentials on launch
        if let cachedAPI = EAIdentityAPI.fromCache() {
            self.api = cachedAPI
            refresh()
        }
    }
    
    /// Login using web-based authentication
    func login() {
        #if os(macOS)
        guard let window = NSApplication.shared.keyWindow else {
            errorMessage = "No window available"
            return
        }
        
        isLoading = true
        errorMessage = nil
        statusMessage = "Opening EA login..."
        
        Task {
            do {
                let webAuth = EAWebAuthenticator()
                statusMessage = "Waiting for login..."
                let token = try await webAuth.authenticate(from: window)
                
                statusMessage = "Token captured! Fetching identity..."
                print("[ExampleApp] Token captured: \(String(token.prefix(20)))...")
                
                // Create API with captured token
                self.api = EAIdentityAPI(accessToken: token)
                
                // Fetch identity
                let identity = try await self.api!.getFullIdentity()
                self.identity = identity
                self.isLoading = false
                self.statusMessage = nil
            } catch let error as EAWebAuthenticator.WebAuthError {
                if case .cancelled = error {
                    // User cancelled, just reset state
                    self.isLoading = false
                    self.statusMessage = nil
                } else {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.statusMessage = nil
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.statusMessage = nil
            }
        }
        #else
        errorMessage = "Web authentication not available on this platform"
        #endif
    }
    
    /// Use a manually entered token
    func useManualToken() {
        guard !manualToken.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        api = EAIdentityAPI(accessToken: manualToken)
        
        Task {
            do {
                let identity = try await api!.getFullIdentity()
                self.identity = identity
                
                // Save the token for future use
                let storage = EATokenStorage()
                let credentials = EACredentials(
                    accessToken: manualToken,
                    refreshToken: nil,
                    expiresAt: Date().addingTimeInterval(3600),
                    userId: identity.pidId
                )
                try storage.saveCredentials(credentials)
                
                self.manualToken = ""
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    /// Refresh identity with current token
    func refresh() {
        guard let api = api else {
            login()
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let identity = try await api.getFullIdentity()
                self.identity = identity
                self.isLoading = false
            } catch EAIdentityError.invalidToken {
                // Token expired, need to re-authenticate
                self.api = nil
                self.identity = nil
                self.errorMessage = "Session expired. Please sign in again."
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    /// Logout and clear stored credentials
    func logout() {
        let storage = EATokenStorage()
        storage.clearCredentials()
        
        api = nil
        identity = nil
        errorMessage = nil
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
