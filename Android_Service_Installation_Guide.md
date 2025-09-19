# Snappy Web Agent - Android Service Installation Guide

## Overview

The Snappy Web Agent Android Service provides the same Socket.IO API as the desktop versions, allowing multiple Android apps to connect simultaneously to communicate with hardware devices via USB Host API.

## System Requirements

### Android TV/Device Requirements
- **Android Version**: Android 5.0 (API level 21) or higher
- **Architecture**: ARM64, ARMv7, x86, or x86_64
- **USB Host Support**: Required for hardware device communication
- **Storage**: ~15MB free space for installation
- **RAM**: Minimum 512MB available for service operation

### Hardware Requirements
- **USB Host Port**: For connecting Snappy devices
- **Network**: Wi-Fi or Ethernet for Socket.IO API access
- **Target Device**: USB device with VID 0xb1b0 and PID 0x5508 or 0x8055

## Installation Methods

### Method 1: ADB Installation (Recommended for Developers)

**Prerequisites:**
- Android Debug Bridge (ADB) installed on your computer
- USB debugging enabled on Android TV device
- Developer options enabled

**Steps:**
1. **Enable Developer Options:**
   - Go to Settings > Device Preferences > About
   - Click "Build" 7 times to enable developer mode
   - Go to Settings > Device Preferences > Developer options
   - Enable "USB debugging"

2. **Connect via ADB:**
   ```bash
   # Connect to Android TV (replace with your device IP)
   adb connect 192.168.1.100:5555
   
   # Verify connection
   adb devices
   ```

3. **Install the Service APK:**
   ```bash
   # Install debug version
   adb install snappy-web-agent-debug.apk
   
   # Or install release version
   adb install snappy-web-agent-release.apk
   ```

4. **Start the Service:**
   ```bash
   # Start the service
   adb shell am start-foreground-service com.yudurobotics.snappywebagent/.SnappyWebAgentService
   ```

### Method 2: USB Drive Installation (User-Friendly)

**Prerequisites:**
- USB drive with APK file
- File manager app on Android TV

**Steps:**
1. **Enable Unknown Sources:**
   - Go to Settings > Device Preferences > Security & restrictions
   - Enable "Unknown sources" for your file manager app

2. **Copy APK to USB Drive:**
   - Copy `snappy-web-agent-release.apk` to USB drive
   - Insert USB drive into Android TV

3. **Install via File Manager:**
   - Open file manager app
   - Navigate to USB drive
   - Click on the APK file
   - Follow installation prompts

4. **Launch Settings:**
   - Find "Snappy Web Agent" in your apps
   - Launch to configure and start the service

### Method 3: Network Installation (Remote)

**Prerequisites:**
- Local web server or network share
- Android TV with web browser

**Steps:**
1. **Host APK on Local Server:**
   ```bash
   # Simple Python web server
   python3 -m http.server 8080
   ```

2. **Download via Browser:**
   - Open browser on Android TV
   - Navigate to `http://your-computer-ip:8080`
   - Download the APK file

3. **Install Downloaded APK:**
   - Open Downloads in file manager
   - Install the APK file

## Post-Installation Setup

### 1. Service Configuration

**Launch Settings App:**
- Find "Snappy Web Agent" in your Android TV launcher
- Launch the app to access service settings

**Configure Service:**
- **Auto-start**: Enable to start service on boot (recommended)
- **Port Range**: Default 8436-8535 (usually automatic)
- **USB Permissions**: Grant when prompted
- **Logging Level**: Set to "Info" for normal operation

### 2. USB Device Setup

**Connect Hardware Device:**
1. Connect your Snappy device to Android TV USB port
2. Android will prompt for USB permissions
3. Grant permission to "Snappy Web Agent"
4. Service will automatically detect and configure the device

**Verify Device Connection:**
```bash
# Check service status via ADB
adb shell dumpsys activity services com.yudurobotics.snappywebagent

# Check USB devices
adb shell lsusb
```

### 3. Service Verification

**Check Service Status:**
```bash
# Via ADB
adb shell am start-foreground-service com.yudurobotics.snappywebagent/.SnappyWebAgentService

# Check if service is running
adb shell ps | grep snappy
```

**Test Socket.IO Connection:**
```bash
# Find the service port (usually 8436)
adb shell netstat -an | grep 8436

# Test basic connectivity
curl http://your-android-tv-ip:8436
```

## Service Management

### Starting the Service

**Via Settings App:**
- Open "Snappy Web Agent" app
- Tap "Start Service"

**Via ADB:**
```bash
adb shell am start-foreground-service com.yudurobotics.snappywebagent/.SnappyWebAgentService
```

**Automatic Start:**
- Service starts automatically on boot if enabled
- Service restarts automatically if crashed

### Stopping the Service

**Via Settings App:**
- Open "Snappy Web Agent" app
- Tap "Stop Service"

**Via ADB:**
```bash
adb shell am force-stop com.yudurobotics.snappywebagent
```

### Service Status

**Check Running Status:**
```bash
# Check if service is active
adb shell dumpsys activity services com.yudurobotics.snappywebagent

# Check network ports
adb shell netstat -an | grep 843
```

## Client App Integration

### Socket.IO Connection

The Android service provides the same API as desktop versions:

```javascript
// Connect to Android service
const socket = io('http://android-tv-ip:8436');

// Same API as desktop versions
socket.on('connect', () => {
    console.log('Connected to Android Snappy Web Agent');
});

socket.on('device-connected', (data) => {
    console.log('Device status:', data.status);
});

socket.on('snappy-data', (data) => {
    console.log('Device data:', data);
});

// Start data collection
socket.emit('start-snappy', (response) => {
    console.log('Start response:', response);
});
```

### Android App Integration

For Android apps connecting to the service:

```java
// Add Socket.IO client dependency to build.gradle
implementation 'io.socket:socket.io-client:2.0.0'

// Connect to local service
Socket socket = IO.socket("http://localhost:8436");
socket.connect();

socket.on("device-connected", new Emitter.Listener() {
    @Override
    public void call(Object... args) {
        // Handle device status
    }
});

socket.on("snappy-data", new Emitter.Listener() {
    @Override
    public void call(Object... args) {
        // Handle device data
    }
});

// Start data collection
socket.emit("start-snappy");
```

## Troubleshooting

### Service Won't Start

**Check Permissions:**
```bash
# Verify app has necessary permissions
adb shell dumpsys package com.yudurobotics.snappywebagent | grep permission
```

**Check System Logs:**
```bash
# View service logs
adb logcat -s SnappyWebAgent

# View system logs
adb logcat | grep SnappyWebAgent
```

**Common Solutions:**
- Restart Android TV device
- Reinstall the APK
- Check available storage space
- Verify USB device is properly connected

### USB Device Not Detected

**Check USB Host Support:**
```bash
# Verify USB host capability
adb shell cat /proc/config.gz | gunzip | grep USB_OTG
```

**Grant USB Permissions:**
- Disconnect and reconnect USB device
- Grant permission when Android prompts
- Check Settings > Apps > Snappy Web Agent > Permissions

**Verify Device VID/PID:**
```bash
# List connected USB devices
adb shell lsusb

# Should show device with VID 0xb1b0 and PID 0x5508 or 0x8055
```

### Port Conflicts

**Check Available Ports:**
```bash
# Check what's using ports in range 8436-8535
adb shell netstat -an | grep 843
```

**Service Port Discovery:**
- Service automatically finds available port
- Check service logs for assigned port
- Connect to discovered port for Socket.IO

### Network Connectivity Issues

**Firewall Settings:**
- Android TV firewall usually allows local connections
- Check router settings for device-to-device communication

**Network Discovery:**
```bash
# Find Android TV IP address
adb shell ip addr show wlan0

# Test connectivity from other devices
ping android-tv-ip
telnet android-tv-ip 8436
```

## Logging and Monitoring

### Service Logs

**View Real-time Logs:**
```bash
# Service-specific logs
adb logcat -s SnappyWebAgent

# All system logs (filter for relevant entries)
adb logcat | grep -i snappy
```

**Log Levels:**
- **ERROR**: Critical errors requiring attention
- **WARN**: Non-critical warnings
- **INFO**: General service information
- **DEBUG**: Detailed debugging information

### Performance Monitoring

**Service Resources:**
```bash
# Check memory usage
adb shell dumpsys meminfo com.yudurobotics.snappywebagent

# Check CPU usage
adb shell top | grep snappy
```

**Network Statistics:**
```bash
# Check active connections
adb shell netstat -an | grep 843

# Check network traffic
adb shell dumpsys netstats
```

## Uninstallation

### Complete Removal

**Stop Service First:**
```bash
adb shell am force-stop com.yudurobotics.snappywebagent
```

**Uninstall APK:**
```bash
adb uninstall com.yudurobotics.snappywebagent
```

**Or via Settings:**
- Go to Settings > Apps > Snappy Web Agent
- Select "Uninstall"

### Clean Removal Verification

```bash
# Verify service is not running
adb shell ps | grep snappy

# Verify ports are released
adb shell netstat -an | grep 843

# Verify app is removed
adb shell pm list packages | grep snappy
```

## Support and Updates

### Getting Help

- **GitHub Repository**: https://github.com/gouthamsk98/snappy-web-agent
- **Issues**: Report bugs and feature requests on GitHub
- **Documentation**: Latest API documentation in README.md

### Updating the Service

**Update Process:**
1. Stop the current service
2. Install new APK (will update existing installation)
3. Start the updated service
4. Verify functionality with test connection

**Version Compatibility:**
- API remains consistent across versions
- Client apps should continue working with service updates
- Check release notes for any breaking changes

## Advanced Configuration

### Custom Port Configuration

Currently, the service automatically selects ports. For future versions with manual configuration:

```bash
# Set custom port via service configuration
adb shell am start-foreground-service \
  com.yudurobotics.snappywebagent/.SnappyWebAgentService \
  --es port 8500
```

### Service Priority

**High Priority Mode:**
- Service runs as foreground service for reliability
- Android system less likely to kill the service
- Persistent notification indicates service status

**Battery Optimization:**
- Add Snappy Web Agent to battery optimization whitelist
- Ensures service continues running on battery power

### Multiple Device Support

The service supports multiple USB devices simultaneously:
- Each device appears as separate data source
- Socket.IO events include device identification
- Client apps can filter by device MAC address

This completes the Android service installation guide. The service provides the same professional experience as the desktop versions while leveraging Android's USB Host capabilities and service architecture.