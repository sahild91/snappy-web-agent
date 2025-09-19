package com.yudurobotics.snappywebagent;

import android.app.Activity;
import android.content.Intent;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Bundle;
import android.util.Log;

/**
 * Transparent activity to handle USB device attachment and permission requests
 */
public class UsbPermissionActivity extends Activity {
    private static final String TAG = "UsbPermissionActivity";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.d(TAG, "UsbPermissionActivity created");

        handleUsbDeviceAttached();
        
        // Close the activity immediately
        finish();
    }

    private void handleUsbDeviceAttached() {
        Intent intent = getIntent();
        if (intent == null) return;

        String action = intent.getAction();
        if (UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action)) {
            UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            if (device != null) {
                Log.d(TAG, "USB device attached: " + device.getProductName());
                
                // Start the service if it's not running
                Intent serviceIntent = new Intent(this, SnappyWebAgentService.class);
                startForegroundService(serviceIntent);
            }
        }
    }
}