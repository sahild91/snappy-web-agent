// JNI wrapper for Snappy Web Agent Android Service
// This file bridges C++ to the Rust library

#include <jni.h>
#include <android/log.h>
#include <string>

#define LOG_TAG "SnappyWebAgent"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// This is just a minimal wrapper - the actual JNI implementation is in Rust
// The Rust library exports the JNI functions directly

extern "C" {
    // These are exported by the Rust library and will be linked
    // The actual implementations are in src/android_jni.rs
    
    // JNI_OnLoad is called when the library is loaded
    JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
        LOGD("JNI_OnLoad called - Snappy Web Agent native library loaded");
        return JNI_VERSION_1_6;
    }
    
    // JNI_OnUnload is called when the library is unloaded
    JNIEXPORT void JNICALL JNI_OnUnload(JavaVM* vm, void* reserved) {
        LOGD("JNI_OnUnload called - Snappy Web Agent native library unloaded");
    }
}

// The actual JNI method implementations are in the Rust library:
// - Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeInit
// - Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeStart
// - Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeStop
// - Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeDestroy
// - Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeSetUsbDevice
// - Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeRemoveUsbDevice
// - Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeIsRunning
// - Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeGetPort
// - Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeGetDeviceCount
// - Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeHasDevice