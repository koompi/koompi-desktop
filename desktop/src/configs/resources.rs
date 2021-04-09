use std::path::PathBuf;
use std::collections::HashMap;

pub trait Resources {
    fn relative_path() -> PathBuf;

    fn additional_paths() -> Option<Vec<PathBuf>> {
        None
    }

    fn base_paths() -> Vec<PathBuf> {
        let sys_dir = PathBuf::from("/usr/share");
        let sys_local_dir = PathBuf::from("/usr/local/share");
        let local_dir = dirs_next::data_dir().unwrap();
        vec![local_dir, sys_local_dir, sys_dir]
    }

    fn paths() -> Vec<PathBuf> {
        let mut paths: Vec<PathBuf> = Self::base_paths().into_iter().map(|path| path.join(Self::relative_path())).collect();
        if let Some(additional_paths) = Self::additional_paths() {
            paths.extend(additional_paths);
        }
        paths
    }

    fn resources(max_depth: Option<usize>) -> HashMap<String, PathBuf> {
        let mut map = HashMap::new();
        Self::paths().into_iter().filter(|path| path.exists() && path.is_dir()).for_each(|path| {
            let mut walkdir = walkdir::WalkDir::new(path.to_path_buf());
            if let Some(max_depth) = max_depth {
                walkdir = walkdir.max_depth(max_depth);
            }
            
            walkdir.into_iter().filter_map(|e| e.ok()).for_each(|entry| {
                let key = entry.file_name().to_str().unwrap().split('.').collect::<Vec<&str>>()[0];
                map.insert(key.to_string(), entry.into_path());
            });
        });
        map
    }
}