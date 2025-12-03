//
//  PersonaXMLParser.swift
//  EAIdentityKit
//
//  XML parser for EA's atom/users endpoint responses
//

import Foundation

/// Parser for the XML response from EA's atom/users endpoint
///
/// Expected XML format:
/// ```xml
/// <users>
///     <user>
///         <userId>1003118773678</userId>
///         <personaId>1781965055</personaId>
///         <EAID>username</EAID>
///     </user>
/// </users>
/// ```
final class PersonaXMLParser: NSObject, XMLParserDelegate {
    
    // MARK: - Properties
    
    private(set) var userId: String?
    private(set) var personaId: String?
    private(set) var eaId: String?
    
    private var currentElement: String = ""
    private var currentValue: String = ""
    private var isInsideUser: Bool = false
    
    // MARK: - Parsing
    
    /// Parse XML data and return PersonaInfo
    /// - Parameter data: XML data from the atom/users endpoint
    /// - Returns: PersonaInfo if parsing succeeds
    /// - Throws: EAIdentityError if parsing fails or required fields are missing
    func parse(data: Data) throws -> PersonaInfo {
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        guard parser.parse() else {
            if let error = parser.parserError {
                throw EAIdentityError.xmlParsingError(error.localizedDescription)
            }
            throw EAIdentityError.xmlParsingError("Unknown parsing error")
        }
        
        guard let userId = userId else {
            throw EAIdentityError.missingField("userId")
        }
        
        guard let personaId = personaId else {
            throw EAIdentityError.missingField("personaId")
        }
        
        guard let eaId = eaId else {
            throw EAIdentityError.missingField("EAID")
        }
        
        return PersonaInfo(userId: userId, personaId: personaId, eaId: eaId)
    }
    
    // MARK: - XMLParserDelegate
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentValue = ""
        
        if elementName == "user" {
            isInsideUser = true
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideUser {
            currentValue += string
        }
    }
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard isInsideUser else { return }
        
        let trimmedValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch elementName {
        case "userId":
            // Only capture the first user's data
            if userId == nil {
                userId = trimmedValue
            }
        case "personaId":
            if personaId == nil {
                personaId = trimmedValue
            }
        case "EAID":
            if eaId == nil {
                eaId = trimmedValue
            }
        case "user":
            isInsideUser = false
        default:
            break
        }
        
        currentValue = ""
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Error will be handled by the parse() method
    }
}

// MARK: - Multiple Users Parser

/// Parser for responses that may contain multiple users
final class MultiplePersonaXMLParser: NSObject, XMLParserDelegate {
    
    // MARK: - Properties
    
    private(set) var personas: [PersonaInfo] = []
    
    private var currentUserId: String?
    private var currentPersonaId: String?
    private var currentEaId: String?
    
    private var currentElement: String = ""
    private var currentValue: String = ""
    private var isInsideUser: Bool = false
    
    // MARK: - Parsing
    
    /// Parse XML data and return all PersonaInfo entries
    /// - Parameter data: XML data from the atom/users endpoint
    /// - Returns: Array of PersonaInfo
    /// - Throws: EAIdentityError if parsing fails
    func parse(data: Data) throws -> [PersonaInfo] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        guard parser.parse() else {
            if let error = parser.parserError {
                throw EAIdentityError.xmlParsingError(error.localizedDescription)
            }
            throw EAIdentityError.xmlParsingError("Unknown parsing error")
        }
        
        return personas
    }
    
    // MARK: - XMLParserDelegate
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentValue = ""
        
        if elementName == "user" {
            isInsideUser = true
            currentUserId = nil
            currentPersonaId = nil
            currentEaId = nil
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideUser {
            currentValue += string
        }
    }
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard isInsideUser else { return }
        
        let trimmedValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch elementName {
        case "userId":
            currentUserId = trimmedValue
        case "personaId":
            currentPersonaId = trimmedValue
        case "EAID":
            currentEaId = trimmedValue
        case "user":
            // Completed parsing a user element
            if let userId = currentUserId,
               let personaId = currentPersonaId,
               let eaId = currentEaId {
                let persona = PersonaInfo(userId: userId, personaId: personaId, eaId: eaId)
                personas.append(persona)
            }
            isInsideUser = false
        default:
            break
        }
        
        currentValue = ""
    }
}
