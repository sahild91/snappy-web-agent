package com.yudurobotics.snappywebagent;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "BootReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        Log.d(TAG, "Received broadcast: " + action);

        if (Intent.ACTION_BOOT_COMPLETED.equals(action) ||
            Intent.ACTION_MY_PACKAGE_REPLACED.equals(action) ||
            Intent.ACTION_PACKAGE_REPLACED.equals(action)) {
            
            Log.d(TAG, "System boot completed or package updated - starting Snappy Web Agent service");
            startSnappyWebAgentService(context);
        }
    }

    private void startSnappyWebAgentService(Context context) {
        try {
            Intent serviceIntent = new Intent(context, SnappyWebAgentService.class);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Android 8.0+ requires startForegroundService
                context.startForegroundService(serviceIntent);
                Log.d(TAG, "Started foreground service via startForegroundService()");
            } else {
                // Pre Android 8.0
                context.startService(serviceIntent);
                Log.d(TAG, "Started service via startService()");
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to start Snappy Web Agent service: " + e.getMessage(), e);
        }
    }
}