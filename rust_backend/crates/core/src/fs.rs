//! Filesystem path helpers shared by the native and extension backends.

use std::path::{Component, Path, PathBuf};

/// Lexically cleans a path like Go's `filepath.Clean`: drops `.` components,
/// folds `name/..`, keeps leading `..` on relative paths, drops `..` above the
/// root, and returns `.` for an empty result. The filesystem is not consulted.
pub fn clean(path: &Path) -> PathBuf {
    let mut result = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                if result.file_name().is_some_and(|name| name != "..") {
                    result.pop();
                } else if !result.has_root() {
                    result.push("..");
                }
            }
            _ => result.push(component),
        }
    }
    if result.as_os_str().is_empty() {
        ".".into()
    } else {
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The copy `isrc::native_files` used before it shared this helper.
    fn previous_isrc_clean(path: &Path) -> PathBuf {
        let mut output = PathBuf::new();
        for component in path.components() {
            match component {
                Component::CurDir => {}
                Component::ParentDir if output.file_name().is_some_and(|name| name != "..") => {
                    output.pop();
                }
                Component::ParentDir if output.has_root() => {}
                other => output.push(other.as_os_str()),
            }
        }
        if output.as_os_str().is_empty() {
            output.push(".");
        }
        output
    }

    #[test]
    fn clean_matches_previous_isrc_copy_and_go_results() {
        let cases = [
            ("", "."),
            (".", "."),
            ("./", "."),
            ("..", ".."),
            ("../..", "../.."),
            ("../../a", "../../a"),
            ("a/..", "."),
            ("a/../..", ".."),
            ("a/b/../../..", ".."),
            ("a/./b/", "a/b"),
            ("a//b///c", "a/b/c"),
            ("a/b/", "a/b"),
            ("/", "/"),
            ("/..", "/"),
            ("/../a", "/a"),
            ("/a/b/../c/./d/", "/a/c/d"),
            ("/a/..", "/"),
            ("//a", "/a"),
            ("a/...", "a/..."),
            ("a/.../..", "a"),
            ("..a/../b", "b"),
            ("\u{00e9}/\u{1f3b5}/../x", "\u{00e9}/x"),
        ];
        for (input, expected) in cases {
            let input = Path::new(input);
            assert_eq!(clean(input), Path::new(expected), "{input:?}");
            assert_eq!(clean(input), previous_isrc_clean(input), "{input:?}");
        }
    }
}
