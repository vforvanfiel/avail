import SwiftUI
import FirebaseAuth

struct AuthView: View {
    @State private var phoneNumber = ""
    @State private var verificationID: String?
    @State private var code = ""
    @State private var isLoading = false
    
    var body: some View {
        if Auth.auth().currentUser != nil {
            MainView()
        } else {
            VStack(spacing: 20) {
                Text("Avail")
                    .font(.largeTitle.bold())
                
                TextField("+1234567890", text: $phoneNumber)
                    .keyboardType(.phonePad)
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
                    .disabled(phoneNumber.isEmpty || isLoading)
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
                
                if isLoading { ProgressView() }
            }
            .padding()
        }
    }
    
    func sendCode() {
        isLoading = true
        PhoneAuthProvider.provider()
            .verifyPhoneNumber(phoneNumber, uiDelegate: nil) { vid, error in
                isLoading = false
                if let error = error { print(error); return }
                verificationID = vid
            }
    }
    
    func verifyCode() {
        guard let vid = verificationID else { return }
        isLoading = true
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: vid, verificationCode: code)
        Auth.auth().signIn(with: credential) { result, error in
            isLoading = false
            if let error = error { print(error) }
        }
    }
}
