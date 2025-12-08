import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct Friend: Identifiable {
    var id: String { phone }
    var name: String
    var status: Bool  // true = available (green)
    var phone: String
    var lastChanged: Date?
}

struct MainView: View {
    @State private var isAvailable = false
    @State private var friends: [Friend] = []
    @State private var showAddFriend = false
    @State private var errorMessage: String?
    @State private var friendsListener: ListenerRegistration?
    @State private var statusListeners: [ListenerRegistration] = []
    @State private var myStatusListener: ListenerRegistration?
    @State private var isSyncingStatus = false
    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    private let service = AvailabilityService()
    private var myPhone: String { Auth.auth().currentUser!.phoneNumber! }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.25), .purple.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 14) {
                            Text("Your status")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Toggle("", isOn: $isAvailable)
                                .labelsHidden()
                                .scaleEffect(3.2)
                                .tint(isAvailable ? .green : .red)
                                .padding(.vertical, 6)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                            Text(isAvailable ? "You're available" : "You're busy")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("Friends see changes instantly")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThickMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Friends")
                                    .font(.headline)
                                Spacer()
                                Button(action: { showAddFriend = true }) {
                                    Label("Add", systemImage: "person.badge.plus")
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.leading)
                            }

                            if friends.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "person.2.circle")
                                        .font(.system(size: 42))
                                        .foregroundColor(.secondary)
                                    Text("No friends yet")
                                        .font(.headline)
                                    Text("Send a request to see live status updates")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.ultraThickMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            } else {
                                ForEach(friends) { friend in
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(friend.status ? .green : .red)
                                            .frame(width: 18, height: 18)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(friend.name)
                                                .font(.headline)
                                            Text(friend.status ? "Available" : "Busy")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            if let lastChanged = friend.lastChanged {
                                                Text(lastChanged, style: .time)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                            .opacity(0.4)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.ultraThickMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                                }
                            }
                        }
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)
                    }
                    .padding()
                }
            }
            .navigationTitle("Avail")
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
            }
            .onChange(of: isAvailable) { newValue in
                if isSyncingStatus {
                    isSyncingStatus = false
                    return
                }
                haptics.impactOccurred()
                updateMyStatus(newValue)
            }
            .onAppear {
                startListeners()
            }
            .onDisappear {
                friendsListener?.remove()
                statusListeners.forEach { $0.remove() }
                myStatusListener?.remove()
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
                isSyncingStatus = true
                isAvailable = status
            case .failure(let error):
                errorMessage = "Could not load your status: \(error.localizedDescription)"
            }
        }
    }

    private func startListeners() {
        loadMyStatus()

        myStatusListener?.remove()
        myStatusListener = service.listenToOwnStatus(phone: myPhone) { result in
            switch result {
            case .success(let status):
                isSyncingStatus = true
                isAvailable = status
            case .failure(let error):
                errorMessage = "Could not refresh your status: \(error.localizedDescription)"
            }
        }

        listenToFriends()
    }

    private func listenToFriends() {
        friendsListener?.remove()
        statusListeners.forEach { $0.remove() }

        friendsListener = service.listenToFriends(
            phone: myPhone,
            onStatusListenersChange: { newListeners in
                statusListeners.forEach { $0.remove() }
                statusListeners = newListeners
            },
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
