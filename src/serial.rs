use std::sync::{ Arc, Mutex };
#[cfg(target_os = "linux")]
use std::fs; // for Linux get_serial
#[cfg(not(target_os = "windows"))]
use std::time::Duration;
use crate::models::*;
use crate::encryption::*;
use tracing::info;
use socketioxide::extract::SocketRef;

// Linux-only helper to fetch serial via sysfs
#[cfg(target_os = "linux")]
fn get_serial(dev: &str) -> Option<String> {
    let dev_name = dev.strip_prefix("/dev/").unwrap_or(dev);
    let path = format!("/sys/class/tty/{}/device/../serial", dev_name);
    fs::read_to_string(path)
        .ok()
        .map(|s| s.trim().to_string())
}

// #[cfg(target_os = "windows")]
// fn get_serial(dev: &str) -> Option<String> {
//     // For Windows, use USB control transfer to get serial number directly from device
//     get_serial_via_usb_control_transfer(dev)
// }

// #[cfg(target_os = "windows")]
// fn get_serial_via_usb_control_transfer(_dev: &str) -> Option<String> {
//     use rusb::{ Context, UsbContext };

//     // Create USB context
//     let context = match Context::new() {
//         Ok(ctx) => ctx,
//         Err(e) => {
//             info!("Failed to create USB context: {}", e);
//             return None;
//         }
//     };

//     // Iterate through all USB devices
//     let devices = match context.devices() {
//         Ok(devices) => devices,
//         Err(e) => {
//             info!("Failed to get USB devices: {}", e);
//             return None;
//         }
//     };

//     for device in devices.iter() {
//         let device_desc = match device.device_descriptor() {
//             Ok(desc) => desc,
//             Err(_) => {
//                 continue;
//             }
//         };

//         // Check if this is one of our target devices (check all supported PIDs)
//         if device_desc.vendor_id() == VID && PIDS.contains(&device_desc.product_id()) {
//             if let Some(descriptor_index) = device_desc.serial_number_string_index() {
//                 if descriptor_index > 0 {
//                     if let Some(serial) = get_device_serial_via_control_transfer(
//                         &device,
//                         descriptor_index
//                     ) {
//                         info!("Found serial via USB control transfer for PID 0x{:04x}: {}", 
//                               device_desc.product_id(), serial);
//                         return Some(serial);
//                     }
//                 }
//             }
//         }
//     }

//     None
// }

#[cfg(target_os = "windows")]
fn get_device_serial_via_control_transfer(
    device: &rusb::Device<rusb::Context>,
    descriptor_index: u8
) -> Option<String> {
    use rusb::{ Direction, Recipient, RequestType };
    use std::time::Duration;

    // Try to open the device
    let handle = match device.open() {
        Ok(handle) => handle,
        Err(e) => {
            info!("Failed to open USB device: {}", e);
            return None;
        }
    };

    // Windows often doesn't return device serial number directly
    // Use control transfer to get string descriptor
    if descriptor_index == 0 {
        return None;
    }

    // GET_DESCRIPTOR request for STRING_DESCRIPTOR
    let request_type = rusb::request_type(Direction::In, RequestType::Standard, Recipient::Device);
    let request = 0x06; // GET_DESCRIPTOR
    let value = (0x03 << 8) | (descriptor_index as u16); // STRING_DESCRIPTOR | descriptor_index
    let index = 0x0409; // language ID (0x0409 = English - US)
    let timeout = Duration::from_millis(1000);

    let mut buffer = [0u8; 255];

    match handle.read_control(request_type, request, value, index, &mut buffer, timeout) {
        Ok(bytes_read) if bytes_read >= 2 => {
            // Parse USB string descriptor
            // First byte is length, second is descriptor type (0x03 for string)
            if buffer[1] == 0x03 && bytes_read > 2 {
                let length = buffer[0] as usize;
                let actual_length = std::cmp::min(length, bytes_read);

                // USB string descriptors are UTF-16LE encoded
                // Extract characters (skip length and type bytes)
                let mut serial_chars = Vec::new();
                for i in (2..actual_length).step_by(2) {
                    if i + 1 < actual_length {
                        let char_code = u16::from_le_bytes([buffer[i], buffer[i + 1]]);
                        if char_code != 0 {
                            if let Some(ch) = char::from_u32(char_code as u32) {
                                serial_chars.push(ch);
                            }
                        }
                    }
                }

                if !serial_chars.is_empty() {
                    let serial_number: String = serial_chars.into_iter().collect();
                    return Some(serial_number.trim().to_string());
                }
            }
        }
        Ok(_) => {
            info!("Control transfer returned insufficient data");
        }
        Err(e) => {
            info!("Control transfer failed: {}", e);
        }
    }

    None
}

#[cfg(not(any(target_os = "linux", target_os = "windows")))]
fn get_serial(_dev: &str) -> Option<String> {
    None
}

// New function to check if any of the supported devices is connected
pub fn is_any_device_connected(vid: u16, pids: &[u16]) -> bool {
    for &pid in pids {
        if is_device_connected(vid, pid) {
            return true;
        }
    }
    false
}

// Enhanced device detection that returns which PID was found
pub fn find_connected_device_info(vid: u16, pids: &[u16]) -> Option<(u16, String)> {
    #[cfg(target_os = "windows")]
    {
        use rusb::{ Context, UsbContext };

        let context = match Context::new() {
            Ok(ctx) => ctx,
            Err(_) => return None,
        };

        let devices = match context.devices() {
            Ok(devices) => devices,
            Err(_) => return None,
        };

        for device in devices.iter() {
            if let Ok(device_desc) = device.device_descriptor() {
                if device_desc.vendor_id() == vid && pids.contains(&device_desc.product_id()) {
                    let pid = device_desc.product_id();
                    let device_name = format!("USB Device (PID: 0x{:04x})", pid);
                    return Some((pid, device_name));
                }
            }
        }
        None
    }

    #[cfg(not(target_os = "windows"))]
    {
        let ports = serialport::available_ports().unwrap_or_else(|_| vec![]);
        for available_port in ports {
            if let serialport::SerialPortType::UsbPort(info) = &available_port.port_type {
                if info.vid == vid && pids.contains(&info.pid) {
                    return Some((info.pid, available_port.port_name.clone()));
                }
            }
        }
        None
    }
}

pub async fn start_snappy_with_socket(_socket: SocketRef) {
    // Import the socketio functions
    use crate::socketio::is_snappy_collecting;

    let hash_key = Arc::new(Mutex::new(Vec::<u8>::new()));
    let current_device_pid = Arc::new(Mutex::new(None::<u16>));
    let (tx, mut rx) = tokio::sync::mpsc::channel::<(String, u16)>(100);
    let hash_key_clone = Arc::clone(&hash_key);
    let current_device_pid_clone = Arc::clone(&current_device_pid);

    let serial_port_checker_t = tokio::spawn(async move {
        info!("Checking connection for snappy data collection...");
        let mut last_connected_device: Option<(String, u16)> = None;
        #[cfg(target_os = "windows")]
        let mut cached_serial: Option<String> = None;
        
        loop {
            if !is_snappy_collecting() {
                info!("Snappy data collection stopped");
                break;
            }
            let mut detected_device: Option<(String, u16)> = None;

            #[cfg(target_os = "windows")]
            {
                // Check for any supported device
                if let Some((found_pid, _device_name)) = find_connected_device_info(VID, PIDS) {
                    // Update current device PID
                    {
                        let mut current_pid = current_device_pid_clone.lock().unwrap();
                        *current_pid = Some(found_pid);
                    }
                    
                    // If we already have the serial cached for this device, use it
                    if cached_serial.is_some() {
                        detected_device = Some(("USB_DEVICE".to_string(), found_pid));
                    } else {
                        // Attempt to get serial for this specific device
                        if let Some(usb_device_info) = find_usb_device_windows_for_pid(found_pid).await {
                            if let Some(serial_number) = usb_device_info.serial_number {
                                let mut hash_key = hash_key_clone.lock().unwrap();
                                let serial_number_array: Vec<u32> = serial_number
                                    .chars()
                                    .map(|c| c as u32)
                                    .collect();
                                let serial_number_u8: Vec<u8> = serial_number_array
                                    .iter()
                                    .take(16)
                                    .map(|&c| c as u8)
                                    .collect();
                                hash_key.clear();
                                hash_key.extend_from_slice(&serial_number_u8);
                                cached_serial = Some(serial_number);
                            }
                            detected_device = Some(("USB_DEVICE".to_string(), found_pid));
                        }
                    }
                } else {
                    // No device connected -> clear cache
                    cached_serial = None;
                    *current_device_pid_clone.lock().unwrap() = None;
                    detected_device = None;
                }
            }

            #[cfg(not(target_os = "windows"))]
            {
                // For other OS, use serial port enumeration
                let available_ports = serialport::available_ports().unwrap_or_else(|_| vec![]);
                for port in available_ports {
                    if let serialport::SerialPortType::UsbPort(info) = &port.port_type {
                        // Check if this port matches any of our supported PIDs
                        if info.vid == VID && PIDS.contains(&info.pid) {
                            // Update current device PID
                            {
                                let mut current_pid = current_device_pid_clone.lock().unwrap();
                                *current_pid = Some(info.pid);
                            }
                            
                            let mut hash_key = hash_key_clone.lock().unwrap();
                            let mut maybe_serial_number: Option<String> =
                                info.serial_number.clone();
                            if
                                maybe_serial_number.is_none() ||
                                maybe_serial_number == Some("6".to_string())
                            {
                                info!(
                                    "Trying to fetch serial from sysfs for port: {}",
                                    port.port_name
                                );
                                maybe_serial_number = get_serial(&port.port_name);
                            }
                            if let Some(serial_number) = maybe_serial_number {
                                let serial_number_array: Vec<u32> = serial_number
                                    .chars()
                                    .map(|c| c as u32)
                                    .collect();
                                let serial_number_u8: Vec<u8> = serial_number_array
                                    .iter()
                                    .take(16)
                                    .map(|&c| c as u8)
                                    .collect();
                                hash_key.clear();
                                hash_key.extend_from_slice(&serial_number_u8);
                            } else {
                                info!("Serial Number: None for PID 0x{:04x}", info.pid);
                            }
                            detected_device = Some((port.port_name.clone(), info.pid));
                            break;
                        }
                    }
                }
            }

            if detected_device != last_connected_device {
                last_connected_device = detected_device.clone();
                if let Some((device_name, pid)) = detected_device {
                    let _ = tx.send((device_name, pid)).await;
                } else {
                    let _ = tx.send((String::new(), 0)).await;
                }
            }
            tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
        }
    });

    let hash_key_for_task = Arc::clone(&hash_key);
    let _current_device_pid_for_task = Arc::clone(&current_device_pid);

    tokio::spawn(async move {
        while let Some((path, device_pid)) = rx.recv().await {
            // Check if we should stop collecting
            if !is_snappy_collecting() {
                break;
            }

            if path.is_empty() {
                info!("No device connected - hash key : {:?}", hash_key_for_task.lock().unwrap());
            } else {
                let mut hash = [0u8; 32];
                let serial_number = hash_key_for_task.lock().unwrap().clone();
                hash_serial(&serial_number, &mut hash);
                let counter = 0x0u32;

                info!("Device connected for snappy data collection - PID: 0x{:04x}", device_pid);

                #[cfg(target_os = "windows")]
                {
                    // For Windows, use USB communication directly
                    let mut session: Option<UsbSession> = None;
                    loop {
                        if !is_snappy_collecting() {
                            info!("Stopping snappy data collection");
                            break;
                        }

                        // Establish session if missing
                        if session.is_none() {
                            match open_usb_session_for_pids(PIDS) {
                                Ok(s) => {
                                    info!(
                                        "USB session established (iface={}, ep=0x{:02x}, PID=0x{:04x})",
                                        s.claimed_iface,
                                        s.endpoint,
                                        s.device_pid
                                    );
                                    session = Some(s);
                                }
                                Err(e) => {
                                    info!("Failed to open USB session: {}", e);
                                    tokio::time::sleep(
                                        tokio::time::Duration::from_millis(500)
                                    ).await;
                                    continue;
                                }
                            }
                        }

                        if let Some(s) = session.as_mut() {
                            match read_snappy_data_via_usb(s, &hash, counter) {
                                Some(Ok(data)) => {
                                    // Pass the device PID to the processing function
                                    process_serial_message_with_emit(&data, s.device_pid);
                                }
                                Some(Err(e)) => {
                                    info!("USB read error: {}", e);
                                    session = None;
                                    tokio::time::sleep(
                                        tokio::time::Duration::from_millis(250)
                                    ).await;
                                }
                                None => {
                                    tokio::time::sleep(
                                        tokio::time::Duration::from_millis(10)
                                    ).await;
                                }
                            }
                        }
                    }
                }

                #[cfg(not(target_os = "windows"))]
                {
                    // For other OS, use serial port communication
                    match serialport::new(&path, 230400).timeout(Duration::from_secs(2)).open() {
                        Ok(mut port) => {
                            info!("Device connected for snappy data collection - PID: 0x{:04x}", device_pid);
                            let mut buffer = [0; 64];
                            let mut data_buffer: Vec<u8> = Vec::new();
                            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

                            loop {
                                if !is_snappy_collecting() {
                                    info!("Stopping snappy data collection");
                                    break;
                                }

                                match port.read(&mut buffer) {
                                    Ok(bytes_read) if bytes_read > 0 => {
                                        info!("Read {} bytes from serial port (PID: 0x{:04x})", bytes_read, device_pid);
                                        data_buffer.extend_from_slice(&buffer[..bytes_read]);
                                        while
                                            let Some(pos) = data_buffer
                                                .windows(2)
                                                .position(|window| window == b"\r\n")
                                        {
                                            let message = &data_buffer[..pos];
                                            let mut decrypted = vec![0u8; data_buffer[..pos].len()];
                                            chacha20_decrypt(
                                                &hash,
                                                counter,
                                                message,
                                                &mut decrypted
                                            );

                                            // Process and emit data with device PID
                                            process_serial_message_with_emit(decrypted.as_slice(), device_pid);

                                            data_buffer.drain(..pos + 2);
                                        }
                                    }
                                    _ => {
                                        tokio::time::sleep(
                                            tokio::time::Duration::from_millis(10)
                                        ).await;
                                    }
                                }
                            }
                        }
                        Err(e) => {
                            info!("Failed to open serial port: {}", e);
                        }
                    }
                }
            }
        }
    });

    serial_port_checker_t.await.expect("Failed to start serial port checker for snappy");
}

fn process_serial_message_with_emit(message: &[u8], device_pid: u16) {
    use crate::socketio::emit_snap_data;

    if message.len() >= 14 && message[..7] == EXPECTED_PREFIX {
        let mac_bytes = &message[7..13]; // 6 bytes for MAC
        let dev_value = &message[13..15]; // 2 bytes for the device value

        // Convert MAC bytes into a readable hex string
        let mut mac_str = String::new();
        for mb in mac_bytes.iter() {
            use std::fmt::Write;
            write!(&mut mac_str, "{:02x}:", mb).unwrap();
        }
        let mac_str = mac_str.trim_end_matches(':'); // Remove trailing colon

        // Convert the 2 bytes into a short value in decimal
        let device_value = ((dev_value[0] as u16) << 8) | (dev_value[1] as u16);

        // Emit the data via socket with PID information
        emit_snap_data(mac_str.to_string(), device_value, device_pid);

        info!("Emitted snap data - MAC: {}, value: {}, PID: 0x{:04x}", mac_str, device_value, device_pid);
    }
}

pub fn is_device_connected(vid: u16, pid: u16) -> bool {
    #[cfg(target_os = "windows")]
    {
        use rusb::{ Context, UsbContext };

        let context = match Context::new() {
            Ok(ctx) => ctx,
            Err(_) => {
                return false;
            }
        };

        let devices = match context.devices() {
            Ok(devices) => devices,
            Err(_) => {
                return false;
            }
        };

        for device in devices.iter() {
            if let Ok(device_desc) = device.device_descriptor() {
                if device_desc.vendor_id() == vid && device_desc.product_id() == pid {
                    return true;
                }
            }
        }
        false
    }

    #[cfg(not(target_os = "windows"))]
    {
        let ports = serialport::available_ports().unwrap_or_else(|_| vec![]);
        for available_port in ports {
            if let serialport::SerialPortType::UsbPort(info) = &available_port.port_type {
                if info.vid == vid && info.pid == pid {
                    return true;
                }
            }
        }
        false
    }
}

#[cfg(target_os = "windows")]
struct UsbDeviceInfo {
    serial_number: Option<String>,
}

#[cfg(target_os = "windows")]
async fn find_usb_device_windows_for_pid(target_pid: u16) -> Option<UsbDeviceInfo> {
    use rusb::{ Context, UsbContext };
    let context = Context::new().ok()?;
    let devices = context.devices().ok()?;
    
    for device in devices.iter() {
        let device_desc = device.device_descriptor().ok()?;
        if device_desc.vendor_id() == VID && device_desc.product_id() == target_pid {
            if let Some(idx) = device_desc.serial_number_string_index() {
                if idx > 0 {
                    if let Some(serial) = get_device_serial_via_control_transfer(&device, idx) {
                        return Some(UsbDeviceInfo { serial_number: Some(serial) });
                    }
                }
            }
            return Some(UsbDeviceInfo { serial_number: None });
        }
    }
    None
}

// Enhanced USB session that tracks which PID it's connected to
#[cfg(target_os = "windows")]
struct UsbSession {
    context: rusb::Context,
    handle: rusb::DeviceHandle<rusb::Context>,
    endpoint: u8,
    claimed_iface: u8,
    device_pid: u16, // Track which PID this session is for
    accumulator: Vec<u8>,
}

#[cfg(target_os = "windows")]
fn open_usb_session_for_pids(pids: &[u16]) -> Result<UsbSession, String> {
    use rusb::{ Context, UsbContext, Direction, TransferType };
    const PREFERRED_CONFIG: u8 = 1;
    const PREFERRED_INTERFACE: u8 = 1;

    fn find_bulk_in_endpoint(device: &rusb::Device<Context>, iface_number: u8) -> Option<u8> {
        if let Ok(cfg) = device.active_config_descriptor() {
            for iface in cfg.interfaces() {
                for desc in iface.descriptors() {
                    if desc.interface_number() == iface_number {
                        for ep in desc.endpoint_descriptors() {
                            if
                                ep.transfer_type() == TransferType::Bulk &&
                                ep.direction() == Direction::In
                            {
                                return Some(ep.address());
                            }
                        }
                    }
                }
            }
        }
        None
    }

    let context = Context::new().map_err(|e| format!("Create USB context failed: {e}"))?;
    let devices = context.devices().map_err(|e| format!("List devices failed: {e}"))?;

    for device in devices.iter() {
        let device_desc = match device.device_descriptor() {
            Ok(d) => d,
            Err(_) => {
                continue;
            }
        };
        
        // Check if this device matches any of our supported PIDs
        if device_desc.vendor_id() != VID || !pids.contains(&device_desc.product_id()) {
            continue;
        }

        let device_pid = device_desc.product_id();
        let mut handle = device.open().map_err(|e| format!("Open device failed: {e}"))?;
        
        if let Ok(active) = handle.active_configuration() {
            if active != PREFERRED_CONFIG {
                let _ = handle.set_active_configuration(PREFERRED_CONFIG);
            }
        } else {
            let _ = handle.set_active_configuration(PREFERRED_CONFIG);
        }

        let claimed_iface = if handle.claim_interface(PREFERRED_INTERFACE).is_ok() {
            PREFERRED_INTERFACE
        } else if handle.claim_interface(0).is_ok() {
            0
        } else {
            continue; // Try next device
        };
        
        let endpoint = find_bulk_in_endpoint(&device, claimed_iface)
            .or_else(|| find_bulk_in_endpoint(&device, 0))
            .unwrap_or(0x81);

        return Ok(UsbSession { 
            context, 
            handle, 
            endpoint, 
            claimed_iface, 
            device_pid,
            accumulator: Vec::new() 
        });
    }
    
    Err("No supported device found".into())
}

#[cfg(target_os = "windows")]
fn read_snappy_data_via_usb(
    session: &mut UsbSession,
    hash: &[u8; 32],
    counter: u32
) -> Option<Result<Vec<u8>, String>> {
    use std::time::Duration;
    const MAX_ACCUMULATOR: usize = 4096;
    let timeout = Duration::from_millis(1000);
    let mut buffer = [0u8; 64];

    match session.handle.read_bulk(session.endpoint, &mut buffer, timeout) {
        Ok(bytes_read) if bytes_read > 0 => {
            info!(
                "Read {} bytes via USB bulk transfer (ep=0x{:02x}, PID=0x{:04x})",
                bytes_read,
                session.endpoint,
                session.device_pid
            );
            session.accumulator.extend_from_slice(&buffer[..bytes_read]);
        }
        Ok(_) => {/* no new bytes; still try to parse existing accumulator */}
        Err(e) => {
            return Some(Err(format!("USB bulk transfer failed: {e}")));
        }
    }

    if session.accumulator.len() > MAX_ACCUMULATOR {
        session.accumulator.clear();
        return Some(Err("Accumulator overflow without frame delimiter; buffer reset".into()));
    }

    if let Some(pos) = session.accumulator.windows(2).position(|w| w == b"\r\n") {
        let ciphertext = session.accumulator[..pos].to_vec();
        session.accumulator.drain(..pos + 2);

        let mut decrypted = vec![0u8; ciphertext.len()];
        crate::encryption::chacha20_decrypt(hash, counter, &ciphertext, &mut decrypted);
        return Some(Ok(decrypted));
    }

    None
}