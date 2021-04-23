#![allow(dead_code)]
use crate::library::misc::device_file::{get_property, set_device_path};
use dbus::blocking::Connection;
use std::fs::OpenOptions;
use std::io::prelude::*;
#[derive(Debug, Clone)]
pub struct Brightness {
    device: BrightnessDevice,
}
impl Brightness {
    pub fn new() -> Self {
        Self {
            device: BrightnessDevice::new(),
        }
    }
    pub fn set_percent(&mut self, percent: u32) {
        self.device.set_bright(percent);
    }
    pub fn get_percent(&self) -> u32 {
        self.device.get_current_level()
    }
    pub fn get_max_percent(&self) -> u32 {
        self.device.get_max_bright()
    }
    pub fn login1_set_brightness(&mut self, level: u32) -> Result<(), Box<dyn std::error::Error>> {
        match self.device.set_dbus_bright(level) {
            Ok(()) => {}
            Err(e) => eprintln!("Not crash but lovable error: {:?}", e),
        }
        Ok(())
    }
    pub fn save_data(&mut self) {
        self.device.save_device_data();
    }
    pub fn restore(&mut self) -> Result<bool, Box<dyn std::error::Error>> {
        self.device.restore();
        Ok(true)
    }
    pub fn information(&self) -> Vec<u32> {
        self.device.info()
    }
}
#[derive(Debug, Clone)]
struct BrightnessDevice {
    id: &'static str,
    class: &'static str,
    max_brightness: u32,
    current_brightness: u32,
}

impl BrightnessDevice {
    fn new() -> Self {
        let max_bright = get_property("max_brightness");
        let cur_bright = get_property("brightness");
        Self {
            id: "intel_backlight",
            class: "backlight",
            max_brightness: max_bright,
            current_brightness: cur_bright,
        }
    }
    fn save_device_data(&mut self) {
        let file = OpenOptions::new().write(true).open(self.get_path());
        match file {
            Ok(mut pfile) => match pfile.write(&[self.current_brightness as u8]) {
                Ok(data) => {
                    println!("write to file {:?} bytes", data);
                }
                Err(e) => {
                    eprintln!("Error: {:?}", e);
                }
            },
            Err(e) => eprintln!("failed to open the file: {:?}", e),
        }
    }

    fn restore(&mut self) {
        let mut buffer: String = String::new();
        let file = OpenOptions::new().read(true).open(self.get_path());
        match file {
            Ok(mut pfile) => {
                pfile.read_to_string(&mut buffer).unwrap();
            }
            Err(e) => println!("read data: {:?}", e),
        }
        println!("data: {}", buffer);
        match buffer.parse::<u32>() {
            Ok(data) => {
                println!("memory buffer: {:?}", data);
                self.current_brightness = data;
            }
            Err(e) => println!("{:?}", e),
        };
        self.update(self.current_brightness);
        self.set_bright(self.val_to_percent(self.current_brightness, true));
    }

    fn get_path(&self) -> std::path::PathBuf {
        let mut xdg_dir: String = String::new();
        match std::env::var("XDG_RUNTIME_DIR") {
            Ok(xdg_path) => xdg_dir = xdg_path,
            Err(e) => println!("path to xdg : {:?}", e),
        }
        std::path::Path::new(&xdg_dir)
            .join("brightnessctl")
            .join(self.class)
            .join(self.id)
    }
    // set current brightness of the system
    fn set_bright(&mut self, level: u32) {
        match set_device_path(format!("{}/{}", self.class, self.id).as_str()) {
            Ok(mut dev) => {
                // give time for cpu to execute on other processes
                std::thread::sleep(std::time::Duration::from_millis(10));
                let value = self.percent_to_value(level);
                match dev.set_attribute_value("brightness", value.to_string()) {
                    Ok(()) => {
                        self.update(value);
                    }
                    Err(e) => {
                        println!("Error: {:?}", e);
                    }
                }
            }
            Err(e) => eprint!("error: {:?}", e),
        }
    }
    // return roundf(powf(percent / 100, p.exponent) * d->max_brightness);
    // calculate percent value range 0..=100 by by round_up(f32::powf(input_v / 100, 1) * max_value, -2) as u32
    fn percent_to_value(&self, val: u32) -> u32 {
        math::round::ceil(
            (f32::powf(val as f32 / 100.0, 1.0) * self.get_max_bright() as f32) as f64,
            -2,
        ) as u32
    }
    // if (val < 0)
    // 		return 0;
    // 	float ret = powf(val / d->max_brightness, 1.0f / p.exponent) * 100;
    // 	return rnd ? roundf(ret) : ret;
    fn val_to_percent(&self, val: u32, rnd: bool) -> u32 {
        if val.le(&0) {
            1
        } else {
            let ret = f32::powf(val as f32 / self.get_max_bright() as f32, 1.0) * 100.0;
            if rnd {
                math::round::ceil(ret as f64, 2) as u32
            } else {
                ret as u32
            }
        }
    }
    fn get_max_bright(&self) -> u32 {
        self.max_brightness
    }
    fn set_dbus_bright(&mut self, level: u32) -> Result<(), Box<dyn std::error::Error>> {
        if level.gt(&100) || level.lt(&0) {
            Err(Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "input value between 0 - 100",
            )))
        } else {
            let sys_conn = Connection::new_system().unwrap();
            let proxy = sys_conn.with_proxy(
                "org.freedesktop.login1",
                "/org/freedesktop/login1/session/auto",
                std::time::Duration::from_millis(100),
            );
            proxy.method_call(
                "org.freedesktop.login1.Session",
                "SetBrightness",
                (self.class, self.id, self.percent_to_value(level)),
            )?;
            self.update(self.percent_to_value(level));

            Ok(())
        }
    }
    fn get_current_level(&self) -> u32 {
        self.val_to_percent(self.current_brightness, true)
    }
    fn info(&self) -> Vec<u32> {
        vec![self.max_brightness, self.get_current_level()]
    }
    fn update(&mut self, current: u32) {
        self.current_brightness = current;
    }
}

#[cfg(test)]
mod tests {
    use super::Brightness;
    use std::time::Duration;
    #[test]
    fn test_bright() {
        let mut bright = Brightness::new();
        // bright.login1_set_brightness(101);
        println!("current : {}", bright.get_percent());
        println!("max_percent: {}", bright.get_max_percent());
        for i in 1..=100 {
            std::thread::sleep(Duration::from_millis(10));
            match bright.login1_set_brightness(i) {
                Ok(()) => {}
                Err(e) => println!("Error: {:?}", e),
            }
        }

        println!("current : {}", bright.get_percent());
        assert_eq!(100, bright.get_percent());
        assert_eq!(2 + 2, 3);
    }
}
