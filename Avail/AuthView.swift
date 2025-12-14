import SwiftUI
import FirebaseAuth

struct AuthView: View {
    @State private var phoneNumber = ""
    @State private var verificationID: String?
    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let service = AvailabilityService()

    private var normalizedPhone: String? {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0.isWholeNumber || $0 == "+" }
        guard digits.count >= 11 else { return nil }
        return digits.hasPrefix("+") ? digits : "+" + digits
    }

    var body: some View {
        if Auth.auth().currentUser != nil {
            MainView()
        } else {
            VStack(spacing: 20) {
                Text("Avail")
                    .font(.largeTitle.bold())

                TextField("+1234567890", text: $phoneNumber)
                    .keyboardType(.numbersAndPunctuation)
                    .textContentType(.telephoneNumber)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                if verificationID == nil {
                    Button("Send Code") {
                        sendCode()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(normalizedPhone == nil || isLoading)
                } else {
                    TextField("Verification code", text: $code)
                        .keyboardType(.numberPad)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)

                    Button("Verify") {
                        verifyCode()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(code.isEmpty || isLoading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }

                if isLoading {
                    ProgressView()
                        .padding()
                }
            }
            .padding()
        }
    }

    private func sendCode() {
        guard let phone = normalizedPhone else {
            errorMessage = "Enter a valid phone number (e.g., +1234567890)"
            return
        }

        isLoading = true
        errorMessage = nil

        Auth.auth().settings?.isAppVerificationDisabledForTesting = false

        PhoneAuthProvider.provider().verifyPhoneNumber(phone, uiDelegate: nil) { verificationID, error in
            Task { @MainActor in
                self.isLoading = false

                if let error = error {
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    return
                }

                self.verificationID = verificationID
            }
        }
    }

    private func verifyCode() {
        guard let vid = verificationID else {
            errorMessage = "No verification ID"
            return
        }

        isLoading = true
        errorMessage = nil

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: vid,
            verificationCode: code
        )

        Auth.auth().signIn(with: credential) { result, error in
            Task { @MainActor in
                self.isLoading = false

                if let error = error {
                    self.errorMessage = "Verification failed: \(error.localizedDescription)"
                    return
                }

                guard let phone = result?.user.phoneNumber else {
                    self.errorMessage = "Could not get phone number"
                    return
                }

                // Check if user profile exists
                self.service.ensureUserProfile(for: phone) { profileResult in
                    Task { @MainActor in
                        switch profileResult {
                        case .failure(let error):
                            self.errorMessage = error.localizedDescription
                        case .success(let isNewUser):
                            if isNewUser {
                                // New user - save default profile
                                self.service.saveUserProfile(phone: phone, name: "Friend") { _ in }
                            }
                        }
                    }
                }
            }
        }
    }
}
