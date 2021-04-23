const PATH: &str = "/sys/class";
use std::path::Path;
use udev::Device;
pub fn set_device_path(path: &str) -> Result<udev::Device, std::io::Error> {
    Device::from_syspath(Path::new(PATH).join(path).as_path())
}
pub fn get_property(property: &str) -> u32 {
    let mut max_val: u32 = 0;
    match set_device_path("backlight/intel_backlight") {
        Ok(dev) => match dev.attribute_value(property) {
            Some(val) => match val.to_str() {
                Some(val_str) => match val_str.parse::<u32>() {
                    Ok(data) => max_val = data,
                    Err(e) => eprintln!("Error: {:?}", e),
                },
                None => eprintln!("failed to convert str"),
            },
            None => println!("No value"),
        },
        Err(e) => eprintln!("Error Type: {:?}", e),
    }
    max_val
}
