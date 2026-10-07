# Bitme

Bina internet ke chat app. Do phone Bluetooth se ya same WiFi se jud kar chat karte hain.

- **Bluetooth mode**: Google Nearby Connections (Android)
- **WiFi mode**: same WiFi par UDP, koi server nahi
- Username set karo, dusre ka username add karo, chat karo

## APK banana (phone se bhi ho jata hai)
1. Ye repo GitHub par push karo
2. **Actions** tab → **Build APK** → **Run workflow**
3. Complete hone par **Artifacts → Bitme-apk** download karo aur install karo

## Computer par chalana
```
flutter create --platforms=android --project-name bitme --org com.bitme /tmp/s && cp -r /tmp/s/android .
python3 tools/patch_android.py
flutter pub get && dart run flutter_launcher_icons
flutter run
```
Bluetooth test ke liye 2 real Android phones chahiye (emulator me nahi chalega).
