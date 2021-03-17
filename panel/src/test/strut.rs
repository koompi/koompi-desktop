#![allow(dead_code)]
#[derive(Default)]
pub struct StrutArea {
    left: u64,
    right: u64,
    top: u64,
    bottom: u64,
}

impl StrutArea {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn set_left(&mut self, left: u64) {
        self.left = left;
    }
    pub fn set_right(&mut self, right: u64) {
        self.right = right;
    }
    pub fn set_top(&mut self, top: u64) {
        self.top = top;
    }
    pub fn set_bottom(&mut self, bottom: u64) {
        self.bottom = bottom;
    }
    pub fn list_props(&self) -> [u64; 4] {
        [self.left, self.right, self.top, self.bottom]
    }
}
#[derive(Default)]
pub struct StrutPartialArea {
    pub left: u64,
    pub right: u64,
    pub top: u64,
    pub bottom: u64,
    pub left_start_y: u64,
    pub left_end_y: u64,
    pub right_start_y: u64,
    pub right_end_y: u64,
    pub top_start_x: u64,
    pub top_end_x: u64,
    pub bottom_start_x: u64,
    pub bottom_end_x: u64,
}
impl StrutPartialArea {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn set_left(&mut self, left: u64) {
        self.left = left;
    }
    pub fn set_right(&mut self, right: u64) {
        self.right = right;
    }
    pub fn set_top(&mut self, top: u64) {
        self.top = top;
    }
    pub fn set_bottom(&mut self, bottom: u64) {
        self.bottom = bottom;
    }
    pub fn set_left_start_y(&mut self, val: u64) {
        self.left_start_y = val;
    }
    pub fn set_left_end_y(&mut self, val: u64) {
        self.left_end_y = val;
    }
    pub fn set_right_start_y(&mut self, val: u64) {
        self.right_start_y = val;
    }
    pub fn set_right_end_y(&mut self, val: u64) {
        self.right_end_y = val;
    }
    pub fn set_top_start_x(&mut self, val: u64) {
        self.top_start_x = val;
    }
    pub fn set_top_end_x(&mut self, val: u64) {
        self.top_end_x = val;
    }
    pub fn set_bottom_end_x(&mut self, val: u64) {
        self.bottom_start_x = val;
    }
    pub fn set_bottom_end_y(&mut self, val: u64) {
        self.bottom_end_x = val;
    }
    pub fn list_props(&self) -> [u64; 12] {
        [
            self.left,
            self.right,
            self.top,
            self.bottom,
            self.left_start_y,
            self.left_end_y,
            self.right_start_y,
            self.right_end_y,
            self.top_start_x,
            self.top_end_x,
            self.bottom_start_x,
            self.bottom_end_x,
        ]
    }
}
