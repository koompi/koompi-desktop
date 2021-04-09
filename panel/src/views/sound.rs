use super::common::icon;
use crate::styles::containers::CustomContainer;
use crate::styles::slider::SliderType;
use iced::{Column, Element};
use iced_wgpu::Renderer;
use iced_winit::{
    button, slider, Align, Button, Command, Container, Length, Program, Row, Slider, Text,
};
use libkoompi::system_settings::sounds::controllers::{
    DeviceControl, SinkController, SourceController,
};
#[derive(Default)]
pub struct Audio {
    controllers: [button::State; 2],
    settings: [button::State; 4],

    slide_dev: slider::State,
    slide_head: slider::State,
    current_index: usize,
    sink_input: SinkController,
    source_output: SourceController,
    input_val: f64,
    output_val: f64,
    list_sinks: Vec<(String, String)>,
    list_sources: Vec<(String, String)>,
    is_output_mute: bool,
    is_input_mute: bool,
}
#[derive(Debug, Clone)]
pub enum AudioMsg {
    OnVolumeChange(f64),
    OnInputChanged(f64),
    OnSwitchView(usize),
    OnMute,
    OnAdvance,
}
impl Audio {
    pub fn new() -> Self {
        let mut sink_obj = SinkController::create();
        let mut source_obj = SourceController::create();
        let current_sink = sink_obj.get_volume();
        let current_source = source_obj.get_volume();
        let list_sink_dev = sink_obj.list_devices();
        let list_source_dev = source_obj.list_devices();
        let mut sinks = Vec::new();
        let mut sources = Vec::new();

        match list_sink_dev {
            Ok(devices) => {
                for dev in devices {
                    sinks.push((
                        match dev.name {
                            Some(dev_name) => dev_name,
                            None => String::from(""),
                        },
                        match dev.description {
                            Some(descr) => descr,
                            None => String::from(""),
                        },
                    ))
                }
            }
            Err(e) => println!("Error: {:?}", e),
        }
        match list_source_dev {
            Ok(devices) => {
                for dev in devices {
                    sources.push((
                        match dev.name {
                            Some(dev_name) => dev_name,
                            None => String::from(""),
                        },
                        match dev.description {
                            Some(descr) => descr,
                            None => String::from(""),
                        },
                    ));
                }
            }
            Err(e) => eprintln!("Error: {:?}", e),
        }
        Self {
            list_sinks: sinks,
            list_sources: sources,
            sink_input: sink_obj,
            source_output: source_obj,
            output_val: match current_sink {
                Ok(mut vec_vol) => match vec_vol.pop() {
                    Some(val) => match val.parse() {
                        Ok(d) => d,
                        Err(e) => {
                            eprintln!("Error: {:?}", e);
                            50.0
                        }
                    },
                    None => 50.0,
                },
                Err(e) => {
                    println!("Error: {:?}", e);
                    50.0
                }
            },
            input_val: match current_source {
                Ok(mut vec_vol) => match vec_vol.pop() {
                    Some(val) => match val.parse() {
                        Ok(d) => d,
                        Err(e) => {
                            println!("Error: {:?}", e);
                            50.0
                        }
                    },
                    None => 50.0,
                },
                Err(e) => {
                    println!("Error: {:?}", e);
                    50.0
                }
            },
            ..Self::default()
        }
    }
}
use AudioMsg::*;
impl Program for Audio {
    type Message = AudioMsg;
    type Renderer = self::Renderer;
    fn update(&mut self, msg: self::AudioMsg) -> Command<AudioMsg> {
        match msg {
            OnVolumeChange(volume) => {
                for dev in &self.list_sinks {
                    match self
                        .sink_input
                        .set_device_volume_by_name(&dev.0, (volume / 100.0).into())
                    {
                        Ok(()) => {}
                        Err(e) => {
                            eprintln!("Error: {:?}", e);
                        }
                    }
                }
                self.output_val = volume;
            }
            OnSwitchView(index) => {
                println!("current index: {}", index);
                self.current_index = index;
            }
            OnInputChanged(volume) => {
                for dev in &self.list_sources {
                    match self
                        .source_output
                        .set_device_volume_by_name(&dev.0, (volume / 100.0).into())
                    {
                        Ok(()) => {}
                        Err(e) => {
                            eprintln!("Error: {:?}", e);
                        }
                    }
                }
                self.input_val = volume;
            }
            OnAdvance => {}
            OnMute => {}
        }
        Command::none()
    }
    fn view(&mut self) -> Element<Self::Message> {
        let [mute, settings, devices, apps] = &mut self.settings;
        let [device, app] = &mut self.controllers;
        let tab = Row::new()
            .width(Length::Fill)
            .align_items(Align::Center)
            .push(Text::new("Audio Volume").size(18));
        let content = Column::new()
            .spacing(10)
            .push(Text::new("Headphones"))
            .push(
                Row::new()
                    .align_items(Align::Center)
                    .spacing(4)
                    .push(if self.is_output_mute {
                        icon('\u{f6e9}')
                    } else {
                        icon('\u{f028}')
                    })
                    .push(
                        Slider::new(
                            &mut self.slide_dev,
                            0.0..=100.0,
                            self.output_val,
                            Self::Message::OnVolumeChange,
                        )
                        .style(SliderType::Default),
                    )
                    .push(Text::new(format!("{} %", self.output_val.to_string()))),
            )
            .push(Text::new("Headset Microphone"))
            .push(
                Row::new()
                    .spacing(4)
                    .align_items(Align::Center)
                    .push(if self.is_input_mute {
                        icon('\u{f131}')
                    } else {
                        icon('\u{f130}')
                    })
                    .push(
                        Slider::new(
                            &mut self.slide_head,
                            0.0..=100.0,
                            self.input_val,
                            AudioMsg::OnInputChanged,
                        )
                        .style(SliderType::Default),
                    )
                    .push(Text::new(format!("{} %", self.input_val.to_string()))),
            );
        Container::new(
            Column::new()
                .spacing(10)
                .align_items(Align::Center)
                .push(tab)
                .push(content),
        )
        .style(CustomContainer::ForegroundGray)
        .padding(10)
        .width(Length::Fill)
        .height(Length::Fill)
        .center_x()
        .into()
    }
}
