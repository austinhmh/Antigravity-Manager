// Re-export core proxy service types and functions from commands/proxy
// This ensures a single type definition is shared across desktop and headless paths.

pub use crate::commands::proxy::{
    AdminServerInstance, ProxyServiceInstance, ProxyServiceState, ProxyStatus,
    ensure_admin_server, internal_start_proxy_service,
};
