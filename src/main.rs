mod socketio;
mod encryption;
mod serial;
mod models;

use axum::routing::get;
use socketioxide::SocketIo;
use tracing::info;
use tracing_subscriber::FmtSubscriber;
use tower_http::cors::{ CorsLayer, Any };

#[cfg(windows)]
use std::ffi::OsString;
#[cfg(windows)]
use std::time::Duration;
#[cfg(windows)]
use windows_service::{
    define_windows_service,
    service_dispatcher,
    service::{
        ServiceControl,
        ServiceControlAccept,
        ServiceExitCode,
        ServiceState,
        ServiceStatus,
        ServiceType,
    },
    service_control_handler::{ self, ServiceControlHandlerResult },
};

#[cfg(windows)]
define_windows_service!(ffi_service_main, my_service_main);

#[cfg(windows)]
fn my_service_main(_arguments: Vec<OsString>) {
    if let Err(_e) = run_service() {
        // Log error or handle it appropriately
    }
}

#[cfg(windows)]
fn run_service() -> windows_service::Result<()> {
    let event_handler = move |control_event| -> ServiceControlHandlerResult {
        match control_event {
            ServiceControl::Stop => {
                // Handle stop event
                ServiceControlHandlerResult::NoError
            }
            ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
            _ => ServiceControlHandlerResult::NotImplemented,
        }
    };

    let status_handle = service_control_handler::register("SnappyWebAgent", event_handler)?;

    status_handle.set_service_status(ServiceStatus {
        service_type: ServiceType::OWN_PROCESS,
        current_state: ServiceState::Running,
        controls_accepted: ServiceControlAccept::STOP,
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    // Start the main application logic
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        start_server().await;
    });

    status_handle.set_service_status(ServiceStatus {
        service_type: ServiceType::OWN_PROCESS,
        current_state: ServiceState::Stopped,
        controls_accepted: ServiceControlAccept::empty(),
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    Ok(())
}

async fn find_available_port(
    start_port: u16,
    max_attempts: u16
) -> Result<u16, Box<dyn std::error::Error>> {
    for port in start_port..start_port + max_attempts {
        let addr = format!("0.0.0.0:{}", port);
        match tokio::net::TcpListener::bind(&addr).await {
            Ok(_) => {
                info!("Found available port: {}", port);
                return Ok(port);
            }
            Err(_) => {
                info!("Port {} is not available, trying next...", port);
                continue;
            }
        }
    }
    Err(
        format!(
            "No available port found in range {}..{}",
            start_port,
            start_port + max_attempts
        ).into()
    )
}

async fn start_server() {
    let (socketio_layer, io) = SocketIo::new_layer();
    io.ns("/", socketio::on_connect);
    let cors = CorsLayer::new().allow_origin(Any).allow_methods(Any).allow_headers(Any);
    let app = axum::Router
        ::new()
        .route(
            "/",
            get(|| async { "alive" })
        )
        .layer(socketio_layer)
        .layer(cors);

    // Try to find an available port starting from 8436
    let port = find_available_port(8436, 10).await.unwrap_or_else(|_| {
        panic!("Could not find an available port");
    });

    info!("Starting the device on port {}...", port);
    let addr = format!("0.0.0.0:{}", port);
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

#[tokio::main]
async fn main() {
    tracing::subscriber
        ::set_global_default(FmtSubscriber::default())
        .expect("Failed to set global default subscriber");

    #[cfg(windows)]
    {
        // Check if running as a service
        let args: Vec<String> = std::env::args().collect();
        if args.len() > 1 && args[1] == "--service" {
            // Run as Windows service
            if let Err(e) = service_dispatcher::start("SnappyWebAgent", ffi_service_main) {
                eprintln!("Failed to start service: {:?}", e);
            }
            return;
        }
    }

    // Run as console application (default)
    start_server().await;
}
