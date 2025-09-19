#!/bin/bash

# Snappy Web Agent - Android Service Build Script
# Builds the Rust core for Android and creates the service APK

set -e

# Configuration
APP_NAME="snappy-web-agent"
PACKAGE_NAME="com.yudurobotics.snappywebagent"
ANDROID_DIR="android-service"
BUILD_DIR="build/android"
RUST_TARGETS=("aarch64-linux-android" "armv7-linux-androideabi" "i686-linux-android" "x86_64-linux-android")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v cargo &> /dev/null; then
        log_error "Cargo is not installed. Please install Rust."
        exit 1
    fi
    
    if [ -z "$ANDROID_HOME" ]; then
        log_error "ANDROID_HOME environment variable is not set."
        log_info "Please set ANDROID_HOME to your Android SDK path."
        exit 1
    fi
    
    if [ -z "$ANDROID_NDK_ROOT" ] && [ -z "$ANDROID_NDK_HOME" ]; then
        log_error "ANDROID_NDK_ROOT or ANDROID_NDK_HOME environment variable is not set."
        log_info "Please set one of them to your Android NDK path."
        exit 1
    fi
    
    # Set NDK_ROOT if not set but NDK_HOME is available
    if [ -z "$ANDROID_NDK_ROOT" ] && [ -n "$ANDROID_NDK_HOME" ]; then
        export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
    fi
    
    if ! command -v "${ANDROID_HOME}/tools/bin/sdkmanager" &> /dev/null; then
        if ! command -v "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" &> /dev/null; then
            log_error "Android SDK manager not found. Please install Android SDK."
            exit 1
        fi
    fi
    
    log_success "All dependencies found"
}

# Setup Rust for Android cross-compilation
setup_rust_android() {
    log_info "Setting up Rust for Android cross-compilation..."
    
    # Add Android targets
    for target in "${RUST_TARGETS[@]}"; do
        log_info "Adding Rust target: $target"
        rustup target add "$target"
    done
    
    # Install cargo-ndk if not present
    if ! command -v cargo-ndk &> /dev/null; then
        log_info "Installing cargo-ndk..."
        cargo install cargo-ndk
    fi
    
    log_success "Rust Android setup completed"
}

# Build Rust libraries for Android
build_rust_libraries() {
    log_info "Building Rust libraries for Android targets..."
    
    mkdir -p "$BUILD_DIR/jniLibs"
    
    for target in "${RUST_TARGETS[@]}"; do
        log_info "Building for target: $target"
        
        # Determine Android ABI name
        case "$target" in
            "aarch64-linux-android")
                android_abi="arm64-v8a"
                ;;
            "armv7-linux-androideabi")
                android_abi="armeabi-v7a"
                ;;
            "i686-linux-android")
                android_abi="x86"
                ;;
            "x86_64-linux-android")
                android_abi="x86_64"
                ;;
            *)
                log_error "Unknown target: $target"
                continue
                ;;
        esac
        
        # Build with cargo-ndk
        cargo ndk --target "$target" --android-platform 21 -- build --release
        
        # Copy the built library to jniLibs directory
        mkdir -p "$BUILD_DIR/jniLibs/$android_abi"
        cp "target/$target/release/lib${APP_NAME//-/_}.so" "$BUILD_DIR/jniLibs/$android_abi/"
        
        log_success "Built library for $android_abi"
    done
    
    log_success "All Rust libraries built successfully"
}

# Copy JNI libraries to Android project
copy_jni_libraries() {
    log_info "Copying JNI libraries to Android project..."
    
    rm -rf "$ANDROID_DIR/app/src/main/jniLibs"
    cp -r "$BUILD_DIR/jniLibs" "$ANDROID_DIR/app/src/main/"
    
    log_success "JNI libraries copied to Android project"
}

# Build Android APK
build_android_apk() {
    log_info "Building Android APK..."
    
    cd "$ANDROID_DIR"
    
    # Clean previous builds
    ./gradlew clean
    
    # Build debug APK
    log_info "Building debug APK..."
    ./gradlew assembleDebug
    
    # Build release APK if keystore is available
    if [ -f "app/release.keystore" ]; then
        log_info "Building release APK..."
        ./gradlew assembleRelease
    else
        log_warning "Release keystore not found. Only debug APK will be built."
        log_info "To build release APK, create app/release.keystore and configure signing in build.gradle"
    fi
    
    cd ..
    
    log_success "Android APK build completed"
}

# Copy APK to build output
copy_apk_to_output() {
    log_info "Copying APK to build output..."
    
    mkdir -p "$BUILD_DIR/apk"
    
    # Copy debug APK
    if [ -f "$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk" ]; then
        cp "$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk" \
           "$BUILD_DIR/apk/${APP_NAME}-debug.apk"
        log_success "Debug APK: $BUILD_DIR/apk/${APP_NAME}-debug.apk"
    fi
    
    # Copy release APK if available
    if [ -f "$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk" ]; then
        cp "$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk" \
           "$BUILD_DIR/apk/${APP_NAME}-release.apk"
        log_success "Release APK: $BUILD_DIR/apk/${APP_NAME}-release.apk"
    fi
}

# Display build summary
show_build_summary() {
    log_info "Build Summary"
    echo "=============================================="
    
    if [ -f "$BUILD_DIR/apk/${APP_NAME}-debug.apk" ]; then
        debug_size=$(du -h "$BUILD_DIR/apk/${APP_NAME}-debug.apk" | cut -f1)
        echo "✓ Debug APK: ${APP_NAME}-debug.apk (${debug_size})"
    fi
    
    if [ -f "$BUILD_DIR/apk/${APP_NAME}-release.apk" ]; then
        release_size=$(du -h "$BUILD_DIR/apk/${APP_NAME}-release.apk" | cut -f1)
        echo "✓ Release APK: ${APP_NAME}-release.apk (${release_size})"
    fi
    
    echo ""
    echo "JNI Libraries built for:"
    for target in "${RUST_TARGETS[@]}"; do
        case "$target" in
            "aarch64-linux-android") echo "  - ARM64 (arm64-v8a)" ;;
            "armv7-linux-androideabi") echo "  - ARMv7 (armeabi-v7a)" ;;
            "i686-linux-android") echo "  - x86 (x86)" ;;
            "x86_64-linux-android") echo "  - x86_64 (x86_64)" ;;
        esac
    done
    
    echo ""
    echo "Installation:"
    echo "  Debug:   adb install $BUILD_DIR/apk/${APP_NAME}-debug.apk"
    if [ -f "$BUILD_DIR/apk/${APP_NAME}-release.apk" ]; then
        echo "  Release: adb install $BUILD_DIR/apk/${APP_NAME}-release.apk"
    fi
    echo ""
    echo "Service Control:"
    echo "  Start:   adb shell am start-foreground-service $PACKAGE_NAME/.SnappyWebAgentService"
    echo "  Stop:    adb shell am force-stop $PACKAGE_NAME"
    echo "  Status:  adb shell dumpsys activity services $PACKAGE_NAME"
    echo "=============================================="
}

# Main execution
main() {
    log_info "Starting Android service build process..."
    
    check_dependencies
    setup_rust_android
    build_rust_libraries
    copy_jni_libraries
    build_android_apk
    copy_apk_to_output
    show_build_summary
    
    log_success "Android service build completed successfully!"
}

# Parse command line arguments
case "${1:-build}" in
    "clean")
        log_info "Cleaning build artifacts..."
        rm -rf "$BUILD_DIR"
        rm -rf "$ANDROID_DIR/app/build"
        rm -rf "$ANDROID_DIR/app/src/main/jniLibs"
        cargo clean
        log_success "Clean completed"
        ;;
    "build")
        main
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  build    Build Android service (default)"
        echo "  clean    Clean build artifacts"
        echo "  help     Show this help"
        echo ""
        echo "Prerequisites:"
        echo "  - ANDROID_HOME environment variable"
        echo "  - ANDROID_NDK_ROOT or ANDROID_NDK_HOME environment variable"
        echo "  - Android SDK with API level 21+"
        echo "  - Android NDK"
        echo "  - Rust toolchain with Android targets"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac