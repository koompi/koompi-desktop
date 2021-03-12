#[derive(Debug)]
pub enum DesktopItemLaunchFlags {
    LAUNCH_ONLY_ONE = 1<<0,
    LAUNCH_USE_CURR_DIR = 1<<1,
    LAUNCH_APPEND_URIS = 1<<2,
    LAUNCH_APPEND_PATHS = 1<<3,
    LAUNCH_DO_NOT_REAP_CHILD = 1<<4,
}