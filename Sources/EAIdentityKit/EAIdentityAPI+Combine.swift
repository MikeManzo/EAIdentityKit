//
//  EAIdentityAPI+Combine.swift
//  EAIdentityKit
//
//  Combine framework extensions for reactive programming
//

import Foundation
import Combine

// MARK: - Combine Extensions

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public extension EAIdentityAPI {
    
    /// Get PID info as a Combine publisher
    /// - Returns: Publisher that emits PIDInfo or EAIdentityError
    func getPIDInfoPublisher() -> AnyPublisher<PIDInfo, EAIdentityError> {
        Future<PIDInfo, EAIdentityError> { [weak self] promise in
            self?.getPIDInfo { result in
                promise(result)
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Get persona info as a Combine publisher
    /// - Parameter pidId: The nucleus ID
    /// - Returns: Publisher that emits PersonaInfo or EAIdentityError
    func getPersonaInfoPublisher(pidId: String) -> AnyPublisher<PersonaInfo, EAIdentityError> {
        Future<PersonaInfo, EAIdentityError> { [weak self] promise in
            self?.getPersonaInfo(pidId: pidId) { result in
                promise(result)
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Get full identity as a Combine publisher
    /// - Returns: Publisher that emits EAIdentity or EAIdentityError
    func getFullIdentityPublisher() -> AnyPublisher<EAIdentity, EAIdentityError> {
        getPIDInfoPublisher()
            .flatMap { [weak self] pidInfo -> AnyPublisher<EAIdentity, EAIdentityError> in
                guard let self = self else {
                    return Fail(error: EAIdentityError.noData).eraseToAnyPublisher()
                }
                
                return self.getPersonaInfoPublisher(pidId: pidInfo.pidId)
                    .map { personaInfo in
                        EAIdentity(
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
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// Get only the nucleus ID as a Combine publisher
    /// - Returns: Publisher that emits the nucleus ID string or EAIdentityError
    func getNucleusIdPublisher() -> AnyPublisher<String, EAIdentityError> {
        getPIDInfoPublisher()
            .map(\.pidId)
            .eraseToAnyPublisher()
    }
    
    /// Get only the persona ID as a Combine publisher
    /// - Parameter pidId: The nucleus ID
    /// - Returns: Publisher that emits the persona ID string or EAIdentityError
    func getPersonaIdPublisher(for pidId: String) -> AnyPublisher<String, EAIdentityError> {
        getPersonaInfoPublisher(pidId: pidId)
            .map(\.personaId)
            .eraseToAnyPublisher()
    }
}

// MARK: - ViewModel Helper

/// A view model that manages EA identity state using Combine
///
/// Use this in SwiftUI or UIKit applications to reactively manage EA identity data.
///
/// ```swift
/// @StateObject private var viewModel = EAIdentityViewModel(accessToken: token)
///
/// var body: some View {
///     if let identity = viewModel.identity {
///         Text("EA ID: \(identity.eaId)")
///     }
/// }
/// .onAppear { viewModel.fetchIdentity() }
/// ```
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@MainActor
public final class EAIdentityViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// The fetched EA identity, nil if not yet loaded
    @Published public private(set) var identity: EAIdentity?
    
    /// The fetched PID info, nil if not yet loaded
    @Published public private(set) var pidInfo: PIDInfo?
    
    /// Error message if the last request failed
    @Published public private(set) var errorMessage: String?
    
    /// Whether a request is currently in progress
    @Published public private(set) var isLoading = false
    
    // MARK: - Private Properties
    
    private let api: EAIdentityAPI
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initialize with an access token
    /// - Parameter accessToken: EA OAuth access token
    public init(accessToken: String) {
        self.api = EAIdentityAPI(accessToken: accessToken)
    }
    
    /// Initialize with an existing API client
    /// - Parameter api: Configured EAIdentityAPI instance
    public init(api: EAIdentityAPI) {
        self.api = api
    }
    
    // MARK: - Public Methods
    
    /// Fetch the complete EA identity
    public func fetchIdentity() {
        isLoading = true
        errorMessage = nil
        
        api.getFullIdentityPublisher()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] identity in
                    self?.identity = identity
                }
            )
            .store(in: &cancellables)
    }
    
    /// Fetch only the PID info
    public func fetchPIDInfo() {
        isLoading = true
        errorMessage = nil
        
        api.getPIDInfoPublisher()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] pidInfo in
                    self?.pidInfo = pidInfo
                }
            )
            .store(in: &cancellables)
    }
    
    /// Reset all state
    public func reset() {
        identity = nil
        pidInfo = nil
        errorMessage = nil
        isLoading = false
        cancellables.removeAll()
    }
}
