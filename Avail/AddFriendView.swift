import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AddFriendView: View {
    @State private var phone = ""
    @State private var message = ""
    @Environment(\.dismiss) var dismiss
    private let db = Firestore.firestore()
    private var myPhone: String { Auth.auth().currentUser!.phoneNumber! }
    
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
                .disabled(phone.isEmpty || phone == myPhone)
                
                Text(message)
                    .foregroundColor(.green)
                
                Spacer()
            }
            .navigationTitle("Add Friend")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
    
    func addFriend() {
        let theirPhone = phone.trimmingCharacters(in: .whitespaces)
        
        // Add each other as friends (mutual)
        let myRef = db.collection("users").document(myPhone).collection("friends").document(theirPhone)
        let theirRef = db.collection("users").document(theirPhone).collection("friends").document(myPhone)
        
        let batch = db.batch()
        batch.setData(["addedAt": FieldValue.serverTimestamp()], forDocument: myRef)
        batch.setData(["addedAt": FieldValue.serverTimestamp()], forDocument: theirRef)
        
        batch.commit { err in
            if let err = err {
                message = "Error: \(err.localizedDescription)"
            } else {
                message = "Request sent! They’ll see you too."
                phone = ""
            }
        }
    }
}
