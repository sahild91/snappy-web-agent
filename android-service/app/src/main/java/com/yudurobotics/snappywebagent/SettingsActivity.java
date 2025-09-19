package com.yudurobotics.snappywebagent;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Bundle;
import android.os.IBinder;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.leanback.app.BackgroundManager;
import java.util.Timer;
import java.util.TimerTask;

public class SettingsActivity extends AppCompatActivity {
    private static final String TAG = "SettingsActivity";
    
    // UI Components
    private TextView statusText;
    private TextView portText;
    private TextView deviceCountText;
    private TextView versionText;
    private Button startServiceButton;
    private Button stopServiceButton;
    private Switch autoStartSwitch;
    private View deviceStatusIndicator;
    
    // Service connection
    private SnappyWebAgentService boundService;
    private boolean isServiceBound = false;
    
    // Status update timer
    private Timer statusUpdateTimer;
    
    private final ServiceConnection serviceConnection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            // This service doesn't support binding, so this won't be called
            // We'll use direct static calls instead
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            boundService = null;
            isServiceBound = false;
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);
        
        Log.d(TAG, "Settings activity created");
        
        initializeViews();
        setupEventListeners();
        setupBackgroundManager();
        startStatusUpdates();
    }

    private void initializeViews() {
        statusText = findViewById(R.id.status_text);
        portText = findViewById(R.id.port_text);
        deviceCountText = findViewById(R.id.device_count_text);
        versionText = findViewById(R.id.version_text);
        startServiceButton = findViewById(R.id.start_service_button);
        stopServiceButton = findViewById(R.id.stop_service_button);
        autoStartSwitch = findViewById(R.id.auto_start_switch);
        deviceStatusIndicator = findViewById(R.id.device_status_indicator);
        
        // Set version
        versionText.setText("Version: " + BuildConfig.VERSION_NAME);
        
        // Load auto-start preference
        boolean autoStart = getSharedPreferences("snappy_prefs", MODE_PRIVATE)
            .getBoolean("auto_start", true);
        autoStartSwitch.setChecked(autoStart);
    }

    private void setupEventListeners() {
        startServiceButton.setOnClickListener(v -> startSnappyService());
        stopServiceButton.setOnClickListener(v -> stopSnappyService());
        
        autoStartSwitch.setOnCheckedChangeListener((buttonView, isChecked) -> {
            getSharedPreferences("snappy_prefs", MODE_PRIVATE)
                .edit()
                .putBoolean("auto_start", isChecked)
                .apply();
            
            String message = isChecked ? "Auto-start enabled" : "Auto-start disabled";
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
        });
        
        // Add test connection button listener
        Button testConnectionButton = findViewById(R.id.test_connection_button);
        testConnectionButton.setOnClickListener(v -> testConnection());
        
        // Add view logs button listener  
        Button viewLogsButton = findViewById(R.id.view_logs_button);
        viewLogsButton.setOnClickListener(v -> viewLogs());
    }

    private void setupBackgroundManager() {
        // Setup Android TV background (optional)
        BackgroundManager backgroundManager = BackgroundManager.getInstance(this);
        backgroundManager.attach(getWindow());
        // You can set a background image here if desired
    }

    private void startSnappyService() {
        Log.d(TAG, "Starting Snappy Web Agent service");
        
        try {
            Intent serviceIntent = new Intent(this, SnappyWebAgentService.class);
            startForegroundService(serviceIntent);
            
            Toast.makeText(this, "Starting Snappy Web Agent service...", Toast.LENGTH_SHORT).show();
            
            // Update UI after a short delay to allow service to start
            statusText.postDelayed(this::updateServiceStatus, 1000);
            
        } catch (Exception e) {
            Log.e(TAG, "Failed to start service", e);
            Toast.makeText(this, "Failed to start service: " + e.getMessage(), 
                         Toast.LENGTH_LONG).show();
        }
    }

    private void stopSnappyService() {
        Log.d(TAG, "Stopping Snappy Web Agent service");
        
        try {
            Intent serviceIntent = new Intent(this, SnappyWebAgentService.class);
            stopService(serviceIntent);
            
            Toast.makeText(this, "Stopping Snappy Web Agent service...", Toast.LENGTH_SHORT).show();
            
            // Update UI after a short delay
            statusText.postDelayed(this::updateServiceStatus, 1000);
            
        } catch (Exception e) {
            Log.e(TAG, "Failed to stop service", e);
            Toast.makeText(this, "Failed to stop service: " + e.getMessage(), 
                         Toast.LENGTH_LONG).show();
        }
    }

    private void testConnection() {
        Log.d(TAG, "Testing Socket.IO connection");
        
        // This would typically use Socket.IO client to test connection
        // For now, just show current service status
        
        if (isServiceRunning()) {
            int port = getCurrentServicePort();
            if (port > 0) {
                String message = String.format("Service is running on port %d\nTest your connection at:\nhttp://localhost:%d", port, port);
                Toast.makeText(this, message, Toast.LENGTH_LONG).show();
            } else {
                Toast.makeText(this, "Service is running but port unknown", Toast.LENGTH_SHORT).show();
            }
        } else {
            Toast.makeText(this, "Service is not running", Toast.LENGTH_SHORT).show();
        }
    }

    private void viewLogs() {
        // Launch log viewer activity or show logs
        // For now, show a simple message
        Toast.makeText(this, "Use 'adb logcat -s SnappyWebAgent' to view logs", Toast.LENGTH_LONG).show();
    }

    private void startStatusUpdates() {
        statusUpdateTimer = new Timer();
        statusUpdateTimer.schedule(new TimerTask() {
            @Override
            public void run() {
                runOnUiThread(() -> updateServiceStatus());
            }
        }, 0, 2000); // Update every 2 seconds
    }

    private void stopStatusUpdates() {
        if (statusUpdateTimer != null) {
            statusUpdateTimer.cancel();
            statusUpdateTimer = null;
        }
    }

    private void updateServiceStatus() {
        try {
            boolean isRunning = isServiceRunning();
            int port = getCurrentServicePort();
            int deviceCount = getConnectedDeviceCount();
            boolean hasDevice = hasConnectedDevice();
            
            // Update status text and color
            if (isRunning) {
                statusText.setText("Service Status: RUNNING");
                statusText.setTextColor(getResources().getColor(android.R.color.holo_green_dark));
                startServiceButton.setEnabled(false);
                stopServiceButton.setEnabled(true);
            } else {
                statusText.setText("Service Status: STOPPED");
                statusText.setTextColor(getResources().getColor(android.R.color.holo_red_dark));
                startServiceButton.setEnabled(true);
                stopServiceButton.setEnabled(false);
            }
            
            // Update port info
            if (port > 0) {
                portText.setText("Port: " + port);
                portText.setVisibility(View.VISIBLE);
            } else {
                portText.setText("Port: Not available");
                portText.setVisibility(View.VISIBLE);
            }
            
            // Update device count
            deviceCountText.setText("Connected Devices: " + deviceCount);
            
            // Update device indicator
            if (hasDevice) {
                deviceStatusIndicator.setBackgroundColor(
                    getResources().getColor(android.R.color.holo_green_dark));
            } else {
                deviceStatusIndicator.setBackgroundColor(
                    getResources().getColor(android.R.color.holo_red_dark));
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error updating service status", e);
            statusText.setText("Service Status: ERROR");
            statusText.setTextColor(getResources().getColor(android.R.color.holo_red_dark));
        }
    }

    // Helper methods to check service status via JNI
    private boolean isServiceRunning() {
        try {
            // We need a way to get the current service handle
            // For now, check if the service process is running
            return isSnappyServiceProcessRunning();
        } catch (Exception e) {
            Log.e(TAG, "Error checking service status", e);
            return false;
        }
    }

    private int getCurrentServicePort() {
        try {
            // This would call the native method if we had a service handle
            // For now, return -1 to indicate unknown
            return -1;
        } catch (Exception e) {
            Log.e(TAG, "Error getting service port", e);
            return -1;
        }
    }

    private int getConnectedDeviceCount() {
        try {
            // This would call the native method if we had a service handle
            // For now, return 0
            return 0;
        } catch (Exception e) {
            Log.e(TAG, "Error getting device count", e);
            return 0;
        }
    }

    private boolean hasConnectedDevice() {
        return getConnectedDeviceCount() > 0;
    }

    // Check if Snappy service process is running (alternative to JNI handle)
    private boolean isSnappyServiceProcessRunning() {
        try {
            // Check if our service is in the running services
            android.app.ActivityManager am = (android.app.ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
            for (android.app.ActivityManager.RunningServiceInfo service : am.getRunningServices(Integer.MAX_VALUE)) {
                if (SnappyWebAgentService.class.getName().equals(service.service.getClassName())) {
                    return true;
                }
            }
            return false;
        } catch (Exception e) {
            Log.e(TAG, "Error checking running services", e);
            return false;
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        Log.d(TAG, "Settings activity resumed");
        updateServiceStatus();
    }

    @Override
    protected void onPause() {
        super.onPause();
        Log.d(TAG, "Settings activity paused");
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        Log.d(TAG, "Settings activity destroyed");
        
        stopStatusUpdates();
        
        if (isServiceBound) {
            unbindService(serviceConnection);
            isServiceBound = false;
        }
    }

    @Override
    public void onBackPressed() {
        // On Android TV, back button behavior
        super.onBackPressed();
    }

    // Handle Android TV D-pad navigation
    @Override
    public boolean dispatchKeyEvent(android.view.KeyEvent event) {
        // Handle D-pad navigation for Android TV
        return super.dispatchKeyEvent(event);
    }
}