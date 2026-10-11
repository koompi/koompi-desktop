//! A compositor that never stops talking: the focused window has to reach the state while
//! the events keep coming, not after they stop.

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use koompi_hyprland::{HyprlandService, Ipc};
use koompi_service::{PollRate, Service};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixListener;

const BEFORE: &str = include_str!("fixtures/activewindow.json");

fn scratch_dir() -> PathBuf {
    let dir = std::env::temp_dir().join(format!("koompi-hyprland-burst-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn reply_for(command: &str, focus_moved: bool) -> String {
    match command {
        "j/clients" => include_str!("fixtures/clients.json").into(),
        "j/workspaces" => include_str!("fixtures/workspaces.json").into(),
        "j/activeworkspace" => include_str!("fixtures/activeworkspace.json").into(),
        "j/activewindow" if focus_moved => BEFORE.replace("org.wezfurlong.wezterm", "moved"),
        "j/activewindow" => BEFORE.into(),
        "j/monitors" => include_str!("fixtures/monitors.json").into(),
        "j/layers" => include_str!("fixtures/layers.json").into(),
        "j/devices" => include_str!("fixtures/devices.json").into(),
        "binds" => include_str!("fixtures/binds.txt").into(),
        _ => String::new(),
    }
}

#[tokio::test]
async fn focus_reaches_the_state_while_another_window_floods_title_events() {
    let dir = scratch_dir();
    let commands = UnixListener::bind(dir.join(".socket.sock")).unwrap();
    let events = UnixListener::bind(dir.join(".socket2.sock")).unwrap();
    let focus_moved = Arc::new(AtomicBool::new(false));

    let moved = focus_moved.clone();
    tokio::spawn(async move {
        loop {
            let Ok((mut stream, _)) = commands.accept().await else { return };
            let moved = moved.clone();
            tokio::spawn(async move {
                let mut command = String::new();
                let _ = stream.read_to_string(&mut command).await;
                let reply = reply_for(command.trim(), moved.load(Ordering::SeqCst));
                let _ = stream.write_all(reply.as_bytes()).await;
                let _ = stream.shutdown().await;
            });
        }
    });

    let moved = focus_moved.clone();
    tokio::spawn(async move {
        let Ok((mut stream, _)) = events.accept().await else { return };
        tokio::time::sleep(Duration::from_millis(400)).await;
        moved.store(true, Ordering::SeqCst);
        stream.write_all(b"activewindowv2>>1\n").await.unwrap();
        loop {
            tokio::time::sleep(Duration::from_millis(10)).await;
            if stream.write_all(b"windowtitlev2>>2,spinner\n").await.is_err() {
                return;
            }
        }
    });

    let service = HyprlandService::with_ipc(Ipc::new(&dir), PollRate::NORMAL);
    let seen = tokio::time::timeout(Duration::from_secs(3), async {
        let mut rx = service.subscribe();
        loop {
            let class = rx.borrow_and_update().active_window.as_ref().map(|w| w.class.clone());
            if class.as_deref() == Some("moved") {
                return;
            }
            if rx.changed().await.is_err() {
                return;
            }
        }
    })
    .await;

    std::fs::remove_dir_all(&dir).ok();
    assert!(seen.is_ok(), "the focused window never arrived while events kept flowing");
}
