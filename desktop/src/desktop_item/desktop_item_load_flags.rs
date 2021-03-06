#[derive(Debug)]
pub enum DesktopItemLoadFlags {
    LOAD_ONLY_IF_EXISTS = 1<<0,
    LOAD_NO_TRANSLATIONS = 1<<1,
}