# KOOMPI Connect: plan

Status: **plan only**, written 2026-10-16. Nothing is built. Facts checked 2026-10-16 against the sources linked.
Goal: the phone and the desktop work as one. Files, the clipboard, notifications, messages, media and input cross between them in about a second, after one QR scan and nothing else, and nothing passes through anyone's cloud.
Either screen can be shown on the other: the phone on the desktop, the desktop on the phone, and a tablet as a second display.
KOOMPI Connect replaces KDE Connect on KOOMPI, and its phone app replaces KDE Connect's.
The name is the brainstorm's: "Connect" is the app of §48 (multi-device continuity) and the pocket mount of §86 (the Partner Window).

## Why replace KDE Connect

What it costs KOOMPI today:

- **Two workarounds exist only for it.**
  - `dots/.local/share/dbus-1/services/org.kde.kdeconnect.service` forces `kdeconnectd` onto Wayland, because on xcb its Remote Input moves only the Xwayland pointer.
  - `koompi-remotedesktop-portal` allows a RemoteDesktop session with an empty app id only while a process named `kdeconnectd` runs.
- **Its desktop UI is a separate Qt app.** It is not part of the bar, the Control Center or the notification center. The 2026-10-07 UX audit lists "KDE Connect SMS" among the launcher's clutter.
- **Its phone app is KDE's.** KOOMPI cannot fix its onboarding, its look, how it survives Android's battery managers, or what it offers.

Memory is not the reason. On the founder's seat (kdeconnect 26.08.2, one paired phone), `kdeconnectd` uses 9.9 MB PSS.

What its users keep reporting, and what this plan has to beat:

- **It drops the phone when the phone sleeps**, through Doze and the OEM battery managers, and does not always come back after the PC resumes ([bug 368438](https://bugs.kde.org/show_bug.cgi?id=368438), [399236](https://bugs.kde.org/show_bug.cgi?id=399236), [374563](https://bugs.kde.org/show_bug.cgi?id=374563) on MIUI, [discuss.kde.org](https://discuss.kde.org/t/kde-connect-almost-never-connected/28801)).
- **Discovery fails** behind a VPN, on guest networks and under client isolation, where the only way in is typing an IP address.
  Its mDNS discovery regressed twice ([bug 487719](https://bugs.kde.org/show_bug.cgi?id=487719), [512138](https://bugs.kde.org/show_bug.cgi?id=512138)).
- **The Android clipboard has to be sent by hand** since Android 10 ([discuss.kde.org](https://discuss.kde.org/t/kdeconnect-automatic-clipboard-sync-or-easier-method-from-android-to-other-devices/50319)).
- **File transfers are slow or stall**, with reports of 150–300 KB/s and of transfers stopping when the screen locks ([discuss.kde.org](https://discuss.kde.org/t/extremely-slow-file-transfers-between-android-and-ubuntu-with-kde-connect/18769)).
  The protocol sends one file at a time over one connection, and the sender gives up after 30 s.
- **Notification sync regresses** between releases ([bug 516582](https://bugs.kde.org/show_bug.cgi?id=516582)).
- **iOS gets a fraction:** no notifications, no SMS, no background connection, and remote input, commands and the clipboard only from the phone to the desktop.

## Who the phone app is for

In Cambodia, StatCounter puts Android at 64% and iOS at 36% of mobile web traffic in September 2026 ([mobile](https://gs.statcounter.com/os-market-share/mobile/cambodia)), and iOS at 45% once tablets count ([mobile and tablet](https://gs.statcounter.com/os-market-share/mobile-tablet/cambodia)).
iOS is a third of the users and close to half once tablets count, so it is a second app to plan for, not a footnote.
The plan keeps iOS users working from the first phase by staying compatible with KDE Connect's own iOS app (D1), and ships our iOS app after Android.

## Decisions

- **D1, the protocol. Recommended: (a).**
  - (a) Speak the KDE Connect protocol, and add KOOMPI's features as new packet types that a device announces in its capabilities. A stock peer ignores types it does not know.
  - (b) A protocol of our own, as §48 sketched it: Noise XX on port 7842 and short-authentication words, with a KDE Connect adapter beside it.

  Why (a):
  - Every existing client works with KOOMPI on day one: KDE Connect for Android and iOS, GSConnect and Valent, KDE Connect on Windows and macOS.
    Phase 1 replaces `kdeconnectd` before our phone app exists, and iOS users keep KDE Connect's iOS app until ours ships.
  - The security is the same for this threat model.
    A pinned self-signed TLS certificate plus a verification code compared once does what Noise XX plus SAS words does: it defeats a man in the middle on the LAN at pairing, and binds every later session to the pinned key.
    QR pairing (below) carries the key's fingerprint, so most users never compare anything.
  - What (a) lacks is added as extensions, not by replacing it: resumable transfers, many files in parallel, and later off-LAN links.

  KDE publishes the protocol: [`kdeconnect-meta/protocol.md`](https://invent.kde.org/network/kdeconnect-meta/-/blob/master/protocol.md), current to September 2026, with 45 packet types in 18 plugins.
  Its version is 8 (desktop 25.04, Android 1.33.0, iOS 0.5), and KDE's master dropped version 7 on 2026-09-18. KOOMPI speaks 8 only.

  The cost of (a): KDE changes the protocol now and then, and it has had security holes that every implementation had to fix.
  The conformance suite (Phase 0) runs against the current `kdeconnectd`, and KDE's security advisories are watched like Arch's.
- **D2, the phone stack. Recommended: a Rust core, with native UI on each platform.**
  - The core is one Rust library: identity and certificates, discovery, the TLS link, the packet codec, pairing, transfers.
    The desktop daemon links it directly, and the phone apps through UniFFI (Kotlin, then Swift).
    So the protocol is written once, tested once and fuzzed once.
  - Android: Kotlin with Jetpack Compose.
  - iOS: SwiftUI, or Compose Multiplatform to share Android's screens. Decide when iOS starts, from how far the Android UI has grown.
  - Not Flutter, although LocalSend shows it works.
    What makes the app good on Android is native code anyway: the notification listener, the foreground service, the Quick Settings tile, the share target, CameraX, MediaProjection.
    The desktop side is the shell's QML, so a cross-platform UI toolkit would buy only iOS.
- **D3, where the code lives. Recommended: a new repo, `koompi/connect`.**
  - It holds the protocol spec, the core, the conformance suite, the desktop daemon and the Android app; the iOS app joins it later.
  - The phone app releases on its own schedule, and the core has to build for Android, which this repo's Cargo workspace (native build plan, N2) should not carry.
  - This repo keeps the shell UI, the package, the firewall rules and the `koompi connect` CLI verb.
- **D4, the daemon is its own service. Recommended.**
  - `koompi-connectd`, a systemd user service, not a crate inside `koompi-shelld`.
  - It listens on the network, parses whatever any device on the LAN sends, and writes large files. A bug there must not take the bar's services down with it, and it gets a sandbox of its own.
  - That is the opposite of native build plan D2 (the menu registrar moves into `shelld`), on purpose: the registrar only speaks to local apps.
- **D5, where the Android app is published. Recommended: Google Play first, an APK from KOOMPI second.**
  - Play allows SMS and the call log for "cross-device synchronization or transfer of SMS or calls (such as between phone and laptop)", through the Permissions Declaration Form ([policy](https://support.google.com/googleplay/android-developer/answer/10208820)).
    KDE Connect's Play build carries SMS that way. So one build can do everything.
  - An app installed from an APK hits Android 13's "restricted settings": the notification listener and the accessibility service stay greyed out until the user finds a hidden menu to allow them.
    A Play install does not, so Play is the route a normal user should take.
  - Remote input needs an accessibility service. Play requires a prominent disclosure, consent and a declaration for that ([policy](https://support.google.com/googleplay/android-developer/answer/16558241)); KDE Connect ships one.
  - Play lets an app ask to be exempt from battery optimisation only when Doze breaks its core function. A link that must stay up is that function, and the declaration has to say so.
- **D6, the licence. Recommended: GPL-3.0-or-later, and the core written by KOOMPI from the spec, not copied from KDE.**
  - KDE Connect is GPL-2.0 or GPL-3.0 (with KDE e.V.'s later-version clause), and this repo is GPL-3.0.
  - Writing the core ourselves keeps KOOMPI the copyright holder of everything in the iOS app.
    GPL code from other authors on Apple's App Store is contested: VLC was pulled over it in 2011. A copyright holder can publish its own code there.
- **D7, the casting engine in our app. Recommended: (a) WebRTC.**
  - (a) **WebRTC**, set up over the paired Connect link, with no server.
    - The phones use Google's libwebrtc (BSD-3), which already captures an Android screen through MediaProjection.
    - The desktop uses GStreamer's `webrtcsink`/`webrtcbin`, with Intel's hardware encoder (`vah264lpenc`).
    - One engine carries all three directions (phone to desktop, desktop to phone, tablet as a display). It brings its own congestion control and jitter buffer, and its licence keeps the iOS app clean (D6).
    - Practitioners report 30–40 ms from screen to screen on a wired LAN. No rigorous figure exists, so step K0 of the casting track measures it.
  - (b) **Moonlight's protocol, with Sunshine as the desktop host.**
    - It is the lowest-latency option: third parties report 18–25 ms end to end on a wired LAN.
    - Touch and pen are mature. Sunshine captures Hyprland, virtual displays included, and encodes on Intel.
    - But all of it is GPL-3 from other authors, so it cannot go into our iOS app (D6). It only covers the desktop to the phone, and it brings its own PIN pairing and web UI.
  - (c) **RDP**, which KDE Connect's virtual monitor switched to in July 2025 (`krdpserver`).
    Clients are everywhere, but it is built for office latency and there is no Hyprland server.

  Sunshine stays an option for game streaming (§57), installed on request. It is not the engine.
- **D8, the iPhone's own Screen Mirroring. Recommended: receive AirPlay with UxPlay, optional and off until the user turns it on.**
  - With it, KOOMPI appears in the iPhone's, iPad's or Mac's own Screen Mirroring list, with no app to install.
    iOS is 36% of Cambodia's phones and 45% with tablets, and this works before our iOS app exists.
  - [UxPlay](https://github.com/FDH2/UxPlay): GPL-3.0, v1.73.7 (2026-09-04), actively maintained, AUR only, so KOOMPI packages it.
  - The founder has to accept two risks:
    - it uses AirPlay's "legacy" protocol, which UxPlay says future iOS releases may not keep (iOS 27 already broke mirroring once, [#535](https://github.com/FDH2/UxPlay/issues/535));
    - the legal status of the FairPlay part is, in its own words, "unclear".

    Shipping it as an optional component, not on by default, keeps that choice with the user.

## How it fits together

| Part | Language | Does |
|---|---|---|
| `connect-core` | Rust | identity, discovery, link, codec, pairing, transfers, the plugin traits. No Linux or Android code. |
| `koompi-connectd` | Rust | the Linux side of each feature, as a systemd user service with its own sandbox |
| Shell | QML | the bar indicator, the Phone panel, phone notifications, Settings → Phone |
| `koompi connect` | Zig (the `koompi` CLI) | `send FILE`, `devices`, `ring`, for scripts and the file manager |
| Casting | GStreamer and WebRTC inside `koompi-connectd`; libwebrtc in the apps | the phone on the desktop, the desktop on the phone, a tablet as a display (D7) |
| AirPlay receiver | UxPlay (C, GPL-3), packaged, as a user service | an iPhone, iPad or Mac mirroring to KOOMPI with no app (D8) |
| Android app | Kotlin, Compose | the phone side; the core through UniFFI |
| iOS app | Swift (D2) | later; the same core |

`koompi-connectd`:

- **API:** NDJSON over `$XDG_RUNTIME_DIR/koompi-connect.sock`, the same shape `koompi-shelld` speaks (`shell-services/shelld/PROTOCOL.md`), so the shell reads it the way it reads `shelld`.
  The shell subscribes to state and events; the CLI sends commands.
- **Notifications:** a phone's notifications are posted to the shell's notification server with their actions, and a reply goes back as text.
  The shell's server does not offer inline reply today (`services/Notifications.qml` sets `actionsSupported` and `imageSupported` only); Phase 1 turns it on.
- **Clipboard:** read and written through Wayland's data-control protocol, so it works without a focused window.
- **Remote input:** Hyprland's virtual pointer and virtual keyboard protocols.
  This retires the D-Bus override and the `kdeconnectd` rule in `koompi-remotedesktop-portal`.
- **Media, battery, lock:** MPRIS, UPower and logind over D-Bus (`zbus`).
- **Volume:** `wpctl`. The shell keeps PipeWire in-process (native build plan, D1); a phone turning the volume is rare enough for one process call.
- **Files:** received into `~/Downloads`, with progress, then open-or-show in the notification.

The shell:

- **Bar:** a phone glyph with the battery when a paired phone is near. A transfer shows its progress there.
- **Phone panel** in the Control Center: drop files on it to send; send the clipboard; ring the phone; its media; touchpad mode. Messages arrive in Phase 3.
- **Notification center:** the phone's notifications, with their actions and a reply field; dismissing one dismisses it on the phone.
- **Settings → Phone:** pairing by QR, per-device permissions, the receipts (below), forget a device.
- **Send to phone** from the launcher's file results and the file manager's context menu, both through `koompi connect send`.

## Pairing and trust

- **QR first.** Settings → Phone shows a QR code holding the desktop's device id, its certificate's SHA-256 fingerprint, its addresses, and a one-time token.
  The phone scans it, opens TLS pinned to that fingerprint, and presents the token. Both sides are then paired, with no dialog to accept and no code to compare.
- **Stock clients** (KDE Connect, GSConnect) pair the usual way: a request, and the same verification code shown on both screens.
- **Per-device permissions**, off until the user turns them on: remote input, running commands, browsing files, SMS.
  On by default: battery, notifications, clipboard, receiving files, media, ring.
- **Receipts** (§48): Settings → Phone lists what crossed, when, which way and how big. Nothing is synced silently.
- **Forget a device** unpins its certificate. A forgotten device can pair again only through a new QR scan or a new request.
- **Hardening:**
  - The packet parser is fuzzed (`cargo-fuzz`) in CI.
  - Packet size and payload size have limits, and pairing requests are rate-limited.
  - The service runs under systemd's sandbox: `ProtectSystem=strict`, `ReadWritePaths` only for its state and `~/Downloads`, `NoNewPrivileges`, and a restricted set of address families.
- **Firewall:** the protocol keeps KDE Connect's ports, so the rules KOOMPI already ships (`sdata/install/setups/system.sh`, `KOOMPI-KDEConnect` in `koompi-sysdefaults`) stay. Only their label changes.

## Screen casting, both ways

One place to start any of it: a **Cast** page in the Control Center with four actions.

- **Show my phone here.**
- **Show this screen on my phone.**
- **Use my tablet as a second screen.**
- **Cast to a TV.**

An iPhone mirroring through AirPlay arrives on its own, as a prompt.
A cast arrives as a normal window: it floats, resizes and goes fullscreen like any other.

| From → to | How | Notes |
|---|---|---|
| iPhone, iPad, Mac → desktop | AirPlay, received by UxPlay (D8) | No app needed. Audio comes along (AAC). Apple's DRM video (the Apple TV app) stays black. |
| Android → desktop | Our app: MediaProjection into the hardware encoder, then WebRTC (D7) | Android asks for consent every session, shows a status chip, and stops on lock. It can share a single app (Android 14+). |
| Desktop → phone or tablet (mirror) | The ScreenCast portal (`xdg-desktop-portal-hyprland`), then `vah264lpenc`, then WebRTC | Touch on the phone becomes the pointer and the phone's keyboard types, through the same virtual input as remote input (Phase 1). |
| Tablet as a second display (extend) | `hyprctl output create headless`, sized to the tablet, then the same pipeline | Removed when the tablet leaves (`hyprctl output remove`), and Hyprland moves its windows back. |
| Desktop → TV | `gnome-network-displays` (GPL-3): Miracast, Miracast over the LAN, and Chromecast | Send only, and it needs NetworkManager, which KOOMPI uses. |

What the platforms allow, and what follows from it:

- **Controlling the phone from the desktop** uses Android's accessibility service (`dispatchGesture`), as RustDesk, TeamViewer and AnyDesk do. It sits under the same Play declaration as remote input (D5).
  Android 17's Advanced Protection mode reportedly revokes that access from apps that are not accessibility tools, so the app has to say why control stopped.
- **The phone's sound:** Android lets an app capture only media and game audio. Calls are never captured, and any app can opt out.
- **An iPhone cannot be controlled from the desktop.** TeamViewer states it outright: iOS does not allow remote control. The iPhone can only show its screen.
- **An iPhone sharing its screen through our app** (rather than AirPlay):
  - up to iOS 26, a broadcast upload extension, held to about 50 MB;
  - on iOS 27, ScreenCaptureKit, which "replaces ReplayKit for screen streaming and mirroring" and needs no extension.
- **Showing the desktop on an iPhone is allowed:** Moonlight and Microsoft's Windows App are in the App Store. Guideline 4.2.7 constrains only clients that mirror a single app.
- **The ScreenCast portal shows its picker at every request.** `xdg-desktop-portal-hyprland` accepts a `custom_picker_binary`, so KOOMPI can draw the picker in the shell's own style; every app that shares the screen (browsers, OBS, calls) gets it.
  A restore token lets a paired tablet come back without asking again.
- **Firewall:**
  - WebRTC keeps its UDP ports inside the range KOOMPI already opens for Connect (1714–1764), so casting adds no rule.
  - UxPlay is run with fixed ports (`-p`: TCP 7000, 7001, 7100 and UDP 6000, 6001, 7011), and that rule is added only when AirPlay is turned on.

Privacy:

- **The desktop shown elsewhere is screen sharing.** The bar's recording light says so, with the device's name and a stop button, for as long as it lasts.
- A phone cannot start viewing the desktop on its own. Only the desktop can start it, unless a per-device permission (off by default) lets that device ask.
- AirPlay asks before showing anything, unless the user marked that device as trusted.

## Phases

Each phase is a campaign in `.work/` (AGENTS.md). One worker per job, and the lead verifies.
End to end it is about six to eight months, plus the casting track's 11–15 weeks, which runs beside the phases with its own worker.
Phase 1 pays off on its own after about a month: KOOMPI's desktop side is new, and every phone keeps the app it already has.
So does casting step K1: an iPhone can mirror to KOOMPI the week it lands.

### Phase 0: the protocol, written down and tested (about 1 week)

- [ ] `PROTOCOL.md` in `koompi/connect`: KDE's `protocol.md` is the base, cited, not copied. Ours adds the notes an implementer needs and every KOOMPI extension packet as it is designed.
  These are the parts of KDE's protocol.md the core has to get right:
  - discovery by UDP broadcast on 1716 and by mDNS as `_kdeconnect._udp`;
  - links on TCP 1716–1764, and payloads on 1739–1764;
  - TLS roles reversed from TCP roles;
  - the identity sent again inside TLS;
  - pairing with a timestamp;
  - payloads on a separate TLS connection, where the sender is the server.
- [ ] `connect-core`: discovery, the link, pairing, ping.
- [ ] The conformance suite: our core against a real `kdeconnectd`, both desktop peers, in a private network namespace on a private bus. No phone is needed.
  It includes the two 2025 holes as tests:
  - [CVE-2025-66270](https://kde.org/info/security/advisory-20251128-1.txt): abort when the identity inside TLS differs from the one outside.
  - [CVE-2025-32898](https://kde.org/info/security/advisory-20250418-3.txt): the verification key includes the pairing timestamp.

**Done when** the core pairs with `kdeconnectd` in the suite, both directions, and they exchange a ping and a file.

### Phase 1: `koompi-connectd` replaces `kdeconnectd`, stock phone apps (about 3–4 weeks)

- [ ] The features people use, against the stock KDE Connect app on Android and iOS:
  - battery;
  - notifications, with actions and reply;
  - clipboard, both ways;
  - share files, links and text;
  - media control, both ways;
  - ring the phone, ping;
  - the phone as a touchpad and keyboard, and as a presentation remote;
  - the laptop's volume from the phone;
  - mute or pause media during a call.
- [ ] The shell: bar glyph, Phone panel, phone notifications with inline reply, Settings → Phone, Send to phone.
- [ ] Discovery that works:
  - advertise `_kdeconnect._udp` through Avahi, which already runs on KOOMPI;
  - answer the UDP broadcast too;
  - put the desktop's addresses in the QR code.

  An iPhone can only use mDNS, because broadcast needs an entitlement Apple grants on request.
  The firewall test (`tests/test_firewall_defaults.sh`) must show mDNS reaching Avahi under KOOMPI's deny-incoming default.
- [ ] **Keep the pairing.** On first start, `koompi-connectd` takes over KDE Connect's identity (`~/.config/kdeconnect/certificate.pem`, `privateKey.pem`, `trusted_devices`).
  The phone sees the same device and the same certificate, so a paired phone stays paired through the switch.
- [ ] Remove KDE Connect from both install routes:
  - the `kdeconnect` package from `koompi-apps` and `setup`;
  - the D-Bus override and the autostart entry;
  - the `kdeconnectd` rule in `koompi-remotedesktop-portal`.

  A migration does the same on existing homes.
- [ ] The parity list, in the suite against `kdeconnectd` wherever both sides are desktop features.

**Done when:**
- The founder's phone, still on the stock KDE Connect app, does everything on the parity list with `koompi-connectd`, checked on the live seat.
- `kdeconnect` is gone from both install routes.
- The UX targets below hold for battery, notifications, clipboard and files.

### Phase 2: KOOMPI Connect for Android (about 6–8 weeks)

- [ ] Onboarding:
  - scan the QR;
  - ask for each permission only when its feature is first used, and say why;
  - walk the user through the battery-manager exemption on Xiaomi, Oppo, Realme, Vivo and Samsung, the phones whose managers cause KDE Connect's disconnect reports.
- [ ] A connection that stays up:
  - a `connectedDevice` foreground service, not `dataSync`, which Android 15 caps at 6 hours a day;
  - reconnect on every Wi-Fi change, with no polling;
  - Android 17's `ACCESS_LOCAL_NETWORK` permission, which any LAN traffic needs once the app targets SDK 37.

  Evaluate a CompanionDeviceManager association with the desktop for running in the background. Not verified yet.
- [ ] The Phase 1 parity list, with a better UI:
  - a Quick Settings tile: send the clipboard, or ring the desktop;
  - the share target: send from any app;
  - a home-screen widget: the desktop's battery, and a drop zone;
  - per-app notification filters.
- [ ] SMS: read and reply from the desktop, in the Play build under the cross-device exception (D5).
- [ ] Say what Android withholds, in the app: since Android 15, one-time codes and other "sensitive" notifications are hidden from every listener without a system role we cannot hold.
- [ ] Extensions over D1, announced in capabilities:
  - resumable transfers;
  - several files at once;
  - receipts on the phone too.

**Done when** the app does everything on the parity list against `koompi-connectd`. The UX targets below must hold on three phones: one Samsung, one Xiaomi or Redmi, and one Oppo or Realme.

### Phase 3: better than KDE Connect (about 6–10 weeks, one feature at a time)

Apple's Continuity is the yardstick, with no cloud. Each feature is its own job, in roughly this order:

1. **Universal clipboard** with images and files, not just text (KDE Connect's is text only).
   The desktop to the phone is automatic.
   The phone to the desktop stays one tap, because Android 10 and later let only the focused app or the keyboard read the clipboard: the tile, the share sheet, the notification's button.
   Making that tap feel like nothing is the UX work.
2. **Messages on the desktop:** SMS threads in the Phone panel, with send and reply, under Play's cross-device exception (D5).
3. **The phone as a webcam:** CameraX encodes H.264, and the desktop decodes it into a `v4l2loopback` device that every app sees as a camera.
   Android's own webcam mode is USB only, and only on phones whose maker opted in (Android 14 QPR1 and later), so the network mode has to be built.
   A camera foreground service cannot start from the background, so the phone shows a screen while it streams.
4. **The phone as a scanner:** photograph a page, have it edge-corrected and land as a PDF in the desktop's Downloads, or in the Vault (§83) when that exists.
5. **Handoff:** "open this on the phone" for the current browser tab and the current file, and the reverse.
6. **Photos:** the phone's new photos offered on the desktop, pulled only when asked.
7. **Share with anyone nearby,** not only paired devices: speak LocalSend's protocol (v2, Apache-2.0, REST over HTTPS on port 53317, which KOOMPI's firewall already opens).
   The same Send menu then reaches a friend's phone running LocalSend, with no pairing.

### Casting track (alongside Phases 1–4)

Each step stands on its own, and the order follows what they depend on.

- [ ] **K0, measure first (about 1 week).** A screen-to-screen latency rig: a timestamp drawn on the source screen, filmed with the received one.
  Run it on the founder's Arc 140V and on a T1 machine (UHD 620 class). Measure the WebRTC pipeline (D7), and Moonlight and scrcpy beside it for reference.
  The targets below are confirmed or corrected from these numbers.
- [ ] **K1, iPhone, iPad and Mac to the desktop over AirPlay (about 1–2 weeks; needs nothing from Connect).**
  - Package UxPlay.
  - Wrap it as a user service that runs only while AirPlay is on.
  - The accept prompt. Check first that UxPlay can hold a connection until the user accepts (its PIN option).
    If it cannot, AirPlay is advertised only while the Cast page is open.
  - The firewall rule.
  - Its window: floating, centred, its title the device's name.
- [ ] **K2, Android to the desktop (about 3–4 weeks; after Phase 2).**
  - Our app's MediaProjection stream, with sound.
  - Control from the desktop's mouse and keyboard.
  - Single-app sharing.
- [ ] **K3, the desktop to a phone or tablet (about 3–4 weeks; after Phase 2).**
  - The portal capture with KOOMPI's own picker, then the hardware encoder.
  - Touch and keyboard back to the desktop.
  - The recording light while it runs.
- [ ] **K4, a tablet as a second display (about 2–3 weeks; after K3).** A headless output sized to the tablet, with touch.
  Pen pressure needs a virtual tablet device; verify how Hyprland takes one (Sunshine uses uinput, which KOOMPI already opens to `ydotool`) before promising it.
- [ ] **K5, cast to a TV (about 1 week; needs nothing from Connect).** Package `gnome-network-displays`, and give it the Cast page's fourth action.
- [ ] **K6, the iPhone through our app (with Phase 4).** Desktop to iPhone and iPad as in K3.
  iPhone to the desktop through ScreenCaptureKit on iOS 27, so that it works where AirPlay is turned off or breaks.

Targets, from K0's numbers once measured. These are the starting points:

| What | Target on 5 GHz Wi-Fi |
|---|---|
| The desktop shown on a phone, 1080p at 30 fps, screen to screen | under 80 ms |
| A tablet as a second display, at 60 fps | under 60 ms |
| An Android phone shown on the desktop | under 100 ms |
| CPU while encoding 1080p30 on a T1 machine | under 15% |

For reference: scrcpy claims 35–70 ms, and Moonlight is reported at 18–25 ms on a wired LAN.

### Phase 4: KOOMPI Connect for iOS (about 6–8 weeks)

- [ ] What iOS lets a third-party app do:
  - share files and links, through a share extension;
  - the clipboard while the app is open (`UIPasteControl` avoids iOS 16's paste prompt);
  - media control, remote input and the presenter;
  - ring the desktop;
  - the phone's battery.

  KDE Connect for iOS 0.5.7 (October 2026) is the floor to beat: clipboard, sharing, touchpad and keyboard, presenter, commands.
- [ ] What it does not allow:
  - mirroring other apps' notifications;
  - SMS;
  - a connection in the background: no app keeps a daemon, so the link lives while the app is open and for a short background task.
- [ ] Discovery by Bonjour only: `NSBonjourServices` lists `_kdeconnect._udp`, with a local-network usage string. Broadcast needs Apple's multicast entitlement.
- [ ] The UI stack per D2.

**Done when** an iPhone does everything on that list with `koompi-connectd` after a QR scan.

### Later, not in this plan

- **Off the LAN:** reach the home machine over the user's own WireGuard tunnel (§48, §86). Never through a KOOMPI relay unless the user opts in.
- **Bluetooth:** wake and small messages when Wi-Fi has client isolation, as on many school and café networks.
  KDE's own Bluetooth backend made A2DP audio stutter under PipeWire and was turned off by default in 26.08 ([bug 513536](https://bugs.kde.org/show_bug.cgi?id=513536)). Ours starts from that lesson.
- **iPhone notifications and messages on the desktop over Bluetooth LE:** ANCS for notifications, MAP for messages. BlueZ can act as the client.
  - [zackb/tether](https://github.com/zackb/tether) (MIT, C++, 2026) does Wi-Fi over TLS with Bonjour, and ANCS and MAP over BLE, with its own iOS app. It is the closest design to study.
  - [iphonebridge](https://github.com/gabrielmeir53/iphonebridge) reports that only Intel adapters bond reliably with an iPhone, so this depends on the hardware.
  - ANCS actions are only a positive and a negative one; no reply text was found in the spec.
- **One keyboard and mouse across the desktop and a tablet**, as Universal Control does: push the pointer off the screen's edge onto the tablet.
  `xdg-desktop-portal-hyprland` now offers the InputCapture portal that this needs.
- **Context capsules and the Partner on the phone** (§48, §86): handoff of drafts and AI context, continue or fork. They depend on the memory stack, not on this plan.

## UX targets

Measured like the native build plan's N0, each with a script, and held by later phases:

| What | Target |
|---|---|
| QR pairing, from opening Settings → Phone to paired | under 15 s |
| Reconnect after the phone rejoins the Wi-Fi | under 5 s |
| A phone notification appearing on the desktop | under 1 s |
| A file transfer | at least 80% of `iperf3` on the same link |
| Android battery attributable to the app, idle, connected | at most 1% a day |
| `koompi-connectd` idle | at most 10 MB PSS, no processes forked |

## Risks

- **Google Play policy** decides what the Play build carries (D5).
  - SMS and the call log need the declaration form's cross-device exception, which Google calls temporary.
  - Remote input needs an accessibility declaration that Play may question.
  - Each Android release tightens something: `dataSync` limits in 15, the local network permission in 17.
- **Battery managers** on the phones common in Cambodia kill background apps whatever the app does right. Onboarding has to walk the user through it, and the reconnect target has to be measured on those phones, not an emulator.
- **Client isolation** on school and café Wi-Fi blocks every device-to-device packet. Until Bluetooth lands, the answer is the phone's hotspot; the app should say so rather than search forever.
- **KDE changes the protocol**, as when it dropped version 7 in September 2026, and it has security fixes every implementation must follow (two in 2025).
  The conformance suite against the current `kdeconnectd` runs in CI.
- **A phone app is a second product.** It needs an owner, a release process, store accounts and crash reporting that stays on the device unless the user sends it.
- **iOS** cannot match Android (Phase 4), and the gap must be stated in the app, not discovered.
- **AirPlay** rests on a protocol Apple does not publish and may change, and a FairPlay part whose legal status is unclear (D8).
- **Casting speed on the low-end machines** (T0/T1) depends on their hardware encoder. K0 measures it before anything is promised on them.
