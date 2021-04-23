use dbus::arg::PropMap;
use dbus::blocking::{Connection, Proxy};
use dbus::Error;
use std::collections::HashMap;
use std::time::Duration;
const SERVICE_NAME: &str = "org.freedesktop.NetworkManager";
const SERVICE_INTERFACE: &str = "org.freedesktop.NetworkManager";
const ACESSPOINT_INTERFACE: &str = "org.freedesktop.NetworkManager.AccessPoint";
#[derive(Default, Debug, PartialEq)]
pub struct AccessPoint {
    pub ssid: String,
    pub strenght: u8,
    pub last_seen: i32,
    pub hwaddress: String,
    pub flags: u32,
    pub frequency: u32,
    pub max_bitrate: u32,
    pub mode: u32,
    pub rns_flags: u32,
    pub wpa_flags: u32,
}

pub fn get_accesspoints() -> Result<Vec<AccessPoint>, Error> {
    let mut vec_accesspoint: Vec<AccessPoint> = Vec::new();
    let conn = match Connection::new_system() {
        Ok(conn) => conn,
        Err(e) => {
            println!("Error: {:?}", e);
            dbus::blocking::Connection::new_system()?
        }
    };
    let mut proxy = conn.with_proxy(
        SERVICE_NAME,
        "/org/freedesktop/NetworkManager",
        Duration::from_millis(2000),
    );
    // Now we make the method call. The ListNames method call take zero input paramters and one output parameter which is an array of strings.Duration
    // Therefore the input is a zero tuple "()" , and the output is a single tuple "(names, "
    let result: Result<Vec<dbus::Path<'static>>, dbus::Error> = proxy
        .method_call(SERVICE_INTERFACE, "GetDevices", ())
        .and_then(|r: (Vec<dbus::Path<'static>>,)| Ok(r.0));
    let device_paths = match result {
        Ok(res) => res,
        Err(e) => {
            println!("Error : {:?}", e);
            Vec::new()
        }
    };
    use dbus::blocking::stdintf::org_freedesktop_dbus::Properties;
    for i in &device_paths {
        proxy = conn.with_proxy(SERVICE_NAME, i, Duration::from_millis(500));
        let dev_type: u32 = match proxy.get("org.freedesktop.NetworkManager.Device", "DeviceType") {
            Ok(res) => res,
            Err(e) => {
                println!("Error: {:?}", e);
                2
            }
        };
        if dev_type == 2 {
            let wifi_deice = Proxy::new(SERVICE_NAME, i, Duration::from_millis(500), &conn);
            let dict: PropMap = HashMap::new();
            let _device: Result<(), Error> = wifi_deice.method_call(
                "org.freedesktop.NetworkManager.Device.Wireless",
                "RequestScan",
                (dict,),
            );
            std::thread::sleep(Duration::from_millis(1000));
            let accessspoint: Result<Vec<dbus::Path<'static>>, dbus::Error> = wifi_deice
                .method_call(
                    "org.freedesktop.NetworkManager.Device.Wireless",
                    "GetAccessPoints",
                    (),
                )
                .and_then(|r: (Vec<dbus::Path<'static>>,)| Ok(r.0));
            match accessspoint {
                Ok(data) => {
                    data.into_iter().for_each(|access_path| {
                        // println!("Path: {:?}", access_path);
                        let p = conn.with_proxy(
                            SERVICE_INTERFACE,
                            access_path,
                            Duration::from_millis(500),
                        );
                        let data: Result<Vec<u8>, dbus::Error> =
                            p.get(ACESSPOINT_INTERFACE, "Ssid");
                        let address: Result<String, dbus::Error> =
                            p.get(ACESSPOINT_INTERFACE, "HwAddress");
                        let strength: Result<u8, dbus::Error> =
                            p.get(ACESSPOINT_INTERFACE, "Strength");
                        let result_strenght = u8::from_le_bytes(
                            [match strength {
                                Ok(d) => d,
                                Err(e) => {
                                    println!("Error: {:?}", e);
                                    // default signal when error
                                    50
                                }
                            }; 1],
                        );
                        let longdata = match data {
                            Ok(ssid_res) => ssid_res,
                            Err(e) => {
                                println!("Error: {:?}", e);
                                Vec::new()
                            }
                        };
                        let acutal_data = std::str::from_utf8(&longdata);
                        vec_accesspoint.push(AccessPoint {
                            ssid: match acutal_data {
                                Ok(a_data) => a_data.to_string(),
                                Err(e) => {
                                    println!("Error: {:?}", e);
                                    String::from("Unknown")
                                }
                            },
                            hwaddress: match address {
                                Ok(addr) => addr.to_string(),
                                Err(e) => {
                                    println!("Error: {:?}", e);
                                    String::from("192.168.1.1")
                                }
                            },
                            strenght: result_strenght,
                            ..Default::default()
                        });
                    });
                }
                Err(e) => {
                    println!("Error: {:?}", e);
                }
            }
        } else {
            continue;
        }
    }
    vec_accesspoint.sort_by(|a, b| a.ssid.cmp(&b.ssid));
    vec_accesspoint.dedup_by(|a, b| a.ssid == b.ssid);
    Ok(vec_accesspoint)
}

#[test]
fn test_access() {
    match get_accesspoints() {
        Ok(res) => {
            println!("Len of accesspiont: {}", res.len());
            for i in res {
                println!("Result: {:?}", i.ssid)
            }
        }
        Err(e) => println!("Error: {:?}", e),
    }
    assert_eq!(1, 1)
}
