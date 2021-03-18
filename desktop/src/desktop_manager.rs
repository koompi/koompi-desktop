use super::desktop_item::DesktopItem;
use super::configs::DesktopConf;
use super::errors::DesktopError;
use std::path::{Path, PathBuf};

pub struct DesktopManager {
    desktop_items: Vec<DesktopItem>,  
    conf: DesktopConf,
    conf_path: PathBuf,
}

impl DesktopManager {
    pub fn new<P: AsRef<Path>>(file: P) -> Result<Self, DesktopError> {
        let local_dir = dirs_next::desktop_dir().unwrap(); 
        let dir = local_dir.read_dir()?;
        let desktop_items: Vec<DesktopItem> = dir.filter_map(|entry| DesktopItem::from_file(entry.unwrap().path()).ok()).collect();

        Ok(Self {
            desktop_items,
            conf_path: file.as_ref().to_path_buf(),
            conf: DesktopConf::new(file)?,
        })
    }

    pub fn config(&self) -> &DesktopConf {
        &self.conf
    }

    pub fn desktop_items(&self) -> &[DesktopItem] {
        self.desktop_items.as_slice()
    }

    pub fn save(&mut self, conf: DesktopConf) -> Result<(), DesktopError> {
        let toml = toml::to_string_pretty(&conf)?;
        std::fs::write(self.conf_path.to_path_buf(), toml)?;
        self.conf = conf;
        Ok(())
    } 
}