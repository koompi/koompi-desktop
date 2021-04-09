use std::path::{PathBuf, Path};
use std::collections::HashMap;
use std::fs;
use crate::constants::{DESKTOP_ENTRY, ICON, INODE_DIR, ICON_THEME, INHERITS};
use crate::configs::{PersistentData, Resources, desktop_item_conf::Sorting};
use super::desktop_item::DesktopItem;
use super::background::WallpaperItem;
use super::configs::DesktopConf;
use super::errors::DesktopError;
use lazy_static::lazy_static;

const WALLPAPERS_DIR: &str = "wallpapers";
const ICONS_DIR: &str = "icons";
lazy_static! {
    static ref LOCAL_DIR: PathBuf = dirs_next::data_local_dir().unwrap().join(WALLPAPERS_DIR);
    static ref DESK_DIR: PathBuf = dirs_next::desktop_dir().unwrap_or(dirs_next::home_dir().unwrap().join("Desktop"));
    static ref DEF_THEME: PathBuf = PathBuf::from("/usr/share").join(ICONS_DIR).join("default").join("index.theme");
}

pub struct DesktopManager {
    desktop_items: Vec<DesktopItem>,
    wallpaper_items: Vec<WallpaperItem>, 
    desktop_icons: HashMap<String, PathBuf>,
    conf: DesktopConf,
}

impl DesktopManager {
    pub fn new() -> Result<Self, DesktopError> {
        let conf = DesktopConf::load()?;
        let desktop_icons = DesktopIconResource::resources(None);
        let desktop_items: Vec<DesktopItem> = DESK_DIR.read_dir()?.filter_map(|e| e.ok()).filter_map(|entry| {
            let file = entry.path();
            let icon_path = Self::get_icon_path(file.to_path_buf(), &desktop_icons);

            DesktopItem::new(file, icon_path).ok()
        }).collect();

        let mut wallpaper_items: Vec<WallpaperItem> = WallpaperResource::resources(Some(1)).values().filter_map(|path| WallpaperItem::from_file(path).ok()).collect();
        wallpaper_items.sort();

        let mut desktop_mn = Self {
            desktop_items, wallpaper_items, conf, desktop_icons
        };
        desktop_mn.sort_desktop_items(desktop_mn.conf.desktop_item_conf.sorting, desktop_mn.conf.desktop_item_conf.sort_descending);

        Ok(desktop_mn)
    }

    pub fn create_new_folder(&mut self) -> Result<Vec<DesktopItem>, DesktopError> {
        let prefix_name = "untitled folder";
        let num_untitled_folders = DESK_DIR.read_dir()?.filter(|entry| {
            let file_name = entry.as_ref().unwrap().file_name(); 
            if let Ok(path_str) = file_name.into_string() {
                path_str.starts_with(prefix_name)
            } else {
                false
            }
        }).count();
        let new_folder = if num_untitled_folders == 0 {
            prefix_name.to_string()
        } else {
            format!("{} {}", prefix_name, num_untitled_folders+1)
        };
        let full_path = DESK_DIR.join(&new_folder);

        fs::create_dir(full_path.to_path_buf())?;
        let icon_path = Self::get_icon_path(full_path.to_path_buf(), &self.desktop_icons);
        self.desktop_items.push(DesktopItem::new(full_path, icon_path)?);

        Ok(self.desktop_items.to_owned())
    }

    pub fn add_wallpaper<P: AsRef<Path>>(&mut self, path: P) -> Result<(DesktopConf, Vec<WallpaperItem>), DesktopError> {
        let mut res = false;
        if path.as_ref().exists() && path.as_ref().is_file() {
            if let Some(ext) = path.as_ref().extension() {
                let exts = ext.to_str().unwrap();
                if exts == "png" || exts == "jpg" {
                    if let Some(file_name) = path.as_ref().file_name() {
                        if !LOCAL_DIR.exists() {
                            fs::create_dir_all(LOCAL_DIR.to_path_buf())?;
                        }

                        let local_path = if LOCAL_DIR.join(file_name).exists() {
                            let mut local_path = LOCAL_DIR.join(file_name);
                            if let Some(name) = path.as_ref().file_stem() {
                                local_path = LOCAL_DIR.join(format!("{}-(1)", name.to_str().unwrap())).with_extension(ext);
                            }
        
                            local_path
                        } else {
                            LOCAL_DIR.join(file_name)
                        };

                        fs::copy(path.as_ref(), local_path.to_path_buf())?;
                        self.wallpaper_items.push(WallpaperItem::from_file(local_path.to_path_buf())?);
                        self.conf.background_conf.wallpaper_conf.wallpaper_path = local_path;

                        res = true;
                    }
                }
            }
        } 

        if res {
            Ok((self.conf.to_owned(), self.wallpaper_items.to_owned()))
        } else {
            Err(DesktopError::PathIsNotAFile(path.as_ref().display().to_string()))
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

    pub fn sort_desktop_items(&mut self, sorting: Sorting, sort_desc: bool) {
        match sorting {
            Sorting::Name => self.desktop_items.sort_by(|a, b| if sort_desc {b.name.cmp(&a.name)} else {a.name.cmp(&b.name)}),
            Sorting::Type => self.desktop_items.sort_by(|a, b| if sort_desc {b.entry_type.cmp(&a.entry_type)} else {a.entry_type.cmp(&b.entry_type)}),
            Sorting::Date => self.desktop_items.sort_by(|a, b| {
                let mut ordering = std::cmp::Ordering::Equal;
                if let Ok(a_metadata) = a.path.metadata() {
                    if let Ok(b_metadata) = b.path.metadata() {
                        if let Ok(a_modified) = a_metadata.modified() {
                            if let Ok(b_modified) = b_metadata.modified() {
                                ordering = if sort_desc {
                                    b_modified.cmp(&a_modified)
                                } else {
                                    a_modified.cmp(&b_modified)
                                };
                            }
                        }
                    }
                }
                ordering
            }),
            Sorting::Manual => self.desktop_items.sort()
        }
    }

    fn get_icon_path(file: PathBuf, desktop_icons: &HashMap<String, PathBuf>) -> Option<PathBuf> {
        let mut icon_name = None;

        if file.is_file() {
            if let Some(extension) = file.extension() {
                if extension.eq("desktop") {
                    let entry = freedesktop_entry_parser::parse_entry(&file).unwrap();
                    let desktop_entry = entry.section(DESKTOP_ENTRY);
                    icon_name = desktop_entry.attr(ICON).map(ToOwned::to_owned);
                }
            }
        }
        if icon_name.is_none() {
            let mime_type = mime_guess::from_path(file.to_path_buf());
            let mime_type = mime_type.first_raw().unwrap_or(INODE_DIR);
            let mime_type_colon = format!("{}:", mime_type);
            icon_name = read_lines(PathBuf::from("/usr/share/mime").join("generic-icons")).unwrap().find_map(|line| if let Ok(line) = line {
                line.strip_prefix(&mime_type_colon).map(ToOwned::to_owned)
            } else {
                None
            });
        }
        icon_name.map(|name| {
            let icon_path = PathBuf::from(&name);
            if icon_path.is_absolute() {
               icon_path
            } else {
                desktop_icons.get(name.split('.').collect::<Vec<&str>>()[0]).map(ToOwned::to_owned)
                    .unwrap_or(PathBuf::from("/usr/share/icons/koompi.svg"))
            }
        })
    }
}

pub struct WallpaperResource;
impl Resources for WallpaperResource {
    fn relative_path() -> PathBuf {
        PathBuf::from(WALLPAPERS_DIR)
    }
}

pub struct DesktopIconResource;
impl Resources for DesktopIconResource {
    fn relative_path() -> PathBuf {
        let mut config = configparser::ini::Ini::new();
        let _ = config.load(DEF_THEME.to_str().unwrap());
        let def_theme = config.get(ICON_THEME, INHERITS);
        let base_path = if let Some(theme) = def_theme {
            PathBuf::from(ICONS_DIR).join(theme)
        } else {
            PathBuf::from(ICONS_DIR).join("hicolor")
        };
        base_path.join("48x48")
    }

    fn additional_paths() -> Option<Vec<PathBuf>> {
        let fallback_path = PathBuf::from("/usr/share").join(ICONS_DIR).join("hicolor");

        Some(vec![
            fallback_path.join("scalable"),
            fallback_path.join("48x48")
        ])
    }
}

use std::fs::File;
use std::io::{self, BufRead};
fn read_lines<P: AsRef<Path>>(filename: P) -> io::Result<io::Lines<io::BufReader<File>>> {
    let file = File::open(filename)?;
    Ok(io::BufReader::new(file).lines())
}