use serde::{Serialize, Deserialize};
use std::fmt::{self, Display, Formatter};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DesktopItemConf {
    pub icon_size: u16,
    pub grid_spacing: u16,
    pub arrangement: Arrangement,
    pub sort_descending: bool,
    pub sorting: Sorting,
    pub show_tooltip: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Arrangement {
    Rows,
    Columns,
}

impl Arrangement {
    pub const ALL: [Arrangement; 2] = [
        Arrangement::Rows, Arrangement::Columns
    ];
}

impl Display for Arrangement {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result { 
        use Arrangement::*;
        write!(f, "{}", match self {
            Rows => "Rows",
            Columns => "Columns"
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Sorting {
    Manual,
    Name,
    Type,
    Date,
}

impl Sorting {
    pub const ALL: [Sorting; 4] = [
        Sorting::Manual,
        Sorting::Name,
        Sorting::Type,
        Sorting::Date,
    ];
}

impl Display for Sorting {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result { 
        use Sorting::*;
        write!(f, "{}", match self {
            Manual => "None",
            Name => "Name",
            Type => "Type",
            Date => "Date"
        })
    }
}

impl Default for DesktopItemConf {
    fn default() -> Self {
        Self {
            icon_size: Self::DEF_ICON_SIZE,
            grid_spacing: Self::DEF_GRID_SPACING,
            arrangement: Arrangement::Rows,
            sort_descending: false,
            sorting: Sorting::Manual,
            show_tooltip: false,
        }
    }
}

impl DesktopItemConf {
    pub const MIN_ICON_SIZE: u16 = 32;
    pub const DEF_ICON_SIZE: u16 = 42;
    pub const MAX_ICON_SIZE: u16 = 78;
    pub const MIN_GRID_SPACING: u16 = 3;
    pub const DEF_GRID_SPACING: u16 = 5;
    pub const MAX_GRID_SPACING: u16 = 10;
}