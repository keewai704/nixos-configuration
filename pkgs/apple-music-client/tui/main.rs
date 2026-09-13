mod tui;

use anyhow::{Context, Result, bail};
use fs2::FileExt;
use siora::library::LibraryStore;
use std::{
    fs::OpenOptions,
    io::{self, IsTerminal},
    os::unix::fs::{DirBuilderExt, OpenOptionsExt},
    path::PathBuf,
};

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--download-track") {
        return siora::download::run_worker();
    }
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        println!(
            "Siora — Apple Music TUI\n\nUsage: siora [--no-auth] [https://music.apple.com/…]\n\nCtrl+f Search   / Filter   Enter Open/play   Space Pause\ne Add to queue   E Play next   q Queue   a Actions   ? Help\nTab Focus   Backspace Back   Ctrl+c Exit\n\n--no-auth  Browse public pages and play public radio without the auth helper\n\nAccount setup: alac-room-auth-import /path/to/apple-music.apkm\nThen use :login in Siora. Existing alac-room data and sessions are preserved."
        );
        return Ok(());
    }
    if args.iter().any(|arg| arg == "--version" || arg == "-V") {
        println!("siora {} (TUI)", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }
    let no_auth = args.iter().any(|arg| arg == "--no-auth");
    let urls: Vec<_> = args.iter().filter(|arg| *arg != "--no-auth").collect();
    if urls.len() > 1 {
        bail!("Specify one Apple Music URL. See siora --help.");
    }
    let url = urls
        .first()
        .map(|url| tui::browse::validate_url(url))
        .transpose()?;
    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        bail!("Siora requires an interactive terminal. See siora --help.");
    }
    let data = std::env::var_os("ALAC_ROOM_DATA_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("XDG_DATA_HOME").map(|path| PathBuf::from(path).join("alac-room"))
        })
        .or_else(|| {
            std::env::var_os("HOME").map(|path| PathBuf::from(path).join(".local/share/alac-room"))
        })
        .context("Set HOME, XDG_DATA_HOME, or ALAC_ROOM_DATA_DIR")?;
    std::fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&data)?;
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .truncate(false)
        .open(data.join("app.lock"))?;
    lock.try_lock_exclusive()
        .context("Siora is already running")?;
    let store = LibraryStore::open(data.join("apple-music.json"))?;
    tui::run(store, data.join("downloads"), no_auth, url)
}
