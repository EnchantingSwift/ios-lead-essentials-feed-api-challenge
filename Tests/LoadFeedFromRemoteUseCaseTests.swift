//
//  Copyright © 2020 Essential Developer. All rights reserved.
//

import XCTest
import FeedAPIChallenge

class RemoteFeedLoader {
    private let url: URL
    private let client: HTTPClient
    
    enum Error: Swift.Error {
        case connectivity
        case invalidData
    }
    
    typealias Result = FeedLoader.Result
    
    init(url: URL, client: HTTPClient) {
        self.url = url
        self.client = client
    }
    
    func load(completion: @escaping (Result) -> Void) {
        client.get(from: url) { result in
            switch result {
            case .failure:
                completion(.failure(Error.connectivity))
            case let .success((data, response)):
                guard response.statusCode == 200,
                    let root = try? JSONDecoder().decode(Root.self, from: data) else {
                        return completion(.failure(Error.invalidData))
                }
                return completion(.success(root.feed))
            }
        }
    }
}

private struct Root: Decodable {
    let items: [Item]
    
    var feed: [FeedImage] {
        return items.map {
            FeedImage(id: $0.id,
                      description: $0.description,
                      location: $0.location,
                      url: $0.imageURL
            )
        }
    }
}

private struct Item: Decodable {
    let id: UUID
    let description: String?
    let location: String?
    let imageURL: URL
    
    enum CodingKeys: String, CodingKey {
        case id = "image_id"
        case description = "image_desc"
        case location = "image_loc"
        case imageURL = "image_url"
    }
}



class HTTPClient {
    typealias Result = (Swift.Result<(Data, HTTPURLResponse), Error>)
    var messages = [(url: URL, completion: (Result) -> Void)]()
    var requestedURLs: [URL] {
        return messages.map { $0.url }
    }
    
    func get(from url: URL, completion: @escaping (Result) -> Void) {
        messages.append((url, completion))
    }
    
    func complete(with error: Error, at index: Int = 0) {
        messages[index].completion(.failure(error))
    }
    
    func complete(withStatusCode code: Int, data: Data, at index: Int = 0) {
        let response = HTTPURLResponse(url: requestedURLs[index],
                                       statusCode: code,
                                       httpVersion: nil,
                                       headerFields: nil
            )!
        messages[index].completion(.success((data, response)))
    }
}

class LoadFeedFromRemoteUseCaseTests: XCTestCase {
    
    //  ***********************
    //
    //  Follow the TDD process:
    //
    //  1. Uncomment and run one test at a time (run tests with CMD+U).
    //  2. Do the minimum to make the test pass and commit.
    //  3. Refactor if needed and commit again.
    //
    //  Repeat this process until all tests are passing.
    //
    //  ***********************
    
    
    func test_load_doesNotRequestDataUponCreation() {
        let (_, client) = makeSUT()
        
        XCTAssertTrue(client.requestedURLs.isEmpty)
    }
    
    func test_loadTwice_requestDataFromURLTwice() {
        let url = URL(string: "another-url.com")!
        let (sut, client) = makeSUT(url: url)
        
        sut.load { _ in }
        sut.load { _ in }
        
        XCTAssertEqual(client.requestedURLs, [url, url])
    }
    
    func test_load_deliversConnectivityErrorOnClientError() {
        let (sut, client) = makeSUT()
        
        expect(sut, toCompleteWith: .failure(RemoteFeedLoader.Error.connectivity), when: {
            let clientError = NSError(domain: "client error", code: 0)
            client.complete(with: clientError)
        })
    }
    
    func test_load_deliversInvalidDataOnNon200HTTPResponse() {
        let (sut, client) = makeSUT()
        
        let samples = [199, 201, 300, 400, 500]
        samples.enumerated().forEach { index, code in
            expect(sut, toCompleteWith: .failure(RemoteFeedLoader.Error.invalidData), when: {
                client.complete(withStatusCode: code, data: makeItemsJSON([]), at: index)
            })
        }
    }
    
    func test_load_deliversInvalidDataOn200HTTPResponseWithInvalidData() {
        let (sut, client) = makeSUT()
        
        expect(sut, toCompleteWith: .failure(RemoteFeedLoader.Error.invalidData), when: {
            let invalidData = Data("invalid data".utf8)
            client.complete(withStatusCode: 200, data: invalidData)
        })
    }
    
    func test_load_deliversEmptyItemsOn200HTTPResponseWithEmptyJSONList() {
        let (sut, client) = makeSUT()
        
        expect(sut, toCompleteWith: .success([]), when: {
            client.complete(withStatusCode: 200, data: makeItemsJSON([]))
        })
    }
    
    func test_load_deliversItemsOn200HTTPResponseWithJSONItemsList() {
        let (sut, client) = makeSUT()
        let item1 = FeedImage(id: UUID(),
                              description: "a description",
                              location: "a location",
                              url: URL(string: "any-url.com")!
        )
        
        let item1JSON = [
            "image_id": item1.id.uuidString,
            "image_desc": item1.description!,
            "image_loc": item1.location!,
            "image_url": item1.url.absoluteString,
        ]
        
        let item2 = FeedImage(id: UUID(),
                              description: nil,
                              location: nil,
                              url: URL(string: "any-url.com")!
        )
        
        let item2JSON = [
            "image_id": item2.id.uuidString,
            "image_url": item2.url.absoluteString,
        ]
        
        expect(sut, toCompleteWith: .success([item1, item2]), when: {
            client.complete(withStatusCode: 200, data: makeItemsJSON([item1JSON, item2JSON]))
        })
    }
    
    // MARK: - Helpers
    
    private func makeSUT(url: URL = URL(string: "any-url.com")!) -> (sut: RemoteFeedLoader, client: HTTPClient) {
        let client = HTTPClient()
        let sut = RemoteFeedLoader(url: url, client: client)
        return (sut, client)
    }
    
    private func makeItemsJSON(_ items: [[String: Any]]) -> Data {
        return try! JSONSerialization.data(withJSONObject: ["items": items])
    }
    
    private func expect(_ sut: RemoteFeedLoader, toCompleteWith expectedResult: RemoteFeedLoader.Result, when action: () -> Void, file: StaticString = #file, line: UInt = #line) {
        let exp = expectation(description: "Wait for load completion")
        
        sut.load { receivedResult in
            switch (receivedResult, expectedResult) {
            case let (.failure(receivedError as RemoteFeedLoader.Error), .failure(expectedError as RemoteFeedLoader.Error)):
                XCTAssertEqual(receivedError, expectedError, file: file, line: line)
                
            case let (.success(receivedItems), .success(expectedItems)):
                XCTAssertEqual(receivedItems, expectedItems, file: file, line: line)
            default:
                XCTFail("Expected \(expectedResult) result, got \(receivedResult) result instead", file: file, line: line)
            }
            
            exp.fulfill()
        }
        
        action()
        
        wait(for: [exp], timeout: 0.1)
    }
}
