//
//  EAIdentityError.swift
//  EAIdentityKit
//
//  A Swift package for retrieving EA Player IDs (nucleus_id/pid)
//
// Copyright (c) 2025 CitizenCoder.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//

import Foundation

/// Errors that can occur when interacting with the EA Identity API
public enum EAIdentityError: Error, LocalizedError, Sendable {
    /// The URL was invalid or could not be constructed
    case invalidURL
    
    /// No data was received from the server
    case noData
    
    /// Failed to decode the response
    case decodingError(String)
    
    /// A network error occurred
    case networkError(String)
    
    /// HTTP error with status code and optional message
    case httpError(statusCode: Int, message: String?)
    
    /// XML parsing failed
    case xmlParsingError(String)
    
    /// A required field was missing from the response
    case missingField(String)
    
    /// The access token is invalid or expired
    case invalidToken
    
    /// Rate limit exceeded
    case rateLimited
    
    /// Authentication required
    case authenticationRequired
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received from server"
        case .decodingError(let details):
            return "Decoding error: \(details)"
        case .networkError(let details):
            return "Network error: \(details)"
        case .httpError(let statusCode, let message):
            return "HTTP error \(statusCode): \(message ?? "Unknown error")"
        case .xmlParsingError(let details):
            return "XML parsing error: \(details)"
        case .missingField(let field):
            return "Missing required field: \(field)"
        case .invalidToken:
            return "Invalid or expired access token"
        case .rateLimited:
            return "Rate limit exceeded. Please wait and try again."
        case .authenticationRequired:
            return "Authentication required. Please log in."
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .invalidToken, .authenticationRequired:
            return "Please re-authenticate with EA to obtain a new access token."
        case .rateLimited:
            return "Wait a few minutes before trying again."
        case .httpError(let statusCode, _):
            switch statusCode {
            case 401:
                return "Your session has expired. Please log in again."
            case 403:
                return "Access denied. The token may lack required permissions."
            case 404:
                return "The requested resource was not found."
            case 429:
                return "Too many requests. Please wait a moment and try again."
            case 500...599:
                return "EA servers are experiencing issues. Please try again later."
            default:
                return nil
            }
        default:
            return nil
        }
    }
}
