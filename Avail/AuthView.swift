import SwiftUI
import FirebaseAuth
import UIKit

// Simple AuthUIDelegate implementation for Phone Auth
class PhoneAuthDelegate: NSObject, AuthUIDelegate {
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        print("🔵 PhoneAuthDelegate: present called")

        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                print("🔴 No window scene")
                completion?()
                return
            }

            guard let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
                print("🔴 No window")
                completion?()
                return
            }

            var topController = window.rootViewController
            while let presented = topController?.presentedViewController {
                topController = presented
            }

            guard let controller = topController else {
                print("🔴 No view controller")
                completion?()
                return
            }

            print("✅ Presenting reCAPTCHA on \(type(of: controller))")
            controller.present(viewControllerToPresent, animated: flag) {
                print("✅ reCAPTCHA presented")
                completion?()
            }
        }
    }

    func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
                completion?()
                return
            }
            window.rootViewController?.dismiss(animated: flag, completion: completion)
        }
    }
}

struct AuthView: View {
    @State private var phoneNumber = ""
    @State private var verificationID: String?
    @State private var code = ""
    @State private var isLoading = false
    @State private var alertMessage: String?
    private let service = AvailabilityService()
    private let authDelegate = PhoneAuthDelegate() // Keep delegate alive for async callback

    private var normalizedPhone: String? { PhoneNumberFormatter.normalize(phoneNumber) }

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

                if let alertMessage {
                    Text(alertMessage)
                        .foregroundColor(.red)
                }

                if isLoading { ProgressView() }
            }
            .padding()
            .alert(
                "Error",
                isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                )
            ) {
                Button("OK") { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func sendCode() {
        guard let formattedPhone = normalizedPhone else {
            alertMessage = "Please enter a valid phone number with country code."
            return
        }

        isLoading = true

        // Use our custom AuthUIDelegate for reCAPTCHA
        PhoneAuthProvider.provider()
            .verifyPhoneNumber(formattedPhone, uiDelegate: self.authDelegate) { vid, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let error = error {
                        alertMessage = error.localizedDescription
                        return
                    }
                    verificationID = vid
                }
            }
    }

    private func verifyCode() {
        guard let vid = verificationID else { return }
        isLoading = true
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: vid, verificationCode: code)

        Auth.auth().signIn(with: credential) { _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    alertMessage = error.localizedDescription
                    return
                }

                guard let phone = Auth.auth().currentUser?.phoneNumber else {
                    alertMessage = "Unable to read your phone number from authentication."
                    return
                }

                service.ensureUserProfile(for: phone) { result in
                    switch result {
                    case .failure(let error):
                        alertMessage = error.localizedDescription
                    case .success(let shouldPrompt):
                        if shouldPrompt {
                            promptForName(phone: phone)
                        }
                    }
                }
            }
        }
    }

    private func promptForName(phone: String) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(
                title: "Welcome!",
                message: "What should friends call you?",
                preferredStyle: .alert
            )

            alertController.addTextField { $0.placeholder = "Your name" }
            alertController.addAction(UIAlertAction(title: "Save", style: .default) { _ in
                let name = alertController.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let finalName = name.isEmpty ? "Friend" : name
                service.saveUserProfile(phone: phone, name: finalName) { result in
                    if case let .failure(error) = result {
                        alertMessage = error.localizedDescription
                    }
                }
            })

            UIApplication.shared.windows.first?.rootViewController?.present(alertController, animated: true)
        }
    }
}
