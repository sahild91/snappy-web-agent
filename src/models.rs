use serde::{ Deserialize, Serialize };

pub const VID: u16 = 0xb1b0;
pub const PID: u16 = 0x5508;
pub const EXPECTED_PREFIX: [u8; 7] = [0x53, 0x4e, 0x41, 0x50, 0x50, 0x59, 0x3a];

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct SerialResponse {
    pub success: bool,
    pub message: String,
    pub command: String,
    pub error: Option<String>,
}
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct EventResponse {
    pub event: String,
    pub status: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct SnapDataEvent {
    pub mac: String,
    pub value: u16,
    pub timestamp: String,
}
#[derive(Deserialize)]
pub struct CargoToml {
    pub package: Package,
}

#[derive(Deserialize)]
pub struct Package {
    pub metadata: Option<Metadata>,
}

#[derive(Deserialize)]
pub struct Metadata {
    pub encryption: Option<EncryptionConfig>,
}

#[derive(Deserialize)]
pub struct EncryptionConfig {
    pub key: Vec<u32>,
}
