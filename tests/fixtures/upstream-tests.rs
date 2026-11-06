#[test]
fn passes() {}

#[test]
fn fails() {
    panic!("this fixture test always fails");
}

#[test]
fn reads_cargo_env() {
    assert_eq!(std::env::var("CARGO_PKG_NAME").as_deref(), Ok("fixture"));
    let cwd = std::env::current_dir().unwrap();
    assert_eq!(std::env::var_os("CARGO_MANIFEST_DIR"), Some(cwd.into_os_string()));
}
