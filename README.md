# Avail - Simple Availability Toggle App

A minimal iOS app to toggle your availability (green/red) and share it with friends via phone number. Built with SwiftUI + Firebase.

## Quick Setup
1. Clone this repo: `git clone https://github.com/vforvanfiel/avail.git`
2. Open `Avail/Avail.xcodeproj` in Xcode (generate if needed: New Project > save as Avail.xcodeproj in the Avail folder).
3. Add Firebase: File > Add Package Dependencies > https://github.com/firebase/firebase-ios-sdk (select FirebaseAuth, FirebaseFirestore, FirebaseFirestoreSwift).
4. Download `GoogleService-Info.plist` from your Firebase Console project and drag it into Xcode (add to Avail target).
5. Enable Phone Auth and Firestore in Firebase Console.
6. Paste the security rules below into Firestore > Rules tab.
7. Build and run on simulator/device!

## Which Firebase project do I use?
- Create **your own Firebase project** in the Firebase Console (any region is fine).
- Download the generated `GoogleService-Info.plist` for your iOS app bundle ID and add it to the Avail target.
- Enable **Phone Authentication** and **Cloud Firestore**, then apply the security rules below.
- If you're unsure of your project ID later, open the Firebase Console > Project Settings; the ID and bundle configs are listed there.

## Firebase Security Rules
rules_version = '2';
service cloud.firestore {
match /databases/{database}/documents {
match /users/{phone} {
allow read, write: if request.auth != null && request.auth.token.phone_number == phone;
match /friends/{friendPhone} {
allow read, write: if request.auth != null && request.auth.token.phone_number == phone;
}
}
match /users/{phone} {
allow read: if request.auth != null;
}
}
}

## How It Works
- **Auth**: Phone number verification via Firebase.
- **Toggle**: Big green/red switch updates your status in real-time.
- **Friends**: Mutual adds by phone—see their statuses instantly.
- **Data**: Firestore docs like `users/{phone}` for status, `friends/{phone}` subcollection.

## Files Structure
- `Avail/AvailApp.swift`: App entry & Firebase init.
- `Avail/AuthView.swift`: Phone login screen.
- `Avail/MainView.swift`: Main toggle + friends list.
- `Avail/AddFriendView.swift`: Add friends sheet.

## Cloning with Xcode (keeps the project in sync)
- You **can** clone directly from Xcode: *Source Control > Clone…* → paste your GitHub URL → choose a folder (e.g., `~/Developer`), then open `Avail/Avail.xcodeproj`.
- Xcode uses git under the hood. When you or teammates push changes, just run **Source Control > Pull** (or `git pull` in Terminal) and the files in the Xcode project update automatically—no need to re-add/drag them once they’re part of the project.
- When adding new files in Xcode, check **Add to targets** before committing. Commit both the new file and the updated `.xcodeproj`; after that, pulls will surface the new files automatically.

## Next Steps
- Test: Install app on two phones, add each other, toggle away!
- Polish: Add widgets, push notifications, or custom names.
- Ship: Update bundle ID in Xcode, submit to App Store.

MIT License. Built with ❤️ using SwiftUI 6 & Firebase (2025). Questions? Open an issue!
