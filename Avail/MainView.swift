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
    @State private var errorMessage: String?
    @State private var friendsListener: ListenerRegistration?
    @State private var statusListener: ListenerRegistration?

    private let service = AvailabilityService()
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

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

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
            .onDisappear {
                friendsListener?.remove()
                statusListener?.remove()
            }
        }
    }

    private func updateMyStatus(_ available: Bool) {
        service.updateStatus(phone: myPhone, available: available) { result in
            if case let .failure(error) = result {
                errorMessage = "Could not update status: \(error.localizedDescription)"
            }
        }
    }

    private func loadMyStatus() {
        service.loadStatus(phone: myPhone) { result in
            switch result {
            case .success(let status):
                isAvailable = status
            case .failure(let error):
                errorMessage = "Could not load your status: \(error.localizedDescription)"
            }
        }
    }

    private func listenToFriends() {
        friendsListener?.remove()
        statusListener?.remove()

        friendsListener = service.listenToFriends(
            phone: myPhone,
            statusListener: statusListener,
            onStatusListenerChange: { statusListener = $0 },
            onChange: { result in
                switch result {
                case .success(let friendsList):
                    friends = friendsList
                case .failure(let error):
                    errorMessage = "Could not load friends: \(error.localizedDescription)"
                }
            }
        )
    }
}
