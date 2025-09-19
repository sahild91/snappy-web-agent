package com.yudurobotics.snappywebagent;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

/**
 * BroadcastReceiver for handling service control actions from notifications
 * and other components that need to start/stop/restart the Snappy Web Agent service
 */
public class ServiceControlReceiver extends BroadcastReceiver {
    private static final String TAG = "ServiceControlReceiver";
    
    public static final String ACTION_START_SERVICE = "com.yudurobotics.snappywebagent.START_SERVICE";
    public static final String ACTION_STOP_SERVICE = "com.yudurobotics.snappywebagent.STOP_SERVICE";
    public static final String ACTION_RESTART_SERVICE = "com.yudurobotics.snappywebagent.RESTART_SERVICE";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (action == null) {
            Log.w(TAG, "Received intent with null action");
            return;
        }

        Log.d(TAG, "Received service control action: " + action);

        switch (action) {
            case ACTION_START_SERVICE:
                startService(context);
                break;
                
            case ACTION_STOP_SERVICE:
                stopService(context);
                break;
                
            case ACTION_RESTART_SERVICE:
                restartService(context);
                break;
                
            // Support legacy action names for backward compatibility
            case "START_SERVICE":
                startService(context);
                break;
                
            case "STOP_SERVICE":
                stopService(context);
                break;
                
            case "RESTART_SERVICE":
                restartService(context);
                break;
                
            default:
                Log.w(TAG, "Unknown service control action: " + action);
        }
    }

    private void startService(Context context) {
        try {
            Intent serviceIntent = new Intent(context, SnappyWebAgentService.class);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent);
                Log.d(TAG, "Started foreground service");
            } else {
                context.startService(serviceIntent);
                Log.d(TAG, "Started service");
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Failed to start Snappy Web Agent service", e);
        }
    }

    private void stopService(Context context) {
        try {
            Intent serviceIntent = new Intent(context, SnappyWebAgentService.class);
            boolean stopped = context.stopService(serviceIntent);
            
            Log.d(TAG, "Service stop requested, result: " + stopped);
            
        } catch (Exception e) {
            Log.e(TAG, "Failed to stop Snappy Web Agent service", e);
        }
    }

    private void restartService(Context context) {
        try {
            Log.d(TAG, "Restarting Snappy Web Agent service");
            
            // Stop service first
            stopService(context);
            
            // Wait a moment before restarting to allow proper cleanup
            new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
                startService(context);
                Log.d(TAG, "Service restart sequence completed");
            }, 1500);
            
        } catch (Exception e) {
            Log.e(TAG, "Failed to restart Snappy Web Agent service", e);
        }
    }
}