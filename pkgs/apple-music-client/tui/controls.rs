use super::item_actions::ACTIONS;
use super::settings::SETTINGS;
use super::*;

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
                Focus::Navigation => self.navigate(self.navigation_list.selected().unwrap_or(0))?,
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

    pub(super) fn cycle_focus(&mut self, reverse: bool) {
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
                    .navigation_list
                    .selected()
                    .unwrap_or(0)
                    .saturating_add_signed(delta)
                    .min(browse::NAV.len() - 1);
                self.navigation_list.select(Some(index));
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
                let api = self.authenticated_api()?;
                self.spawn_job(ShutdownBehavior::Detach, move || {
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
