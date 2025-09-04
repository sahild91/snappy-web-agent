use serde_json::Value;
use socketioxide::{ extract::{ AckSender, Data, SocketRef } };
use tracing::info;
use std::sync::{ Arc, Mutex };
use std::sync::atomic::{ AtomicBool, Ordering };
use chrono::Utc;
use crate::{ models::*, serial };

// Global state for controlling data collection
static SNAPPY_COLLECTING: AtomicBool = AtomicBool::new(false);

// Use a thread-safe approach instead of unsafe
static SNAPPY_SOCKET: std::sync::OnceLock<Arc<Mutex<Option<SocketRef>>>> = std::sync::OnceLock::new();

// Function to check if snappy is collecting data
pub fn is_snappy_collecting() -> bool {
    SNAPPY_COLLECTING.load(Ordering::Relaxed)
}

// Enhanced function to emit snap data with PID information
pub fn emit_snap_data(mac: String, value: u16, pid: u16) {
    let socket_ref = SNAPPY_SOCKET.get_or_init(|| Arc::new(Mutex::new(None)));
    if let Ok(socket_guard) = socket_ref.lock() {
        if let Some(ref socket) = *socket_guard {
            let timestamp = Utc::now().to_rfc3339();

            let snap_data = SnapDataEvent {
                mac,
                value,
                timestamp,
                pid, // Include PID in the data
            };

            let _ = socket.emit("snappy-data", &snap_data);
        }
    }
}

pub async fn on_connect(socket: SocketRef, Data(_data): Data<Value>) {
    info!(ns = socket.ns(), ?socket.id, "Socket.IO connected");
    check_port_connection(socket.clone());
    
    socket.on("version", |ack: AckSender| {
        let version = env!("CARGO_PKG_VERSION");
        let serial_response = SerialResponse {
            success: true,
            message: version.to_string(),
            command: "version".to_string(),
            error: None,
        };
        ack.send(&serial_response).ok();
    });

    // Enhanced device info command to show supported PIDs
    socket.on("device-info", |ack: AckSender| {
        let supported_pids: Vec<String> = PIDS.iter()
            .map(|&pid| format!("0x{:04x}", pid))
            .collect();
        
        let device_info = format!(
            "VID: 0x{:04x}, Supported PIDs: [{}]", 
            VID, 
            supported_pids.join(", ")
        );
        
        let serial_response = SerialResponse {
            success: true,
            message: device_info,
            command: "device-info".to_string(),
            error: None,
        };
        ack.send(&serial_response).ok();
    });
    
    let socket_for_start = socket.clone();
    socket.on("start-snappy", move |ack: AckSender| {
        info!("Starting snappy data collection for all supported devices");
        SNAPPY_COLLECTING.store(true, Ordering::Relaxed);

        // Store socket reference for data emission
        let socket_ref = SNAPPY_SOCKET.get_or_init(|| Arc::new(Mutex::new(None)));
        if let Ok(mut socket_guard) = socket_ref.lock() {
            *socket_guard = Some(socket_for_start.clone());
        }

        // Start the data collection task
        let socket_ref = socket_for_start.clone();
        tokio::spawn(async move {
            serial::start_snappy_with_socket(socket_ref).await;
        });

        let serial_response = SerialResponse {
            success: true,
            message: format!("Snappy data collection started for PIDs: {:?}", 
                           PIDS.iter().map(|&p| format!("0x{:04x}", p)).collect::<Vec<_>>()),
            command: "start-snappy".to_string(),
            error: None,
        };
        let _ = ack.send(&serial_response);
    });

    socket.on("stop-snappy", move |ack: AckSender| {
        info!("Stopping snappy data collection");
        SNAPPY_COLLECTING.store(false, Ordering::Relaxed);

        // Clear socket reference
        let socket_ref = SNAPPY_SOCKET.get_or_init(|| Arc::new(Mutex::new(None)));
        if let Ok(mut socket_guard) = socket_ref.lock() {
            *socket_guard = None;
        }

        let serial_response = SerialResponse {
            success: true,
            message: "Snappy data collection stopped for all devices".to_string(),
            command: "stop-snappy".to_string(),
            error: None,
        };
        let _ = ack.send(&serial_response);
    });
}

fn check_port_connection(socket: SocketRef) {
    tokio::spawn(async move {
        let mut last_status = None;
        let mut last_connected_pid: Option<u16> = None;
        
        loop {
            // Check if any of our supported devices is connected
            let status = Some(serial::is_any_device_connected(VID, PIDS));
            let connected_device_info = serial::find_connected_device_info(VID, PIDS);
            let current_pid = connected_device_info.as_ref().map(|(pid, _)| *pid);
            
            // Emit status if connection status changed or if different device connected
            if status != last_status || current_pid != last_connected_pid {
                let event_response = if let Some((pid, device_name)) = &connected_device_info {
                    EventResponse {
                        event: "device-connection".to_string(),
                        status: format!("true,pid:0x{:04x},device:{}", *pid, device_name),
                    }
                } else {
                    EventResponse {
                        event: "device-connection".to_string(),
                        status: "false".to_string(),
                    }
                };
                
                socket.emit("device-connected", &event_response).ok();
                last_status = status;
                last_connected_pid = current_pid;
            }
            
            tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
        }
    });
}