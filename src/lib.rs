pub mod project;
pub mod runtime;

/// Minimal HTTP/1.0 client for the local control API (no extra dependency).
pub mod client {
    use std::io::{Read, Write};
    use std::net::TcpStream;
    use std::time::Duration;

    pub fn request(port: u16, method: &str, path: &str, body: &str, timeout: Duration) -> Result<(u16, String), String> {
        let addr = format!("127.0.0.1:{port}");
        let mut s = TcpStream::connect_timeout(&addr.parse().unwrap(), Duration::from_millis(400))
            .map_err(|e| format!("app unreachable: {e}"))?;
        s.set_read_timeout(Some(timeout)).ok();
        s.set_write_timeout(Some(timeout)).ok();
        let req = format!(
            "{method} {path} HTTP/1.0\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        s.write_all(req.as_bytes()).map_err(|e| e.to_string())?;
        let mut buf = Vec::new();
        s.read_to_end(&mut buf).map_err(|e| e.to_string())?;
        let text = String::from_utf8_lossy(&buf).to_string();
        let (head, body) = text.split_once("\r\n\r\n").unwrap_or((&text, ""));
        let code = head
            .split_whitespace()
            .nth(1)
            .and_then(|c| c.parse().ok())
            .unwrap_or(0);
        Ok((code, body.to_string()))
    }
}
