# SafeGuard

एक Flutter प्रोजेक्ट से दो Android ऐप बनते हैं।

| फ़्लेवर | Android application ID | Firebase Android कॉन्फ़िग |
| --- | --- | --- |
| `parent` | `com.safeguard.app.parent` | `android/app/src/parent/google-services.json` |
| `child` | `com.safeguard.app.child` | `android/app/src/child/google-services.json` |

[FIREBASE-SETUP.md](FIREBASE-SETUP.md) में Firebase project, Android registrations और क्लाउड बिल्ड की जानकारी है। दोनों फ़्लेवर Firebase फ़ाइलों के साथ चलेंगे। बैकएंड के लिए प्रोजेक्ट रूट से Firebase deployment करें।

```sh
cd functions
npm ci
cd ..
firebase deploy --project YOUR_FIREBASE_PROJECT_ID --only firestore,storage,functions
```

यहाँ से Flutter और Android SDK वाले होस्ट पर टेस्ट APK बन सकते हैं। यही काम GitHub Actions में **Build SafeGuard APKs** करता है।

```sh
sh scripts/prepare-android.sh
flutter pub get
flutter analyze
flutter build apk --debug --flavor parent
flutter build apk --debug --flavor child
```

## वर्तमान कार्यान्वयन

- मोबाइल नंबर और पासवर्ड के साथ Parent signup और custom-token login।
- Child के लिए anonymous Firebase session, समय-सीमित pair code और pairing status।
- Parent से lock, vibration, tone, flashlight और message requests। Child ऐप में अनुरोध की समीक्षा, अनुमति और दृश्य सूचना के बाद action चलता है। परिणाम Parent history में दिखाई देता है।
- Firestore में authenticated access rules और FCM से Child को pending request notification।
- स्क्रीन/कैमरा/माइक capture, Storage media upload, SMS, overlay, alarm, silent/DND, device reboot, shutdown, wipe और credential reset का कार्यान्वयन अभी बाकी है।

## वास्तविक डिवाइस पर जाँच

1. Parent और Child को अलग Android devices में इंस्टॉल करें।
2. Child का कोड दिखना और Refresh Code के बाद पुराना कोड अस्वीकार होना जाँचें।
3. Parent पर signup, logout और दूसरे लॉगिन में सही और गलत पासवर्ड आज़माएँ।
4. सही code से pairing करें। Child पर connected status और Parent पर linked device दिखना चाहिए।
5. Child पर notification की अनुमति दें। Parent से request भेजकर background notification, Child पर Decline और Allow, और Parent पर status जाँचें।
6. Device Admin के बिना lock request पर त्रुटि की पुष्टि करें। फिर Child की Android सेटिंग में अनुमति देकर lock जाँचें।
7. दूसरे Parent account से paired family के commands पढ़ने और बदलने की कोशिश अस्वीकृत होनी चाहिए।
