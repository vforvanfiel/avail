import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFirestoreSwift

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

    func listenToOwnStatus(phone: String, onChange: @escaping (Result<Bool, Error>) -> Void) -> ListenerRegistration {
        db.collection("users").document(phone).addSnapshotListener { snapshot, error in
            if let error = error {
                onChange(.failure(error))
                return
            }

            if let status = snapshot?.data()?["status"] as? Bool {
                onChange(.success(status))
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

    func addFriend(myPhone: String, friendPhone: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let myRef = db.collection("users").document(myPhone).collection("friends").document(friendPhone)
        let theirRef = db.collection("users").document(friendPhone).collection("friends").document(myPhone)

        let batch = db.batch()
        batch.setData(["addedAt": FieldValue.serverTimestamp()], forDocument: myRef)
        batch.setData(["addedAt": FieldValue.serverTimestamp()], forDocument: theirRef)

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
