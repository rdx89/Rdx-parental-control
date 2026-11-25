# SafeGuard Firebase और APK बिल्ड

दोनों APK के लिए एक ही Firebase project रखें।

1. Firebase Console में प्रोजेक्ट खोलें। Project settings में दो Android apps रजिस्टर करें।
   - Parent का package name `com.safeguard.app.parent` है।
   - Child का package name `com.safeguard.app.child` है।
2. प्रत्येक Android app की अलग `google-services.json` डाउनलोड करें। दोनों फ़ाइलें Parent और Child के नाम से पहचान कर रखें।
3. प्रोजेक्ट में Authentication शुरू करें। Child की बैकएंड पहचान के लिए **Sign-in method → Anonymous** सक्षम करें। Parent का मोबाइल और पासवर्ड लॉगिन Custom Token का उपयोग करेगा।
4. Cloud Firestore में default database बनाएँ। Production mode चुनें, ताकि नियम डिप्लॉय होने से पहले client access बंद रहे।
5. Cloud Functions और Cloud Storage के लिए प्रोजेक्ट पर Blaze billing सक्षम करें और Storage में default bucket बनाएँ। यह कदम Firebase project owner के नियंत्रण में है।
6. GitHub repository के **Settings → Secrets and variables → Actions** में Parent JSON को `FIREBASE_PARENT_CONFIG` और Child JSON को `FIREBASE_CHILD_CONFIG` में रखें। APK बिल्ड के लिए इन दो Firebase client configs की ज़रूरत है। Firebase deploy के लिए project access अलग है।

वर्कफ़्लो मैनुअल है। GitHub Actions में **Build SafeGuard APKs** रन होने के बाद दो artifacts मिलते हैं। हर artifact में एक debug-signed APK होगा। ये टेस्ट इंस्टॉल के लिए हैं। Backend deployment और Android पर end-to-end जाँच अलग से पूरी होनी है।
