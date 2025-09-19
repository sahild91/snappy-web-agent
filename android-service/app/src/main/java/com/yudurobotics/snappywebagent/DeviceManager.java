package com.yudurobotics.snappywebagent;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.util.Log;
import java.util.HashMap;
import java.util.concurrent.ConcurrentHashMap;

public class DeviceManager {
    private static final String TAG = "DeviceManager";
    private static final String ACTION_USB_PERMISSION = "com.yudurobotics.snappywebagent.USB_PERMISSION";
    
    // Target device VID/PIDs (from Rust models.rs)
    private static final int TARGET_VID = 0xb1b0;
    private static final int[] TARGET_PIDS = {0x5508, 0x8055};
    
    private final Context context;
    private final SnappyWebAgentService service;
    private final long nativeHandle;
    private final UsbManager usbManager;
    
    private boolean isMonitoring = false;
    private final ConcurrentHashMap<String, UsbDeviceConnection> activeConnections = 
        new ConcurrentHashMap<>();
    
    private final BroadcastReceiver usbReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            
            if (ACTION_USB_PERMISSION.equals(action)) {
                handleUsbPermissionResult(intent);
            } else if (UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action)) {
                UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                if (device != null && isTargetDevice(device)) {
                    Log.d(TAG, "Target USB device attached: " + device.getProductName());
                    requestPermissionAndConnect(device);
                }
            } else if (UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)) {
                UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                if (device != null && isTargetDevice(device)) {
                    Log.d(TAG, "Target USB device detached: " + device.getProductName());
                    handleDeviceDetached(device);
                }
            }
        }
    };

    public DeviceManager(SnappyWebAgentService service, long nativeHandle) {
        this.service = service;
        this.context = service.getApplicationContext();
        this.nativeHandle = nativeHandle;
        this.usbManager = (UsbManager) context.getSystemService(Context.USB_SERVICE);
    }

    public void startMonitoring() {
        if (isMonitoring) return;
        
        Log.d(TAG, "Starting USB device monitoring");
        
        // Register broadcast receiver for USB events
        IntentFilter filter = new IntentFilter();
        filter.addAction(ACTION_USB_PERMISSION);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        context.registerReceiver(usbReceiver, filter);
        
        isMonitoring = true;
        
        // Check for already connected target devices
        scanForExistingDevices();
    }

    public void stopMonitoring() {
        if (!isMonitoring) return;
        
        Log.d(TAG, "Stopping USB device monitoring");
        
        try {
            context.unregisterReceiver(usbReceiver);
        } catch (IllegalArgumentException e) {
            Log.w(TAG, "Receiver was not registered: " + e.getMessage());
        }
        
        // Close all active connections
        for (UsbDeviceConnection connection : activeConnections.values()) {
            connection.close();
        }
        activeConnections.clear();
        
        isMonitoring = false;
    }

    private void scanForExistingDevices() {
        Log.d(TAG, "Scanning for existing target devices");
        
        HashMap<String, UsbDevice> deviceList = usbManager.getDeviceList();
        for (UsbDevice device : deviceList.values()) {
            if (isTargetDevice(device)) {
                Log.d(TAG, "Found existing target device: " + device.getProductName());
                requestPermissionAndConnect(device);
            }
        }
    }

    private boolean isTargetDevice(UsbDevice device) {
        if (device.getVendorId() != TARGET_VID) {
            return false;
        }
        
        int productId = device.getProductId();
        for (int targetPid : TARGET_PIDS) {
            if (productId == targetPid) {
                return true;
            }
        }
        
        return false;
    }

    private void requestPermissionAndConnect(UsbDevice device) {
        if (usbManager.hasPermission(device)) {
            Log.d(TAG, "Already have permission for device: " + device.getProductName());
            connectToDevice(device);
        } else {
            Log.d(TAG, "Requesting permission for device: " + device.getProductName());
            PendingIntent permissionIntent = PendingIntent.getBroadcast(
                context, 0, 
                new Intent(ACTION_USB_PERMISSION), 
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE
            );
            usbManager.requestPermission(device, permissionIntent);
        }
    }

    private void handleUsbPermissionResult(Intent intent) {
        UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
        if (device == null) return;

        if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
            Log.d(TAG, "USB permission granted for device: " + device.getProductName());
            connectToDevice(device);
        } else {
            Log.w(TAG, "USB permission denied for device: " + device.getProductName());
        }
    }

    private void connectToDevice(UsbDevice device) {
        Log.d(TAG, "Attempting to connect to device: " + device.getProductName());
        
        UsbDeviceConnection connection = usbManager.openDevice(device);
        if (connection == null) {
            Log.e(TAG, "Failed to open USB device connection");
            return;
        }

        // Store the connection
        String deviceKey = getDeviceKey(device);
        activeConnections.put(deviceKey, connection);
        
        // Get file descriptor for native code
        int fileDescriptor = connection.getFileDescriptor();
        String serialNumber = device.getSerialNumber();
        if (serialNumber == null) {
            serialNumber = "unknown";
        }
        
        Log.d(TAG, String.format("Connected to device - VID: 0x%04x, PID: 0x%04x, Serial: %s, FD: %d", 
                                device.getVendorId(), device.getProductId(), serialNumber, fileDescriptor));
        
        // Pass device info to native code
        SnappyWebAgentService.nativeSetUsbDevice(
            nativeHandle, 
            fileDescriptor, 
            device.getVendorId(), 
            device.getProductId(), 
            serialNumber
        );
        
        // Notify service of device connection
        service.onUsbDeviceStatusChanged(device, true);
    }

    private void handleDeviceDetached(UsbDevice device) {
        String deviceKey = getDeviceKey(device);
        UsbDeviceConnection connection = activeConnections.remove(deviceKey);
        
        if (connection != null) {
            connection.close();
            Log.d(TAG, "Closed connection for detached device: " + device.getProductName());
        }
        
        // Notify native code that device was removed
        SnappyWebAgentService.nativeRemoveUsbDevice(nativeHandle);
        
        // Notify service of device disconnection
        service.onUsbDeviceStatusChanged(device, false);
    }

    private String getDeviceKey(UsbDevice device) {
        return String.format("%04x:%04x:%s", 
                           device.getVendorId(), 
                           device.getProductId(), 
                           device.getSerialNumber());
    }

    // Public method to get current device status
    public boolean isDeviceConnected() {
        return !activeConnections.isEmpty();
    }
    
    public int getConnectedDeviceCount() {
        return activeConnections.size();
    }
}