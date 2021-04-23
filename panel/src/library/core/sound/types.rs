use libpulse_binding::{
    channelmap,
    context::introspect,
    def,
    def::{DevicePortType, PortAvailable},
    direction::FlagSet,
    format,
    proplist::Proplist,
    sample,
    time::MicroSeconds,
    volume::{ChannelVolumes, Volume},
};

/// These structs are direct representations of what libpulse_binding gives
/// created to be copyable / cloneable for use in and out of callbacks

/// This is a wrapper around SinkPortInfo and SourcePortInfo as they have the same members
#[derive(Clone, Debug)]
pub struct DevicePortInfo {
    /// Name of the sink.
    pub name: Option<String>,
    /// Description of this sink.
    pub description: Option<String>,
    /// The higher this value is, the more useful this port is as a default.
    pub priority: u32,
    /// A flag indicating availability status of this port.
    pub available: PortAvailable,
}

impl<'a> From<&'a Box<introspect::SinkPortInfo<'a>>> for DevicePortInfo {
    fn from(item: &'a Box<introspect::SinkPortInfo<'a>>) -> Self {
        DevicePortInfo {
            name: item.name.as_ref().map(|cow| cow.to_string()),
            description: item.description.as_ref().map(|cow| cow.to_string()),
            priority: item.priority,
            available: item.available,
        }
    }
}

impl<'a> From<&'a introspect::SinkPortInfo<'a>> for DevicePortInfo {
    fn from(item: &'a introspect::SinkPortInfo<'a>) -> Self {
        DevicePortInfo {
            name: item.name.as_ref().map(|cow| cow.to_string()),
            description: item.description.as_ref().map(|cow| cow.to_string()),
            priority: item.priority,
            available: item.available,
        }
    }
}

impl<'a> From<&'a Box<introspect::SourcePortInfo<'a>>> for DevicePortInfo {
    fn from(item: &'a Box<introspect::SourcePortInfo<'a>>) -> Self {
        DevicePortInfo {
            name: item.name.as_ref().map(|cow| cow.to_string()),
            description: item.description.as_ref().map(|cow| cow.to_string()),
            priority: item.priority,
            available: item.available,
        }
    }
}

impl<'a> From<&'a introspect::SourcePortInfo<'a>> for DevicePortInfo {
    fn from(item: &'a introspect::SourcePortInfo<'a>) -> Self {
        DevicePortInfo {
            name: item.name.as_ref().map(|cow| cow.to_string()),
            description: item.description.as_ref().map(|cow| cow.to_string()),
            priority: item.priority,
            available: item.available,
        }
    }
}

/// This is a wrapper around SinkState and SourceState as they have the same values
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum DevState {
    /// This state is used when the server does not support sink state introspection.
    Invalid = -1,
    /// Running, sink is playing and used by at least one non-corked sink-input.
    Running = 0,
    /// When idle, the sink is playing but there is no non-corked sink-input attached to it.
    Idle = 1,
    /// When suspended, actual sink access can be closed, for instance.
    Suspended = 2,
}

impl<'a> From<def::SourceState> for DevState {
    fn from(s: def::SourceState) -> Self {
        match s {
            def::SourceState::Idle => DevState::Idle,
            def::SourceState::Invalid => DevState::Invalid,
            def::SourceState::Running => DevState::Running,
            def::SourceState::Suspended => DevState::Suspended,
        }
    }
}

impl<'a> From<def::SinkState> for DevState {
    fn from(s: def::SinkState) -> Self {
        match s {
            def::SinkState::Idle => DevState::Idle,
            def::SinkState::Invalid => DevState::Invalid,
            def::SinkState::Running => DevState::Running,
            def::SinkState::Suspended => DevState::Suspended,
        }
    }
}

#[derive(Clone, Debug)]
pub struct DeviceInfo {
    /// Index of the sink.
    pub index: u32,
    /// Name of the sink.
    pub name: Option<String>,
    /// Description of this sink.
    pub description: Option<String>,
    /// Sample spec of this sink.
    pub sample_spec: sample::Spec,
    /// Channel map.
    pub channel_map: channelmap::Map,
    /// Index of the owning module of this sink, or `None` if is invalid.
    pub owner_module: Option<u32>,
    /// Volume of the sink.
    pub volume: ChannelVolumes,
    /// Mute switch of the sink.
    pub mute: bool,
    /// Index of the monitor source connected to this sink.
    pub monitor: Option<u32>,
    /// The name of the monitor source.
    pub monitor_name: Option<String>,
    /// Length of queued audio in the output buffer.
    pub latency: MicroSeconds,
    /// Driver name.
    pub driver: Option<String>,
    /// Flags.
    pub flags: FlagsType,
    /// Property list.
    pub proplist: Proplist,
    /// The latency this device has been configured to.
    pub configured_latency: MicroSeconds,
    /// Some kind of “base” volume that refers to unamplified/unattenuated volume in the context of
    /// the output device.
    pub base_volume: Volume,
    /// State.
    pub state: DevState,
    /// Number of volume steps for sinks which do not support arbitrary volumes.
    pub n_volume_steps: u32,
    /// Card index, or `None` if invalid.
    pub card: Option<u32>,
    /// Set of available ports.
    pub ports: Vec<DevicePortInfo>,
    // Pointer to active port in the set, or None.
    pub active_port: Option<DevicePortInfo>,
    /// Set of formats supported by the sink.
    pub formats: Vec<format::Info>,
}
#[derive(Clone, Debug)]
pub enum FlagsType {
    Sink(def::SinkFlagSet),
    Source(def::SourceFlagSet),
}
impl<'a> From<&'a introspect::SinkInfo<'a>> for DeviceInfo {
    fn from(item: &'a introspect::SinkInfo<'a>) -> Self {
        DeviceInfo {
            name: item.name.as_ref().map(|cow| cow.to_string()),
            index: item.index,
            description: item.description.as_ref().map(|cow| cow.to_string()),
            sample_spec: item.sample_spec,
            channel_map: item.channel_map,
            owner_module: item.owner_module,
            volume: item.volume,
            mute: item.mute,
            monitor: Some(item.monitor_source),
            monitor_name: item.monitor_source_name.as_ref().map(|cow| cow.to_string()),
            latency: item.latency,
            driver: item.driver.as_ref().map(|cow| cow.to_string()),
            flags: FlagsType::Sink(item.flags),
            proplist: item.proplist.clone(),
            configured_latency: item.configured_latency,
            base_volume: item.base_volume,
            state: DevState::from(item.state),
            n_volume_steps: item.n_volume_steps,
            card: item.card,
            ports: item.ports.iter().map(From::from).collect(),
            active_port: item.active_port.as_ref().map(From::from),
            formats: item.formats.clone(),
        }
    }
}

impl<'a> From<&'a introspect::SourceInfo<'a>> for DeviceInfo {
    fn from(item: &'a introspect::SourceInfo<'a>) -> Self {
        DeviceInfo {
            name: item.name.as_ref().map(|cow| cow.to_string()),
            index: item.index,
            description: item.description.as_ref().map(|cow| cow.to_string()),
            sample_spec: item.sample_spec,
            channel_map: item.channel_map,
            owner_module: item.owner_module,
            volume: item.volume,
            mute: item.mute,
            monitor: item.monitor_of_sink,
            monitor_name: item
                .monitor_of_sink_name
                .as_ref()
                .map(|cow| cow.to_string()),
            latency: item.latency,
            driver: item.driver.as_ref().map(|cow| cow.to_string()),
            flags: FlagsType::Source(item.flags),
            proplist: item.proplist.clone(),
            configured_latency: item.configured_latency,
            base_volume: item.base_volume,
            state: DevState::from(item.state),
            n_volume_steps: item.n_volume_steps,
            card: item.card,
            ports: item.ports.iter().map(From::from).collect(),
            active_port: item.active_port.as_ref().map(From::from),
            formats: item.formats.clone(),
        }
    }
}

#[derive(Clone)]
pub struct ApplicationInfo {
    /// Index of the sink input.
    pub index: u32,
    /// Name of the sink input.
    pub name: Option<String>,
    /// Index of the module this sink input belongs to, or `None` when it does not belong to any
    /// module.
    pub owner_module: Option<u32>,
    /// Index of the client this sink input belongs to, or invalid when it does not belong to any
    /// client.
    pub client: Option<u32>,
    /// Index of the connected sink/source.
    pub connection_id: u32,
    /// The sample specification of the sink input.
    pub sample_spec: sample::Spec,
    /// Channel map.
    pub channel_map: channelmap::Map,
    /// The volume of this sink input.
    pub volume: ChannelVolumes,
    /// Latency due to buffering in sink input, see
    /// [`def::TimingInfo`](../../def/struct.TimingInfo.html) for details.
    pub buffer_usec: MicroSeconds,
    /// Latency of the sink device, see
    /// [`def::TimingInfo`](../../def/struct.TimingInfo.html) for details.
    pub connection_usec: MicroSeconds,
    /// The resampling method used by this sink input.
    pub resample_method: Option<String>,
    /// Driver name.
    pub driver: Option<String>,
    /// Stream muted.
    pub mute: bool,
    /// Property list.
    pub proplist: Proplist,
    /// Stream corked.
    pub corked: bool,
    /// Stream has volume. If not set, then the meaning of this struct’s volume member is unspecified.
    pub has_volume: bool,
    /// The volume can be set. If not set, the volume can still change even though clients can’t
    /// control the volume.
    pub volume_writable: bool,
    /// Stream format information.
    pub format: format::Info,
}

impl<'a> From<&'a introspect::SinkInputInfo<'a>> for ApplicationInfo {
    fn from(item: &'a introspect::SinkInputInfo<'a>) -> Self {
        ApplicationInfo {
            index: item.index,
            name: item.name.as_ref().map(|cow| cow.to_string()),
            owner_module: item.owner_module,
            client: item.client,
            connection_id: item.sink,
            sample_spec: item.sample_spec,
            channel_map: item.channel_map,
            volume: item.volume,
            buffer_usec: item.buffer_usec,
            connection_usec: item.sink_usec,
            resample_method: item.resample_method.as_ref().map(|cow| cow.to_string()),
            driver: item.driver.as_ref().map(|cow| cow.to_string()),
            mute: item.mute,
            proplist: item.proplist.clone(),
            corked: item.corked,
            has_volume: item.has_volume,
            volume_writable: item.volume_writable,
            format: item.format.clone(),
        }
    }
}

impl<'a> From<&'a introspect::SourceOutputInfo<'a>> for ApplicationInfo {
    fn from(item: &'a introspect::SourceOutputInfo<'a>) -> Self {
        ApplicationInfo {
            index: item.index,
            name: item.name.as_ref().map(|cow| cow.to_string()),
            owner_module: item.owner_module,
            client: item.client,
            connection_id: item.source,
            sample_spec: item.sample_spec,
            channel_map: item.channel_map,
            volume: item.volume,
            buffer_usec: item.buffer_usec,
            connection_usec: item.source_usec,
            resample_method: item.resample_method.as_ref().map(|cow| cow.to_string()),
            driver: item.driver.as_ref().map(|cow| cow.to_string()),
            mute: item.mute,
            proplist: item.proplist.clone(),
            corked: item.corked,
            has_volume: item.has_volume,
            volume_writable: item.volume_writable,
            format: item.format.clone(),
        }
    }
}

pub struct ServerInfo {
    /// User name of the daemon process.
    pub user_name: Option<String>,
    /// Host name the daemon is running on.
    pub host_name: Option<String>,
    /// Version string of the daemon.
    pub server_version: Option<String>,
    /// Server package name (usually “pulseaudio”).
    pub server_name: Option<String>,
    /// Default sample specification.
    pub sample_spec: sample::Spec,
    /// Name of default sink.
    pub default_sink_name: Option<String>,
    /// Name of default source.
    pub default_source_name: Option<String>,
    /// A random cookie for identifying this instance of PulseAudio.
    pub cookie: u32,
    /// Default channel map.
    pub channel_map: channelmap::Map,
}

impl<'a> From<&'a introspect::ServerInfo<'a>> for ServerInfo {
    fn from(info: &'a introspect::ServerInfo<'a>) -> Self {
        ServerInfo {
            user_name: info.user_name.as_ref().map(|cow| cow.to_string()),
            host_name: info.host_name.as_ref().map(|cow| cow.to_string()),
            server_version: info.server_version.as_ref().map(|cow| cow.to_string()),
            server_name: info.server_name.as_ref().map(|cow| cow.to_string()),
            sample_spec: info.sample_spec,
            default_sink_name: info.default_sink_name.as_ref().map(|cow| cow.to_string()),
            default_source_name: info.default_source_name.as_ref().map(|cow| cow.to_string()),
            cookie: info.cookie,
            channel_map: info.channel_map,
        }
    }
}
#[derive(Clone, Debug)]
pub struct CardSndProfile2 {
    pub name: Option<String>,
    pub description: Option<String>,
    pub n_sink: u32,
    pub n_sources: u32,
    pub priority: u32,
    pub available: bool,
}
impl<'a> From<&'a introspect::CardProfileInfo2<'a>> for CardSndProfile2 {
    fn from(card_pf: &'a introspect::CardProfileInfo2<'a>) -> Self {
        Self {
            name: card_pf.name.as_ref().map(|s| s.to_string()),
            description: card_pf.description.as_ref().map(|s| s.to_string()),
            n_sink: card_pf.n_sinks,
            n_sources: card_pf.n_sources,
            priority: card_pf.priority,
            available: card_pf.available,
        }
    }
}
#[derive(Clone, Debug)]
pub struct CardPortSoundInfo {
    pub name: Option<String>,
    pub description: Option<String>,
    pub priority: u32,
    pub available: PortAvailable,
    pub direction: FlagSet,
    pub proplist: Proplist,
    pub latency_offset: i64,
    pub profiles: Vec<CardSndProfile2>,
    pub availability_group: Option<String>,
    pub dev_type: DevicePortType,
}

impl<'a> From<&'a introspect::CardPortInfo<'a>> for CardPortSoundInfo {
    fn from(card_portinfo: &'a introspect::CardPortInfo<'a>) -> Self {
        let mut vec_profiles: Vec<CardSndProfile2> = Vec::new();
        for i in card_portinfo.profiles.iter() {
            vec_profiles.push(CardSndProfile2::from(i));
        }
        Self {
            name: card_portinfo.name.as_ref().map(|s| s.to_string()),
            description: card_portinfo.description.as_ref().map(|s| s.to_string()),
            priority: card_portinfo.priority,
            available: card_portinfo.available,
            direction: card_portinfo.direction,
            proplist: card_portinfo.proplist.clone(),
            latency_offset: card_portinfo.latency_offset,
            profiles: vec_profiles,
            availability_group: card_portinfo
                .availability_group
                .as_ref()
                .map(|s| s.to_string()),
            dev_type: card_portinfo.r#type,
        }
    }
}

#[derive(Clone, Debug)]
pub struct SoundCardInfo {
    pub index: u32,
    pub name: Option<String>,
    pub owner_module: Option<u32>,
    pub driver: Option<String>,
    pub proplist: Proplist,
    pub ports: Vec<CardPortSoundInfo>,
    pub profiles: Vec<CardSndProfile2>,
    pub active_profile: CardSndProfile2,
}

impl<'a> From<&'a introspect::CardInfo<'a>> for SoundCardInfo {
    fn from(info: &'a introspect::CardInfo<'a>) -> Self {
        let mut vec_ports: Vec<CardPortSoundInfo> = Vec::new();
        let mut vec_profiles: Vec<CardSndProfile2> = Vec::new();
        for (i, j) in info.ports.iter().zip(info.profiles.iter()) {
            vec_ports.push(CardPortSoundInfo::from(i));
            vec_profiles.push(CardSndProfile2::from(j))
        }
        SoundCardInfo {
            index: info.index,
            name: info.name.as_ref().map(|s| s.to_string()),
            owner_module: info.owner_module,
            driver: info.driver.as_ref().map(|s| s.to_string()),
            proplist: info.proplist.clone(),
            ports: vec_ports,
            profiles: vec_profiles,
            active_profile: CardSndProfile2::from(info.active_profile.as_ref().unwrap().as_ref()),
        }
    }
}
