use super::*;

pub(super) const ACTIONS: &[&str] = &[
    "Play now / open",
    "Play next",
    "Add to queue",
    "Open album",
    "Open artist",
    "Like on Apple Music",
    "Clear Apple Music rating",
    "Add to Apple Music library",
    "Add to playlist",
    "Start station",
    "Download",
    "Remove download",
    "Details / link",
];

pub(super) const SETTINGS: &[&str] = &[
    "Sign in",
    "Reconnect",
    "Two-factor code",
    "Audio quality",
    "Output device",
    "Crossfade seconds",
    "Atmos passthrough",
    "Equalizer",
    "Cache limit (MB)",
    "Storefront",
];

pub(super) const COMMANDS: &[&str] = &[
    "login",
    "connect",
    "code",
    "settings",
    "devices",
    "quality aac|lossless|hires|atmos",
    "device auto|pipewire|alsa/…",
    "crossfade 0..12",
    "passthrough on|off",
    "eq off|gain1,gain2,…,gain10",
    "cache-limit 256..1048576",
    "storefront jp",
    "playlist-new NAME",
    "queue-save NAME",
    "cancel-download",
    "stop",
    "quit",
];

pub(super) const BINDINGS: &[(&str, &str)] = &[
    ("Click", "Select; buttons and menus act immediately"),
    ("Double-click", "Open / play selected row"),
    ("Right-click", "Item actions"),
    ("Middle-click", "Add row to queue"),
    ("Wheel", "Scroll pane; over volume adjusts volume"),
    ("Drag progress", "Seek (except live radio)"),
    ("Enter", "Open / play"),
    ("Space", "Play / pause"),
    ("Tab", "Next pane"),
    ("Shift+Tab", "Previous pane"),
    ("↑↓ / j k", "Move"),
    ("PgUp/PgDn", "Page through list"),
    ("Backspace", "Back (restores position)"),
    ("Ctrl+f", "Search Apple Music / My Library"),
    ("/", "Filter loaded items"),
    ("t", "Search result type"),
    ("L", "Switch search scope"),
    ("o", "Sort list"),
    ("m", "Load next page"),
    ("e", "Append to queue"),
    ("E", "Play next"),
    ("a", "Selected item actions"),
    ("A", "Current track actions"),
    ("q", "Queue"),
    ("l", "Lyrics"),
    ("i", "Selected item details"),
    ("n / p", "Next / previous track"),
    ("← →", "Seek 10 seconds (except live radio)"),
    ("+ / -", "Volume"),
    ("s", "Shuffle upcoming tracks"),
    ("r", "Repeat off / all / one"),
    ("d / Delete", "Remove selected queue entry"),
    ("J / K", "Move queue entry down / up"),
    ("u", "Undo queue edit"),
    ("g", "Select playing queue entry"),
    (",", "Settings"),
    ("?", "Help"),
    (":", "Command palette"),
    ("Esc", "Close / leave input"),
    ("Ctrl+c", "Quit"),
];

impl App {
    pub(super) fn key(&mut self, key: KeyEvent) -> Result<()> {
        if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
            self.quit = true;
            return Ok(());
        }
        if self.input.is_some() {
            return self.input_key(key);
        }
        if self.overlay.is_some() {
            return self.overlay_key(key);
        }
        if key.modifiers.contains(KeyModifiers::CONTROL) {
            if key.code == KeyCode::Char('f') {
                self.begin_search();
            }
            return Ok(());
        }
        match key.code {
            KeyCode::Char(':') => self.input = Some(Input::new(InputKind::Command, String::new())),
            KeyCode::Char('?') => {
                self.panel_scroll = 0;
                self.overlay = Some(Overlay::Help);
            }
            KeyCode::Char(',') => {
                self.overlay = Some(Overlay::Settings(
                    ListState::default().with_selected(Some(0)),
                ))
            }
            KeyCode::Tab => self.cycle_focus(false),
            KeyCode::BackTab => self.cycle_focus(true),
            KeyCode::Esc => {
                self.panel = None;
                self.focus = Focus::Browse;
            }
            KeyCode::Backspace => self.back(),
            KeyCode::Up | KeyCode::Char('k') => self.move_cursor(-1),
            KeyCode::Down | KeyCode::Char('j') => self.move_cursor(1),
            KeyCode::PageUp => self.move_cursor(-10),
            KeyCode::PageDown => self.move_cursor(10),
            KeyCode::Home => self.move_cursor(isize::MIN),
            KeyCode::End => self.move_cursor(isize::MAX),
            KeyCode::Enter => match self.focus {
                Focus::Navigation => self.navigate(self.nav.selected().unwrap_or(0))?,
                Focus::Panel if self.panel == Some(Panel::Queue) => {
                    if let Some(id) = self.queue.selected {
                        self.play(id)?;
                    }
                }
                Focus::Browse => self.open_item(self.selected_item()?)?,
                _ => {}
            },
            KeyCode::Char(' ') => self.pause()?,
            KeyCode::Char('n') => self.next(false)?,
            KeyCode::Char('p') => self.previous()?,
            KeyCode::Left | KeyCode::Right if self.loaded && !self.is_radio() => {
                self.command(json!([
                    "seek",
                    if key.code == KeyCode::Left { -10 } else { 10 },
                    "relative"
                ]));
                self.schedule_next()?;
            }
            KeyCode::Char('+') | KeyCode::Char('=') => {
                self.volume(self.store.data.preferences.volume + 5.)?
            }
            KeyCode::Char('-') => self.volume(self.store.data.preferences.volume - 5.)?,
            KeyCode::Char('q') => self.toggle_panel(Panel::Queue),
            KeyCode::Char('l') => self.toggle_panel(Panel::Lyrics),
            KeyCode::Char('i') => self.toggle_panel(Panel::Details),
            KeyCode::Char('a') => {
                let queue_id = if self.focus == Focus::Panel && self.panel == Some(Panel::Queue) {
                    self.queue.selected
                } else {
                    None
                };
                self.actions(self.selected_item()?, queue_id);
            }
            KeyCode::Char('A') => {
                let item = self
                    .queue
                    .current()
                    .context("Nothing is playing")?
                    .item
                    .clone();
                self.actions(item, self.queue.current);
            }
            KeyCode::Char('e') | KeyCode::Char('E') => {
                self.enqueue(self.selected_item()?, key.code == KeyCode::Char('E'))?
            }
            KeyCode::Char('/') => {
                self.focus = Focus::Browse;
                self.input = Some(Input::new(
                    InputKind::Filter(self.page.filter.clone()),
                    self.page.filter.clone(),
                ));
            }
            KeyCode::Char('t') if self.focus == Focus::Browse => {
                self.page.kind = (self.page.kind + 1) % browse::KINDS.len();
                self.page.refresh();
            }
            KeyCode::Char('L') => {
                if let Some((term, library)) = self.page.search.clone() {
                    self.search(term, !library)?;
                } else {
                    self.begin_search();
                }
            }
            KeyCode::Char('o') if self.focus == Focus::Browse => {
                self.page.sort = (self.page.sort + 1) % 4;
                self.page.refresh();
            }
            KeyCode::Char('m') if self.focus == Focus::Browse => self.load_more()?,
            KeyCode::Char('s') => {
                self.media_command(MediaCommand::Shuffle(!self.store.data.preferences.shuffle))?
            }
            KeyCode::Char('r') => {
                let repeat = match self.store.data.preferences.repeat.as_str() {
                    "off" => "Playlist",
                    "all" => "Track",
                    _ => "None",
                };
                self.media_command(MediaCommand::Repeat(repeat.into()))?;
            }
            code if self.focus == Focus::Panel && self.panel == Some(Panel::Queue) => {
                let changed = match code {
                    KeyCode::Char('J') => self.queue.reorder(1),
                    KeyCode::Char('K') => self.queue.reorder(-1),
                    KeyCode::Char('d') | KeyCode::Delete => self.queue.remove(),
                    KeyCode::Char('u') => self.queue.undo(),
                    KeyCode::Char('g') => {
                        self.queue.selected = self.queue.current;
                        false
                    }
                    _ => false,
                };
                if changed {
                    self.schedule_next()?;
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn cycle_focus(&mut self, reverse: bool) {
        let mut panes = vec![Focus::Browse, Focus::Navigation];
        if self.panel.is_some() {
            panes.push(Focus::Panel);
        }
        let index = panes
            .iter()
            .position(|&focus| focus == self.focus)
            .unwrap_or(0);
        self.focus = panes[(index + if reverse { panes.len() - 1 } else { 1 }) % panes.len()];
    }

    fn toggle_panel(&mut self, panel: Panel) {
        if self.panel == Some(panel) {
            self.panel = None;
            self.focus = Focus::Browse;
        } else {
            self.panel = Some(panel);
            self.focus = Focus::Panel;
            self.panel_scroll = 0;
            if panel == Panel::Queue && self.queue.selected.is_none() {
                self.queue.selected = self.queue.current;
            }
        }
    }

    fn move_cursor(&mut self, delta: isize) {
        match self.focus {
            Focus::Browse => self.page.move_by(delta),
            Focus::Navigation => {
                let index = self
                    .nav
                    .selected()
                    .unwrap_or(0)
                    .saturating_add_signed(delta)
                    .min(browse::NAV.len() - 1);
                self.nav.select(Some(index));
            }
            Focus::Panel if self.panel == Some(Panel::Queue) => self.queue.move_cursor(delta),
            Focus::Panel => {
                self.panel_scroll = (self.panel_scroll as usize)
                    .saturating_add_signed(delta)
                    .min(u16::MAX as usize) as u16
            }
        }
    }

    fn begin_search(&mut self) {
        let (term, library) = self.search_draft.clone();
        self.input = Some(Input::new(InputKind::Search(library), term));
    }

    fn actions(&mut self, item: MusicItem, queue_id: Option<u64>) {
        self.overlay = Some(Overlay::Actions(
            item,
            queue_id,
            ListState::default().with_selected(Some(0)),
        ));
    }

    fn input_key(&mut self, key: KeyEvent) -> Result<()> {
        let input = self.input.as_mut().unwrap();
        if key.code == KeyCode::Esc {
            if let InputKind::Filter(original) = &input.kind {
                self.page.filter = original.clone();
                self.page.refresh();
            }
            self.input = None;
            return Ok(());
        }
        if key.modifiers.contains(KeyModifiers::CONTROL) {
            match key.code {
                KeyCode::Char('l') => {
                    if let InputKind::Search(library) = &mut input.kind {
                        *library = !*library;
                    }
                }
                KeyCode::Char('u') => {
                    input.text.clear();
                    input.cursor = 0;
                }
                KeyCode::Char('a') => input.cursor = 0,
                KeyCode::Char('e') => input.cursor = input.text.len(),
                _ => {}
            }
        } else {
            match key.code {
                KeyCode::Enter => return self.submit_input(),
                KeyCode::Tab | KeyCode::BackTab
                    if matches!(input.kind, InputKind::Search(_) | InputKind::Filter(_)) =>
                {
                    return self.submit_input();
                }
                KeyCode::Tab | KeyCode::BackTab => {
                    self.input = None;
                    self.cycle_focus(key.code == KeyCode::BackTab);
                    return Ok(());
                }
                KeyCode::Char(ch) if !key.modifiers.contains(KeyModifiers::ALT) => {
                    input.insert(&ch.to_string())
                }
                KeyCode::Backspace => {
                    let previous = input.previous();
                    input.text.drain(previous..input.cursor);
                    input.cursor = previous;
                }
                KeyCode::Delete => {
                    let next = input.next();
                    input.text.drain(input.cursor..next);
                }
                KeyCode::Left => input.cursor = input.previous(),
                KeyCode::Right => input.cursor = input.next(),
                KeyCode::Home => input.cursor = 0,
                KeyCode::End => input.cursor = input.text.len(),
                _ => {}
            }
        }
        self.preview_filter();
        Ok(())
    }

    pub(super) fn preview_filter(&mut self) {
        if let Some(Input {
            kind: InputKind::Filter(_),
            text,
            ..
        }) = &self.input
        {
            self.page.filter = text.clone();
            self.page.refresh();
        }
    }

    fn submit_input(&mut self) -> Result<()> {
        let Input { kind, text, .. } = self.input.take().unwrap();
        match kind {
            InputKind::Search(library) => self.search(text, library)?,
            InputKind::Filter(_) => self.focus = Focus::Browse,
            InputKind::Command => self.run_command(&text)?,
            InputKind::Username => {
                if text.trim().is_empty() {
                    bail!("Enter your Apple ID");
                }
                self.input = Some(Input::new(InputKind::Password(text), String::new()));
            }
            InputKind::Password(username) => {
                if text.is_empty() {
                    bail!("Enter your password");
                }
                let auth = self.auth()?;
                let generation = self.auth_generation;
                self.job(false, move || {
                    Job::Login(
                        generation,
                        apple_music::sign_in(&auth.http, &username, &text, None),
                    )
                })?;
                self.auth_busy = true;
                self.account = "Signing in…".into();
            }
            InputKind::Code => {
                let auth = self.auth()?;
                let generation = self.auth_generation;
                self.job(false, move || {
                    Job::Login(
                        generation,
                        apple_music::sign_in(&auth.http, "", "", Some(&text)),
                    )
                })?;
                self.auth_busy = true;
            }
            InputKind::Setting(name) => self.setting(name, text.trim())?,
            InputKind::PlaylistName(queue) => self.create_playlist(text, queue)?,
        }
        Ok(())
    }

    fn overlay_key(&mut self, key: KeyEvent) -> Result<()> {
        if key.code == KeyCode::Esc || key.code == KeyCode::Backspace {
            self.overlay = None;
            return Ok(());
        }
        if key.code == KeyCode::Tab || key.code == KeyCode::BackTab {
            self.overlay = None;
            self.cycle_focus(key.code == KeyCode::BackTab);
            return Ok(());
        }
        let mut overlay = self.overlay.take().unwrap();
        let delta = match key.code {
            KeyCode::Up | KeyCode::Char('k') => -1,
            KeyCode::Down | KeyCode::Char('j') => 1,
            KeyCode::PageUp => -10,
            KeyCode::PageDown => 10,
            _ => 0,
        };
        if delta != 0 {
            match &mut overlay {
                Overlay::Actions(_, _, state) => move_list(state, ACTIONS.len(), delta),
                Overlay::Settings(state) => move_list(state, SETTINGS.len(), delta),
                Overlay::Replace(_, _, _, state) => move_list(state, 3, delta),
                Overlay::RemoveDownload(_, state) => move_list(state, 2, delta),
                Overlay::Devices(devices, state) => move_list(state, devices.len(), delta),
                Overlay::Playlists(_, page) => page.move_by(delta),
                _ => {
                    self.panel_scroll = (self.panel_scroll as usize)
                        .saturating_add_signed(delta)
                        .min(u16::MAX as usize) as u16
                }
            }
        }
        if key.code != KeyCode::Enter {
            self.overlay = Some(overlay);
            return Ok(());
        }
        match overlay {
            Overlay::Actions(item, queue_id, state) => {
                let action = state.selected().unwrap_or(0);
                if action == 0
                    && let Some(id) = queue_id
                {
                    self.play(id)?;
                } else {
                    self.item_action(item, action)?;
                }
            }
            Overlay::Settings(state) => self.open_setting(state.selected().unwrap_or(0))?,
            Overlay::Replace(items, key, origin, state) => match state.selected().unwrap_or(0) {
                0 => self.replace_queue(items, key, origin, true)?,
                1 => self.replace_queue(items, key, origin, false)?,
                _ => {}
            },
            Overlay::Playlists(item, page) => {
                let playlist = page.item().context("No playlist selected")?.clone();
                let api = self.api()?;
                self.job(false, move || {
                    Job::Mutation(
                        api.add_playlist_tracks(&playlist.id, &[(item.id, item.kind)])
                            .map(|_| "Added to playlist".into()),
                    )
                })?;
            }
            Overlay::Devices(devices, state) => {
                let name = devices
                    .get(state.selected().unwrap_or(0))
                    .and_then(|value| value["name"].as_str())
                    .context("No output selected")?;
                self.setting("device", name)?;
            }
            Overlay::RemoveDownload(item, state) if state.selected() == Some(1) => {
                self.remove_download(item)?
            }
            _ => {}
        }
        Ok(())
    }

    fn item_action(&mut self, item: MusicItem, index: usize) -> Result<()> {
        match index {
            0 => self.open_item(item)?,
            1 | 2 => self.enqueue(item, index == 1)?,
            3 | 4 => {
                let api = self.api()?;
                let relationship = if index == 3 { "albums" } else { "artists" };
                self.fetch(false, move || {
                    api.related(
                        &item.kind,
                        &item.id,
                        relationship,
                        item.kind.starts_with("library-"),
                    )
                    .map(|value| api_page(relationship, value))
                })?;
            }
            5 | 6 => {
                let api = self.api()?;
                let target = item.clone();
                self.job(false, move || {
                    Job::Favorite(
                        item,
                        index == 5,
                        api.rate(
                            &target.kind,
                            &target.id,
                            if index == 5 { Some(1) } else { None },
                        ),
                    )
                })?;
            }
            7 => {
                let api = self.api()?;
                self.job(false, move || {
                    Job::Mutation((|| {
                        let (id, kind) = api.catalog_reference(&item)?;
                        api.library_add(&kind, &id)?;
                        Ok("Added to Apple Music library".into())
                    })())
                })?;
            }
            8 => {
                if !item.is_song() && !item.kind.contains("music-videos") {
                    bail!("Select a song or music video");
                }
                let api = self.api()?;
                self.job(false, move || {
                    Job::Playlists(
                        item,
                        (|| {
                            let mut page =
                                api_page("Choose playlist", api.browse("library-playlists")?);
                            while let Some(next) = page.next.clone() {
                                if page.items.len() >= 10_000 {
                                    bail!("Playlist list exceeds 10,000 items");
                                }
                                page.append(api_page("", api.next_page(&next)?));
                            }
                            Ok(page)
                        })(),
                    )
                })?;
            }
            9 => self.start_station(item)?,
            10 => self.download(item)?,
            11 => {
                self.overlay = Some(Overlay::RemoveDownload(
                    item,
                    ListState::default().with_selected(Some(0)),
                ))
            }
            _ => {
                self.overlay = Some(Overlay::Text(
                    format!("Selected · {}", item.title),
                    render::item_details(&item),
                ))
            }
        }
        Ok(())
    }

    fn enqueue(&mut self, item: MusicItem, next: bool) -> Result<()> {
        if playable(&item) {
            self.queue.add(item, next);
            self.status = if next {
                "Added to play next"
            } else {
                "Added to end of queue"
            }
            .into();
            return self.schedule_next();
        }
        if !item.kind.contains("albums") && !item.kind.contains("playlists") {
            bail!("Open the artist and choose an album first");
        }
        let api = self.api()?;
        self.job(false, move || {
            Job::Enqueue(
                next,
                (|| {
                    let mut page = api_page(
                        "",
                        api.related(
                            &item.kind,
                            &item.id,
                            "tracks",
                            item.kind.starts_with("library-"),
                        )?,
                    );
                    while let Some(next) = page.next.clone() {
                        if page.items.len() >= 10_000 {
                            bail!("Collection exceeds 10,000 tracks");
                        }
                        page.append(api_page("", api.next_page(&next)?));
                    }
                    Ok(page.items.into_iter().filter(playable).collect())
                })(),
            )
        })
    }

    fn download(&mut self, item: MusicItem) -> Result<()> {
        if self.downloading {
            bail!("A download is already running; :cancel-download stops it");
        }
        if !playable(&item) || item.kind == "stations" {
            bail!("Only songs and music videos can be downloaded");
        }
        let auth = self.auth()?;
        let (prefs, cache) = (self.store.data.preferences.clone(), self.cache.clone());
        self.download_cancel = Arc::new(AtomicBool::new(false));
        let cancel = self.download_cancel.clone();
        self.job(true, move || {
            let result = player::prepare(&item, &prefs, &cache, &cancel, &auth);
            Job::Download(item, prefs.quality, result)
        })?;
        self.downloading = true;
        self.status = "Downloading… :cancel-download cancels".into();
        Ok(())
    }

    fn remove_download(&mut self, item: MusicItem) -> Result<()> {
        let path = self
            .store
            .data
            .items
            .iter()
            .find(|row| row.key() == item.key())
            .and_then(|row| row.local_path.clone())
            .context("No cached download for this item")?;
        if self.loaded
            || self.downloading
            || self.preparing
            || self
                .queue
                .current()
                .is_some_and(|entry| entry.item.local_path.as_ref() == Some(&path))
            || self
                .ready
                .as_ref()
                .is_some_and(|ready| ready.track.path == path)
        {
            bail!("Stop playback and pending downloads before removing this file");
        }
        self.cancel_prefetch();
        player::remove_cached_track(&self.cache, &path)?;
        for row in &mut self.store.data.items {
            if row.local_path.as_ref() == Some(&path) {
                row.local_path = None;
                row.cached_quality = None;
            }
        }
        self.save()?;
        self.status = "Cached download removed".into();
        Ok(())
    }

    pub(super) fn run_command(&mut self, text: &str) -> Result<()> {
        let (command, value) = text
            .trim()
            .split_once(char::is_whitespace)
            .unwrap_or((text.trim(), ""));
        match command {
            "quit" => self.quit = true,
            "stop" => self.stop(),
            "login" => self.connect(Some(LoginPrompt::Account))?,
            "connect" => self.connect(None)?,
            "code" => self.connect(Some(LoginPrompt::Code))?,
            "settings" => {
                self.overlay = Some(Overlay::Settings(
                    ListState::default().with_selected(Some(0)),
                ))
            }
            "devices" => self.job(false, || {
                Job::Devices(player::Mpv::new("null", false).and_then(|mut mpv| mpv.devices()))
            })?,
            "playlist-new" | "queue-save" => {
                let queue = command == "queue-save";
                if value.is_empty() {
                    self.input = Some(Input::new(InputKind::PlaylistName(queue), String::new()));
                } else {
                    self.create_playlist(value.into(), queue)?;
                }
            }
            "cancel-download" => {
                self.download_cancel.store(true, Ordering::Release);
                self.status = "Cancelling download…".into();
            }
            "quality" | "device" | "crossfade" | "passthrough" | "eq" | "cache-limit"
            | "storefront" => self.setting(command, value.trim())?,
            "" => {}
            _ => bail!("Unknown command: {command}. Use ? for help."),
        }
        Ok(())
    }

    fn create_playlist(&mut self, name: String, queue: bool) -> Result<()> {
        let api = self.api()?;
        let tracks: Vec<_> = if queue {
            self.queue
                .entries
                .iter()
                .filter(|entry| entry.item.is_song() || entry.item.kind.contains("music-videos"))
                .map(|entry| (entry.item.id.clone(), entry.item.kind.clone()))
                .collect()
        } else {
            Vec::new()
        };
        if queue && tracks.is_empty() {
            bail!("The queue has no songs to save");
        }
        self.job(false, move || {
            Job::Mutation(
                api.create_playlist(&name, "", &tracks)
                    .map(|_| format!("Created playlist: {name}")),
            )
        })
    }
}

fn move_list(state: &mut ListState, length: usize, delta: isize) {
    state.select((length > 0).then(|| {
        state
            .selected()
            .unwrap_or(0)
            .saturating_add_signed(delta)
            .min(length - 1)
    }));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unicode_editing_and_paste_never_treat_text_as_shortcuts() {
        let mut input = Input::new(InputKind::Search(false), "夜🌙".into());
        input.cursor = input.previous();
        input.insert("日本語 q e\x1b\r\n");
        assert_eq!(input.text, "夜日本語 q e🌙");
        assert!(input.text.is_char_boundary(input.cursor));
        assert_eq!(input.next(), input.text.len());
        assert!(Input::new(InputKind::Password("account".into()), "secret".into()).masked());
    }
}
