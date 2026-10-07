import re, glob
perms = ["INTERNET", "ACCESS_WIFI_STATE", "CHANGE_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE",
         "BLUETOOTH", "BLUETOOTH_ADMIN", "BLUETOOTH_SCAN", "BLUETOOTH_ADVERTISE", "BLUETOOTH_CONNECT",
         "ACCESS_COARSE_LOCATION", "ACCESS_FINE_LOCATION", "NEARBY_WIFI_DEVICES"]
m = "android/app/src/main/AndroidManifest.xml"
s = open(m).read()
add = "".join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in perms)
s = s.replace("<application", add + "    <application", 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Bitme"', s, 1)
open(m, "w").write(s)
for g in glob.glob("android/app/build.gradle*"):
    t = open(g).read()
    t = t.replace("minSdk = flutter.minSdkVersion", "minSdk = 23").replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 23")
    open(g, "w").write(t)
print("patched")

