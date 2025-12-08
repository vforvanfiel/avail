import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFirestoreSwift

struct AvailabilityService {
    private let db = Firestore.firestore()

    func ensureUserProfile(for phone: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let ref = db.collection("users").document(phone)
        ref.getDocument { snapshot, error in
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

    func saveUserProfile(phone: String, name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection("users").document(phone).setData([
            "name": name,
            "status": true,
            "lastChanged": FieldValue.serverTimestamp()
        ], merge: true) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func updateStatus(phone: String, available: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        db.collection("users").document(phone).setData([
            "status": available,
            "lastChanged": FieldValue.serverTimestamp()
        ], merge: true) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func loadStatus(phone: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        db.collection("users").document(phone).getDocument { snap, error in
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

    func listenToFriends(
        phone: String,
        statusListener: ListenerRegistration?,
        onStatusListenerChange: @escaping (ListenerRegistration?) -> Void,
        onChange: @escaping (Result<[Friend], Error>) -> Void
    ) -> ListenerRegistration {
        db.collection("users").document(phone).collection("friends")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    onChange(.failure(error))
                    return
                }

                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    statusListener?.remove()
                    onStatusListenerChange(nil)
                    onChange(.success([]))
                    return
                }

                let phones = docs.map { $0.documentID }
                statusListener?.remove()
                let listener = db.collection("users").whereField(FieldPath.documentID(), in: phones)
                    .addSnapshotListener { snap, statusError in
                        if let statusError = statusError {
                            onChange(.failure(statusError))
                            return
                        }

                        let friends = snap?.documents.compactMap { try? $0.data(as: Friend.self) } ?? []
                        onChange(.success(friends))
                    }

                onStatusListenerChange(listener)
            }
    }

    func addFriend(myPhone: String, friendPhone: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let myRef = db.collection("users").document(myPhone).collection("friends").document(friendPhone)
        let theirRef = db.collection("users").document(friendPhone).collection("friends").document(myPhone)

        let batch = db.batch()
        batch.setData(["addedAt": FieldValue.serverTimestamp()], forDocument: myRef)
        batch.setData(["addedAt": FieldValue.serverTimestamp()], forDocument: theirRef)

        batch.commit { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
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
