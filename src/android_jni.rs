// Android JNI bindings for Snappy Web Agent
// This module provides JNI functions for Android service integration

use jni::objects::{JClass, JString};
use jni::sys::{jboolean, jint, jlong};
use jni::JNIEnv;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::task::JoinHandle;
use crate::find_available_port;
use tracing::{info, warn, error};

#[cfg(feature = "android")]
use android_logger;

// Android USB device structure
#[derive(Debug, Clone)]
pub struct AndroidUsbDevice {
    pub file_descriptor: i32,
    pub vendor_id: u16,
    pub product_id: u16,
    pub serial_number: String,
}

// Android service state
#[derive(Debug)]
pub struct AndroidServiceState {
    pub is_running: bool,
    pub current_port: Option<u16>,
    pub runtime: tokio::runtime::Runtime,
    pub server_handle: Option<JoinHandle<()>>,
    pub connected_devices: HashMap<String, AndroidUsbDevice>,
    pub device_info: Option<AndroidUsbDevice>,
    pub usb_device_fd: Option<i32>,
}

impl AndroidServiceState {
    pub fn new() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let runtime = tokio::runtime::Runtime::new()?;
        
        Ok(AndroidServiceState {
            is_running: false,
            current_port: None,
            runtime,
            server_handle: None,
            connected_devices: HashMap::new(),
            device_info: None,
            usb_device_fd: None,
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

// Global service state
type ServiceState = Arc<Mutex<AndroidServiceState>>;

// Helper function to safely clone Arc from raw pointer
unsafe fn handle_to_state_clone(handle: jlong) -> ServiceState {
    let ptr = handle as *const Mutex<AndroidServiceState>;
    let arc = Arc::from_raw(ptr);
    let cloned = arc.clone();
    std::mem::forget(arc); // Don't drop the original
    cloned
}

// Convert ServiceState to raw pointer
fn state_to_handle(state: ServiceState) -> jlong {
    Arc::into_raw(state) as *const _ as jlong
}

// Global state for accessing from other modules
static mut GLOBAL_SERVICE_STATE: Option<ServiceState> = None;

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

#[unsafe(no_mangle)]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeInit(
    _env: JNIEnv,
    _class: JClass,
) -> jlong {
    // Initialize Android logging
    #[cfg(feature = "android")]
    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::Debug)
            .with_tag("SnappyWebAgent")
    );

    info!("Initializing Android service");

    let service_state = match AndroidServiceState::new() {
        Ok(state) => state,
        Err(e) => {
            error!("Failed to create service state: {}", e);
            return 0;
        }
    };

    let state = Arc::new(Mutex::new(service_state));
    set_global_service_state(state.clone());
    
    let handle = state_to_handle(state);
    info!("Android service initialized, handle: {}", handle);
    handle
}

#[unsafe(no_mangle)]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeStart(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    info!("Starting Android service, handle: {}", handle);

    if handle == 0 {
        error!("Invalid service handle");
        return;
    }

    let state = unsafe { handle_to_state_clone(handle) };
    
    // Check if already running
    {
        let service_state = match state.lock() {
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
    }

    // Start the server in a background task
    let state_for_spawn = state.clone();
    
    let handle_result = {
        let mut service_state = match state.lock() {
            Ok(guard) => guard,
            Err(e) => {
                error!("Failed to lock service state: {}", e);
                return;
            }
        };

        service_state.runtime.spawn(async move {
            // Use String error to make it Send
            let port = match find_available_port(8436, 100).await {
                Ok(port) => {
                    info!("Found available port: {}", port);
                    
                    // Update the port in the state
                    if let Ok(mut state_guard) = state_for_spawn.lock() {
                        state_guard.current_port = Some(port);
                    }
                    
                    port
                }
                Err(e) => {
                    error!("Failed to find available port: {}", e);
                    return;
                }
            };
            
            start_android_server(port).await;
        })
    };

    // Update state with the server handle
    {
        let mut service_state = match state.lock() {
            Ok(guard) => guard,
            Err(e) => {
                error!("Failed to lock service state for handle update: {}", e);
                return;
            }
        };

        service_state.server_handle = Some(handle_result);
        service_state.is_running = true;
    }
    
    info!("Android service started successfully");
}

#[unsafe(no_mangle)]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeStop(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    info!("Stopping Android service, handle: {}", handle);

    if handle == 0 {
        error!("Invalid service handle");
        return;
    }

    let state = unsafe { handle_to_state_clone(handle) };
    
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
    
    info!("Android service stopped");
}

#[unsafe(no_mangle)]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeDestroy(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    info!("Destroying Android service, handle: {}", handle);

    if handle == 0 {
        error!("Invalid service handle");
        return;
    }

    let state = unsafe { handle_to_state_clone(handle) };
    
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
    
    // Properly drop the original Arc
    unsafe {
        let ptr = handle as *const Mutex<AndroidServiceState>;
        let _arc = Arc::from_raw(ptr); // This will drop when it goes out of scope
    }
    
    info!("Android service destroyed");
}

#[unsafe(no_mangle)]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeSetUsbDevice(
    mut env: JNIEnv,
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

    let serial_str = match env.get_string(&serial_number) {
        Ok(s) => s.into(),
        Err(e) => {
            error!("Failed to get serial number string: {}", e);
            return;
        }
    };

    let device = AndroidUsbDevice {
        file_descriptor: file_descriptor as i32,
        vendor_id: vendor_id as u16,
        product_id: product_id as u16,
        serial_number: serial_str,
    };

    let state = unsafe { handle_to_state_clone(handle) };
    
    let mut service_state = match state.lock() {
        Ok(guard) => guard,
        Err(e) => {
            error!("Failed to lock service state: {}", e);
            return;
        }
    };

    service_state.add_device(device);
    
    info!("USB device added - VID: 0x{:04x}, PID: 0x{:04x}, Total devices: {}", 
          vendor_id, product_id, service_state.get_device_count());
}

#[unsafe(no_mangle)]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeRemoveUsbDevice(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
    vendor_id: jint,
    product_id: jint,
) {
    info!("Removing USB device - VID: 0x{:04x}, PID: 0x{:04x}", vendor_id, product_id);

    if handle == 0 {
        error!("Invalid service handle");
        return;
    }

    let state = unsafe { handle_to_state_clone(handle) };
    
    let mut service_state = match state.lock() {
        Ok(guard) => guard,
        Err(e) => {
            error!("Failed to lock service state: {}", e);
            return;
        }
    };

    if service_state.remove_device(vendor_id as u16, product_id as u16) {
        info!("USB device removed - VID: 0x{:04x}, PID: 0x{:04x}, Remaining: {}", 
              vendor_id, product_id, service_state.get_device_count());
    } else {
        warn!("Attempted to remove device that wasn't found");
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeIsRunning(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jboolean {
    if handle == 0 {
        return 0; // false
    }

    let state = unsafe { handle_to_state_clone(handle) };
    let is_running = match state.lock() {
        Ok(service_state) => service_state.is_running,
        Err(_) => false,
    };

    if is_running { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeGetPort(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jint {
    if handle == 0 {
        return -1;
    }

    let state = unsafe { handle_to_state_clone(handle) };
    let port = match state.lock() {
        Ok(service_state) => service_state.current_port.map(|p| p as jint).unwrap_or(-1),
        Err(_) => -1,
    };

    port
}

#[unsafe(no_mangle)]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeGetDeviceCount(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jint {
    if handle == 0 {
        return 0;
    }

    let state = unsafe { handle_to_state_clone(handle) };
    let count = match state.lock() {
        Ok(service_state) => service_state.get_device_count() as jint,
        Err(_) => 0,
    };

    count
}

#[unsafe(no_mangle)]
pub extern "C" fn Java_com_yudurobotics_snappywebagent_SnappyWebAgentService_nativeHasDevice(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jboolean {
    if handle == 0 {
        return 0;
    }

    let state = unsafe { handle_to_state_clone(handle) };
    let has_device = match state.lock() {
        Ok(service_state) => service_state.device_info.is_some(),
        Err(_) => false,
    };

    if has_device { 1 } else { 0 }
}

// Register socket handlers function that was missing
pub fn register_handlers(io: &socketioxide::SocketIo) {
    io.ns("/", crate::socketio::on_connect);
}

// Android-specific server implementation
async fn start_android_server(port: u16) {
    use axum::routing::get;
    use socketioxide::SocketIo;
    use tower_http::cors::{CorsLayer, Any};

    info!("Starting Android server on port {}", port);

    let (layer, io) = SocketIo::new_layer();

    // Register socket handlers
    register_handlers(&io);

    let app = axum::Router::new()
        .route("/", get(|| async { "Snappy Web Agent Android Service" }))
        .route("/health", get(|| async { "OK" }))
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any)
        )
        .layer(layer);

    let listener = match tokio::net::TcpListener::bind(("0.0.0.0", port)).await {
        Ok(listener) => listener,
        Err(e) => {
            error!("Failed to bind to port {}: {}", port, e);
            return;
        }
    };

    info!("Android server listening on 0.0.0.0:{}", port);

    if let Err(e) = axum::serve(listener, app).await {
        error!("Android server error: {}", e);
    }
}

// Android-specific utility functions

pub fn get_android_service_status() -> String {
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
#[cfg(feature = "android")]
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
    error!("{}", message);
}