//
//  Copyright © 2018 Essential Developer. All rights reserved.
//

import Foundation

public final class RemoteFeedLoader: FeedLoader {
    private let url: URL
    private let client: HTTPClient
    
    public enum Error: Swift.Error {
        case connectivity
        case invalidData
    }
    
    public init(url: URL, client: HTTPClient) {
        self.url = url
        self.client = client
    }
    
    public func load(completion: @escaping (FeedLoader.Result) -> Void) {
        client.get(from: url) { result in
            switch result {
            case .failure:
                completion(.failure(Error.connectivity))
                
            case let .success((data, response)):
                guard response.statusCode == 200,
                    let root = try? JSONDecoder().decode(Root.self, from: data) else {
                        return completion(.failure(Error.invalidData))
                }
                completion(.success(root.feed))
            }
        }
    }
}

private struct Root: Decodable {
    private let items: [Item]
    
    var feed: [FeedImage] {
        return items.map {
            return FeedImage(
                id: $0.id,
                description: $0.description,
                location: $0.location,
                url: $0.imageURL)
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
