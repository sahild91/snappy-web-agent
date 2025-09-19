package com.yudurobotics.snappywebagent;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;
import androidx.core.app.NotificationCompat;
import java.util.HashMap;

public class SnappyWebAgentService extends Service {
    private static final String TAG = "SnappyWebAgent";
    private static final String CHANNEL_ID = "SnappyWebAgentChannel";
    private static final int NOTIFICATION_ID = 1001;
    
    // Rust library name
    static {
        System.loadLibrary("snappy_web_agent");
    }

    // Native methods (implemented in Rust via JNI)
    public static native long nativeInit();
    public static native void nativeStart(long handle);
    public static native void nativeStop(long handle);
    public static native void nativeDestroy(long handle);
    public static native void nativeSetUsbDevice(long handle, int fileDescriptor, 
                                                int vendorId, int productId, String serialNumber);
    public static native void nativeRemoveUsbDevice(long handle);
    public static native boolean nativeIsRunning(long handle);
    public static native int nativeGetPort(long handle);

    private long nativeHandle = 0;
    private PowerManager.WakeLock wakeLock;
    private DeviceManager deviceManager;
    private com.yudurobotics.snappywebagent.NotificationManager notificationManager;

    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "Service onCreate()");

        createNotificationChannel();
        
        // Initialize native Rust core
        nativeHandle = nativeInit();
        if (nativeHandle == 0) {
            Log.e(TAG, "Failed to initialize native core");
            stopSelf();
            return;
        }

        // Initialize device manager for USB handling
        deviceManager = new DeviceManager(this, nativeHandle);
        notificationManager = new com.yudurobotics.snappywebagent.NotificationManager(this);

        // Acquire wake lock to prevent service from sleeping
        PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, TAG + "::WakeLock");
        wakeLock.acquire();

        Log.d(TAG, "Service created successfully");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.d(TAG, "Service onStartCommand()");

        // Start foreground service with persistent notification
        startForeground(NOTIFICATION_ID, createNotification("Starting Snappy Web Agent..."));

        // Start the native Rust service
        nativeStart(nativeHandle);
        
        // Check if service started successfully
        if (nativeIsRunning(nativeHandle)) {
            int port = nativeGetPort(nativeHandle);
            String message = "Snappy Web Agent running on port " + port;
            Log.d(TAG, message);
            
            // Update notification with port information
            updateNotification(message);
            
            // Start USB device monitoring
            deviceManager.startMonitoring();
        } else {
            Log.e(TAG, "Failed to start native service");
            stopSelf();
            return START_NOT_STICKY;
        }

        // Return START_STICKY to automatically restart if killed
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        Log.d(TAG, "Service onDestroy()");

        // Stop USB monitoring
        if (deviceManager != null) {
            deviceManager.stopMonitoring();
        }

        // Stop native service
        if (nativeHandle != 0) {
            nativeStop(nativeHandle);
            nativeDestroy(nativeHandle);
            nativeHandle = 0;
        }

        // Release wake lock
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }

        super.onDestroy();
        Log.d(TAG, "Service destroyed");
    }

    @Override
    public IBinder onBind(Intent intent) {
        // This service doesn't support binding
        return null;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Snappy Web Agent Service",
                NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("Snappy Web Agent background service for device communication");
            channel.setShowBadge(false);

            NotificationManager notificationManager = getSystemService(NotificationManager.class);
            notificationManager.createNotificationChannel(channel);
        }
    }

    private Notification createNotification(String message) {
        Intent notificationIntent = new Intent(this, SettingsActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        return new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Snappy Web Agent")
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_dialog_info) // TODO: Replace with custom icon
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build();
    }

    private void updateNotification(String message) {
        Notification notification = createNotification(message);
        NotificationManager notificationManager = 
            (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.notify(NOTIFICATION_ID, notification);
    }

    // Called by DeviceManager when USB device status changes
    public void onUsbDeviceStatusChanged(UsbDevice device, boolean connected) {
        if (nativeHandle == 0) return;

        if (connected) {
            Log.d(TAG, "USB device connected: " + device.getProductName());
            // DeviceManager will handle the file descriptor and call nativeSetUsbDevice
        } else {
            Log.d(TAG, "USB device disconnected: " + device.getProductName());
            nativeRemoveUsbDevice(nativeHandle);
        }
    }

    // Public method to get current service status
    public boolean isServiceRunning() {
        return nativeHandle != 0 && nativeIsRunning(nativeHandle);
    }

    public int getCurrentPort() {
        if (nativeHandle != 0) {
            return nativeGetPort(nativeHandle);
        }
        return -1;
    }
}