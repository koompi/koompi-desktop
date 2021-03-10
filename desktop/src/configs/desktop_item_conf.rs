use serde::{Serialize, Deserialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct DesktopItemConf {
    pub icon_size: u16,
    pub arrangement: Arrangement,
    pub sort_descending: bool,
    pub sorting: Sort,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum Arrangement {
    Rows,
    Columns,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum Sort {
    Manual,
    Name,
    Type,
    Date,
}

impl Default for DesktopItemConf {
    fn default() -> Self {
        Self {
            icon_size: 55,
            arrangement: Arrangement::Rows,
            sort_descending: false,
            sorting: Sort::Manual,
        }
    }
}