import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit
import UserNotifications

struct Friend: Identifiable {
    var id: String { phone }
    var name: String
    var status: Bool  // true = available (green)
    var phone: String
    var lastChanged: Date?
}

struct FriendRequest: Identifiable {
    var id: String { phone }
    var phone: String
    var name: String
    var createdAt: Date?

    static func sortByDate(_ lhs: FriendRequest, _ rhs: FriendRequest) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
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

struct MainView: View {
    @State private var isAvailable = false
    @State private var friends: [Friend] = []
    @State private var incomingRequests: [FriendRequest] = []
    @State private var outgoingRequests: [FriendRequest] = []
    @State private var showAddFriend = false
    @State private var errorMessage: String?
    @State private var friendsListener: ListenerRegistration?
    @State private var incomingListener: ListenerRegistration?
    @State private var outgoingListener: ListenerRegistration?
    @State private var statusListeners: [ListenerRegistration] = []
    @State private var myStatusListener: ListenerRegistration?
    @State private var isSyncingStatus = false
    @State private var isDeletingAccount = false
    @State private var showDeleteConfirmation = false
    @State private var notificationStatus: UNAuthorizationStatus?
    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    private let service = AvailabilityService()
    private var myPhone: String { Auth.auth().currentUser?.phoneNumber ?? "" }

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
                                        Menu {
                                            Button(role: .destructive) {
                                                removeFriend(friend.phone)
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }

                                            Button(role: .destructive) {
                                                blockFriend(friend.phone)
                                            } label: {
                                                Label("Block", systemImage: "hand.raised")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .foregroundColor(.secondary)
                                        }
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

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Requests")
                                .font(.headline)

                            if incomingRequests.isEmpty && outgoingRequests.isEmpty {
                                Text("No pending requests")
                                    .foregroundColor(.secondary)
                            } else {
                                if !incomingRequests.isEmpty {
                                    Text("Incoming")
                                        .font(.subheadline.weight(.semibold))
                                    ForEach(incomingRequests) { request in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(request.name)
                                                    .font(.headline)
                                                Spacer()
                                                if let createdAt = request.createdAt {
                                                    Text(createdAt, style: .time)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Text(request.phone)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)

                                            HStack {
                                                Button("Decline", role: .destructive) {
                                                    declineRequest(request)
                                                }
                                                .buttonStyle(.bordered)

                                                Button("Accept") {
                                                    acceptRequest(request)
                                                }
                                                .buttonStyle(.borderedProminent)
                                            }
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.ultraThickMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                }

                                if !outgoingRequests.isEmpty {
                                    Text("Sent")
                                        .font(.subheadline.weight(.semibold))
                                    ForEach(outgoingRequests) { request in
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(request.phone)
                                                    .font(.headline)
                                                Text("Awaiting approval")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            if let createdAt = request.createdAt {
                                                Text(createdAt, style: .time)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.ultraThickMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Account & Notifications")
                                .font(.headline)

                            Button {
                                requestNotificationPermission()
                            } label: {
                                Label(permissionLabelText, systemImage: "bell")
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                doSignOut()
                            } label: {
                                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete account", systemImage: "trash")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(isDeletingAccount)
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
                refreshNotificationStatus()
            }
            .onDisappear {
                friendsListener?.remove()
                incomingListener?.remove()
                outgoingListener?.remove()
                statusListeners.forEach { $0.remove() }
                myStatusListener?.remove()
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive, action: deleteAccount)
                Button("Cancel", role: .cancel) { showDeleteConfirmation = false }
            }
        }
    }

    private func updateMyStatus(_ available: Bool) {
        guard !myPhone.isEmpty else {
            errorMessage = "Missing phone number. Please sign in again."
            return
        }
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
                if status != isAvailable {
                    isSyncingStatus = true
                    isAvailable = status
                    DispatchQueue.main.async {
                        self.isSyncingStatus = false
                    }
                } else {
                    isSyncingStatus = false
                }
            case .failure(let error):
                errorMessage = "Could not load your status: \(error.localizedDescription)"
            }
        }
    }

    private func startListeners() {
        guard !myPhone.isEmpty else {
            errorMessage = "Missing phone number. Please sign in again."
            return
        }
        loadMyStatus()

        myStatusListener?.remove()
        myStatusListener = service.listenToOwnStatus(phone: myPhone) { result in
            switch result {
            case .success(let status):
                if status != isAvailable {
                    isSyncingStatus = true
                    isAvailable = status
                    DispatchQueue.main.async {
                        self.isSyncingStatus = false
                    }
                } else {
                    isSyncingStatus = false
                }
            case .failure(let error):
                errorMessage = "Could not refresh your status: \(error.localizedDescription)"
            }
        }

        listenToFriends()
        listenToRequests()
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

    private func listenToRequests() {
        incomingListener?.remove()
        outgoingListener?.remove()

        incomingListener = service.listenToIncomingRequests(phone: myPhone) { result in
            switch result {
            case .success(let list):
                incomingRequests = list
            case .failure(let error):
                errorMessage = "Could not load requests: \(error.localizedDescription)"
            }
        }

        outgoingListener = service.listenToOutgoingRequests(phone: myPhone) { result in
            switch result {
            case .success(let list):
                outgoingRequests = list
            case .failure(let error):
                errorMessage = "Could not load outgoing requests: \(error.localizedDescription)"
            }
        }
    }

    private func acceptRequest(_ request: FriendRequest) {
        service.accept(friendRequest: request.phone, for: myPhone) { result in
            if case let .failure(error) = result {
                errorMessage = "Could not accept: \(error.localizedDescription)"
            }
        }
    }

    private func declineRequest(_ request: FriendRequest) {
        service.decline(friendRequest: request.phone, for: myPhone) { result in
            if case let .failure(error) = result {
                errorMessage = "Could not decline: \(error.localizedDescription)"
            }
        }
    }

    private func removeFriend(_ phone: String) {
        service.removeFriend(myPhone: myPhone, friendPhone: phone) { result in
            if case let .failure(error) = result {
                errorMessage = "Could not remove friend: \(error.localizedDescription)"
            }
        }
    }

    private func blockFriend(_ phone: String) {
        service.blockFriend(myPhone: myPhone, friendPhone: phone) { result in
            if case let .failure(error) = result {
                errorMessage = "Could not block friend: \(error.localizedDescription)"
            }
        }
    }

    private func doSignOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
        }
    }

    private func deleteAccount() {
        guard !myPhone.isEmpty else {
            errorMessage = "Missing phone number. Please sign in again."
            return
        }
        isDeletingAccount = true
        service.deleteAccount(phone: myPhone) { result in
            switch result {
            case .failure(let error):
                errorMessage = "Could not delete account: \(error.localizedDescription)"
                isDeletingAccount = false
            case .success:
                Auth.auth().currentUser?.delete { authError in
                    DispatchQueue.main.async {
                        if let authError = authError {
                            errorMessage = "Deleted data but could not delete auth record: \(authError.localizedDescription)"
                        }
                        isDeletingAccount = false
                        doSignOut()
                    }
                }
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                notificationStatus = granted ? .authorized : .denied
            }
        }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationStatus = settings.authorizationStatus
            }
        }
    }

    private var permissionLabelText: String {
        switch notificationStatus {
        case .authorized:
            return "Notifications enabled"
        case .denied:
            return "Enable notifications"
        case .notDetermined:
            return "Allow notifications"
        default:
            return "Notification settings"
        }
    }
}
