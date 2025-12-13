import Foundation
import FirebaseAuth
import FirebaseFirestore

struct AvailabilityService {
    private let db = Firestore.firestore()

    func ensureUserProfile(for phone: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let ref = db.collection("users").document(phone)
        ref.getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if snapshot?.exists == true {
                    completion(.success(false))
                } else {
                    completion(.success(true))
                }
            }
        }
    }

    func saveUserProfile(phone: String, name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection("users").document(phone).setData([
            "name": name,
            "status": true,
            "lastChanged": FieldValue.serverTimestamp()
        ], merge: true) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func updateStatus(phone: String, available: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection("users").document(phone).setData([
            "status": available,
            "lastChanged": FieldValue.serverTimestamp()
        ], merge: true) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func loadStatus(phone: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        db.collection("users").document(phone).getDocument { snap, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let status = snap?.data()?["status"] as? Bool {
                    completion(.success(status))
                } else {
                    completion(.success(false))
                }
            }
        }
    }

    func listenToOwnStatus(phone: String, onChange: @escaping (Result<Bool, Error>) -> Void) -> ListenerRegistration {
        db.collection("users").document(phone).addSnapshotListener { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    onChange(.failure(error))
                    return
                }

                if let status = snapshot?.data()?["status"] as? Bool {
                    onChange(.success(status))
                }
            }
        }
    }

    func listenToFriends(
        phone: String,
        onStatusListenersChange: @escaping ([ListenerRegistration]) -> Void,
        onChange: @escaping (Result<[Friend], Error>) -> Void
    ) -> ListenerRegistration {
        db.collection("users").document(phone).collection("friends")
            .addSnapshotListener { snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        onChange(.failure(error))
                        return
                    }

                    onStatusListenersChange([])

                    guard let docs = snapshot?.documents, !docs.isEmpty else {
                        onChange(.success([]))
                        return
                    }

                    let phones = docs.map { $0.documentID }
                    var latestFriends: [String: Friend] = [:]
                    var statusListeners: [ListenerRegistration] = []

                    for chunk in phones.chunked(by: 10) {
                        let listener = db.collection("users")
                            .whereField(FieldPath.documentID(), in: chunk)
                            .addSnapshotListener { snap, statusError in
                                DispatchQueue.main.async {
                                    if let statusError = statusError {
                                        onChange(.failure(statusError))
                                        return
                                    }

                                    snap?.documents.forEach { doc in
                                        let data = doc.data()
                                        let name = data["name"] as? String ?? "Friend"
                                        let status = data["status"] as? Bool ?? false
                                        let lastChanged = (data["lastChanged"] as? Timestamp)?.dateValue()

                                        latestFriends[doc.documentID] = Friend(
                                            phone: doc.documentID,
                                            name: name,
                                            status: status,
                                            lastChanged: lastChanged
                                        )
                                    }

                                    latestFriends = latestFriends.filter { phones.contains($0.key) }
                                    let sorted = latestFriends.values.sorted(by: Friend.sortByFreshness)
                                    onChange(.success(sorted))
                                }
                            }

                        statusListeners.append(listener)
                    }

                    onStatusListenersChange(statusListeners)
                }
            }
    }

    func listenToIncomingRequests(
        phone: String,
        onChange: @escaping (Result<[FriendRequest], Error>) -> Void
    ) -> ListenerRegistration {
        db.collection("users").document(phone).collection("friendRequests")
            .addSnapshotListener { snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        onChange(.failure(error))
                        return
                    }

                    let requests: [FriendRequest] = snapshot?.documents.compactMap { doc in
                        let data = doc.data()
                        guard let status = data["status"] as? String, status == "pending" else { return nil }
                        let name = data["name"] as? String ?? "Unknown"
                        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                        return FriendRequest(phone: doc.documentID, name: name, createdAt: createdAt)
                    } ?? []

                    onChange(.success(requests.sorted(by: FriendRequest.sortByDate)))
                }
            }
    }

    func listenToOutgoingRequests(
        phone: String,
        onChange: @escaping (Result<[FriendRequest], Error>) -> Void
    ) -> ListenerRegistration {
        db.collection("users").document(phone).collection("sentRequests")
            .addSnapshotListener { snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        onChange(.failure(error))
                        return
                    }

                    let requests: [FriendRequest] = snapshot?.documents.compactMap { doc in
                        let data = doc.data()
                        guard let status = data["status"] as? String, status == "pending" else { return nil }
                        let name = data["name"] as? String ?? "Pending friend"
                        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                        return FriendRequest(phone: doc.documentID, name: name, createdAt: createdAt)
                    } ?? []

                    onChange(.success(requests.sorted(by: FriendRequest.sortByDate)))
                }
            }
    }

    func sendFriendRequest(from myPhone: String, to friendPhone: String, completion: @escaping (Result<Void, Error>) -> Void) {
        fetchName(for: myPhone) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let myName):
                let incomingRef = db.collection("users").document(friendPhone)
                    .collection("friendRequests").document(myPhone)
                let outgoingRef = db.collection("users").document(myPhone)
                    .collection("sentRequests").document(friendPhone)

                incomingRef.getDocument { snap, error in
                    if let error = error {
                        DispatchQueue.main.async { completion(.failure(error)) }
                        return
                    }

                    if snap?.exists == true {
                        DispatchQueue.main.async { completion(.success(())) }
                        return
                    }

                    let batch = db.batch()
                    batch.setData([
                        "status": "pending",
                        "name": myName,
                        "createdAt": FieldValue.serverTimestamp()
                    ], forDocument: incomingRef)
                    batch.setData([
                        "status": "pending",
                        "name": "Awaiting approval",
                        "createdAt": FieldValue.serverTimestamp()
                    ], forDocument: outgoingRef)

                    batch.commit { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                completion(.success(()))
                            }
                        }
                    }
                }
            }
        }
    }

    func accept(friendRequest phone: String, for myPhone: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let myFriendsRef = db.collection("users").document(myPhone).collection("friends").document(phone)
        let theirFriendsRef = db.collection("users").document(phone).collection("friends").document(myPhone)
        let incomingRef = db.collection("users").document(myPhone).collection("friendRequests").document(phone)
        let outgoingRef = db.collection("users").document(phone).collection("sentRequests").document(myPhone)

        let batch = db.batch()
        batch.setData(["addedAt": FieldValue.serverTimestamp()], forDocument: myFriendsRef)
        batch.setData(["addedAt": FieldValue.serverTimestamp()], forDocument: theirFriendsRef)
        batch.deleteDocument(incomingRef)
        batch.deleteDocument(outgoingRef)

        batch.commit { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func decline(friendRequest phone: String, for myPhone: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let incomingRef = db.collection("users").document(myPhone).collection("friendRequests").document(phone)
        let outgoingRef = db.collection("users").document(phone).collection("sentRequests").document(myPhone)

        let batch = db.batch()
        batch.deleteDocument(incomingRef)
        batch.deleteDocument(outgoingRef)

        batch.commit { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func removeFriend(myPhone: String, friendPhone: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let myRef = db.collection("users").document(myPhone).collection("friends").document(friendPhone)
        let theirRef = db.collection("users").document(friendPhone).collection("friends").document(myPhone)

        let batch = db.batch()
        batch.deleteDocument(myRef)
        batch.deleteDocument(theirRef)

        batch.commit { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func blockFriend(myPhone: String, friendPhone: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let blockRef = db.collection("users").document(myPhone).collection("blocked").document(friendPhone)
        let incomingRef = db.collection("users").document(myPhone).collection("friendRequests").document(friendPhone)
        let outgoingRef = db.collection("users").document(friendPhone).collection("sentRequests").document(myPhone)
        let myFriendRef = db.collection("users").document(myPhone).collection("friends").document(friendPhone)
        let theirFriendRef = db.collection("users").document(friendPhone).collection("friends").document(myPhone)

        let batch = db.batch()
        batch.setData([
            "blockedAt": FieldValue.serverTimestamp(),
            "by": myPhone
        ], forDocument: blockRef)
        batch.deleteDocument(incomingRef)
        batch.deleteDocument(outgoingRef)
        batch.deleteDocument(myFriendRef)
        batch.deleteDocument(theirFriendRef)

        batch.commit { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func fetchName(for phone: String, completion: @escaping (Result<String, Error>) -> Void) {
        db.collection("users").document(phone).getDocument { doc, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let name = doc?.data()?["name"] as? String, !name.isEmpty {
                    completion(.success(name))
                } else {
                    completion(.success("Friend"))
                }
            }
        }
    }

    func deleteAccount(phone: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let userRef = db.collection("users").document(phone)

        userRef.collection("friends").getDocuments { friendsSnapshot, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let batch = db.batch()
            friendsSnapshot?.documents.forEach { doc in
                let friendPhone = doc.documentID
                let myRef = userRef.collection("friends").document(friendPhone)
                let theirRef = db.collection("users").document(friendPhone).collection("friends").document(phone)
                batch.deleteDocument(myRef)
                batch.deleteDocument(theirRef)
            }

            batch.deleteDocument(userRef)

            userRef.collection("friendRequests").getDocuments { incomingSnapshot, _ in
                incomingSnapshot?.documents.forEach { batch.deleteDocument($0.reference) }

                userRef.collection("sentRequests").getDocuments { outgoingSnapshot, _ in
                    outgoingSnapshot?.documents.forEach { batch.deleteDocument($0.reference) }

                    userRef.collection("blocked").getDocuments { blockedSnapshot, _ in
                        blockedSnapshot?.documents.forEach { batch.deleteDocument($0.reference) }

                        batch.commit { error in
                            DispatchQueue.main.async {
                                if let error = error {
                                    completion(.failure(error))
                                } else {
                                    completion(.success(()))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

enum PhoneNumberFormatter {
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0.isWholeNumber }
        guard digits.count >= 10 else { return nil }
        return "+" + digits
    }
}

extension Friend {
    static func sortByFreshness(_ lhs: Friend, _ rhs: Friend) -> Bool {
        switch (lhs.lastChanged, rhs.lastChanged) {
        case let (l?, r?):
            return l > r
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            return lhs.name < rhs.name
        }
    }
}

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        var result: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            result.append(Array(self[index..<end]))
            index += size
        }
        return result
    }
}
