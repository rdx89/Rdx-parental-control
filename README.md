# RDX SafeGuard

Created by Rahul Pipliwal

एक Flutter प्रोजेक्ट से दो Android ऐप बनते हैं।

| फ़्लेवर | Android application ID | Firebase Android कॉन्फ़िग |
| --- | --- | --- |
| `parent` | `com.safeguard.app.parent` | `android/app/src/parent/google-services.json` |
| `child` | `com.safeguard.app.child` | `android/app/src/child/google-services.json` |

[FIREBASE-SETUP.md](FIREBASE-SETUP.md) में Firebase project, Android registrations और क्लाउड बिल्ड की जानकारी है। Firebase Authentication ऐप की पहचान और FCM push संभालता है। Cloudflare Worker HTTPS API और D1 pairing व request status संभालते हैं। Parent ऐप में मोबाइल नंबर और पासवर्ड दिखाई देते हैं। Firebase Authentication अंदरूनी login alias से पासवर्ड संभालता है।

APK बिल्ड के लिए GitHub पर **Build SafeGuard APKs** चलाएँ। Workflow `SAFEGUARD_API_URL` repository variable लेता है। स्थानीय Android build में `flutter build apk --debug --flavor parent --dart-define=SAFEGUARD_API_URL=https://your-worker.workers.dev` चलाएँ। Child के लिए `--flavor child` रखें।

Cloudflare deployment के लिए `worker/wrangler.jsonc` में अपना D1 database binding रखें। पहली बार `wrangler d1 migrations apply rdx-safeguard --remote --config worker/wrangler.jsonc` चलाएँ और फिर उसी config से `wrangler deploy` करें। Worker के secrets में `FIREBASE_API_KEY`, स्थायी random `LOGIN_ALIAS_SECRET`, और FCM के लिए project-scoped `FCM_ACCOUNT` रखें।

## वर्तमान कार्यान्वयन

- मोबाइल नंबर और पासवर्ड के साथ Parent signup और Firebase-managed login।
- Child के लिए anonymous Firebase session, समय-सीमित pair code और pairing status।
- Parent से lock, vibration, tone, flashlight, message, alarm, silent mode, Do Not Disturb और battery level requests। Child ऐप में अनुरोध की समीक्षा, अनुमति और दृश्य सूचना के बाद action चलता है। परिणाम Parent history में दिखाई देता है। Parent या Child pairing हटा सकते हैं और पुराने अनुरोध नई pairing में नहीं चलेंगे।
- D1 में परिवार के हिसाब से सुरक्षित pending requests और FCM से Child को request notification।
- स्क्रीन/कैमरा/माइक capture, Storage media upload, SMS, overlay, device reboot, shutdown, wipe और credential reset का कार्यान्वयन अभी बाकी है।

## वास्तविक डिवाइस पर जाँच

1. Parent और Child को अलग Android devices में इंस्टॉल करें।
2. Child का कोड दिखना और Refresh Code के बाद पुराना कोड अस्वीकार होना जाँचें।
3. Parent पर signup, logout और दूसरे लॉगिन में सही और गलत पासवर्ड आज़माएँ।
4. सही code से pairing करें। Child पर connected status और Parent पर linked device दिखना चाहिए।
5. Child पर notification की अनुमति दें। Parent से request भेजकर background notification, Child पर Decline और Allow, और Parent पर status जाँचें।
6. Device Admin के बिना lock request पर त्रुटि की पुष्टि करें। फिर Child की Android सेटिंग में अनुमति देकर lock जाँचें।
7. दूसरे Parent account से paired family के commands पढ़ने और बदलने की कोशिश अस्वीकृत होनी चाहिए।
