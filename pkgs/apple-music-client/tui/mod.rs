pub mod browse;
mod controls;
mod cover;
mod events;
mod mouse;
mod navigation;
mod playback;
mod queue;
mod render;
mod settings;

use anyhow::{Context, Result, bail};
use browse::{Page, api_page, playable};
use crossterm::{
    SynchronizedUpdate,
    cursor::{Hide, Show},
    event::{
        self, DisableBracketedPaste, DisableMouseCapture, EnableBracketedPaste, EnableMouseCapture,
        Event as TerminalEvent, KeyCode, KeyEvent, KeyEventKind, KeyModifiers,
    },
    execute,
    terminal::{
        EndSynchronizedUpdate, EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode,
        enable_raw_mode,
    },
};
use queue::Queue;
use ratatui::{Terminal, backend::CrosstermBackend, widgets::ListState};
use serde_json::{Value, json};
use siora::{
    apple_music::{self, AppleMusic, LoginState},
    audio_output::{self, AudioCommand, AudioEvent},
    auth_service::{self, AuthRuntime, Endpoints},
    library::LibraryStore,
    model::MusicItem,
    mpris::{self, MediaCommand},
    player::{self, PreparedTrack},
};
use std::{
    io::{self, IsTerminal, Write},
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, Sender},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

#[derive(Clone, Copy, PartialEq)]
enum Focus {
    Browse,
    Navigation,
    Panel,
}

#[derive(Clone, Copy, PartialEq)]
enum Panel {
    Queue,
    Lyrics,
    Details,
}

#[derive(Clone, Copy)]
enum LoginPrompt {
    Account,
    Code,
}

enum InputKind {
    Search(bool),
    Filter(String),
    Command,
    Username,
    Password(String),
    Code,
    Setting(&'static str),
    PlaylistName(bool),
}

struct Input {
    kind: InputKind,
    text: String,
    cursor: usize,
}

impl Input {
    fn new(kind: InputKind, text: String) -> Self {
        let cursor = text.len();
        Self { kind, text, cursor }
    }

    fn insert(&mut self, text: &str) {
        let text = browse::clean(text);
        if self.text.len() + text.len() <= 4096 {
            self.text.insert_str(self.cursor, &text);
            self.cursor += text.len();
        }
    }

    fn previous(&self) -> usize {
        self.text[..self.cursor]
            .char_indices()
            .next_back()
            .map_or(0, |(index, _)| index)
    }

    fn next(&self) -> usize {
        self.text[self.cursor..]
            .chars()
            .next()
            .map_or(self.cursor, |ch| self.cursor + ch.len_utf8())
    }

    fn masked(&self) -> bool {
        matches!(self.kind, InputKind::Password(_) | InputKind::Code)
    }
}

enum Overlay {
    Help,
    Actions(MusicItem, Option<u64>, ListState),
    Settings(ListState),
    Replace(Vec<MusicItem>, String, String, ListState),
    Playlists(MusicItem, Box<Page>),
    Devices(Vec<Value>, ListState),
    RemoveDownload(MusicItem, ListState),
    Text(String, String),
}

enum Job {
    Page(u64, bool, Result<Page>),
    Connected(
        u64,
        Option<LoginPrompt>,
        Result<(auth_service::ServiceStatus, Option<AppleMusic>)>,
    ),
    Login(u64, Result<LoginState>),
    Prepared(u64, u64, String, Result<PreparedTrack>),
    Prefetched(u64, u64, u64, String, Result<PreparedTrack>),
    Radio(u64, Result<String>),
    Station(u64, bool, Result<Vec<MusicItem>>),
    Mutation(Result<String>),
    Favorite(MusicItem, bool, Result<Value>),
    Playlists(MusicItem, Result<Page>),
    Download(MusicItem, String, Result<PreparedTrack>),
    Enqueue(bool, Result<Vec<MusicItem>>),
    Devices(Result<Vec<Value>>),
    Cover(cover::Role, String, Result<Option<image::DynamicImage>>),
}

struct Ready {
    id: u64,
    track: PreparedTrack,
}

struct Station {
    serial: u64,
    item: MusicItem,
    busy: bool,
    waiting: bool,
    failed: bool,
}

struct App {
    store: LibraryStore,
    cache: PathBuf,
    page: Page,
    covers: cover::Covers,
    mouse: mouse::Mouse,
    history: Vec<Page>,
    focus: Focus,
    panel: Option<Panel>,
    panel_scroll: u16,
    nav: ListState,
    queue: Queue,
    queue_list: ListState,
    input: Option<Input>,
    search_draft: (String, bool),
    overlay: Option<Overlay>,
    status: String,
    account: String,
    api: Option<AppleMusic>,
    runtime: Option<AuthRuntime>,
    auth_busy: bool,
    auth_ready: bool,
    auth_problem: Option<String>,
    auth_generation: u64,
    request: u64,
    pending_page: Option<u64>,
    generation: u64,
    prefetch: u64,
    ready: Option<Ready>,
    preparing: bool,
    loaded: bool,
    snapshot: Value,
    source: Value,
    lyrics: String,
    station: Option<Station>,
    station_serial: u64,
    cancel: Arc<AtomicBool>,
    next_cancel: Arc<AtomicBool>,
    download_cancel: Arc<AtomicBool>,
    downloading: bool,
    audio: Sender<AudioCommand>,
    audio_events: Receiver<AudioEvent>,
    audio_thread: Option<JoinHandle<()>>,
    mpris: Option<(Sender<mpris::Metadata>, Receiver<MediaCommand>)>,
    last_published: Option<mpris::Metadata>,
    tx: Sender<Job>,
    rx: Receiver<Job>,
    jobs: usize,
    prepare_threads: Vec<JoinHandle<()>>,
    dirty: bool,
    quit: bool,
}

pub fn run(store: LibraryStore, cache: PathBuf, no_auth: bool, url: Option<String>) -> Result<()> {
    let stop = Arc::new(AtomicBool::new(false));
    for signal in [
        signal_hook::consts::SIGTERM,
        signal_hook::consts::SIGHUP,
        signal_hook::consts::SIGINT,
    ] {
        signal_hook::flag::register(signal, stop.clone())?;
    }
    let previous_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        restore_terminal();
        previous_hook(info);
    }));
    enable_raw_mode()?;
    let _guard = TerminalGuard;
    execute!(
        io::stdout(),
        EnterAlternateScreen,
        EnableBracketedPaste,
        EnableMouseCapture,
        Hide
    )?;
    let graphics = cover::Graphics::from_terminal();
    let mut terminal = Terminal::new(CrosstermBackend::new(TerminalOutput(io::stdout())))?;
    let mut app = App::new(store, cache, no_auth, graphics);
    if let Some(url) = url {
        app.open_url(url)?;
    }
    let interaction = (|| -> Result<()> {
        while !app.quit && !stop.load(Ordering::Relaxed) {
            if !terminal_connected() {
                break;
            }
            io::stdout().sync_update(|_| {
                if let Err(error) = app.poll() {
                    app.status = format!("{error:#}");
                }
                terminal
                    .draw(|frame| render::draw(frame, &mut app))
                    .map(|_| ())
            })??;
            if event::poll(Duration::from_millis(60))? {
                if !terminal_connected() {
                    break;
                }
                let result = match event::read()? {
                    TerminalEvent::Key(key) if key.kind != KeyEventKind::Release => app.key(key),
                    TerminalEvent::Mouse(event) => app.mouse_event(event),
                    TerminalEvent::Paste(value) => {
                        if let Some(input) = &mut app.input {
                            input.insert(&value);
                        }
                        app.preview_filter();
                        Ok(())
                    }
                    TerminalEvent::Resize(_, _) => {
                        app.covers.resize();
                        Ok(())
                    }
                    _ => Ok(()),
                };
                if let Err(error) = result {
                    app.status = format!("{error:#}");
                }
            }
        }
        Ok(())
    })();
    if app.dirty {
        app.store.save()?;
    }
    if terminal_connected() {
        interaction
    } else {
        Ok(())
    }
}

fn terminal_connected() -> bool {
    io::stdin().is_terminal() && io::stdout().is_terminal()
}

struct TerminalOutput(io::Stdout);

impl Write for TerminalOutput {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        match self.0.write(bytes) {
            Err(_) if !self.0.is_terminal() => Ok(bytes.len()),
            result => result,
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        match self.0.flush() {
            Err(_) if !self.0.is_terminal() => Ok(()),
            result => result,
        }
    }
}

struct TerminalGuard;
impl Drop for TerminalGuard {
    fn drop(&mut self) {
        restore_terminal();
    }
}

fn restore_terminal() {
    let _ = disable_raw_mode();
    let _ = execute!(
        io::stdout(),
        EndSynchronizedUpdate,
        DisableBracketedPaste,
        DisableMouseCapture,
        LeaveAlternateScreen,
        Show
    );
}

impl Drop for App {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::Release);
        self.next_cancel.store(true, Ordering::Release);
        self.download_cancel.store(true, Ordering::Release);
        let _ = self.audio.send(AudioCommand::Shutdown);
        if let Some(handle) = self.audio_thread.take() {
            let _ = handle.join();
        }
        for handle in self.prepare_threads.drain(..) {
            let _ = handle.join();
        }
    }
}

impl App {
    fn new(store: LibraryStore, cache: PathBuf, no_auth: bool, graphics: cover::Graphics) -> Self {
        let page = Page::new("Recent · played on this device", store.recent_items());
        let (audio, audio_events, audio_thread) = audio_output::start_joinable();
        let (tx, rx) = mpsc::channel();
        let mut app = Self {
            store,
            cache,
            page,
            covers: cover::Covers::new(graphics),
            mouse: mouse::Mouse::default(),
            history: Vec::new(),
            focus: Focus::Browse,
            panel: None,
            panel_scroll: 0,
            nav: ListState::default().with_selected(Some(8)),
            queue: Queue::default(),
            queue_list: ListState::default(),
            input: None,
            search_draft: (String::new(), false),
            overlay: None,
            status: "Ctrl+f Search · :login Account · ? Help".into(),
            account: "Public / signed out".into(),
            api: None,
            runtime: None,
            auth_busy: false,
            auth_ready: false,
            auth_problem: None,
            auth_generation: 0,
            request: 0,
            pending_page: None,
            generation: 0,
            prefetch: 0,
            ready: None,
            preparing: false,
            loaded: false,
            snapshot: json!({}),
            source: Value::Null,
            lyrics: String::new(),
            station: None,
            station_serial: 0,
            cancel: Arc::new(AtomicBool::new(false)),
            next_cancel: Arc::new(AtomicBool::new(false)),
            download_cancel: Arc::new(AtomicBool::new(false)),
            downloading: false,
            audio,
            audio_events,
            audio_thread: Some(audio_thread),
            mpris: mpris::start().ok(),
            last_published: None,
            tx,
            rx,
            jobs: 0,
            prepare_threads: Vec::new(),
            dirty: false,
            quit: false,
        };
        if !no_auth && let Err(error) = app.connect(None) {
            app.status = error.to_string();
        }
        app
    }

    fn job(&mut self, prepare: bool, work: impl FnOnce() -> Job + Send + 'static) -> Result<()> {
        if self.jobs >= 8 {
            bail!("Background jobs are busy; please retry shortly");
        }
        let tx = self.tx.clone();
        let handle = thread::Builder::new()
            .name("siora-work".into())
            .spawn(move || {
                let _ = tx.send(work());
            })?;
        self.jobs += 1;
        if prepare {
            self.prepare_threads.push(handle);
        }
        Ok(())
    }

    fn auth(&self) -> Result<Endpoints> {
        if !self.auth_ready {
            bail!(
                "{}",
                self.auth_problem.as_deref().unwrap_or(
                    "認証ヘルパーが未接続です。:connect または :login を実行してください。"
                )
            );
        }
        let runtime = self.runtime.as_ref().context(
            "Authentication helper unavailable; start Siora without --no-auth after importing the Apple Music runtime",
        )?;
        Ok(runtime.endpoints().clone())
    }

    fn api(&self) -> Result<AppleMusic> {
        self.api
            .clone()
            .context("Sign in with :login or reconnect with :connect")
    }

    fn save(&mut self) -> Result<()> {
        self.dirty = true;
        self.store.save()?;
        self.dirty = false;
        Ok(())
    }

    fn auth_failed(&mut self, message: String, show: bool) {
        self.auth_generation += 1;
        self.auth_busy = false;
        self.auth_ready = false;
        self.api = None;
        self.auth_problem = Some(message.clone());
        self.account = "Auth unavailable".into();
        self.status = message.clone();
        if self.input.as_ref().is_some_and(|input| {
            matches!(
                input.kind,
                InputKind::Username | InputKind::Password(_) | InputKind::Code
            )
        }) {
            self.input = None;
        }
        if show {
            self.panel_scroll = 0;
            self.overlay = Some(Overlay::Text(
                "Apple Musicの認証セットアップ".into(),
                message,
            ));
        }
    }

    fn connect(&mut self, prompt: Option<LoginPrompt>) -> Result<()> {
        if self.auth_busy {
            bail!("Authentication is already in progress");
        }
        let restart = self
            .runtime
            .as_mut()
            .is_none_or(|runtime| !runtime.is_running().unwrap_or(false));
        if restart {
            self.runtime = None;
            match AuthRuntime::spawn() {
                Ok(runtime) => self.runtime = Some(runtime),
                Err(error) => {
                    self.auth_failed(error.to_string(), prompt.is_some());
                    return Err(error);
                }
            }
        }
        let auth = self
            .runtime
            .as_ref()
            .context("認証ヘルパーがありません。")?
            .endpoints()
            .clone();
        self.auth_generation += 1;
        let generation = self.auth_generation;
        self.auth_ready = false;
        let storefront = self.store.data.preferences.storefront.clone();
        self.job(false, move || {
            Job::Connected(
                generation,
                prompt,
                (|| {
                    let state = if restart {
                        auth_service::wait_ready(&auth)?
                    } else {
                        auth_service::status(&auth.http)?
                    };
                    let api = if state.authenticated {
                        Some(AppleMusic::from_wrapper(&auth.http, &storefront)?)
                    } else {
                        None
                    };
                    Ok((state, api))
                })(),
            )
        })?;
        self.auth_busy = true;
        self.account = "Connecting…".into();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::anyhow;

    fn song(id: &str, title: &str) -> MusicItem {
        MusicItem {
            id: id.into(),
            kind: "songs".into(),
            title: title.into(),
            ..Default::default()
        }
    }

    fn app(root: &std::path::Path) -> Result<App> {
        Ok(App::new(
            LibraryStore::open(root.join("state.json"))?,
            root.join("downloads"),
            true,
            cover::Graphics::text((10, 20)),
        ))
    }

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn search_enqueue_and_back_keep_playback_and_browse_state_independent() -> Result<()> {
        let root = tempfile::tempdir()?;
        let mut app = app(root.path())?;
        let album = vec![song("1", "夜に駆ける"), song("2", "群青")];
        app.page = Page::new("Album", album.clone());
        app.page.move_by(1);
        app.page.filter = "群".into();
        app.page.refresh();
        let current = app.queue.replace(album, "songs:1", "Album", false, false);
        app.show_page(Page::new("Search", vec![song("3", "アイドル")]));
        app.key(key(KeyCode::Char('E')))?;
        assert_eq!(app.page.item().unwrap().id, "3");
        assert_eq!(app.queue.current, current);
        assert_eq!(app.queue.entries[1].item.id, "3");
        app.key(key(KeyCode::Char('q')))?;
        app.key(key(KeyCode::Char('q')))?;
        app.key(key(KeyCode::Backspace))?;
        assert_eq!(app.page.item().unwrap().id, "2");
        assert_eq!(app.page.filter, "群");
        assert_eq!(app.queue.entries[1].item.id, "3");
        assert!(!root.path().join("state.json").exists());
        Ok(())
    }

    #[test]
    fn late_search_and_preparation_results_cannot_replace_newer_state() -> Result<()> {
        let root = tempfile::tempdir()?;
        let mut app = app(root.path())?;
        app.request = 10;
        app.pending_page = Some(10);
        let title = app.page.title.clone();
        app.handle_job(Job::Page(
            9,
            false,
            Ok(Page::new("stale", vec![song("1", "wrong")])),
        ))?;
        assert_eq!(app.page.title, title);
        assert_eq!(app.pending_page, Some(10));
        app.generation = 3;
        app.handle_job(Job::Prepared(
            2,
            1,
            "aac".into(),
            Err(anyhow!("stale error")),
        ))?;
        assert!(app.source.is_null());
        app.handle_job(Job::Page(10, false, Err(anyhow!("network unavailable"))))
            .unwrap_err();
        assert_eq!(app.page.title, title);
        assert_eq!(app.pending_page, None);
        Ok(())
    }

    #[test]
    fn changing_quality_during_a_download_does_not_relabel_the_file() -> Result<()> {
        let root = tempfile::tempdir()?;
        let mut app = app(root.path())?;
        app.store.data.preferences.quality = "hires".into();
        app.handle_job(Job::Download(
            song("1", "song"),
            "aac".into(),
            Ok(PreparedTrack {
                path: root.path().join("track.m4a"),
                source: json!({"codec":"aac"}),
                lyrics: None,
            }),
        ))?;
        assert_eq!(
            app.store.data.items[0].cached_quality.as_deref(),
            Some("aac")
        );
        assert_eq!(app.store.data.preferences.quality, "hires");
        Ok(())
    }

    #[test]
    fn japanese_input_enter_only_commits_filter_and_tab_only_changes_focus() -> Result<()> {
        let root = tempfile::tempdir()?;
        let mut app = app(root.path())?;
        app.page = Page::new("Songs", vec![song("1", "群青"), song("2", "夜に駆ける")]);
        app.key(key(KeyCode::Char('/')))?;
        app.key(key(KeyCode::Char('群')))?;
        app.key(key(KeyCode::Enter))?;
        assert!(app.queue.entries.is_empty());
        assert_eq!(app.page.item().unwrap().id, "1");
        app.key(key(KeyCode::Tab))?;
        assert!(app.focus == Focus::Navigation);
        assert!(app.queue.entries.is_empty());
        Ok(())
    }

    #[test]
    fn login_prompts_require_a_ready_helper_and_ignore_old_auth_results() -> Result<()> {
        let root = tempfile::tempdir()?;
        let mut app = app(root.path())?;
        app.auth_generation = 1;
        let ready = auth_service::ServiceStatus {
            running: true,
            ..Default::default()
        };
        app.handle_job(Job::Connected(
            1,
            Some(LoginPrompt::Account),
            Ok((ready, None)),
        ))?;
        assert!(app.auth_ready);
        assert!(matches!(
            app.input.as_ref().map(|input| &input.kind),
            Some(InputKind::Username)
        ));
        assert!(app.api.is_none());
        app.input = Some(Input::new(
            InputKind::Password("test".into()),
            "SECRET".into(),
        ));
        app.auth_failed("alac-room-auth-import is required".into(), true);
        assert!(app.input.is_none());
        assert!(
            app.auth()
                .unwrap_err()
                .to_string()
                .contains("alac-room-auth-import")
        );
        app.handle_job(Job::Connected(
            1,
            Some(LoginPrompt::Account),
            Ok((ready, None)),
        ))?;
        app.handle_job(Job::Login(1, Ok(LoginState::Authenticated)))?;
        assert!(!app.auth_ready);
        assert!(app.input.is_none());
        assert!(!app.status.contains("SECRET"));
        Ok(())
    }

    #[test]
    #[ignore = "requires ffmpeg and mpv"]
    fn music_video_playback_never_enables_a_video_window() -> Result<()> {
        let root = tempfile::tempdir()?;
        let path = root.path().join("video.mp4");
        let status = std::process::Command::new("ffmpeg")
            .args([
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "color=size=64x64:rate=1",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440",
                "-t",
                "3",
                "-c:v",
                "mpeg4",
                "-c:a",
                "aac",
            ])
            .arg(&path)
            .status()?;
        assert!(status.success());
        let mut mpv = player::Mpv::new("null", false)?;
        mpv.load(&path, true)?;
        let video = mpv.command(json!(["get_property", "vid"]))?;
        let window = mpv.command(json!(["get_property", "force-window"]))?;
        assert!(video == json!("no") || video == json!(false));
        assert!(window == json!("no") || window == json!(false));
        Ok(())
    }
}
