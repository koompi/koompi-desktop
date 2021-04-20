use std::path::PathBuf;

pub trait Config {
    fn config_file() -> PathBuf;

    fn base_paths() -> Vec<PathBuf> {
        vec![
            dirs_next::config_dir().unwrap(),
            PathBuf::from("/etc")
        ]
    }

    fn cache_file() -> Option<PathBuf> {
        None
    }

    fn paths(&self) -> Vec<PathBuf> {
        let mut paths: Vec<PathBuf> = Self::base_paths().into_iter().filter_map(|base| {
            let path = base.join(Self::config_file());

            if path.exists() && path.is_file() {
                Some(path)
            } else {
                None
            }
        }).collect();
        if let Some(cache_file) = Self::cache_file() {
            Self::base_paths().into_iter().for_each(|base| {
                let path = base.join(cache_file.to_path_buf());
                if path.exists() && path.is_file() {
                    paths.push(path);
                }
            })
        }
        paths
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
}