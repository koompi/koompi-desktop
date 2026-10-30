//! A second opinion when NetworkManager reports `Limited`.
//!
//! NetworkManager's check is a plain-HTTP fetch of `ConnectivityCheckUri`. A network
//! that blocks outbound port 80 fails it every time while the web works over HTTPS, and
//! the seat then reads as having no internet. A captive portal never lands here: it
//! answers the HTTP fetch with its login page, which NetworkManager reports as `Portal`.
//! `Limited` means the fetch got no answer at all.
//!
//! The second opinion is a TCP connect to the same host on 443, nothing more. The crate
//! holds no HTTP client and no TLS stack (`tests/test_shell_services.sh`), and a connect
//! that completes through the default route to the check host is what the port-80 block
//! leaves standing. It cannot tell a network that accepts every SYN apart from the
//! internet; those networks are rare and NetworkManager's own verdict is no better there.

use std::time::Duration;

use tokio::net::{lookup_host, TcpStream};

/// NetworkManager's own default interval, so a seat that stays limited is checked no
/// more often than NetworkManager checks it.
pub const PROBE_INTERVAL: Duration = Duration::from_secs(300);

/// One address that hangs, typically IPv6 with no route, must not use up the whole try.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(4);
const PROBE_TIMEOUT: Duration = Duration::from_secs(12);

/// `host:443` for the host in NetworkManager's check URI, or `None` when there is no
/// check configured or the URI names no host.
pub fn https_target(check_uri: &str) -> Option<String> {
    let rest = check_uri
        .strip_prefix("http://")
        .or_else(|| check_uri.strip_prefix("https://"))?;
    let authority = rest.split(['/', '?', '#']).next()?;
    let host = authority
        .rsplit_once('@')
        .map_or(authority, |(_, host)| host);
    // the check's own port says nothing about 443
    let host = match host.strip_prefix('[') {
        Some(v6) => format!("[{}]", v6.split_once(']')?.0),
        None => host.split(':').next()?.to_owned(),
    };
    (!host.is_empty() && host != "[]").then(|| format!("{host}:443"))
}

/// Whether a TCP connection to `target` (`host:port`) completes on any of its addresses.
pub async fn reachable(target: &str) -> bool {
    let attempt = async {
        for addr in lookup_host(target).await.ok()? {
            if let Ok(Ok(_)) = tokio::time::timeout(CONNECT_TIMEOUT, TcpStream::connect(addr)).await
            {
                return Some(());
            }
        }
        None
    };
    matches!(
        tokio::time::timeout(PROBE_TIMEOUT, attempt).await,
        Ok(Some(()))
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_target_is_the_check_host_on_443() {
        let cases = [
            (
                "http://ping.archlinux.org/nm-check.txt",
                Some("ping.archlinux.org:443"),
            ),
            (
                "http://fedoraproject.org/static/hotspot.txt",
                Some("fedoraproject.org:443"),
            ),
            (
                "http://connectivity-check.ubuntu.com./",
                Some("connectivity-check.ubuntu.com.:443"),
            ),
            (
                "https://nmcheck.gnome.org/check_network_status.txt",
                Some("nmcheck.gnome.org:443"),
            ),
            ("http://example.com:8080/check", Some("example.com:443")),
            ("http://user@example.com/", Some("example.com:443")),
            ("http://[2001:db8::1]:80/check", Some("[2001:db8::1]:443")),
            ("http://example.com", Some("example.com:443")),
            ("", None),
            ("ftp://example.com/", None),
            ("http:///nohost", None),
        ];
        for (uri, want) in cases {
            assert_eq!(https_target(uri).as_deref(), want, "{uri}");
        }
    }

    #[tokio::test]
    async fn a_listening_port_is_reachable_and_a_closed_one_is_not() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let open = listener.local_addr().unwrap();
        assert!(reachable(&open.to_string()).await);

        drop(listener);
        assert!(!reachable(&open.to_string()).await);
    }

    #[tokio::test]
    async fn a_name_that_does_not_resolve_is_not_reachable() {
        assert!(!reachable("koompi-probe-test.invalid:443").await);
    }
}
