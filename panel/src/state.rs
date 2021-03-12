use iced_winit::{program, Program};
#[derive(Default)]
pub struct MultiState<P>
where
    P: 'static + Program + Default + CommonState,
{
    pub vec_s: Vec<program::State<P>>,
}

impl<P> MultiState<P>
where
    P: 'static + Program + Default + CommonState,
{
    pub fn new() -> Self {
        Self::default()
    }
    pub fn set_state(&mut self, state: program::State<P>) {
        self.vec_s.push(state);
    }
    pub fn get_list_state(&self) -> &Vec<program::State<P>> {
        &self.vec_s
    }
}

pub enum Common<P>
where
    P: 'static + Program + CommonState,
{
    WindowState(program::State<P>),
    MenuState(program::State<P>),
}

pub trait CommonState {
    fn get_name(&self) -> String;
}
