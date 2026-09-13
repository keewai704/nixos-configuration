pub mod browse;
mod controls;
mod queue;
mod render;

use anyhow::{Context, Result, anyhow, bail};
use browse::{Page, api_page, playable, public_page};
use crossterm::{
    cursor::{Hide, Show},
    event::{
        self, DisableBracketedPaste, EnableBracketedPaste, Event as TerminalEvent, KeyCode,
        KeyEvent, KeyEventKind, KeyModifiers,
    },
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use queue::Queue;
use ratatui::{Terminal, backend::CrosstermBackend, widgets::ListState};
use serde_json::{Value, json};
use siora::{
    apple_music::{self, AppleMusic, LoginState},
    audio_output::{self, AudioCommand, AudioEvent},
    auth_service::{self, AuthRuntime, Endpoints},
    library::{LibraryStore, Preferences},
    model::MusicItem,
    mpris::{self, MediaCommand},
    player::{self, PreparedTrack},
};
use std::{
    io,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, Sender},
    },
    thread::{self, JoinHandle},
    time::Duration,
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
    Connected(Result<AppleMusic>),
    Login(Result<LoginState>),
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
        Hide
    )?;
    let mut terminal = Terminal::new(CrosstermBackend::new(io::stdout()))?;
    let mut app = App::new(store, cache, no_auth);
    if let Some(url) = url {
        app.open_url(url)?;
    }
    while !app.quit && !stop.load(Ordering::Relaxed) {
        if let Err(error) = app.poll() {
            app.status = format!("{error:#}");
        }
        terminal.draw(|frame| render::draw(frame, &mut app))?;
        if event::poll(Duration::from_millis(60))? {
            let result = match event::read()? {
                TerminalEvent::Key(key) if key.kind != KeyEventKind::Release => app.key(key),
                TerminalEvent::Paste(value) => {
                    if let Some(input) = &mut app.input {
                        input.insert(&value);
                    }
                    app.preview_filter();
                    Ok(())
                }
                _ => Ok(()),
            };
            if let Err(error) = result {
                app.status = format!("{error:#}");
            }
        }
    }
    if app.dirty {
        app.store.save()?;
    }
    Ok(())
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
        DisableBracketedPaste,
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
    fn new(store: LibraryStore, cache: PathBuf, no_auth: bool) -> Self {
        let page = Page::new("Recent · played on this device", store.recent_items());
        let (audio, audio_events, audio_thread) = audio_output::start_joinable();
        let (tx, rx) = mpsc::channel();
        let mut app = Self {
            store,
            cache,
            page,
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
        if !no_auth {
            match AuthRuntime::spawn() {
                Ok(runtime) => {
                    app.runtime = Some(runtime);
                    if let Err(error) = app.connect(true) {
                        app.status = error.to_string();
                    }
                }
                Err(error) => app.status = error.to_string(),
            }
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
        self.runtime.as_ref().map(|runtime| runtime.endpoints().clone()).context("Authentication helper unavailable; start Siora without --no-auth after importing the Apple Music runtime")
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

    fn connect(&mut self, wait: bool) -> Result<()> {
        if self.auth_busy {
            bail!("Authentication is already in progress");
        }
        let auth = self.auth()?;
        let storefront = self.store.data.preferences.storefront.clone();
        self.job(false, move || {
            Job::Connected((|| {
                let state = if wait {
                    auth_service::wait_ready(&auth)?
                } else {
                    auth_service::status(&auth.http)?
                };
                if state.needs_code {
                    bail!("Two-factor code required; use :code");
                }
                if !state.authenticated {
                    bail!("Sign in with :login");
                }
                AppleMusic::from_wrapper(&auth.http, &storefront)
            })())
        })?;
        self.auth_busy = true;
        self.account = "Connecting…".into();
        Ok(())
    }

    fn fetch(
        &mut self,
        append: bool,
        work: impl FnOnce() -> Result<Page> + Send + 'static,
    ) -> Result<()> {
        let request = self.request + 1;
        self.job(false, move || Job::Page(request, append, work()))?;
        self.request = request;
        self.pending_page = Some(request);
        self.status = "Loading… You can keep browsing or start another search.".into();
        Ok(())
    }

    fn show_page(&mut self, page: Page) {
        if let Some(search) = &page.search {
            self.search_draft = search.clone();
        }
        self.request += 1;
        self.pending_page = None;
        self.history.push(std::mem::replace(&mut self.page, page));
        if self.history.len() > 50 {
            self.history.remove(0);
        }
        self.focus = Focus::Browse;
    }

    fn back(&mut self) {
        self.request += 1;
        self.pending_page = None;
        if let Some(page) = self.history.pop() {
            self.page = page;
        }
        self.focus = Focus::Browse;
    }

    fn navigate(&mut self, index: usize) -> Result<()> {
        let (title, section) = browse::NAV[index];
        self.nav.select(Some(index));
        match section {
            "recent" | "favorites" | "downloads" => {
                let items = if section == "recent" {
                    self.store.recent_items()
                } else {
                    self.store
                        .data
                        .items
                        .iter()
                        .filter(|item| {
                            if section == "favorites" {
                                self.store.data.favorites.contains(&item.key())
                            } else {
                                item.local_path.as_ref().is_some_and(|path| path.is_file())
                            }
                        })
                        .cloned()
                        .collect()
                };
                self.show_page(Page::new(format!("{title} · on this device"), items));
                self.status.clear();
                Ok(())
            }
            "new" | "radio" => {
                let storefront = self.store.data.preferences.storefront.clone();
                self.fetch(false, move || public_page(section, &storefront))
            }
            _ => {
                let api = self.api()?;
                self.fetch(false, move || {
                    api.browse(section).map(|value| api_page(title, value))
                })
            }
        }
    }

    fn search(&mut self, term: String, library: bool) -> Result<()> {
        self.search_draft = (term.clone(), library);
        if term.trim().is_empty() {
            bail!("Enter a search term");
        }
        let api = self.api.clone();
        if library && api.is_none() {
            bail!("My Library search requires :login");
        }
        let storefront = self.store.data.preferences.storefront.clone();
        self.fetch(false, move || {
            let mut page = if let Some(api) = api {
                api_page(format!("Search: {term}"), api.search(&term, library)?)
            } else {
                let mut url =
                    reqwest::Url::parse(&format!("https://music.apple.com/{storefront}/search"))?;
                url.query_pairs_mut().append_pair("term", &term);
                public_page(url.as_str(), &storefront)?
            };
            page.title = format!(
                "Search · {} · {term}",
                if library { "My Library" } else { "Apple Music" }
            );
            page.search = Some((term, library));
            Ok(page)
        })
    }

    fn open_url(&mut self, url: String) -> Result<()> {
        let url = browse::validate_url(&url)?;
        let storefront = self.store.data.preferences.storefront.clone();
        self.fetch(false, move || public_page(&url, &storefront))
    }

    fn open_item(&mut self, item: MusicItem) -> Result<()> {
        if playable(&item) {
            return self.play_context(item);
        }
        if !item.kind.starts_with("library-")
            && let Some(url) = &item.url
        {
            return self.open_url(url.clone());
        }
        let api = self.api()?;
        self.fetch(false, move || {
            let relationship = if item.kind.contains("artists") {
                "albums"
            } else {
                "tracks"
            };
            let mut page = api_page(
                &item.title,
                api.related(
                    &item.kind,
                    &item.id,
                    relationship,
                    item.kind.starts_with("library-"),
                )?,
            );
            page.album = item.kind.contains("albums");
            Ok(page)
        })
    }

    fn load_more(&mut self) -> Result<()> {
        if self.pending_page.is_some() {
            bail!("A page is already loading");
        }
        let next = self
            .page
            .next_url()
            .context("No next page for this category; use t to choose a search result type")?;
        let api = self.api()?;
        let kind = self.page.kind;
        let search = self.page.search.clone();
        self.fetch(true, move || {
            api.next_page(&next).map(|value| {
                let mut page = api_page("", value);
                page.kind = kind;
                page.search = search;
                page
            })
        })
    }

    fn selected_item(&self) -> Result<MusicItem> {
        if self.focus == Focus::Panel && self.panel == Some(Panel::Queue) {
            self.queue.selected().map(|entry| entry.item.clone())
        } else {
            self.page.item().cloned()
        }
        .context("Select an item first")
    }

    fn play_context(&mut self, item: MusicItem) -> Result<()> {
        let items = if self.page.items.iter().any(|row| row.key() == item.key()) {
            let mut items = self.page.items.clone();
            match self.page.sort {
                1 => items.sort_by_cached_key(|item| item.title.to_lowercase()),
                2 => items.sort_by_cached_key(|item| item.artist.to_lowercase()),
                3 => items.sort_by_cached_key(|item| item.album.to_lowercase()),
                _ => {}
            }
            items
        } else {
            vec![item.clone()]
        };
        let origin = self.page.title.clone();
        if !self.queue.manual_upcoming().is_empty() {
            self.overlay = Some(Overlay::Replace(
                items,
                item.key(),
                origin,
                ListState::default().with_selected(Some(0)),
            ));
            return Ok(());
        }
        self.replace_queue(items, item.key(), origin, false)
    }

    fn replace_queue(
        &mut self,
        items: Vec<MusicItem>,
        key: String,
        origin: String,
        keep: bool,
    ) -> Result<()> {
        self.station = None;
        let id = self
            .queue
            .replace(
                items,
                &key,
                &origin,
                keep,
                self.store.data.preferences.shuffle,
            )
            .context("This item cannot be played")?;
        self.play(id)
    }

    fn cancel_prefetch(&mut self) {
        self.next_cancel.store(true, Ordering::Release);
        self.next_cancel = Arc::new(AtomicBool::new(false));
        self.prefetch += 1;
        self.ready = None;
        let _ = self.audio.send(AudioCommand::ClearNext(self.generation));
    }

    fn play(&mut self, id: u64) -> Result<()> {
        let entry = self
            .queue
            .entries
            .iter()
            .find(|entry| entry.id == id)
            .cloned()
            .context("Queue entry no longer exists")?;
        if entry.item.kind == "stations" && !siora::radio::is_public_station(&entry.item.id) {
            return self.start_station(entry.item);
        }
        self.cancel.store(true, Ordering::Release);
        self.cancel = Arc::new(AtomicBool::new(false));
        self.cancel_prefetch();
        self.generation += 1;
        let generation = self.generation;
        self.audio.send(AudioCommand::Stop(generation))?;
        self.queue.current = Some(id);
        self.preparing = false;
        self.loaded = false;
        self.snapshot = json!({});
        self.source = Value::Null;
        self.lyrics.clear();
        if entry.item.kind == "stations" {
            self.job(false, move || {
                Job::Radio(generation, siora::radio::station_stream_url(&entry.item.id))
            })?;
        } else {
            let auth = self.auth()?;
            let item = self.cached(entry.item);
            let prefs = self.store.data.preferences.clone();
            let cache = self.cache.clone();
            let cancel = self.cancel.clone();
            self.job(true, move || {
                Job::Prepared(
                    generation,
                    id,
                    prefs.quality.clone(),
                    player::prepare(&item, &prefs, &cache, &cancel, &auth),
                )
            })?;
        }
        self.preparing = true;
        self.status = "Preparing audio…".into();
        Ok(())
    }

    fn cached(&self, mut item: MusicItem) -> MusicItem {
        if let Some(cached) = self.store.data.items.iter().find(|cached| {
            cached.key() == item.key()
                && cached.cached_quality.as_deref() == Some(&self.store.data.preferences.quality)
        }) {
            item.local_path = cached.local_path.clone().filter(|path| path.is_file());
            item.cached_quality = cached.cached_quality.clone();
        } else {
            item.local_path = None;
            item.cached_quality = None;
        }
        item
    }

    fn prepared(&mut self, id: u64, quality: &str, track: &PreparedTrack) -> Result<()> {
        if let Some(entry) = self.queue.entries.iter_mut().find(|entry| entry.id == id) {
            entry.item.local_path = Some(track.path.clone());
            entry.item.cached_quality = Some(quality.into());
            self.store.upsert(entry.item.clone());
        }
        self.save()
    }

    fn schedule_next(&mut self) -> Result<()> {
        self.cancel_prefetch();
        if self.preparing || !self.loaded || self.is_radio() {
            return Ok(());
        }
        if self
            .station
            .as_ref()
            .is_some_and(|station| !station.busy && !station.failed)
            && self
                .queue
                .entries
                .len()
                .saturating_sub(self.queue.index(self.queue.current).unwrap_or(0) + 1)
                <= 2
        {
            self.fetch_station(false)?;
        }
        let Some(id) = self.queue.next(&self.store.data.preferences.repeat, true) else {
            return Ok(());
        };
        let item = self
            .queue
            .entries
            .iter()
            .find(|entry| entry.id == id)
            .map(|entry| entry.item.clone())
            .context("Next track missing")?;
        if item.kind == "stations" {
            return Ok(());
        }
        let item = self.cached(item);
        let auth = self.auth()?;
        let (generation, serial) = (self.generation, self.prefetch);
        let (prefs, cache, cancel) = (
            self.store.data.preferences.clone(),
            self.cache.clone(),
            self.next_cancel.clone(),
        );
        self.job(true, move || {
            Job::Prefetched(
                generation,
                serial,
                id,
                prefs.quality.clone(),
                player::prepare(&item, &prefs, &cache, &cancel, &auth),
            )
        })
    }

    fn is_radio(&self) -> bool {
        self.queue
            .current()
            .is_some_and(|entry| entry.item.kind == "stations")
    }

    fn stop(&mut self) {
        self.cancel.store(true, Ordering::Release);
        self.cancel_prefetch();
        self.generation += 1;
        let _ = self.audio.send(AudioCommand::Stop(self.generation));
        self.loaded = false;
        self.preparing = false;
        self.queue.current = None;
        self.station = None;
        self.snapshot = json!({});
        self.source = Value::Null;
        self.lyrics.clear();
        self.status = "Stopped".into();
    }

    fn next(&mut self, automatic: bool) -> Result<()> {
        if automatic && self.is_radio() {
            return Ok(());
        }
        if let Some(id) = self
            .queue
            .next(&self.store.data.preferences.repeat, automatic)
        {
            return self.play(id);
        }
        if let Some(station) = &mut self.station {
            station.waiting = true;
            station.failed = false;
            self.fetch_station(false)?;
        } else {
            self.stop();
        }
        Ok(())
    }

    fn previous(&mut self) -> Result<()> {
        if !self.is_radio() && self.snapshot["position"].as_f64().unwrap_or(0.) > 3. {
            self.command(json!(["seek", 0, "absolute"]));
            self.schedule_next()
        } else if let Some(index) = self.queue.index(self.queue.current) {
            self.play(self.queue.entries[index.saturating_sub(1)].id)
        } else {
            Ok(())
        }
    }

    fn command(&self, command: Value) {
        let _ = self.audio.send(AudioCommand::Command(command));
    }

    fn pause(&mut self) -> Result<()> {
        if self.loaded {
            self.command(json!(["cycle", "pause"]));
            Ok(())
        } else if self.preparing {
            self.stop();
            Ok(())
        } else if let Some(id) = self.queue.current {
            self.play(id)
        } else if let Some(id) = self.queue.entries.first().map(|entry| entry.id) {
            self.play(id)
        } else {
            self.open_item(self.selected_item()?)
        }
    }

    fn start_station(&mut self, item: MusicItem) -> Result<()> {
        let api = self.api()?;
        if self.station.as_ref().is_some_and(|station| station.busy) {
            bail!("Station is loading");
        }
        self.station_serial += 1;
        let serial = self.station_serial;
        let seed = item.clone();
        self.job(false, move || {
            Job::Station(
                serial,
                true,
                (|| {
                    let station = if item.kind == "stations" {
                        item
                    } else {
                        api.item_station(&item)?
                    };
                    let tracks = api.station_tracks(&station.id)?;
                    let mut result = vec![station];
                    result.extend(tracks);
                    Ok(result)
                })(),
            )
        })?;
        self.station = Some(Station {
            serial,
            item: seed,
            busy: true,
            waiting: false,
            failed: false,
        });
        self.status = "Loading station…".into();
        Ok(())
    }

    fn fetch_station(&mut self, initial: bool) -> Result<()> {
        let api = self.api()?;
        let Some(station) = &self.station else {
            return Ok(());
        };
        if station.busy {
            return Ok(());
        }
        let (serial, id) = (station.serial, station.item.id.clone());
        self.job(false, move || {
            Job::Station(serial, initial, api.station_tracks(&id))
        })?;
        if let Some(station) = &mut self.station {
            station.busy = true;
        }
        Ok(())
    }

    fn volume(&mut self, value: f64) -> Result<()> {
        if !value.is_finite() {
            bail!("Volume must be finite");
        }
        self.store.data.preferences.volume = value.clamp(0., 100.);
        if self.loaded {
            self.command(json!([
                "set_property",
                "volume",
                self.store.data.preferences.volume
            ]));
        }
        self.save()
    }

    fn poll(&mut self) -> Result<()> {
        self.prepare_threads.retain(|handle| !handle.is_finished());
        while let Ok(job) = self.rx.try_recv() {
            self.jobs = self.jobs.saturating_sub(1);
            if let Err(error) = self.handle_job(job) {
                self.status = format!("{error:#}");
            }
        }
        while let Ok(event) = self.audio_events.try_recv() {
            let result = match event {
                AudioEvent::Loaded(id, result) if id == self.generation => {
                    self.preparing = false;
                    match result {
                        Ok(()) => {
                            self.loaded = true;
                            self.status = "Playing".into();
                            if let Some(entry) = self.queue.current() {
                                self.store.upsert(entry.item.clone());
                                self.store.record_play(&entry.item.key())?;
                                self.save()?;
                            }
                            self.schedule_next()
                        }
                        Err(error) => {
                            self.loaded = false;
                            Err(error)
                        }
                    }
                }
                AudioEvent::Snapshot(id, value) if id == self.generation => {
                    self.snapshot = value;
                    if self.loaded && self.snapshot["eof_reached"] == true && self.ready.is_none() {
                        self.loaded = false;
                        self.next(true)
                    } else {
                        Ok(())
                    }
                }
                AudioEvent::Transition(id, path) if id == self.generation => {
                    if let Some(ready) = self.ready.take().filter(|ready| ready.track.path == path)
                    {
                        self.queue.current = Some(ready.id);
                        self.source = ready.track.source;
                        self.lyrics = ready.track.lyrics.unwrap_or_default();
                        if let Some(entry) = self.queue.current() {
                            self.store.record_play(&entry.item.key())?;
                        }
                        self.save()?;
                        self.schedule_next()
                    } else {
                        Ok(())
                    }
                }
                AudioEvent::Error(id, error) if id == self.generation => {
                    self.ready = None;
                    Err(anyhow!(error))
                }
                _ => Ok(()),
            };
            if let Err(error) = result {
                self.status = format!("{error:#}");
            }
        }
        loop {
            let command = self.mpris.as_ref().and_then(|(_, rx)| rx.try_recv().ok());
            let Some(command) = command else {
                break;
            };
            if let Err(error) = self.media_command(command) {
                self.status = error.to_string();
            }
        }
        self.publish();
        Ok(())
    }

    fn handle_job(&mut self, job: Job) -> Result<()> {
        match job {
            Job::Page(request, append, result) if request == self.request => {
                self.pending_page = None;
                let page = result?;
                if append {
                    self.page.append(page);
                } else {
                    self.show_page(page);
                }
                self.status = if self.page.items.is_empty() {
                    "No results".into()
                } else {
                    format!(
                        "{} items loaded · / filters only loaded items{}",
                        self.page.items.len(),
                        if self.page.next_url().is_some() {
                            " · m loads more"
                        } else {
                            ""
                        }
                    )
                };
            }
            Job::Connected(result) => {
                self.auth_busy = false;
                match result {
                    Ok(api) => {
                        self.api = Some(api);
                        self.account = "Connected".into();
                        self.status = "Apple Music connected".into();
                    }
                    Err(error) => {
                        self.api = None;
                        self.account = "Signed out / unavailable".into();
                        return Err(error);
                    }
                }
            }
            Job::Login(result) => {
                self.auth_busy = false;
                let state = match result {
                    Ok(state) => state,
                    Err(error) => {
                        self.account = "Sign-in failed".into();
                        return Err(error);
                    }
                };
                match state {
                    LoginState::Authenticated => self.connect(false)?,
                    LoginState::TwoFactorRequired => {
                        self.account = "Two-factor code required".into();
                        self.input = Some(Input::new(InputKind::Code, String::new()));
                    }
                }
            }
            Job::Prepared(generation, id, quality, result)
                if generation == self.generation && self.queue.current == Some(id) =>
            {
                self.preparing = false;
                let track = result?;
                self.prepared(id, &quality, &track)?;
                self.source = track.source;
                self.lyrics = track.lyrics.unwrap_or_default();
                self.audio.send(AudioCommand::Load(
                    generation,
                    track.path,
                    false,
                    self.store.data.preferences.clone(),
                ))?;
            }
            Job::Prefetched(generation, serial, id, quality, result)
                if generation == self.generation && serial == self.prefetch =>
            {
                let track = result?;
                self.prepared(id, &quality, &track)?;
                let prefs = self.store.data.preferences.clone();
                self.audio.send(AudioCommand::Next(
                    generation,
                    track.path.clone(),
                    false,
                    prefs.clone(),
                    prefs.crossfade_seconds,
                ))?;
                self.ready = Some(Ready { id, track });
            }
            Job::Radio(generation, result) if generation == self.generation => {
                self.preparing = false;
                let url = result?;
                self.source = json!({"live": true});
                self.audio.send(AudioCommand::Radio(
                    generation,
                    url,
                    self.store.data.preferences.clone(),
                ))?;
            }
            Job::Station(serial, initial, result)
                if self
                    .station
                    .as_ref()
                    .is_some_and(|station| station.serial == serial) =>
            {
                let station = self.station.as_mut().unwrap();
                station.busy = false;
                let mut items = match result {
                    Ok(items) if !items.is_empty() => items,
                    Ok(_) => {
                        station.failed = true;
                        bail!("Station returned no tracks; n retries");
                    }
                    Err(error) => {
                        station.failed = true;
                        return Err(error);
                    }
                };
                if initial {
                    station.item = items.remove(0);
                    if items.is_empty() {
                        station.failed = true;
                        bail!("Station returned no tracks; n retries");
                    }
                    let origin = station.item.title.clone();
                    let first = items[0].key();
                    let id = self
                        .queue
                        .replace(items, &first, &origin, true, false)
                        .context("Station returned no playable tracks")?;
                    self.play(id)?;
                } else {
                    let origin = station.item.title.clone();
                    let waiting = station.waiting;
                    station.waiting = false;
                    self.queue.append_station(items, &origin);
                    if waiting {
                        self.next(false)?;
                    } else {
                        self.schedule_next()?;
                    }
                }
            }
            Job::Mutation(result) => self.status = result?,
            Job::Favorite(item, favorite, result) => {
                result?;
                self.store.upsert(item.clone());
                self.store.set_favorite(&item.key(), favorite)?;
                self.save()?;
                self.status = if favorite {
                    "Liked on Apple Music"
                } else {
                    "Apple Music rating cleared"
                }
                .into();
            }
            Job::Playlists(item, result) => {
                self.overlay = Some(Overlay::Playlists(item, Box::new(result?)))
            }
            Job::Download(mut item, quality, result) => {
                self.downloading = false;
                let track = result?;
                item.local_path = Some(track.path);
                item.cached_quality = Some(quality);
                self.store.upsert(item);
                self.save()?;
                self.status = "Download saved".into();
            }
            Job::Enqueue(next, result) => {
                let mut items = result?;
                if next {
                    items.reverse();
                }
                let count = items.len();
                for item in items {
                    self.queue.add(item, next);
                }
                self.status = format!("Added {count} tracks to queue");
                self.schedule_next()?;
            }
            Job::Devices(result) => {
                self.overlay = Some(Overlay::Devices(
                    result?,
                    ListState::default().with_selected(Some(0)),
                ))
            }
            _ => {}
        }
        Ok(())
    }

    fn media_command(&mut self, command: MediaCommand) -> Result<()> {
        match command {
            MediaCommand::PlayPause => self.pause()?,
            MediaCommand::Play if !self.loaded => self.pause()?,
            MediaCommand::Play => self.command(json!(["set_property", "pause", false])),
            MediaCommand::Pause if self.loaded => {
                self.command(json!(["set_property", "pause", true]))
            }
            MediaCommand::Pause => {}
            MediaCommand::Stop => self.stop(),
            MediaCommand::Next => self.next(false)?,
            MediaCommand::Previous => self.previous()?,
            MediaCommand::Seek(value) if !self.is_radio() => {
                self.command(json!(["seek", value, "relative"]));
                self.schedule_next()?;
            }
            MediaCommand::SetPosition(value) if !self.is_radio() => {
                self.command(json!(["seek", value, "absolute"]));
                self.schedule_next()?;
            }
            MediaCommand::Seek(_) | MediaCommand::SetPosition(_) => {}
            MediaCommand::Volume(value) => self.volume(value)?,
            MediaCommand::Shuffle(value) => {
                if value != self.store.data.preferences.shuffle {
                    self.store.data.preferences.shuffle = value;
                    if value {
                        self.queue.shuffle();
                    }
                    self.save()?;
                    self.schedule_next()?;
                }
            }
            MediaCommand::Repeat(value) => {
                self.store.data.preferences.repeat = match value.as_str() {
                    "Track" => "one",
                    "Playlist" => "all",
                    _ => "off",
                }
                .into();
                self.save()?;
                self.schedule_next()?;
            }
            MediaCommand::OpenUri(url) => self.open_url(url)?,
        }
        Ok(())
    }

    fn publish(&mut self) {
        if let Some((tx, _)) = &self.mpris {
            let item = self.queue.current().map(|entry| &entry.item);
            let prefs = &self.store.data.preferences;
            let metadata = mpris::Metadata {
                title: item.map(|item| item.title.clone()).unwrap_or_default(),
                artist: item.map(|item| item.artist.clone()).unwrap_or_default(),
                album: item.map(|item| item.album.clone()).unwrap_or_default(),
                duration: self.snapshot["duration"].as_f64().unwrap_or(0.),
                position: self.snapshot["position"].as_f64().unwrap_or(0.),
                paused: self.snapshot["paused"].as_bool().unwrap_or(true),
                active: self.loaded,
                volume: prefs.volume,
                shuffle: prefs.shuffle,
                repeat: match prefs.repeat.as_str() {
                    "one" => "Track",
                    "all" => "Playlist",
                    _ => "None",
                }
                .into(),
                artwork_url: None,
            };
            if self.last_published.as_ref() != Some(&metadata) {
                let _ = tx.send(metadata.clone());
                self.last_published = Some(metadata);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
