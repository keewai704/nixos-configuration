mod authentication;
pub mod browse;
mod commands;
mod controls;
mod cover;
mod events;
mod input;
mod item_actions;
mod mouse;
mod navigation;
mod playback;
mod queue;
mod render;
mod settings;
mod terminal;

use input::{Input, InputKind};
pub use terminal::run;

use anyhow::{Context, Result, bail};
use browse::{Page, api_page, playable};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use queue::Queue;
use ratatui::widgets::ListState;
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

enum ShutdownBehavior {
    Detach,
    Wait,
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
    download_directory: PathBuf,
    page: Page,
    covers: cover::Covers,
    mouse: mouse::Mouse,
    history: Vec<Page>,
    focus: Focus,
    panel: Option<Panel>,
    panel_scroll: u16,
    navigation_list: ListState,
    queue: Queue,
    queue_list: ListState,
    input: Option<Input>,
    search_draft: (String, bool),
    overlay: Option<Overlay>,
    status: String,
    account: String,
    api: Option<AppleMusic>,
    auth_runtime: Option<AuthRuntime>,
    auth_busy: bool,
    auth_ready: bool,
    auth_problem: Option<String>,
    auth_generation: u64,
    page_generation: u64,
    pending_page: Option<u64>,
    playback_generation: u64,
    prefetch_generation: u64,
    prefetched_track: Option<Ready>,
    preparing: bool,
    loaded: bool,
    playback_snapshot: Value,
    playback_source: Value,
    lyrics: String,
    station: Option<Station>,
    station_serial: u64,
    playback_cancel: Arc<AtomicBool>,
    prefetch_cancel: Arc<AtomicBool>,
    download_cancel: Arc<AtomicBool>,
    downloading: bool,
    audio_commands: Sender<AudioCommand>,
    audio_events: Receiver<AudioEvent>,
    audio_thread: Option<JoinHandle<()>>,
    mpris: Option<(Sender<mpris::Metadata>, Receiver<MediaCommand>)>,
    last_published: Option<mpris::Metadata>,
    job_sender: Sender<Job>,
    job_receiver: Receiver<Job>,
    pending_jobs: usize,
    shutdown_threads: Vec<JoinHandle<()>>,
    library_dirty: bool,
    quit: bool,
}

impl Drop for App {
    fn drop(&mut self) {
        self.playback_cancel.store(true, Ordering::Release);
        self.prefetch_cancel.store(true, Ordering::Release);
        self.download_cancel.store(true, Ordering::Release);
        let _ = self.audio_commands.send(AudioCommand::Shutdown);
        if let Some(handle) = self.audio_thread.take() {
            let _ = handle.join();
        }
        for handle in self.shutdown_threads.drain(..) {
            let _ = handle.join();
        }
    }
}

impl App {
    fn new(
        store: LibraryStore,
        download_directory: PathBuf,
        no_auth: bool,
        graphics: cover::Graphics,
    ) -> Self {
        let page = Page::new("Recent · played on this device", store.recent_items());
        let (audio_commands, audio_events, audio_thread) = audio_output::start_joinable();
        let (job_sender, job_receiver) = mpsc::channel();
        let mut app = Self {
            store,
            download_directory,
            page,
            covers: cover::Covers::new(graphics),
            mouse: mouse::Mouse::default(),
            history: Vec::new(),
            focus: Focus::Browse,
            panel: None,
            panel_scroll: 0,
            navigation_list: ListState::default().with_selected(Some(8)),
            queue: Queue::default(),
            queue_list: ListState::default(),
            input: None,
            search_draft: (String::new(), false),
            overlay: None,
            status: "Ctrl+f Search · :login Account · ? Help".into(),
            account: "Public / signed out".into(),
            api: None,
            auth_runtime: None,
            auth_busy: false,
            auth_ready: false,
            auth_problem: None,
            auth_generation: 0,
            page_generation: 0,
            pending_page: None,
            playback_generation: 0,
            prefetch_generation: 0,
            prefetched_track: None,
            preparing: false,
            loaded: false,
            playback_snapshot: json!({}),
            playback_source: Value::Null,
            lyrics: String::new(),
            station: None,
            station_serial: 0,
            playback_cancel: Arc::new(AtomicBool::new(false)),
            prefetch_cancel: Arc::new(AtomicBool::new(false)),
            download_cancel: Arc::new(AtomicBool::new(false)),
            downloading: false,
            audio_commands,
            audio_events,
            audio_thread: Some(audio_thread),
            mpris: mpris::start().ok(),
            last_published: None,
            job_sender,
            job_receiver,
            pending_jobs: 0,
            shutdown_threads: Vec::new(),
            library_dirty: false,
            quit: false,
        };
        if !no_auth && let Err(error) = app.connect_authentication(None) {
            app.status = error.to_string();
        }
        app
    }

    fn spawn_job(
        &mut self,
        shutdown: ShutdownBehavior,
        work: impl FnOnce() -> Job + Send + 'static,
    ) -> Result<()> {
        if self.pending_jobs >= 8 {
            bail!("Background jobs are busy; please retry shortly");
        }
        let job_sender = self.job_sender.clone();
        let handle = thread::Builder::new()
            .name("siora-work".into())
            .spawn(move || {
                let _ = job_sender.send(work());
            })?;
        self.pending_jobs += 1;
        if matches!(shutdown, ShutdownBehavior::Wait) {
            self.shutdown_threads.push(handle);
        }
        Ok(())
    }

    fn save(&mut self) -> Result<()> {
        self.library_dirty = true;
        self.store.save()?;
        self.library_dirty = false;
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
        app.page_generation = 10;
        app.pending_page = Some(10);
        let title = app.page.title.clone();
        app.handle_job(Job::Page(
            9,
            false,
            Ok(Page::new("stale", vec![song("1", "wrong")])),
        ))?;
        assert_eq!(app.page.title, title);
        assert_eq!(app.pending_page, Some(10));
        app.playback_generation = 3;
        app.handle_job(Job::Prepared(
            2,
            1,
            "aac".into(),
            Err(anyhow!("stale error")),
        ))?;
        assert!(app.playback_source.is_null());
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
        app.handle_auth_failure("alac-room-auth-import is required".into(), true);
        assert!(app.input.is_none());
        assert!(
            app.authentication_endpoints()
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
