# ══════════════════════════════════════════════════════════
# Flutter 核心（官方推荐）
# ══════════════════════════════════════════════════════════
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ══════════════════════════════════════════════════════════
# 你项目里用到的插件（关键！不加会崩）
# ══════════════════════════════════════════════════════════

# workmanager
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }

# flutter_foreground_task
-keep class com.pravera.flutter_foreground_task.** { *; }
-keep class com.pravera.flutter_foreground_task.service.** { *; }

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# device_info_plus
-keep class dev.fluttercommunity.plus.device_info.** { *; }

# package_info_plus
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# app_settings
-keep class com.spencerccf.app_settings.** { *; }

# supabase_flutter（用 HTTP，无 Java 层，但防万一）
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# video_player
-keep class io.flutter.plugins.videoplayer.** { *; }

# cached_network_image（纯 Dart，无 Java 层）

# ══════════════════════════════════════════════════════════
# 第三方库警告忽略
# ══════════════════════════════════════════════════════════
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn com.google.android.play.core.**
-dontwarn javax.annotation.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# ══════════════════════════════════════════════════════════
# 保留元数据（反射、序列化必须）
# ══════════════════════════════════════════════════════════
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ══════════════════════════════════════════════════════════
# 保留原生方法（JNI）
# ══════════════════════════════════════════════════════════
-keepclasseswithmembernames class * {
    native <methods>;
}

# ══════════════════════════════════════════════════════════
# Parcelable / Serializable（Android 序列化）
# ══════════════════════════════════════════════════════════
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ══════════════════════════════════════════════════════════
# WebView（如果有用）
# ══════════════════════════════════════════════════════════
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, java.lang.String, android.graphics.Bitmap);
    public boolean *(android.webkit.WebView, java.lang.String);
}
-keepclassmembers class * extends android.webkit.WebChromeClient {
    public void *(android.webkit.WebView, java.lang.String);
}