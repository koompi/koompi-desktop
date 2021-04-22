use lazy_static::lazy_static;
use std::path::PathBuf;

// Resource & Config Locations
lazy_static! {
    pub static ref DATA_DIRS: Vec<PathBuf> = std::env::var("XDG_DATA_DIRS").unwrap_or(String::from("/usr/local/share:/usr/share")).split(':').filter_map(|dir| {
        let path = PathBuf::from(dir);
        if path.exists() && path.is_dir() {
            Some(path)
        } else {
            None
        }
    }).collect();
    pub static ref LOCAL_DATA: PathBuf = dirs_next::data_dir().unwrap();

    pub static ref CONF_DIRS: Vec<PathBuf> = std::env::var("XDG_CONFIG_DIRS").unwrap_or(String::from("/etc/xdg")).split(':').filter_map(|dir| {
        let path = PathBuf::from(dir);
        if path.exists() && path.is_dir() {
            Some(path)
        } else {
            None
        }
    }).collect();
    pub static ref LOCAL_CONF: PathBuf = dirs_next::config_dir().unwrap();
}

// Desktop Entry Types
pub const APP: &str = "Application";
pub const LINK: &str = "Link";
pub const DIR: &str = "Directory";
pub const FILE: &str = "File";

/// Desktop Entry Keys
pub const DESKTOP_ENTRY: &str = "Desktop Entry";
pub const NAME: &str =		"Name";
// pub const GENERIC_NAME: &str =	"GenericName";
pub const TYPE: &str =		"Type";
pub const TRY_EXEC: &str =	"TryExec";
pub const NO_DISPLAY: &str =	"NoDisplay";
pub const COMMENT: &str =	"Comment";
pub const EXEC: &str =		"Exec";
// pub const ACTIONS: &str =	"Actions";
pub const ICON: &str =		"Icon";
pub const HIDDEN: &str =	"Hidden";
pub const MIME_TYPE: &str =	"MimeType";
// pub const PATH: &str =		"Path";
pub const TERMINAL: &str =	"Terminal";
// pub const CATEGORIES: &str =	"Categories";
// pub const ONLY_SHOW_IN: &str =	"OnlyShowIn";

/// Mimetype
pub const MIME_FILE: &str = "mimeapps.list";
pub const DEFAULT_APPS: &str = "Default Applications";
pub const ADDED_ASSOCS: &str = "Added Associations";
pub const REM_ASSOCS: &str = "Removed Associations";
pub const MIME_INFO_CACHE: &str = "mimeinfo.cache";
pub const MIME_CACHE: &str = "MIME Cache";
pub const INODE_DIR: &str = "inode/directory";