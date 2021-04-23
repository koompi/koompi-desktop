use super::errors::{ControllerError, ControllerErrorType::*};
use super::sound_api::Handler;
use super::types::{ApplicationInfo, DeviceInfo, ServerInfo, SoundCardInfo};
use libpulse_binding as pulse;
use pulse::{
    callbacks::ListResult,
    context::{
        introspect, subscribe,
        subscribe::{Facility, InterestMaskSet},
    },
    volume::Volume,
};
use std::cell::RefCell;
use std::clone::Clone;
use std::rc::Rc;

pub trait DeviceControl<T> {
    fn get_default_device(&mut self) -> Result<T, ControllerError>;
    fn set_default_device(&mut self, name: &str) -> Result<bool, ControllerError>;

    fn list_devices(&mut self) -> Result<Vec<T>, ControllerError>;
    fn get_device_by_index(&mut self, index: u32) -> Result<T, ControllerError>;
    fn get_device_by_name(&mut self, name: &str) -> Result<T, ControllerError>;
    fn set_device_volume_by_index(&mut self, index: u32, volume: f64);
    fn set_device_volume_by_name(&mut self, name: &str, volume: f64)
        -> Result<(), ControllerError>;
    fn increase_device_volume_by_percent(&mut self, index: u32, delta: f64);
    fn decrease_device_volume_by_percent(&mut self, index: u32, delta: f64);
    fn get_volume(&mut self) -> Result<Vec<String>, ControllerError>;
}

pub trait AppControl<T> {
    fn list_applications(&mut self) -> Result<Vec<T>, ControllerError>;

    fn get_app_by_index(&mut self, index: u32) -> Result<T, ControllerError>;
    fn increase_app_volume_by_percent(&mut self, index: u32, delta: f64);
    fn decrease_app_volume_by_percent(&mut self, index: u32, delta: f64);

    fn move_app_by_index(
        &mut self,
        stream_index: u32,
        device_index: u32,
    ) -> Result<bool, ControllerError>;
    fn move_app_by_name(
        &mut self,
        stream_index: u32,
        device_name: &str,
    ) -> Result<bool, ControllerError>;
    fn set_app_mute(&mut self, index: u32, mute: bool) -> Result<bool, ControllerError>;
    fn set_app_mute_by_name(&mut self, name: &str, mute: bool) -> Result<bool, ControllerError>;
}

pub trait AppEvent {
    fn subscribe(&mut self) -> Result<(), ControllerError>;
    fn sink_event(&mut self) -> Result<u32, ControllerError>;
    fn source_event(&mut self) -> Result<u32, ControllerError>;
    fn sink_input_event(&mut self) -> Result<u32, ControllerError>;
    fn source_input_event(&mut self) -> Result<u32, ControllerError>;
    fn module_event(&mut self) -> Result<u32, ControllerError>;
    fn client_event(&mut self) -> Result<u32, ControllerError>;
    fn sample_cache_event(&mut self) -> Result<u32, ControllerError>;
    fn server_event(&mut self) -> Result<u32, ControllerError>;
    fn card_event(&mut self) -> Result<u32, ControllerError>;
}
pub trait SoundCard<T> {
    fn get_sound_card_by_index(&mut self, index: u32) -> Result<T, ControllerError>;
    fn get_sound_card_by_name(&mut self, name: &str) -> Result<T, ControllerError>;
    fn get_card_info_list(&mut self) -> Result<Vec<T>, ControllerError>;
    fn set_card_profile_by_index(
        &mut self,
        index: u32,
        profile: &str,
    ) -> Result<bool, ControllerError>;
    fn set_card_profile_by_name(
        &mut self,
        name: &str,
        profiel: &str,
    ) -> Result<bool, ControllerError>;
}

pub trait SinkPort {
    fn set_sink_port_by_name(
        &mut self,
        name: &str,
        port_name: &str,
    ) -> Result<bool, ControllerError>;
    fn set_sink_port_by_index(
        &mut self,
        index: u32,
        port_name: &str,
    ) -> Result<bool, ControllerError>;
}
pub trait SourcePort {
    fn set_source_port_by_name(
        &mut self,
        name: &str,
        port_name: &str,
    ) -> Result<bool, ControllerError>;
    fn set_source_port_by_index(
        &mut self,
        index: u32,
        port_name: &str,
    ) -> Result<bool, ControllerError>;
}

pub fn volume_from_percent(volume: f64) -> f64 {
    (volume * 100.0) * (f64::from(Volume::NORMAL.0) / 100.0)
}
#[derive(Default)]
pub struct SinkController {
    pub handler: Handler,
}

impl SinkController {
    pub fn create() -> Self {
        let handler = Handler::connect("SinkController").expect("Unable to connect to PulseAudio");
        SinkController { handler }
    }

    pub fn get_server_info(&mut self) -> Result<ServerInfo, ControllerError> {
        let server = Rc::new(RefCell::new(Some(None)));
        let server_ref = server.clone();
        let op = self.handler.introspect.get_server_info(move |res| {
            server_ref
                .borrow_mut()
                .as_mut()
                .unwrap()
                .replace(res.into());
        });
        self.handler.wait_for_operation(op)?;
        let mut result = server.borrow_mut();
        result.take().unwrap().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting information about the server",
        ))
    }
}

impl<'a> SoundCard<SoundCardInfo> for SinkController {
    fn get_sound_card_by_index(&mut self, index: u32) -> Result<SoundCardInfo, ControllerError> {
        let soundinfo = Rc::new(RefCell::new(Some(None)));
        let soundinfo_ref = soundinfo.clone();
        let op = self.handler.introspect.get_card_info_by_index(
            index,
            move |card_info: ListResult<&introspect::CardInfo>| {
                if let ListResult::Item(item) = card_info {
                    soundinfo_ref
                        .borrow_mut()
                        .as_mut()
                        .unwrap()
                        .replace(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = soundinfo.borrow_mut();
        result
            .take()
            .unwrap()
            .ok_or(ControllerError::new(GetInfoError, "Cannot Get Sound Card"))
    }

    fn get_sound_card_by_name(&mut self, name: &str) -> Result<SoundCardInfo, ControllerError> {
        let soundinfo = Rc::new(RefCell::new(Some(None)));
        let soundinfo_ref = soundinfo.clone();
        let op = self.handler.introspect.get_card_info_by_name(
            name,
            move |card_info: ListResult<&introspect::CardInfo>| {
                if let ListResult::Item(item) = card_info {
                    soundinfo_ref
                        .borrow_mut()
                        .as_mut()
                        .unwrap()
                        .replace(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = soundinfo.borrow_mut();
        result
            .take()
            .unwrap()
            .ok_or(ControllerError::new(GetInfoError, "Cannot Get Sound Card"))
        // Err(ControllerError::new(GetInfoError, "Sound Card Error"))
    }
    fn get_card_info_list(&mut self) -> Result<Vec<SoundCardInfo>, ControllerError> {
        let soundlist = Rc::new(RefCell::new(Some(Vec::new())));
        let soundlist_ref = soundlist.clone();

        let op = self.handler.introspect.get_card_info_list(
            move |card_list: ListResult<&introspect::CardInfo>| {
                if let ListResult::Item(list_item) = card_list {
                    soundlist_ref
                        .borrow_mut()
                        .as_mut()
                        .unwrap()
                        .push(list_item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = soundlist.borrow_mut();
        result.take().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting device list",
        ))
        // Err(ControllerError::new(GetInfoError, "Sound Card Error"))
    }
    fn set_card_profile_by_index(
        &mut self,
        index: u32,
        profile: &str,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let ref_success = success.clone();
        let op = self.handler.introspect.set_card_profile_by_index(
            index,
            profile,
            Some(Box::new(move |res| {
                ref_success.borrow_mut().clone_from(&res);
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }
    fn set_card_profile_by_name(
        &mut self,
        name: &str,
        profile: &str,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let ref_success = success.clone();
        let op = self.handler.introspect.set_card_profile_by_name(
            name,
            profile,
            Some(Box::new(move |res| {
                ref_success.borrow_mut().clone_from(&res);
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }
}

impl SinkPort for SinkController {
    fn set_sink_port_by_name(
        &mut self,
        name: &str,
        port_name: &str,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let ref_success = success.clone();
        let op = self.handler.introspect.set_sink_port_by_name(
            name,
            port_name,
            Some(Box::new(move |res| {
                ref_success.borrow_mut().clone_from(&res);
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }
    fn set_sink_port_by_index(
        &mut self,
        index: u32,
        port_name: &str,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let ref_success = success.clone();
        let op = self.handler.introspect.set_sink_port_by_index(
            index,
            port_name,
            Some(Box::new(move |res| {
                ref_success.borrow_mut().clone_from(&res);
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }
}
impl DeviceControl<DeviceInfo> for SinkController {
    fn get_default_device(&mut self) -> Result<DeviceInfo, ControllerError> {
        let server_info = self.get_server_info();
        match server_info {
            Ok(info) => self.get_device_by_name(info.default_sink_name.unwrap().as_ref()),
            Err(e) => Err(e),
        }
    }
    fn set_default_device(&mut self, name: &str) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let success_ref = success.clone();

        let op = self
            .handler
            .context
            .borrow_mut()
            .set_default_sink(name, move |res| success_ref.borrow_mut().clone_from(&res));
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }

    fn list_devices(&mut self) -> Result<Vec<DeviceInfo>, ControllerError> {
        let list = Rc::new(RefCell::new(Some(Vec::new())));
        let list_ref = list.clone();

        let op = self.handler.introspect.get_sink_info_list(
            move |sink_list: ListResult<&introspect::SinkInfo>| {
                if let ListResult::Item(item) = sink_list {
                    list_ref.borrow_mut().as_mut().unwrap().push(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = list.borrow_mut();
        result.take().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting device list",
        ))
    }
    fn get_device_by_index(&mut self, index: u32) -> Result<DeviceInfo, ControllerError> {
        let device = Rc::new(RefCell::new(Some(None)));
        let dev_ref = device.clone();
        let op = self.handler.introspect.get_sink_info_by_index(
            index,
            move |sink_list: ListResult<&introspect::SinkInfo>| {
                if let ListResult::Item(item) = sink_list {
                    dev_ref.borrow_mut().as_mut().unwrap().replace(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = device.borrow_mut();
        result.take().unwrap().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting requested device",
        ))
    }

    fn get_device_by_name(&mut self, name: &str) -> Result<DeviceInfo, ControllerError> {
        let device = Rc::new(RefCell::new(Some(None)));
        let dev_ref = device.clone();
        let op = self.handler.introspect.get_sink_info_by_name(
            name,
            move |sink_list: ListResult<&introspect::SinkInfo>| {
                if let ListResult::Item(item) = sink_list {
                    dev_ref.borrow_mut().as_mut().unwrap().replace(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = device.borrow_mut();
        result.take().unwrap().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting requested device",
        ))
    }

    fn set_device_volume_by_index(&mut self, index: u32, volume: f64) {
        let new_volume = Volume::from(Volume(volume_from_percent(volume) as u32));
        let mut dev_ref = self
            .get_device_by_index(index)
            .expect("Could not find device specified");
        let volumes = dev_ref.volume.scale(new_volume).unwrap();
        let op = self
            .handler
            .introspect
            .set_sink_volume_by_index(index, &volumes, None);
        self.handler.wait_for_operation(op).expect("error");
    }
    fn set_device_volume_by_name(
        &mut self,
        name: &str,
        volume: f64,
    ) -> Result<(), ControllerError> {
        let new_volume = Volume::from(Volume(volume_from_percent(volume) as u32));
        match self.get_device_by_name(name) {
            Ok(mut dev_ref) => {
                let volumes = dev_ref.volume.scale(new_volume).unwrap();
                let op = self
                    .handler
                    .introspect
                    .set_sink_volume_by_name(name, volumes, None);
                self.handler.wait_for_operation(op).expect("error");
                Ok(())
            }
            Err(e) => Err(e),
        }
    }
    fn increase_device_volume_by_percent(&mut self, index: u32, delta: f64) {
        let mut dev_ref = self
            .get_device_by_index(index)
            .expect("Could not find device specified");
        let new_vol = Volume::from(Volume(volume_from_percent(delta) as u32));
        println!("{:?}", new_vol.print_verbose(true));
        let volumes = dev_ref
            .volume
            .increase(new_vol)
            .expect("Volume couldn't be set");
        let op = self
            .handler
            .introspect
            .set_sink_volume_by_index(index, &volumes, None);
        self.handler.wait_for_operation(op).expect("error");
    }
    fn decrease_device_volume_by_percent(&mut self, index: u32, delta: f64) {
        let mut dev_ref = self
            .get_device_by_index(index)
            .expect("Could not find device specified");
        let new_vol = Volume::from(Volume(volume_from_percent(delta) as u32));
        println!("{:?}", new_vol.print_verbose(true));
        let volumes = dev_ref.volume.decrease(new_vol).unwrap();
        let op = self
            .handler
            .introspect
            .set_sink_volume_by_index(index, &volumes, None);
        self.handler.wait_for_operation(op).expect("error");
    }
    fn get_volume(&mut self) -> Result<Vec<String>, ControllerError> {
        let devices = self.list_devices();
        let mut data_volume: Vec<String> = Vec::new();
        match devices {
            Ok(res_device) => {
                for dev in res_device {
                    let mut vol = dev.volume.get().to_vec();
                    while vol.len() != 0 {
                        match vol.pop() {
                            Some(val) => {
                                let mut human_volum =
                                    val.print().split_whitespace().collect::<String>();
                                human_volum.retain(|c| c != '%');
                                data_volume.push(human_volum);
                            }
                            None => eprintln!("Cannot pop vaolume out of vector: "),
                        }
                    }
                }
                Ok(data_volume)
            }
            Err(e) => Err(ControllerError::new(
                GetInfoError,
                &format!("Error: {:?}", e),
            )),
        }
    }
}

impl AppControl<ApplicationInfo> for SinkController {
    fn list_applications(&mut self) -> Result<Vec<ApplicationInfo>, ControllerError> {
        let list = Rc::new(RefCell::new(Some(Vec::new())));
        let list_ref = list.clone();

        let op = self.handler.introspect.get_sink_input_info_list(
            move |sink_list: ListResult<&introspect::SinkInputInfo>| {
                if let ListResult::Item(item) = sink_list {
                    list_ref.borrow_mut().as_mut().unwrap().push(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = list.borrow_mut();
        result.take().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting application list",
        ))
    }

    fn get_app_by_index(&mut self, index: u32) -> Result<ApplicationInfo, ControllerError> {
        let app = Rc::new(RefCell::new(Some(None)));
        let app_ref = app.clone();
        let op = self.handler.introspect.get_sink_input_info(
            index,
            move |sink_list: ListResult<&introspect::SinkInputInfo>| {
                if let ListResult::Item(item) = sink_list {
                    app_ref.borrow_mut().as_mut().unwrap().replace(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = app.borrow_mut();
        result.take().unwrap().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting requested app",
        ))
    }

    fn increase_app_volume_by_percent(&mut self, index: u32, delta: f64) {
        let mut app_ref = self
            .get_app_by_index(index)
            .expect("Could not find device specified");
        let new_vol = Volume::from(Volume(volume_from_percent(delta) as u32));
        println!("{:?}", new_vol.print_verbose(true));
        let volumes = app_ref
            .volume
            .increase(new_vol)
            .expect("Volume couldn't be set");
        let op = self
            .handler
            .introspect
            .set_sink_input_volume(index, &volumes, None);
        self.handler.wait_for_operation(op).expect("error");
    }

    fn decrease_app_volume_by_percent(&mut self, index: u32, delta: f64) {
        let mut app_ref = self
            .get_app_by_index(index)
            .expect("Could not find device specified");
        let new_vol = Volume::from(Volume(volume_from_percent(delta) as u32));
        println!("{:?}", new_vol.print_verbose(true));
        let volumes = app_ref
            .volume
            .decrease(new_vol)
            .expect("Volume couldn't be set");
        let op = self
            .handler
            .introspect
            .set_sink_input_volume(index, &volumes, None);
        self.handler.wait_for_operation(op).expect("error");
    }

    fn move_app_by_index(
        &mut self,
        stream_index: u32,
        device_index: u32,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let success_ref = success.clone();
        let op = self.handler.introspect.move_sink_input_by_index(
            stream_index,
            device_index,
            Some(Box::new(move |res| {
                success_ref.borrow_mut().clone_from(&res)
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }

    fn move_app_by_name(
        &mut self,
        stream_index: u32,
        device_name: &str,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let success_ref = success.clone();
        let op = self.handler.introspect.move_sink_input_by_name(
            stream_index,
            device_name,
            Some(Box::new(move |res| {
                success_ref.borrow_mut().clone_from(&res)
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }

    fn set_app_mute(&mut self, index: u32, mute: bool) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let success_ref = success.clone();
        let op = self.handler.introspect.set_sink_input_mute(
            index,
            mute,
            Some(Box::new(move |res| {
                success_ref.borrow_mut().clone_from(&res)
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }
    fn set_app_mute_by_name(&mut self, name: &str, is_mute: bool) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(Some(true)));
        let ref_success = success.clone();
        let op = self.handler.introspect.set_sink_mute_by_name(
            name,
            is_mute,
            Some(Box::new(move |res| {
                println!("set mut sucess: {}", res);
                ref_success.borrow_mut().clone_from(&Some(res))
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result.unwrap())
    }
}
#[derive(Default)]
pub struct SourceController {
    pub handler: Handler,
}
impl SourcePort for SourceController {
    fn set_source_port_by_name(
        &mut self,
        name: &str,
        port_name: &str,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let ref_success = success.clone();
        let op = self.handler.introspect.set_source_port_by_name(
            name,
            port_name,
            Some(Box::new(move |res| {
                ref_success.borrow_mut().clone_from(&res);
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }
    fn set_source_port_by_index(
        &mut self,
        index: u32,
        port_name: &str,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let ref_success = success.clone();
        let op = self.handler.introspect.set_sink_port_by_index(
            index,
            port_name,
            Some(Box::new(move |res| {
                ref_success.borrow_mut().clone_from(&res);
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }
}
impl<'a> SoundCard<SoundCardInfo> for SourceController {
    fn get_sound_card_by_index(&mut self, index: u32) -> Result<SoundCardInfo, ControllerError> {
        let soundinfo = Rc::new(RefCell::new(Some(None)));
        let soundinfo_ref = soundinfo.clone();
        let op = self.handler.introspect.get_card_info_by_index(
            index,
            move |card_info: ListResult<&introspect::CardInfo>| {
                if let ListResult::Item(item) = card_info {
                    soundinfo_ref
                        .borrow_mut()
                        .as_mut()
                        .unwrap()
                        .replace(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = soundinfo.borrow_mut();
        result
            .take()
            .unwrap()
            .ok_or(ControllerError::new(GetInfoError, "Cannot Get Sound Card"))
    }

    fn get_sound_card_by_name(&mut self, name: &str) -> Result<SoundCardInfo, ControllerError> {
        let soundinfo = Rc::new(RefCell::new(Some(None)));
        let soundinfo_ref = soundinfo.clone();
        let op = self.handler.introspect.get_card_info_by_name(
            name,
            move |card_info: ListResult<&introspect::CardInfo>| {
                if let ListResult::Item(item) = card_info {
                    soundinfo_ref
                        .borrow_mut()
                        .as_mut()
                        .unwrap()
                        .replace(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = soundinfo.borrow_mut();
        result
            .take()
            .unwrap()
            .ok_or(ControllerError::new(GetInfoError, "Cannot Get Sound Card"))
        // Err(ControllerError::new(GetInfoError, "Sound Card Error"))
    }
    fn get_card_info_list(&mut self) -> Result<Vec<SoundCardInfo>, ControllerError> {
        let soundlist = Rc::new(RefCell::new(Some(Vec::new())));
        let soundlist_ref = soundlist.clone();

        let op = self.handler.introspect.get_card_info_list(
            move |card_list: ListResult<&introspect::CardInfo>| {
                if let ListResult::Item(list_item) = card_list {
                    soundlist_ref
                        .borrow_mut()
                        .as_mut()
                        .unwrap()
                        .push(list_item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = soundlist.borrow_mut();
        result.take().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting device list",
        ))
        // Err(ControllerError::new(GetInfoError, "Sound Card Error"))
    }
    fn set_card_profile_by_index(
        &mut self,
        index: u32,
        profile: &str,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let ref_success = success.clone();
        let op = self.handler.introspect.set_card_profile_by_index(
            index,
            profile,
            Some(Box::new(move |res| {
                ref_success.borrow_mut().clone_from(&res);
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }
    fn set_card_profile_by_name(
        &mut self,
        name: &str,
        profile: &str,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let ref_success = success.clone();
        let op = self.handler.introspect.set_card_profile_by_name(
            name,
            profile,
            Some(Box::new(move |res| {
                ref_success.borrow_mut().clone_from(&res);
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }
}

impl SourceController {
    pub fn create() -> Self {
        let handler = Handler::connect("SourceController").unwrap();
        SourceController { handler }
    }

    pub fn get_server_info(&mut self) -> Result<ServerInfo, ControllerError> {
        let server = Rc::new(RefCell::new(Some(None)));
        let server_ref = server.clone();

        let op = self.handler.introspect.get_server_info(move |res| {
            server_ref
                .borrow_mut()
                .as_mut()
                .unwrap()
                .replace(res.into());
        });
        self.handler.wait_for_operation(op)?;
        let mut result = server.borrow_mut();
        result.take().unwrap().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting application list",
        ))
    }
}

impl DeviceControl<DeviceInfo> for SourceController {
    fn get_default_device(&mut self) -> Result<DeviceInfo, ControllerError> {
        let server_info = self.get_server_info();
        match server_info {
            Ok(info) => self.get_device_by_name(info.default_sink_name.unwrap().as_ref()),
            Err(e) => Err(e),
        }
    }
    fn set_default_device(&mut self, name: &str) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let success_ref = success.clone();

        let op = self
            .handler
            .context
            .borrow_mut()
            .set_default_source(name, move |res| success_ref.borrow_mut().clone_from(&res));
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }

    fn list_devices(&mut self) -> Result<Vec<DeviceInfo>, ControllerError> {
        let list = Rc::new(RefCell::new(Some(Vec::new())));
        let list_ref = list.clone();

        let op = self.handler.introspect.get_source_info_list(
            move |sink_list: ListResult<&introspect::SourceInfo>| {
                if let ListResult::Item(item) = sink_list {
                    list_ref.borrow_mut().as_mut().unwrap().push(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = list.borrow_mut();
        result.take().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting application list",
        ))
    }
    fn get_device_by_index(&mut self, index: u32) -> Result<DeviceInfo, ControllerError> {
        let device = Rc::new(RefCell::new(Some(None)));
        let dev_ref = device.clone();
        let op = self.handler.introspect.get_source_info_by_index(
            index,
            move |sink_list: ListResult<&introspect::SourceInfo>| {
                if let ListResult::Item(item) = sink_list {
                    dev_ref.borrow_mut().as_mut().unwrap().replace(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = device.borrow_mut();
        result.take().unwrap().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting application list",
        ))
    }
    fn get_device_by_name(&mut self, name: &str) -> Result<DeviceInfo, ControllerError> {
        let device = Rc::new(RefCell::new(Some(None)));
        let dev_ref = device.clone();
        let op = self.handler.introspect.get_source_info_by_name(
            name,
            move |sink_list: ListResult<&introspect::SourceInfo>| {
                if let ListResult::Item(item) = sink_list {
                    dev_ref.borrow_mut().as_mut().unwrap().replace(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = device.borrow_mut();
        result.take().unwrap().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting application list",
        ))
    }

    fn set_device_volume_by_index(&mut self, index: u32, volume: f64) {
        let new_volume = Volume::from(Volume(volume_from_percent(volume) as u32));
        let mut dev_ref = self
            .get_device_by_index(index)
            .expect("Could not find device specified");
        let volumes = dev_ref.volume.scale(new_volume).unwrap();
        let op = self
            .handler
            .introspect
            .set_source_volume_by_index(index, volumes, None);
        self.handler.wait_for_operation(op).expect("error");
    }
    fn set_device_volume_by_name(
        &mut self,
        name: &str,
        volume: f64,
    ) -> Result<(), ControllerError> {
        let new_volume = Volume::from(Volume(volume_from_percent(volume) as u32));
        match self.get_device_by_name(name) {
            Ok(mut dev_ref) => {
                let volumes = dev_ref.volume.scale(new_volume).unwrap();
                let op = self
                    .handler
                    .introspect
                    .set_source_volume_by_name(name, volumes, None);
                self.handler.wait_for_operation(op).expect("error");
                Ok(())
            }
            Err(e) => Err(e),
        }
    }
    fn increase_device_volume_by_percent(&mut self, index: u32, delta: f64) {
        let mut dev_ref = self
            .get_device_by_index(index)
            .expect("Could not find device specified");
        let new_vol = Volume::from(Volume(volume_from_percent(delta) as u32));
        println!("{:?}", new_vol.print_verbose(true));
        let volumes = dev_ref
            .volume
            .increase(new_vol)
            .expect("Volume couldn't be set");
        let op = self
            .handler
            .introspect
            .set_source_volume_by_index(index, &volumes, None);
        self.handler.wait_for_operation(op).expect("error");
    }
    fn decrease_device_volume_by_percent(&mut self, index: u32, delta: f64) {
        let mut dev_ref = self
            .get_device_by_index(index)
            .expect("Could not find device specified");
        let new_vol = Volume::from(Volume(volume_from_percent(delta) as u32));
        println!("{:?}", new_vol.print_verbose(true));
        let volumes = dev_ref.volume.decrease(new_vol).unwrap();
        let op = self
            .handler
            .introspect
            .set_source_volume_by_index(index, &volumes, None);
        self.handler.wait_for_operation(op).expect("error");
    }
    fn get_volume(&mut self) -> Result<Vec<String>, ControllerError> {
        let devices = self.list_devices();
        let mut data_volume: Vec<String> = Vec::new();
        match devices {
            Ok(res_device) => {
                for dev in res_device {
                    let mut vol = dev.volume.get().to_vec();
                    while vol.len() != 0 {
                        match vol.pop() {
                            Some(val) => {
                                let mut human_volum =
                                    val.print().split_whitespace().collect::<String>();
                                human_volum.retain(|c| c != '%');
                                data_volume.push(human_volum);
                            }
                            None => eprintln!("Cannot pop vaolume out of vector: "),
                        }
                    }
                }
                Ok(data_volume)
            }
            Err(e) => Err(ControllerError::new(
                GetInfoError,
                &format!("Error: {:?}", e),
            )),
        }
    }
}

impl AppControl<ApplicationInfo> for SourceController {
    fn list_applications(&mut self) -> Result<Vec<ApplicationInfo>, ControllerError> {
        let list = Rc::new(RefCell::new(Some(Vec::new())));
        let list_ref = list.clone();

        let op = self.handler.introspect.get_source_output_info_list(
            move |sink_list: ListResult<&introspect::SourceOutputInfo>| {
                if let ListResult::Item(item) = sink_list {
                    list_ref.borrow_mut().as_mut().unwrap().push(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = list.borrow_mut();
        result.take().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting application list",
        ))
    }

    fn get_app_by_index(&mut self, index: u32) -> Result<ApplicationInfo, ControllerError> {
        let app = Rc::new(RefCell::new(Some(None)));
        let app_ref = app.clone();
        let op = self.handler.introspect.get_source_output_info(
            index,
            move |sink_list: ListResult<&introspect::SourceOutputInfo>| {
                if let ListResult::Item(item) = sink_list {
                    app_ref.borrow_mut().as_mut().unwrap().replace(item.into());
                }
            },
        );
        self.handler.wait_for_operation(op)?;
        let mut result = app.borrow_mut();
        result.take().unwrap().ok_or(ControllerError::new(
            GetInfoError,
            "Error getting application list",
        ))
    }

    fn increase_app_volume_by_percent(&mut self, index: u32, delta: f64) {
        println!("function increase_app_volume_by_percent : {} ", index);
        let mut app_ref = self
            .get_app_by_index(index)
            .expect("Could not find device specified");
        let new_vol = Volume::from(Volume(volume_from_percent(delta) as u32));
        println!("{:?}", new_vol.print_verbose(true));
        let volumes = app_ref
            .volume
            .increase(new_vol)
            .expect("Volume couldn't be set");
        let op = self
            .handler
            .introspect
            .set_source_output_volume(index, &volumes, None);
        self.handler.wait_for_operation(op).expect("error");
    }

    fn decrease_app_volume_by_percent(&mut self, index: u32, delta: f64) {
        let mut app_ref = self
            .get_app_by_index(index)
            .expect("Could not find device specified");
        let new_vol = Volume::from(Volume(volume_from_percent(delta) as u32));
        println!("{:?}", new_vol.print_verbose(true));
        let volumes = app_ref
            .volume
            .decrease(new_vol)
            .expect("Volume couldn't be set");
        let op = self
            .handler
            .introspect
            .set_source_output_volume(index, &volumes, None);
        self.handler.wait_for_operation(op).expect("error");
    }

    fn move_app_by_index(
        &mut self,
        stream_index: u32,
        device_index: u32,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let success_ref = success.clone();
        let op = self.handler.introspect.move_source_output_by_index(
            stream_index,
            device_index,
            Some(Box::new(move |res| {
                success_ref.borrow_mut().clone_from(&res)
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }

    fn move_app_by_name(
        &mut self,
        stream_index: u32,
        device_name: &str,
    ) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let success_ref = success.clone();
        let op = self.handler.introspect.move_source_output_by_name(
            stream_index,
            device_name,
            Some(Box::new(move |res| {
                success_ref.borrow_mut().clone_from(&res)
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }

    fn set_app_mute(&mut self, index: u32, mute: bool) -> Result<bool, ControllerError> {
        let success = Rc::new(RefCell::new(false));
        let success_ref = success.clone();
        let op = self.handler.introspect.set_source_mute_by_index(
            index,
            mute,
            Some(Box::new(move |res| {
                success_ref.borrow_mut().clone_from(&res)
            })),
        );

        self.handler.wait_for_operation(op)?;
        let result = success.borrow_mut().clone();
        Ok(result)
    }
    fn set_app_mute_by_name(&mut self, name: &str, mute: bool) -> Result<bool, ControllerError> {
        let sucess = Rc::new(RefCell::new(false));
        let sucess_ref = sucess.clone();
        let op = self.handler.introspect.set_source_mute_by_name(
            name,
            mute,
            Some(Box::new(move |res| {
                sucess_ref.borrow_mut().clone_from(&res);
            })),
        );
        self.handler.wait_for_operation(op)?;
        let result = sucess.borrow_mut().clone();
        Ok(result)
    }
}

impl AppEvent for SourceController {
    /// this function is used to listen to any event notification . e.g add or remove headphone, bluetooth headset connect and more but it is not working yet.
    ///  since we're in a single thread library in the future we could run it in the gui even loop and use crossbream_channel to send msg from the backend thread
    fn subscribe(&mut self) -> Result<(), ControllerError> {
        self.handler.context.borrow_mut().subscribe(
            InterestMaskSet::SINK
                | InterestMaskSet::SOURCE
                | InterestMaskSet::CARD
                | InterestMaskSet::SOURCE_OUTPUT
                | InterestMaskSet::CLIENT
                | InterestMaskSet::SERVER,
            |success: bool| {
                println!("Subscribe sucess: {}", success);
            },
        );
        self.handler
            .context
            .borrow_mut()
            .set_event_callback(Some(Box::new(move |name, list| {
                println!("Name: {:?} {:?}", name, list);
            })));
        self.handler
            .context
            .borrow_mut()
            .set_subscribe_callback(Some(Box::new(move |facility, operation, index| {
                if let Some(facility) = facility {
                    match facility {
                        Facility::Server | Facility::Client => {
                            println!("{:?} {:?}", facility, operation);
                            return;
                        }
                        _ => {}
                    }
                    match operation {
                        Some(subscribe::Operation::New) => {
                            println!("new added index: {} ", index);
                        }
                        Some(subscribe::Operation::Changed) => {
                            println!("Changed  index: {}", index);
                        }
                        Some(subscribe::Operation::Removed) => {
                            println!("Remove index: {}", index);
                        }
                        _ => {}
                    }
                }
            })));
        Ok(())
    }
    fn sink_event(&mut self) -> Result<u32, ControllerError> {
        Ok(1)
    }
    fn source_event(&mut self) -> Result<u32, ControllerError> {
        Ok(1)
    }
    fn sink_input_event(&mut self) -> Result<u32, ControllerError> {
        Ok(1)
    }
    fn source_input_event(&mut self) -> Result<u32, ControllerError> {
        Ok(1)
    }
    fn module_event(&mut self) -> Result<u32, ControllerError> {
        Ok(1)
    }
    fn client_event(&mut self) -> Result<u32, ControllerError> {
        Ok(1)
    }
    fn sample_cache_event(&mut self) -> Result<u32, ControllerError> {
        Ok(1)
    }
    fn server_event(&mut self) -> Result<u32, ControllerError> {
        Ok(1)
    }
    fn card_event(&mut self) -> Result<u32, ControllerError> {
        Ok(1)
    }
}
