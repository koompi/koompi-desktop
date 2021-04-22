use std::path::{PathBuf, Path};
use crate::constants::{DATA_DIRS, LOCAL_DATA};
use std::collections::HashMap;

pub trait Resources {
    fn relative_path() -> PathBuf;

    fn base_paths() -> Vec<PathBuf> {
        let mut base_paths = vec![LOCAL_DATA.to_path_buf()];
        DATA_DIRS.iter().for_each(|path| base_paths.push(path.to_path_buf()));
        base_paths
    }
    
    fn additional_paths() -> Option<Vec<PathBuf>> {
        None
    }

    fn paths(&self) -> Vec<PathBuf> {
        let mut paths: Vec<PathBuf> = Self::base_paths().into_iter().filter_map(|base| {
            let path = base.join(Self::relative_path());
            if path.exists() {
                Some(path)
            } else {
                None
            }
        }).collect();
        if let Some(additional_paths) = Self::additional_paths() {
            additional_paths.into_iter().for_each(|path| {
                if path.exists() && path.is_dir() {
                    paths.push(path)
                }
            })
        }
        paths
    }

    fn find_path_exists<P: AsRef<Path>>(&self, file: P) -> Option<PathBuf> {
        self.paths().into_iter().find_map(|p| {
            let path = p.join(file.as_ref());
            if path.exists() {
                Some(path)
            } else {
                None
            }
        })
    }

    fn resources(&self, max_depth: Option<usize>) -> HashMap<String, PathBuf> {
        let mut map = HashMap::new();
        self.paths().into_iter().filter(|path| path.exists() && path.is_dir()).for_each(|path| {
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