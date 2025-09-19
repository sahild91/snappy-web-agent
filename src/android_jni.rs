use jni::objects::{JClass, JString};
use jni::sys::{jlong, jint, jboolean};
use jni::JNIEnv;
use std::sync::{Arc, Mutex};
use std::os::unix::io::RawFd;
use tracing::{info, error, warn};
use tokio::runtime::Runtime;
use crate::{start_server, find_available_port};
use std::collections::HashMap;

// Android service state
pub struct AndroidServiceState {
    pub runtime: Runtime,
    pub server_handle: Option<tokio::task::JoinHandle<()>>,
    pub current_port: Option<u16>,
    pub usb_device_fd: Option<RawFd>,
    pub device_info: Option<AndroidUsbDevice>,
    pub is_running: bool,
    pub connected_devices: HashMap<String, AndroidUsbDevice>,
}

#[derive(Debug, Clone)]
pub struct AndroidUsbDevice {
    pub vendor_id: u16,
    pub product_id: u16,
    pub serial_number: String,
    pub file_descriptor: RawFd,
}

impl AndroidServiceState {
    pub fn new() -> Result<Self, String> {
        let runtime = Runtime::new().map_err(|e| format!("Failed to create Tokio runtime: {}", e))?;
        
        Ok(AndroidServiceState {
            runtime,
            server_handle: None,
            current_port: None,
            usb_device_fd: None,
            device_info: None,
            is_running: false,
            connected_devices: HashMap::new(),
        })
    }
    
    pub fn add_device(&mut self, device: AndroidUsbDevice) {
        let key = format!("{}:{}", device.vendor_id, device.product_id);
        self.connected_devices.insert(key, device.clone());
        
        // Set as primary device if none exists
        if self.device_info.is_none() {
            self.device_info = Some(device.clone());
            self.usb_device_fd = Some(device.file_descriptor);
        }
    }
    
    pub fn remove_device(&mut self, vendor_id: u16, product_id: u16) -> bool {
        let key = format!("{}:{}", vendor_id, product_id);
        let removed = self.connected_devices.remove(&key).is_some();
        
        // Clear primary device if it was removed
        if let Some(ref device) = self.device_info {
            if device.vendor_id == vendor_id && device.product_id == product_id {
                self.device_info = None;
                self.usb_device_fd = None;
                
                // Set another device as primary if available
                if let Some(new_device) = self.connected_devices.values().next() {
                    self.device_info = Some(new_device.clone());
                    self.usb_device_fd = Some(new_device.file_descriptor);
                }
            }
        }
        
        removed
    }
    
    pub fn get_device_count(&self) -> usize {
        self.connected_devices.len()
    }
}

// Global service state (boxed to get stable pointer)
type ServiceState = Arc<Mutex<AndroidServiceState>>;

// Convert raw pointer back to ServiceState
unsafe fn handle_to_state(handle: jlong) -> ServiceState {
    Arc::from_raw(handle as *const Mutex<AndroidServiceState>)
}

// Convert ServiceState to raw pointer
fn state_to_handle(state: ServiceState) -> jlong {
    Arc::into_raw(state) as *const _ as jlong
}

// Global state for accessing from other modules
static mut GLOBAL_SERVICE_STATE: Option<ServiceState> = None;
static GLOBAL_STATE_INIT: std::sync::Once = std::sync::Once::new();

// Get global service state (for use by serial.rs and other modules)
pub fn get_android_service_state() -> Option<ServiceState> {
    unsafe {
        GLOBAL_SERVICE_STATE.as_ref().map(|state| state.clone())
    }
}

// Set global service state
fn set_global_service_state(state: ServiceState) {
    unsafe {
        GLOBAL_SERVICE_STATE = Some(state);
    }
}

#[no_mangle]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeInit(
    env: JNIEnv,
    _class: JClass,
) -> jlong {
    // Initialize Android logging
    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::Debug)
            .with_tag("SnappyWebAgent")
    );

    info!("Initializing Android Snappy Web Agent service");

    match AndroidServiceState::new() {
        Ok(state) => {
            let service_state = Arc::new(Mutex::new(state));
            let handle = state_to_handle(service_state.clone());
            
            // Set global state for access from other modules
            GLOBAL_STATE_INIT.call_once(|| {
                set_global_service_state(service_state.clone());
            });
            
            info!("Android service initialized successfully, handle: {}", handle);
            handle
        }
        Err(e) => {
            error!("Failed to initialize Android service: {}", e);
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeStart(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    info!("Starting Android service, handle: {}", handle);

    if handle == 0 {
        error!("Invalid service handle");
        return;
    }

    let state = unsafe { handle_to_state(handle) };
    let mut service_state = match state.lock() {
        Ok(guard) => guard,
        Err(e) => {
            error!("Failed to lock service state: {}", e);
            return;
        }
    };

    if service_state.is_running {
        info!("Service is already running");
        return;
    }

    info!("Starting Android server with port discovery...");
    
    // Clone the state Arc for the async task
    let state_for_task = state.clone();
    
    // Start the server in the background
    let server_handle = service_state.runtime.spawn(async move {
        match find_available_port(8436, 100).await {
            Ok(port) => {
                info!("Found available port: {}, starting Android server", port);
                
                // Update the port in the state
                if let Ok(mut state_guard) = state_for_task.lock() {
                    state_guard.current_port = Some(port);
                }
                
                start_android_server(port).await;
            }
            Err(e) => {
                error!("Failed to find available port: {}", e);
            }
        }
    });

    service_state.server_handle = Some(server_handle);
    service_state.is_running = true;
    
    // Leak the Arc to keep the state alive
    std::mem::forget(state);
    
    info!("Android service started successfully");
}

#[no_mangle]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeStop(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    info!("Stopping Android service, handle: {}", handle);

    if handle == 0 {
        error!("Invalid service handle");
        return;
    }

    let state = unsafe { handle_to_state(handle) };
    let mut service_state = match state.lock() {
        Ok(guard) => guard,
        Err(e) => {
            error!("Failed to lock service state: {}", e);
            return;
        }
    };

    if !service_state.is_running {
        info!("Service is not running");
        return;
    }

    // Stop the server
    if let Some(handle) = service_state.server_handle.take() {
        handle.abort();
    }

    service_state.is_running = false;
    service_state.current_port = None;
    
    // Leak the Arc to keep the state alive
    std::mem::forget(state);
    
    info!("Android service stopped");
}

#[no_mangle]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeDestroy(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    info!("Destroying Android service, handle: {}", handle);

    if handle == 0 {
        error!("Invalid service handle");
        return;
    }

    let state = unsafe { handle_to_state(handle) };
    
    // Stop the service first
    {
        let mut service_state = match state.lock() {
            Ok(guard) => guard,
            Err(e) => {
                error!("Failed to lock service state for destruction: {}", e);
                return;
            }
        };

        if let Some(handle) = service_state.server_handle.take() {
            handle.abort();
        }

        service_state.is_running = false;
        service_state.connected_devices.clear();
        service_state.device_info = None;
        service_state.usb_device_fd = None;
    }
    
    // Clear global state
    unsafe {
        GLOBAL_SERVICE_STATE = None;
    }
    
    // Don't forget the Arc here - let it drop naturally
    info!("Android service destroyed");
}

#[no_mangle]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeSetUsbDevice(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
    file_descriptor: jint,
    vendor_id: jint,
    product_id: jint,
    serial_number: JString,
) {
    info!("Setting USB device - FD: {}, VID: 0x{:04x}, PID: 0x{:04x}", 
          file_descriptor, vendor_id, product_id);

    if handle == 0 {
        error!("Invalid service handle");
        return;
    }

    let serial_str = match env.get_string(serial_number) {
        Ok(s) => s.into(),
        Err(e) => {
            error!("Failed to convert serial number string: {}", e);
            "unknown".to_string()
        }
    };

    let state = unsafe { handle_to_state(handle) };
    let mut service_state = match state.lock() {
        Ok(guard) => guard,
        Err(e) => {
            error!("Failed to lock service state: {}", e);
            return;
        }
    };

    let device_info = AndroidUsbDevice {
        vendor_id: vendor_id as u16,
        product_id: product_id as u16,
        serial_number: serial_str.clone(),
        file_descriptor: file_descriptor,
    };

    service_state.add_device(device_info);
    
    // Leak the Arc to keep the state alive
    std::mem::forget(state);

    info!("USB device added - Serial: {}, Total devices: {}", 
          serial_str, service_state.get_device_count());
}

#[no_mangle]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeRemoveUsbDevice(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    info!("Removing USB device");

    if handle == 0 {
        error!("Invalid service handle");
        return;
    }

    let state = unsafe { handle_to_state(handle) };
    let mut service_state = match state.lock() {
        Ok(guard) => guard,
        Err(e) => {
            error!("Failed to lock service state: {}", e);
            return;
        }
    };

    // For now, remove the primary device
    // In future versions, could specify which device to remove
    if let Some(device) = service_state.device_info.as_ref() {
        let vendor_id = device.vendor_id;
        let product_id = device.product_id;
        let removed = service_state.remove_device(vendor_id, product_id);
        
        if removed {
            info!("USB device removed - VID: 0x{:04x}, PID: 0x{:04x}, Remaining: {}", 
                  vendor_id, product_id, service_state.get_device_count());
        } else {
            warn!("Attempted to remove device that wasn't found");
        }
    } else {
        warn!("No USB device to remove");
    }
    
    // Leak the Arc to keep the state alive
    std::mem::forget(state);
}

#[no_mangle]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeIsRunning(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jboolean {
    if handle == 0 {
        return 0; // false
    }

    let state = unsafe { handle_to_state(handle) };
    let is_running = match state.lock() {
        Ok(service_state) => service_state.is_running,
        Err(_) => false,
    };
    
    // Leak the Arc to keep the state alive
    std::mem::forget(state);

    if is_running { 1 } else { 0 }
}

#[no_mangle]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeGetPort(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jint {
    if handle == 0 {
        return -1;
    }

    let state = unsafe { handle_to_state(handle) };
    let port = match state.lock() {
        Ok(service_state) => service_state.current_port.map(|p| p as jint).unwrap_or(-1),
        Err(_) => -1,
    };
    
    // Leak the Arc to keep the state alive
    std::mem::forget(state);

    port
}

#[no_mangle]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeGetDeviceCount(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jint {
    if handle == 0 {
        return 0;
    }

    let state = unsafe { handle_to_state(handle) };
    let count = match state.lock() {
        Ok(service_state) => service_state.get_device_count() as jint,
        Err(_) => 0,
    };
    
    // Leak the Arc to keep the state alive
    std::mem::forget(state);

    count
}

#[no_mangle]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeHasDevice(
    env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jboolean {
    if handle == 0 {
        return 0;
    }

    let state = unsafe { handle_to_state(handle) };
    let has_device = match state.lock() {
        Ok(service_state) => service_state.device_info.is_some(),
        Err(_) => false,
    };
    
    // Leak the Arc to keep the state alive
    std::mem::forget(state);

    if has_device { 1 } else { 0 }
}

// Android-specific server implementation
async fn start_android_server(port: u16) {
    use axum::routing::get;
    use socketioxide::SocketIo;
    use tower_http::cors::{CorsLayer, Any};
    use crate::socketio;

    info!("Starting Android server on port {}", port);

    let (socketio_layer, io) = SocketIo::new_layer();
    io.ns("/", socketio::on_connect);
    
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);
    
    let app = axum::Router::new()
        .route("/", get(|| async { "Snappy Web Agent - Android Service" }))
        .route("/health", get(|| async { "OK" }))
        .route("/status", get(get_service_status))
        .layer(socketio_layer)
        .layer(cors);

    let addr = format!("0.0.0.0:{}", port);
    
    match tokio::net::TcpListener::bind(&addr).await {
        Ok(listener) => {
            info!("Android server listening on {}", addr);
            if let Err(e) = axum::serve(listener, app).await {
                error!("Android server error: {}", e);
            }
        }
        Err(e) => {
            error!("Failed to bind Android server to {}: {}", addr, e);
        }
    }
}

// HTTP endpoint to get service status
async fn get_service_status() -> String {
    if let Some(state) = get_android_service_state() {
        if let Ok(service_state) = state.lock() {
            let status = serde_json::json!({
                "running": service_state.is_running,
                "port": service_state.current_port,
                "device_count": service_state.get_device_count(),
                "has_device": service_state.device_info.is_some(),
                "version": env!("CARGO_PKG_VERSION")
            });
            return status.to_string();
        }
    }
    
    serde_json::json!({
        "running": false,
        "port": null,
        "device_count": 0,
        "has_device": false,
        "version": env!("CARGO_PKG_VERSION")
    }).to_string()
}

// Android-specific USB device access functions for use by serial.rs
pub fn get_android_usb_device() -> Option<AndroidUsbDevice> {
    if let Some(state) = get_android_service_state() {
        if let Ok(service_state) = state.lock() {
            return service_state.device_info.clone();
        }
    }
    None
}

pub fn get_android_usb_devices() -> Vec<AndroidUsbDevice> {
    if let Some(state) = get_android_service_state() {
        if let Ok(service_state) = state.lock() {
            return service_state.connected_devices.values().cloned().collect();
        }
    }
    Vec::new()
}

pub fn is_android_device_connected() -> bool {
    if let Some(state) = get_android_service_state() {
        if let Ok(service_state) = state.lock() {
            return service_state.device_info.is_some();
        }
    }
    false
}

// Helper function to setup Android logging
pub fn init_android_logging() {
    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::Info)
            .with_tag("SnappyWebAgent")
    );
}

// JNI utility functions
pub fn log_jni_error(env: &JNIEnv, message: &str) {
    if let Ok(exception) = env.exception_check() {
        if exception {
            if let Err(e) = env.exception_describe() {
                error!("Failed to describe JNI exception: {}", e);
            }
            if let Err(e) = env.exception_clear() {
                error!("Failed to clear JNI exception: {}", e);
            }
        }
    }
    error!("JNI Error: {}", message);
}

// Android-specific serial port operations (to be used by serial.rs)
#[cfg(any(target_os = "android", feature = "android"))]
pub mod android_serial {
    use super::*;
    use std::os::unix::io::{AsRawFd, RawFd};
    use std::fs::File;
    
    pub struct AndroidSerialPort {
        pub file: File,
        pub device_info: AndroidUsbDevice,
    }
    
    impl AndroidSerialPort {
        pub fn from_android_device(device: AndroidUsbDevice) -> Result<Self, String> {
            // Create File from the file descriptor passed from Java
            let file = unsafe {
                std::os::unix::io::FromRawFd::from_raw_fd(device.file_descriptor)
            };
            
            Ok(AndroidSerialPort {
                file,
                device_info: device,
            })
        }
    }
    
    impl AsRawFd for AndroidSerialPort {
        fn as_raw_fd(&self) -> RawFd {
            self.file.as_raw_fd()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_android_service_state_creation() {
        let state = AndroidServiceState::new().expect("Should create state");
        assert!(!state.is_running);
        assert_eq!(state.get_device_count(), 0);
        assert!(state.device_info.is_none());
    }
    
    #[test]
    fn test_device_management() {
        let mut state = AndroidServiceState::new().expect("Should create state");
        
        let device1 = AndroidUsbDevice {
            vendor_id: 0xb1b0,
            product_id: 0x5508,
            serial_number: "test123".to_string(),
            file_descriptor: 10,
        };
        
        let device2 = AndroidUsbDevice {
            vendor_id: 0xb1b0,
            product_id: 0x8055,
            serial_number: "test456".to_string(),
            file_descriptor: 11,
        };
        
        // Add devices
        state.add_device(device1.clone());
        assert_eq!(state.get_device_count(), 1);
        assert!(state.device_info.is_some());
        
        state.add_device(device2.clone());
        assert_eq!(state.get_device_count(), 2);
        
        // Remove device
        let removed = state.remove_device(0xb1b0, 0x5508);
        assert!(removed);
        assert_eq!(state.get_device_count(), 1);
        
        // Primary device should switch to the remaining device
        assert!(state.device_info.is_some());
        assert_eq!(state.device_info.as_ref().unwrap().product_id, 0x8055);
    }
}