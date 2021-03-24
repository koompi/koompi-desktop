use super::desktop_item::DesktopItem;
use super::background::WallpaperItem;
use super::configs::DesktopConf;
use super::errors::DesktopError;
use std::path::{Path, PathBuf};
const WALLPAPERS_DIR: &str = "wallpapers";

pub struct DesktopManager {
    desktop_items: Vec<DesktopItem>,
    wallpaper_items: Vec<WallpaperItem>,
    conf: DesktopConf,
    conf_path: PathBuf,
}

impl DesktopManager {
    pub fn new<P: AsRef<Path>>(file: P) -> Result<Self, DesktopError> {
        // PathBuf::from("/home/hangleang/Desktop")
        if let Some(desktop_dir) = dirs_next::desktop_dir() {
            let sys_wallpapers_dir = Path::new("/usr/share").join(WALLPAPERS_DIR);
            let local_wallpapers_dir = dirs_next::data_local_dir().unwrap().join(WALLPAPERS_DIR);
            let desktop_items: Vec<DesktopItem> = desktop_dir.read_dir()?.filter_map(|entry| DesktopItem::from_file(entry.unwrap().path()).ok()).collect();
            let mut wallpaper_items: Vec<WallpaperItem> = Vec::new();
            if sys_wallpapers_dir.exists() && sys_wallpapers_dir.is_dir() {
                let sys_wallpaper_items = sys_wallpapers_dir.read_dir()?.filter_map(|entry| WallpaperItem::from_file(entry.unwrap().path(), false).ok());
                wallpaper_items.extend(sys_wallpaper_items);
            }
            if local_wallpapers_dir.exists() && local_wallpapers_dir.is_dir() {
                let local_wallpaper_items = local_wallpapers_dir.read_dir()?.filter_map(|entry| WallpaperItem::from_file(entry.unwrap().path(), true).ok());
                wallpaper_items.extend(local_wallpaper_items);
            }
            wallpaper_items.sort();

            Ok(Self {
                desktop_items, wallpaper_items,
                conf_path: file.as_ref().to_path_buf(),
                conf: DesktopConf::new(file)?,
            })
        } else {
            Err(DesktopError::DesktopNotFound)
        }
    }

    pub fn config(&self) -> &DesktopConf {
        &self.conf
    }

    pub fn desktop_items(&self) -> &[DesktopItem] {
        self.desktop_items.as_slice()
    }

    pub fn wallpaper_items(&self) -> &[WallpaperItem] {
        self.wallpaper_items.as_slice()
    }

    pub fn save(&mut self, conf: DesktopConf) -> Result<(), DesktopError> {
        let toml = toml::to_string_pretty(&conf)?;
        std::fs::write(self.conf_path.to_path_buf(), toml)?;
        self.conf = conf;
        Ok(())
    }
}
