use std::path::PathBuf;
use crate::constants::{CONF_DIRS, LOCAL_CONF};

pub trait Config {
    fn config_file() -> PathBuf;

    fn base_paths() -> Vec<PathBuf> {
        let mut base_paths = vec![LOCAL_CONF.to_path_buf()];
        CONF_DIRS.iter().for_each(|path| base_paths.push(path.to_path_buf()));
        base_paths
    }

    fn additional_base_paths() -> Option<Vec<PathBuf>> {
        None
    }

    fn paths(&self) -> Vec<PathBuf> {
        let mut base_paths = Self::base_paths();
        if let Some(additional_paths) = Self::additional_base_paths() {
            base_paths.extend(additional_paths);
        }
        base_paths.into_iter().filter_map(|base| {
            let path = base.join(Self::config_file());

            if path.exists() && path.is_file() {
                Some(path)
            } else {
                None
            }
        }).collect()
    }

    fn find_value(&self, section: &str, key: &str) -> Option<String> {
        let mut config = configparser::ini::Ini::new();

        self.paths().into_iter().find_map(|path| {
            if let Ok(_) = config.load(path.to_str().unwrap()) {
                config.get(section, key)
            } else {
                None
            }
        })
    }

    fn find_values(&self, section: &str, key: &str) -> Vec<String> {
        let mut config = configparser::ini::Ini::new();

        let values = self.paths().into_iter().fold(Vec::new(), |mut vals, path| {
            if let Ok(_) = config.load(path.to_str().unwrap()) {
                if let Some(val) = config.get(section, key) {
                    vals.push(val);
                }
            }
            vals
        });

        values
    }
}