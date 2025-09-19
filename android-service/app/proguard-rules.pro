# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# Keep native methods (JNI)
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Snappy Web Agent service classes
-keep class com.yudurobotics.snappywebagent.SnappyWebAgentService {
    public static native long nativeInit();
    public static native void nativeStart(long);
    public static native void nativeStop(long);
    public static native void nativeDestroy(long);
    public static native void nativeSetUsbDevice(long, int, int, int, java.lang.String);
    public static native void nativeRemoveUsbDevice(long);
    public static native boolean nativeIsRunning(long);
    public static native int nativeGetPort(long);
    public static native int nativeGetDeviceCount(long);
    public static native boolean nativeHasDevice(long);
}

# Keep service and receiver classes
-keep class com.yudurobotics.snappywebagent.SnappyWebAgentService
-keep class com.yudurobotics.snappywebagent.BootReceiver
-keep class com.yudurobotics.snappywebagent.ServiceControlReceiver
-keep class com.yudurobotics.snappywebagent.SettingsActivity
-keep class com.yudurobotics.snappywebagent.DeviceManager
-keep class com.yudurobotics.snappywebagent.NotificationManager

# Keep USB device related classes
-keep class android.hardware.usb.** { *; }

# Keep Android TV leanback classes
-keep class androidx.leanback.** { *; }

# Keep notification classes
-keep class androidx.core.app.NotificationCompat** { *; }

# Keep service classes
-keep class android.app.Service
-keep class android.content.BroadcastReceiver

# Keep R class and resources
-keepclassmembers class **.R$* {
    public static <fields>;
}

# Keep BuildConfig
-keep class com.yudurobotics.snappywebagent.BuildConfig { *; }

# Keep Parcelable implementations
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# Keep enum classes
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep custom exceptions
-keep public class * extends java.lang.Exception

# Android support library specific rules
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**

# Material Design Components
-keep class com.google.android.material.** { *; }

# USB Host API
-keep class android.hardware.usb.UsbDevice { *; }
-keep class android.hardware.usb.UsbManager { *; }
-keep class android.hardware.usb.UsbDeviceConnection { *; }

# Keep classes with special naming patterns
-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet);
}

-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet, int);
}

# Keep classes that are referenced only in XML layouts
-keep public class * extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
    public void set*(...);
    *** get*();
}

# Keep activity classes
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# Android TV specific
-keep class * extends androidx.leanback.app.BrowseFragment
-keep class * extends androidx.leanback.app.BackgroundManager

# Log tag obfuscation prevention
-keepattributes *Annotation*
-keep class * {
    @androidx.annotation.Keep *;
}