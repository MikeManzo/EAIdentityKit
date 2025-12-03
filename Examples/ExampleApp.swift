//
//  ExampleApp.swift
//  EAIdentityKit Example
//
//  Example macOS application demonstrating EAIdentityKit usage
//

/*
 
 To use this example:
 
 1. Create a new macOS App project in Xcode
 2. Add EAIdentityKit as a package dependency
 3. Replace the ContentView.swift with this file's ContentView
 4. Run the app
 
 */

import SwiftUI
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
            
            // Main Content
            if viewModel.isLoading {
                LoadingView()
            } else if let identity = viewModel.identity {
                IdentityDisplayView(identity: identity)
                
                Divider()
                
                HStack(spacing: 12) {
                    Button("Refresh") {
                        viewModel.fetchIdentity()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Logout") {
                        viewModel.logout()
                    }
                    .foregroundColor(.red)
                }
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error) {
                    viewModel.fetchIdentity()
                }
            } else {
                AuthenticationView(viewModel: viewModel)
            }
            
            Spacer()
            
            // Status bar
            HStack {
                Circle()
                    .fill(viewModel.isAuthenticated ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(viewModel.isAuthenticated ? "Authenticated" : "Not authenticated")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(30)
        .frame(minWidth: 550, minHeight: 500)
    }
}

// MARK: - Authentication View

struct AuthenticationView: View {
    @ObservedObject var viewModel: IdentityViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showCredentialAuth = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Web Authentication (Recommended)
            VStack(spacing: 12) {
                Text("Sign in with EA")
                    .font(.headline)
                
                Button(action: { viewModel.authenticateWithWeb() }) {
                    HStack {
                        Image(systemName: "globe")
                        Text("Sign in with Browser")
                    }
                    .frame(maxWidth: 250)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Text("Recommended - Opens EA login in your browser")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(maxWidth: 300)
            
            // Credential Authentication (Alternative)
            VStack(spacing: 12) {
                Button(action: { showCredentialAuth.toggle() }) {
                    HStack {
                        Text("Or sign in with email/password")
                        Image(systemName: showCredentialAuth ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                
                if showCredentialAuth {
                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                        
                        Button("Sign In") {
                            viewModel.authenticateWithCredentials(email: email, password: password)
                        }
                        .buttonStyle(.bordered)
                        .disabled(email.isEmpty || password.isEmpty)
                        
                        Text("Note: May fail if CAPTCHA or 2FA is required")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: 300)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            
            Divider()
                .frame(maxWidth: 300)
            
            // Manual Token Entry
            VStack(spacing: 12) {
                DisclosureGroup("Advanced: Enter token manually") {
                    VStack(spacing: 8) {
                        SecureField("Access Token", text: $viewModel.manualToken)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Use Token") {
                            viewModel.useManualToken()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.manualToken.isEmpty)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: 300)
            }
        }
        .animation(.easeInOut, value: showCredentialAuth)
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
                    .font(.title2)
                Text("Identity Retrieved")
                    .font(.headline)
            }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    // Primary identifiers
                    Group {
                        InfoRow(label: "EA ID (Username)", value: identity.eaId, copyable: true, highlight: true)
                        InfoRow(label: "Nucleus ID (pidId)", value: identity.pidId, copyable: true, highlight: true)
                        InfoRow(label: "Persona ID", value: identity.personaId, copyable: true, highlight: true)
                    }
                    
                    Divider()
                    
                    // Account details
                    Group {
                        InfoRow(label: "Status", value: identity.status ?? "Unknown")
                        InfoRow(label: "Country", value: identity.country ?? "Unknown")
                        InfoRow(label: "Locale", value: identity.locale ?? "Unknown")
                        InfoRow(label: "Created", value: formatDate(identity.dateCreated))
                    }
                }
                .padding()
            } label: {
                Text("Account Information")
            }
            
            // Copy all button
            Button(action: copyAllToClipboard) {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Copy All IDs")
                }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "Unknown" }
        // Simple formatting - could use DateFormatter for more complex formatting
        return dateString.replacingOccurrences(of: "T", with: " ")
                        .replacingOccurrences(of: "Z", with: "")
                        .prefix(19)
                        .description
    }
    
    private func copyAllToClipboard() {
        let text = """
        EA ID: \(identity.eaId)
        Nucleus ID: \(identity.pidId)
        Persona ID: \(identity.personaId)
        """
        
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String
    var copyable: Bool = false
    var highlight: Bool = false
    
    @State private var copied = false
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
            
            Text(value)
                .fontWeight(highlight ? .semibold : .regular)
                .foregroundColor(highlight ? .primary : .secondary)
                .textSelection(.enabled)
            
            Spacer()
            
            if copyable {
                Button(action: copyToClipboard) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copied ? .green : .blue)
                        .frame(width: 20)
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
    @State private var dots = ""
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Fetching identity\(dots)")
                .foregroundColor(.secondary)
                .onReceive(timer) { _ in
                    dots = dots.count >= 3 ? "" : dots + "."
                }
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
            
            Text("Error")
                .font(.headline)
            
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            
            HStack(spacing: 12) {
                Button("Retry") {
                    retryAction()
                }
                .buttonStyle(.borderedProminent)
            }
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
    @Published var manualToken = ""
    
    private let client = EAClient.shared
    
    var isAuthenticated: Bool {
        client.isAuthenticated
    }
    
    init() {
        // Auto-fetch if already authenticated
        if isAuthenticated {
            fetchIdentity()
        }
    }
    
    func authenticateWithWeb() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                #if os(macOS)
                try await client.authenticate()
                #endif
                await fetchIdentityAsync()
            } catch let error as EAAuthError {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func authenticateWithCredentials(email: String, password: String) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await client.authenticate(email: email, password: password)
                await fetchIdentityAsync()
            } catch let error as EAAuthError {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func useManualToken() {
        guard !manualToken.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        // Create a new API instance with the manual token
        let api = EAIdentityAPI(accessToken: manualToken)
        
        Task {
            do {
                let identity = try await api.getFullIdentity()
                self.identity = identity
                self.manualToken = ""
            } catch let error as EAIdentityError {
                self.errorMessage = error.localizedDescription
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }
    
    func fetchIdentity() {
        isLoading = true
        errorMessage = nil
        
        Task {
            await fetchIdentityAsync()
        }
    }
    
    private func fetchIdentityAsync() async {
        do {
            #if os(macOS)
            let identity = try await client.getIdentity(anchor: NSApplication.shared.keyWindow)
            #else
            let identity = try await client.getIdentity()
            #endif
            self.identity = identity
        } catch let error as EAIdentityError {
            self.errorMessage = error.localizedDescription
        } catch let error as EAAuthError {
            self.errorMessage = error.localizedDescription
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        self.isLoading = false
    }
    
    func logout() {
        client.logout()
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
