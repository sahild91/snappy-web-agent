package com.yudurobotics.snappywebagent;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;
import androidx.core.app.NotificationCompat;

public class NotificationManager {
    private static final String TAG = "NotificationManager";
    
    // Notification channels
    private static final String CHANNEL_SERVICE = "snappy_service_channel";
    private static final String CHANNEL_STATUS = "snappy_status_channel";
    private static final String CHANNEL_ERROR = "snappy_error_channel";
    
    // Notification IDs
    public static final int NOTIFICATION_SERVICE = 1001;
    public static final int NOTIFICATION_STATUS = 1002;
    public static final int NOTIFICATION_ERROR = 1003;
    
    private final Context context;
    private final android.app.NotificationManager systemNotificationManager;
    
    public NotificationManager(Context context) {
        this.context = context.getApplicationContext();
        this.systemNotificationManager = (android.app.NotificationManager) 
            context.getSystemService(Context.NOTIFICATION_SERVICE);
        
        createNotificationChannels();
        Log.d(TAG, "NotificationManager initialized");
    }
    
    private void createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Service channel (low importance, no sound)
            NotificationChannel serviceChannel = new NotificationChannel(
                CHANNEL_SERVICE,
                "Snappy Web Agent Service",
                android.app.NotificationManager.IMPORTANCE_LOW
            );
            serviceChannel.setDescription("Persistent notification for Snappy Web Agent service");
            serviceChannel.setShowBadge(false);
            serviceChannel.enableLights(false);
            serviceChannel.enableVibration(false);
            serviceChannel.setSound(null, null);
            
            // Status channel (default importance)
            NotificationChannel statusChannel = new NotificationChannel(
                CHANNEL_STATUS,
                "Service Status Updates",
                android.app.NotificationManager.IMPORTANCE_DEFAULT
            );
            statusChannel.setDescription("Status updates for Snappy Web Agent");
            statusChannel.setShowBadge(true);
            statusChannel.enableLights(true);
            statusChannel.setLightColor(0xFF00FF00); // Green
            
            // Error channel (high importance)
            NotificationChannel errorChannel = new NotificationChannel(
                CHANNEL_ERROR,
                "Service Errors",
                android.app.NotificationManager.IMPORTANCE_HIGH
            );
            errorChannel.setDescription("Error notifications from Snappy Web Agent");
            errorChannel.setShowBadge(true);
            errorChannel.enableLights(true);
            errorChannel.setLightColor(0xFFFF0000); // Red
            
            systemNotificationManager.createNotificationChannel(serviceChannel);
            systemNotificationManager.createNotificationChannel(statusChannel);
            systemNotificationManager.createNotificationChannel(errorChannel);
            
            Log.d(TAG, "Notification channels created");
        }
    }
    
    /**
     * Create the persistent foreground service notification
     */
    public Notification createServiceNotification(String message) {
        return createServiceNotification(message, null, -1);
    }
    
    public Notification createServiceNotification(String message, String subText, int port) {
        Intent notificationIntent = new Intent(context, SettingsActivity.class);
        notificationIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        
        PendingIntent pendingIntent = PendingIntent.getActivity(
            context, 0, notificationIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        
        // Action buttons
        PendingIntent stopIntent = createStopServicePendingIntent();
        PendingIntent settingsIntent = createSettingsPendingIntent();
        
        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_SERVICE)
            .setContentTitle("Snappy Web Agent")
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_dialog_info) // TODO: Replace with custom icon
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopIntent)
            .addAction(android.R.drawable.ic_menu_preferences, "Settings", settingsIntent);
        
        // Add subtext if provided
        if (subText != null) {
            builder.setSubText(subText);
        }
        
        // Show port information in expanded view
        if (port > 0) {
            NotificationCompat.BigTextStyle bigTextStyle = new NotificationCompat.BigTextStyle()
                .bigText(message + "\n\nSocket.IO API available at:\nhttp://localhost:" + port)
                .setSummaryText("Port: " + port);
            builder.setStyle(bigTextStyle);
        }
        
        return builder.build();
    }
    
    /**
     * Update the service notification with current status
     */
    public void updateServiceNotification(String message, int port, int deviceCount, boolean hasError) {
        String status = hasError ? "ERROR" : "Running";
        String subText = String.format("Port: %d | Devices: %d", port, deviceCount);
        
        Notification notification = createServiceNotification(message, subText, port);
        systemNotificationManager.notify(NOTIFICATION_SERVICE, notification);
        
        Log.d(TAG, "Service notification updated: " + message);
    }
    
    /**
     * Show a status notification (auto-dismiss)
     */
    public void showStatusNotification(String title, String message, boolean isSuccess) {
        int icon = isSuccess ? android.R.drawable.ic_dialog_info : android.R.drawable.ic_dialog_alert;
        int color = isSuccess ? 0xFF00AA00 : 0xFFFF6600;
        
        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_STATUS)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(icon)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setColor(color)
            .setContentIntent(createSettingsPendingIntent());
        
        systemNotificationManager.notify(NOTIFICATION_STATUS, builder.build());
        Log.d(TAG, "Status notification shown: " + title);
    }
    
    /**
     * Show an error notification
     */
    public void showErrorNotification(String title, String message) {
        showErrorNotification(title, message, null);
    }
    
    public void showErrorNotification(String title, String message, String bigText) {
        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ERROR)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setColor(0xFFFF0000)
            .setContentIntent(createSettingsPendingIntent());
        
        // Add expanded text if provided
        if (bigText != null) {
            builder.setStyle(new NotificationCompat.BigTextStyle().bigText(bigText));
        }
        
        systemNotificationManager.notify(NOTIFICATION_ERROR, builder.build());
        Log.e(TAG, "Error notification shown: " + title);
    }
    
    /**
     * Show device connection status notification
     */
    public void showDeviceNotification(String deviceName, boolean connected) {
        String title = connected ? "Device Connected" : "Device Disconnected";
        String message = connected ? 
            deviceName + " is ready for data collection" :
            deviceName + " has been disconnected";
        
        showStatusNotification(title, message, connected);
    }
    
    /**
     * Cancel a specific notification
     */
    public void cancelNotification(int notificationId) {
        systemNotificationManager.cancel(notificationId);
        Log.d(TAG, "Cancelled notification ID: " + notificationId);
    }
    
    /**
     * Cancel all notifications except the service notification
     */
    public void cancelStatusNotifications() {
        systemNotificationManager.cancel(NOTIFICATION_STATUS);
        systemNotificationManager.cancel(NOTIFICATION_ERROR);
        Log.d(TAG, "Status notifications cancelled");
    }
    
    // Helper methods for creating PendingIntents
    private PendingIntent createStopServicePendingIntent() {
        Intent stopIntent = new Intent(context, ServiceControlReceiver.class);
        stopIntent.setAction("STOP_SERVICE");
        
        return PendingIntent.getBroadcast(
            context, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }
    
    private PendingIntent createSettingsPendingIntent() {
        Intent settingsIntent = new Intent(context, SettingsActivity.class);
        settingsIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        
        return PendingIntent.getActivity(
            context, 0, settingsIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }
    
    /**
     * Create a notification for service startup issues
     */
    public void showStartupErrorNotification(String error) {
        showErrorNotification(
            "Service Startup Failed",
            "Snappy Web Agent failed to start",
            "Error details: " + error + "\n\nPlease check:\n" +
            "• USB device connections\n" +
            "• Available ports (8436-8535)\n" +
            "• System permissions\n\n" +
            "Try restarting the service or check logs."
        );
    }
    
    /**
     * Create a notification for USB permission issues
     */
    public void showUsbPermissionNotification() {
        showErrorNotification(
            "USB Permission Required",
            "Grant USB access to communicate with devices",
            "Snappy Web Agent needs permission to access USB devices.\n\n" +
            "Please:\n" +
            "1. Connect your Snappy device\n" +
            "2. Grant permission when prompted\n" +
            "3. Restart the service if needed"
        );
    }
    
    /**
     * Update notification with real-time statistics
     */
    public void updateWithStatistics(int port, int deviceCount, int activeConnections, long dataPackets) {
        String message = "Service running successfully";
        String bigText = String.format(
            "Socket.IO API: http://localhost:%d\n" +
            "Connected devices: %d\n" +
            "Active clients: %d\n" +
            "Data packets processed: %,d",
            port, deviceCount, activeConnections, dataPackets
        );
        
        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_SERVICE)
            .setContentTitle("Snappy Web Agent")
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(bigText))
            .setContentIntent(createSettingsPendingIntent())
            .addAction(android.R.drawable.ic_media_pause, "Stop", createStopServicePendingIntent())
            .addAction(android.R.drawable.ic_menu_preferences, "Settings", createSettingsPendingIntent());
        
        systemNotificationManager.notify(NOTIFICATION_SERVICE, builder.build());
    }
    
    /**
     * Show network information notification
     */
    public void showNetworkInfoNotification(String ipAddress, int port) {
        String title = "Network Access Available";
        String message = String.format("API accessible at http://%s:%d", ipAddress, port);
        String bigText = String.format(
            "Your Snappy Web Agent is accessible from other devices on your network.\n\n" +
            "Local URL: http://localhost:%d\n" +
            "Network URL: http://%s:%d\n\n" +
            "Use these URLs to connect client applications.",
            port, ipAddress, port
        );
        
        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_STATUS)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setColor(0xFF0099FF)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(bigText))
            .setContentIntent(createSettingsPendingIntent());
        
        systemNotificationManager.notify(NOTIFICATION_STATUS, builder.build());
    }
}