import SwiftUI
import FirebaseAuth
import UIKit

struct AddFriendView: View {
    @State private var phone = ""
    @State private var message = ""
    @State private var isSending = false
    @Environment(\.dismiss) var dismiss
    private let service = AvailabilityService()
    private let notifier = UINotificationFeedbackGenerator()

    private var myPhone: String { Auth.auth().currentUser!.phoneNumber! }
    private var normalizedPhone: String? { PhoneNumberFormatter.normalize(phone) }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Add someone by phone number")
                    .font(.headline)

                TextField("+1234567890", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                Button("Send Request") {
                    addFriend()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || normalizedPhone == nil || normalizedPhone == myPhone)

                if isSending {
                    ProgressView()
                        .padding(.top, 4)
                }

                Text(message)
                    .foregroundColor(message.starts(with: "Error") ? .red : .green)

                Spacer()
            }
            .navigationTitle("Add Friend")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }

    private func addFriend() {
        guard !isSending else { return }
        guard let theirPhone = normalizedPhone else {
            message = "Error: Please enter a valid phone number with country code."
            return
        }

        if theirPhone == myPhone {
            message = "Error: You can't add yourself."
            return
        }

        isSending = true
        message = ""

        service.addFriend(myPhone: myPhone, friendPhone: theirPhone) { result in
            isSending = false
            switch result {
            case .failure(let error):
                message = "Error: \(error.localizedDescription)"
            case .success:
                message = "Request sent! They’ll see you too."
                notifier.notificationOccurred(.success)
                phone = ""
            }
        }
    }
}
