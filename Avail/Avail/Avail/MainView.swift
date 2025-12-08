import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFirestoreSwift

struct Friend: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var status: Bool  // true = available (green)
    var phone: String
}

struct MainView: View {
    @State private var isAvailable = false
    @State private var friends: [Friend] = []
    @State private var showAddFriend = false
    private let db = Firestore.firestore()
    private var myPhone: String { Auth.auth().currentUser!.phoneNumber! }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Toggle("", isOn: $isAvailable)
                    .labelsHidden()
                    .scaleEffect(4)
                    .tint(isAvailable ? .green : .red)
                    .padding()
                
                Text(isAvailable ? "Available" : "Unavailable")
                    .font(.title)
                    .bold()
                
                List(friends) { friend in
                    HStack {
                        Circle()
                            .fill(friend.status ? .green : .red)
                            .frame(width: 20, height: 20)
                        Text(friend.name)
                        Spacer()
                        Text(friend.status ? "Available" : "Busy")
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Avail")
            .toolbar {
                Button(action: { showAddFriend = true }) {
                    Image(systemName: "person.badge.plus")
                }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
            }
            .onChange(of: isAvailable) { updateMyStatus($0) }
            .onAppear {
                loadMyStatus()
                listenToFriends()
            }
        }
    }
    
    func updateMyStatus(_ available: Bool) {
        let ref = db.collection("users").document(myPhone)
        ref.setData(["status": available, "lastChanged": FieldValue.serverTimestamp()], merge: true)
    }
    
    func loadMyStatus() {
        db.collection("users").document(myPhone).getDocument { snap, _ in
            if let data = snap?.data(), let status = data["status"] as? Bool {
                isAvailable = status
            }
        }
    }
    
    func listenToFriends() {
        db.collection("users").document(myPhone).collection("friends")
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let phones = docs.map { $0.documentID }
                db.collection("users").whereField(FieldPath.documentID(), in: phones)
                    .addSnapshotListener { snap, _ in
                        friends = snap?.documents.compactMap { try? $0.data(as: Friend.self) } ?? []
                    }
            }
    }
}
