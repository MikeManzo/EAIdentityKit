//
//  EAIdentityKitTests.swift
//  EAIdentityKitTests
//
//  Unit tests for EAIdentityKit
//

import XCTest
@testable import EAIdentityKit

final class EAIdentityKitTests: XCTestCase {
    
    // MARK: - Model Tests
    
    func testPersonaInfoEquatable() {
        let persona1 = PersonaInfo(userId: "123", personaId: "456", eaId: "TestUser")
        let persona2 = PersonaInfo(userId: "123", personaId: "456", eaId: "TestUser")
        let persona3 = PersonaInfo(userId: "789", personaId: "456", eaId: "TestUser")
        
        XCTAssertEqual(persona1, persona2)
        XCTAssertNotEqual(persona1, persona3)
    }
    
    func testEAIdentityEquatable() {
        let identity1 = EAIdentity(
            pidId: "123",
            personaId: "456",
            eaId: "TestUser",
            status: "ACTIVE"
        )
        let identity2 = EAIdentity(
            pidId: "123",
            personaId: "456",
            eaId: "TestUser",
            status: "ACTIVE"
        )
        
        XCTAssertEqual(identity1, identity2)
    }
    
    // MARK: - XML Parser Tests
    
    func testPersonaXMLParserSuccess() throws {
        let xmlString = """
            <?xml version="1.0" encoding="UTF-8"?>
            <users>
                <user>
                    <userId>1003118773678</userId>
                    <personaId>1781965055</personaId>
                    <EAID>TestUsername</EAID>
                </user>
            </users>
            """
        
        let data = xmlString.data(using: .utf8)!
        let parser = PersonaXMLParser()
        
        let result = try parser.parse(data: data)
        
        XCTAssertEqual(result.userId, "1003118773678")
        XCTAssertEqual(result.personaId, "1781965055")
        XCTAssertEqual(result.eaId, "TestUsername")
    }
    
    func testPersonaXMLParserMultipleUsers() throws {
        let xmlString = """
            <?xml version="1.0" encoding="UTF-8"?>
            <users>
                <user>
                    <userId>1003118773678</userId>
                    <personaId>1781965055</personaId>
                    <EAID>FirstUser</EAID>
                </user>
                <user>
                    <userId>2003118773678</userId>
                    <personaId>2781965055</personaId>
                    <EAID>SecondUser</EAID>
                </user>
            </users>
            """
        
        let data = xmlString.data(using: .utf8)!
        let parser = MultiplePersonaXMLParser()
        
        let results = try parser.parse(data: data)
        
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].eaId, "FirstUser")
        XCTAssertEqual(results[1].eaId, "SecondUser")
    }
    
    func testPersonaXMLParserMissingField() {
        let xmlString = """
            <?xml version="1.0" encoding="UTF-8"?>
            <users>
                <user>
                    <userId>1003118773678</userId>
                    <EAID>TestUsername</EAID>
                </user>
            </users>
            """
        
        let data = xmlString.data(using: .utf8)!
        let parser = PersonaXMLParser()
        
        XCTAssertThrowsError(try parser.parse(data: data)) { error in
            guard case EAIdentityError.missingField(let field) = error else {
                XCTFail("Expected missingField error")
                return
            }
            XCTAssertEqual(field, "personaId")
        }
    }
    
    func testPersonaXMLParserEmptyResponse() {
        let xmlString = """
            <?xml version="1.0" encoding="UTF-8"?>
            <users>
            </users>
            """
        
        let data = xmlString.data(using: .utf8)!
        let parser = PersonaXMLParser()
        
        XCTAssertThrowsError(try parser.parse(data: data)) { error in
            guard case EAIdentityError.missingField(_) = error else {
                XCTFail("Expected missingField error")
                return
            }
        }
    }
    
    // MARK: - PID Response Decoding Tests
    
    func testPIDResponseDecoding() throws {
        let json = """
            {
                "pid": {
                    "pidId": "1234567890",
                    "externalRefType": "NUCLEUS",
                    "country": "US",
                    "language": "en",
                    "locale": "en_US",
                    "status": "ACTIVE",
                    "dateCreated": "2020-01-01T00:00:00Z",
                    "registrationSource": "eadm-origin"
                }
            }
            """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(PIDResponse.self, from: data)
        
        XCTAssertEqual(response.pid.pidId, "1234567890")
        XCTAssertEqual(response.pid.externalRefType, "NUCLEUS")
        XCTAssertEqual(response.pid.country, "US")
        XCTAssertEqual(response.pid.status, "ACTIVE")
    }
    
    func testPIDResponseDecodingMinimal() throws {
        let json = """
            {
                "pid": {
                    "pidId": "1234567890"
                }
            }
            """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(PIDResponse.self, from: data)
        
        XCTAssertEqual(response.pid.pidId, "1234567890")
        XCTAssertNil(response.pid.country)
        XCTAssertNil(response.pid.status)
    }
    
    // MARK: - Error Tests
    
    func testErrorDescriptions() {
        let errors: [EAIdentityError] = [
            .invalidURL,
            .noData,
            .decodingError("Test"),
            .networkError("Test"),
            .httpError(statusCode: 401, message: "Unauthorized"),
            .xmlParsingError("Test"),
            .missingField("testField"),
            .invalidToken,
            .rateLimited,
            .authenticationRequired
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
        }
    }
    
    func testHTTPErrorRecoverySuggestions() {
        let error401 = EAIdentityError.httpError(statusCode: 401, message: nil)
        XCTAssertNotNil(error401.recoverySuggestion)
        
        let error429 = EAIdentityError.httpError(statusCode: 429, message: nil)
        XCTAssertNotNil(error429.recoverySuggestion)
        
        let error500 = EAIdentityError.httpError(statusCode: 500, message: nil)
        XCTAssertNotNil(error500.recoverySuggestion)
    }
    
    // MARK: - API Initialization Tests
    
    func testAPIInitialization() {
        let api = EAIdentityAPI(accessToken: "test_token")
        XCTAssertNotNil(api)
    }
    
    func testAPIInitializationWithCustomSession() {
        let config = URLSessionConfiguration.ephemeral
        let api = EAIdentityAPI(accessToken: "test_token", configuration: config)
        XCTAssertNotNil(api)
    }
    
    // MARK: - Token Storage Tests
    
    func testTokenStorageInitialization() {
        let storage = EATokenStorage()
        XCTAssertNotNil(storage)
    }
    
    func testTokenStorageCustomService() {
        let storage = EATokenStorage(service: "com.test.service")
        XCTAssertNotNil(storage)
    }
    
    // MARK: - Endpoints Tests
    
    func testEndpointURLs() {
        XCTAssertEqual(
            EAIdentityAPI.Endpoints.identityPids,
            "https://gateway.ea.com/proxy/identity/pids/me"
        )
        
        XCTAssertEqual(
            EAIdentityAPI.Endpoints.personas(pidId: "123"),
            "https://gateway.ea.com/proxy/identity/pids/123/personas"
        )
        
        XCTAssertTrue(
            EAIdentityAPI.Endpoints.achievements(personaId: "123").contains("123")
        )
        
        XCTAssertEqual(
            EAIdentityAPI.Endpoints.subscriptions(pidId: "123"),
            "https://gateway.ea.com/proxy/subscription/pids/123/subscriptionsv2/groups/EA%20Play"
        )
        
        XCTAssertEqual(
            EAIdentityAPI.Endpoints.entitlements(pidId: "123"),
            "https://gateway.ea.com/proxy/identity/pids/123/entitlements"
        )
    }
}

// MARK: - Mock Tests

final class MockURLProtocol: URLProtocol {
    static var mockResponses: [URL: (Data?, HTTPURLResponse?, Error?)] = [:]
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let url = request.url,
              let (data, response, error) = MockURLProtocol.mockResponses[url] else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            if let response = response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    override func stopLoading() {}
}

final class EAIdentityAPIIntegrationTests: XCTestCase {
    
    var api: EAIdentityAPI!
    var session: URLSession!
    
    override func setUp() {
        super.setUp()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        
        api = EAIdentityAPI(accessToken: "test_token", session: session)
    }
    
    override func tearDown() {
        MockURLProtocol.mockResponses.removeAll()
        super.tearDown()
    }
    
    func testGetPIDInfoSuccess() async throws {
        let url = URL(string: EAIdentityAPI.Endpoints.identityPids)!
        let responseJSON = """
            {
                "pid": {
                    "pidId": "1234567890",
                    "status": "ACTIVE",
                    "country": "US"
                }
            }
            """
        
        MockURLProtocol.mockResponses[url] = (
            responseJSON.data(using: .utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil),
            nil
        )
        
        let pidInfo = try await api.getPIDInfo()
        
        XCTAssertEqual(pidInfo.pidId, "1234567890")
        XCTAssertEqual(pidInfo.status, "ACTIVE")
        XCTAssertEqual(pidInfo.country, "US")
    }
    
    func testGetPIDInfoUnauthorized() async {
        let url = URL(string: EAIdentityAPI.Endpoints.identityPids)!
        
        MockURLProtocol.mockResponses[url] = (
            nil,
            HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil),
            nil
        )
        
        do {
            _ = try await api.getPIDInfo()
            XCTFail("Expected error to be thrown")
        } catch let error as EAIdentityError {
            if case .invalidToken = error {
                // Expected
            } else {
                XCTFail("Expected invalidToken error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testGetPersonaInfoSuccess() async throws {
        let pidId = "1234567890"
        let url = URL(string: EAIdentityAPI.Endpoints.personas(pidId: pidId))!
        
        let responseJSON = """
            {
                "personas": {
                    "persona": [
                        {
                            "personaId": 9876543210,
                            "displayName": "TestPlayer",
                            "name": "TestPlayer",
                            "namespaceName": "cem_ea_id"
                        }
                    ]
                }
            }
            """
        
        MockURLProtocol.mockResponses[url] = (
            responseJSON.data(using: .utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil),
            nil
        )
        
        let personaInfo = try await api.getPersonaInfo(pidId: pidId)
        
        XCTAssertEqual(personaInfo.userId, pidId)
        XCTAssertEqual(personaInfo.personaId, "9876543210")
        XCTAssertEqual(personaInfo.eaId, "TestPlayer")
    }
}

