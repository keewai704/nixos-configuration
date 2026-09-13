use super::*;
use crossterm::event::{MouseButton, MouseEvent, MouseEventKind};
use ratatui::layout::Rect;
use unicode_width::UnicodeWidthChar;

#[derive(Clone, PartialEq)]
pub enum Action {
    Key(KeyCode),
    Selected(KeyCode),
    Search,
    Navigation,
    Navigate(usize),
    Quit,
    Stop,
    BrowseRow(String),
    QueueRow(u64),
    MenuRow(usize),
    Caret(u16),
    SearchScope,
    Seek(u64),
    Volume,
    QueueMove(isize),
    QueueRemove,
    QueueUndo,
}

#[derive(Clone, Copy)]
pub enum Pane {
    Navigation,
    Browse(usize),
    Queue(usize),
    Text,
}

#[derive(Default)]
pub struct Mouse {
    hits: Vec<(Rect, Action)>,
    panes: Vec<(Rect, Pane)>,
    last_click: Option<(Action, Instant)>,
    seek_drag: Option<(u64, Rect)>,
}

impl Mouse {
    pub fn clear(&mut self) {
        self.hits.clear();
        self.panes.clear();
    }
    pub fn hit(&mut self, area: Rect, action: Action) {
        if !area.is_empty() {
            self.hits.push((area, action));
        }
    }
    pub fn pane(&mut self, area: Rect, pane: Pane) {
        if !area.is_empty() {
            self.panes.push((area, pane));
        }
    }
    fn target(&self, x: u16, y: u16) -> Option<(Rect, Action)> {
        self.hits
            .iter()
            .rev()
            .find(|(rect, _)| contains(*rect, x, y))
            .cloned()
    }
    fn double_click(&mut self, action: &Action, now: Instant) -> bool {
        let double = self.last_click.as_ref().is_some_and(|(last, time)| {
            last == action && now.duration_since(*time) <= Duration::from_millis(350)
        });
        self.last_click = if double {
            None
        } else {
            Some((action.clone(), now))
        };
        double
    }
}

fn contains(rect: Rect, x: u16, y: u16) -> bool {
    x >= rect.x && x < rect.right() && y >= rect.y && y < rect.bottom()
}

impl App {
    pub(super) fn mouse_event(&mut self, event: MouseEvent) -> Result<()> {
        if !event.modifiers.is_empty() {
            return Ok(());
        }
        if let MouseEventKind::ScrollUp | MouseEventKind::ScrollDown = event.kind {
            let delta = if event.kind == MouseEventKind::ScrollUp {
                -3
            } else {
                3
            };
            return self.mouse_scroll(event.column, event.row, delta);
        }
        if event.kind == MouseEventKind::Drag(MouseButton::Left) {
            if let Some((track, area)) = self.mouse.seek_drag {
                self.mouse_seek(track, area, event.column);
            }
            return Ok(());
        }
        if event.kind == MouseEventKind::Up(MouseButton::Left) {
            if self.mouse.seek_drag.take().is_some() {
                self.schedule_next()?;
            }
            return Ok(());
        }
        let MouseEventKind::Down(button) = event.kind else {
            return Ok(());
        };
        let Some((rect, action)) = self.mouse.target(event.column, event.row) else {
            if button == MouseButton::Left && (self.overlay.is_some() || self.input.is_some()) {
                self.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE))?;
            }
            return Ok(());
        };
        let double =
            button == MouseButton::Left && self.mouse.double_click(&action, Instant::now());
        match action {
            Action::BrowseRow(key) => {
                if !self.page.select_key(&key) {
                    return Ok(());
                }
                self.focus = Focus::Browse;
                self.mouse_row_action(button, double)?;
            }
            Action::QueueRow(id) => {
                if self.queue.index(Some(id)).is_none() {
                    return Ok(());
                }
                self.queue.selected = Some(id);
                self.focus = Focus::Panel;
                self.mouse_row_action(button, double)?;
            }
            _ if button != MouseButton::Left => {}
            Action::Key(key) => self.key(KeyEvent::new(key, KeyModifiers::NONE))?,
            Action::Selected(key) => {
                self.focus = Focus::Browse;
                self.key(KeyEvent::new(key, KeyModifiers::NONE))?;
            }
            Action::Search => self.key(KeyEvent::new(KeyCode::Char('f'), KeyModifiers::CONTROL))?,
            Action::Navigation => self.focus = Focus::Navigation,
            Action::Quit => self.quit = true,
            Action::Stop => self.stop(),
            Action::Navigate(index) => self.navigate(index)?,
            Action::MenuRow(index) => {
                match &mut self.overlay {
                    Some(
                        Overlay::Actions(_, _, state)
                        | Overlay::Settings(state)
                        | Overlay::Replace(_, _, _, state)
                        | Overlay::Devices(_, state)
                        | Overlay::RemoveDownload(_, state),
                    ) => state.select(Some(index)),
                    Some(Overlay::Playlists(_, page)) => page.select_visible(index),
                    _ => return Ok(()),
                }
                self.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE))?;
            }
            Action::Caret(offset) => {
                if let Some(input) = &mut self.input {
                    let column = usize::from(event.column.saturating_sub(rect.x) + offset);
                    input.cursor = caret(&input.text, column, input.masked());
                }
            }
            Action::SearchScope => {
                if let Some(Input {
                    kind: InputKind::Search(library),
                    ..
                }) = &mut self.input
                {
                    *library = !*library;
                }
            }
            Action::Seek(track) => {
                self.cancel_prefetch();
                self.mouse.seek_drag = Some((track, rect));
                self.mouse_seek(track, rect, event.column);
            }
            Action::Volume => {}
            Action::QueueMove(delta) => {
                if self.queue.reorder(delta) {
                    self.schedule_next()?;
                }
            }
            Action::QueueRemove => {
                if self.queue.remove() {
                    self.schedule_next()?;
                }
            }
            Action::QueueUndo => {
                if self.queue.undo() {
                    self.schedule_next()?;
                }
            }
        }
        Ok(())
    }

    fn mouse_row_action(&mut self, button: MouseButton, double: bool) -> Result<()> {
        let code = match (button, double) {
            (MouseButton::Left, true) => Some(KeyCode::Enter),
            (MouseButton::Right, _) => Some(KeyCode::Char('a')),
            (MouseButton::Middle, _) => Some(KeyCode::Char('e')),
            _ => None,
        };
        if let Some(code) = code {
            self.key(KeyEvent::new(code, KeyModifiers::NONE))?;
        }
        Ok(())
    }

    fn mouse_seek(&self, track: u64, area: Rect, column: u16) {
        if self.queue.current != Some(track) || !self.loaded || self.is_radio() {
            return;
        }
        let duration = self.playback_snapshot["duration"].as_f64().unwrap_or(0.);
        if duration <= 0. || !duration.is_finite() {
            return;
        }
        let fraction = f64::from(
            column
                .saturating_sub(area.x)
                .min(area.width.saturating_sub(1)),
        ) / f64::from(area.width.saturating_sub(1).max(1));
        self.command(json!(["seek", fraction * duration, "absolute"]));
    }

    fn mouse_scroll(&mut self, x: u16, y: u16, delta: isize) -> Result<()> {
        if self.input.is_some() {
            return Ok(());
        }
        if self.overlay.is_some() {
            for _ in 0..delta.unsigned_abs() {
                self.key(KeyEvent::new(
                    if delta < 0 {
                        KeyCode::Up
                    } else {
                        KeyCode::Down
                    },
                    KeyModifiers::NONE,
                ))?;
            }
            return Ok(());
        }
        if self
            .mouse
            .target(x, y)
            .is_some_and(|(_, action)| action == Action::Volume)
        {
            return self
                .volume(self.store.data.preferences.volume + if delta < 0 { 5. } else { -5. });
        }
        match self
            .mouse
            .panes
            .iter()
            .rev()
            .find(|(rect, _)| contains(*rect, x, y))
            .map(|(_, pane)| *pane)
        {
            Some(Pane::Browse(rows)) => self.page.scroll(delta, rows),
            Some(Pane::Navigation) => {
                let index = self
                    .navigation_list
                    .selected()
                    .unwrap_or(0)
                    .saturating_add_signed(delta)
                    .min(browse::NAV.len() - 1);
                self.navigation_list.select(Some(index));
            }
            Some(Pane::Queue(rows)) => {
                let start = self
                    .queue_list
                    .offset()
                    .saturating_add_signed(delta)
                    .min(self.queue.entries.len().saturating_sub(rows));
                *self.queue_list.offset_mut() = start;
                if let Some(index) = self.queue.index(self.queue.selected) {
                    let visible = index.clamp(
                        start,
                        (start + rows)
                            .saturating_sub(1)
                            .min(self.queue.entries.len().saturating_sub(1)),
                    );
                    self.queue.selected = self.queue.entries.get(visible).map(|entry| entry.id);
                }
            }
            Some(Pane::Text) => {
                self.panel_scroll = (self.panel_scroll as usize)
                    .saturating_add_signed(delta)
                    .min(u16::MAX as usize) as u16
            }
            None => {}
        }
        Ok(())
    }
}

fn caret(text: &str, column: usize, masked: bool) -> usize {
    let mut width = 0;
    for (index, character) in text.char_indices() {
        let next = width
            + if masked {
                1
            } else {
                character.width().unwrap_or(0)
            };
        if column < next {
            return index;
        }
        width = next;
    }
    text.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overlays_win_hit_testing_and_click_identity_survives_row_movement() {
        let mut mouse = Mouse::default();
        let row = Action::BrowseRow("songs:1".into());
        mouse.hit(Rect::new(0, 0, 20, 10), row.clone());
        mouse.hit(Rect::new(2, 2, 10, 3), Action::MenuRow(2));
        assert!(matches!(mouse.target(4, 3), Some((_, Action::MenuRow(2)))));
        let now = Instant::now();
        assert!(!mouse.double_click(&row, now));
        mouse.clear();
        assert!(mouse.double_click(&row, now + Duration::from_millis(100)));
        assert!(!mouse.double_click(
            &Action::BrowseRow("songs:2".into()),
            now + Duration::from_millis(200)
        ));
    }

    #[test]
    fn mouse_caret_uses_display_columns_and_keeps_utf8_boundaries() {
        assert_eq!(caret("夜abc", 1, false), 0);
        assert_eq!(caret("夜abc", 2, false), 3);
        assert_eq!(caret("夜abc", 1, true), 3);
        assert_eq!(caret("夜abc", 20, false), 6);
    }

    #[test]
    fn row_selection_context_menu_and_selected_add_use_the_clicked_item() -> Result<()> {
        let root = tempfile::tempdir()?;
        let mut app = App::new(
            LibraryStore::open(root.path().join("state.json"))?,
            root.path().join("downloads"),
            true,
            cover::Graphics::text((10, 20)),
        );
        let item = |id: &str| MusicItem {
            id: id.into(),
            kind: "songs".into(),
            title: id.into(),
            ..Default::default()
        };
        app.page = Page::new("Songs", vec![item("1"), item("2")]);
        let event = |button| MouseEvent {
            kind: MouseEventKind::Down(button),
            column: 3,
            row: 2,
            modifiers: KeyModifiers::NONE,
        };
        app.mouse
            .hit(Rect::new(0, 2, 20, 1), Action::BrowseRow("songs:2".into()));
        app.mouse_event(event(MouseButton::Left))?;
        assert_eq!(app.page.item().unwrap().id, "2");
        assert!(app.queue.entries.is_empty());
        app.mouse_event(event(MouseButton::Right))?;
        assert!(matches!(&app.overlay, Some(Overlay::Actions(item, None, _)) if item.id == "2"));
        app.overlay = None;
        app.focus = Focus::Panel;
        app.panel = Some(Panel::Queue);
        app.queue.add(item("3"), false);
        app.mouse.clear();
        app.mouse
            .hit(Rect::new(0, 2, 20, 1), Action::Selected(KeyCode::Char('e')));
        app.mouse_event(event(MouseButton::Left))?;
        assert_eq!(app.queue.entries.last().unwrap().item.id, "2");
        Ok(())
    }
    #[test]
    fn dragging_seeks_the_original_track_and_release_clears_the_drag() -> Result<()> {
        let root = tempfile::tempdir()?;
        let mut app = App::new(
            LibraryStore::open(root.path().join("state.json"))?,
            root.path().join("downloads"),
            true,
            cover::Graphics::text((10, 20)),
        );
        app.audio_commands.send(AudioCommand::Shutdown)?;
        app.audio_thread.take().unwrap().join().unwrap();
        let (audio, commands) = mpsc::channel();
        app.audio_commands = audio;
        app.queue.add(
            MusicItem {
                id: "1".into(),
                kind: "songs".into(),
                ..Default::default()
            },
            false,
        );
        let track = app.queue.entries[0].id;
        app.queue.current = Some(track);
        app.loaded = true;
        app.playback_snapshot = json!({"duration": 100.});
        app.mouse.hit(Rect::new(10, 2, 101, 1), Action::Seek(track));
        let event = |kind, column| MouseEvent {
            kind,
            column,
            row: 2,
            modifiers: KeyModifiers::NONE,
        };
        app.mouse_event(event(MouseEventKind::Down(MouseButton::Left), 35))?;
        app.mouse_event(event(MouseEventKind::Drag(MouseButton::Left), 85))?;
        let seeks: Vec<_> = commands
            .try_iter()
            .filter_map(|command| match command {
                AudioCommand::Command(value) => Some(value),
                _ => None,
            })
            .collect();
        assert_eq!(
            seeks,
            vec![
                json!(["seek", 25., "absolute"]),
                json!(["seek", 75., "absolute"])
            ]
        );
        app.queue.current = None;
        app.mouse_event(event(MouseEventKind::Drag(MouseButton::Left), 110))?;
        assert!(commands.try_recv().is_err());
        app.queue.current = Some(track);
        app.mouse_event(event(MouseEventKind::Up(MouseButton::Left), 110))?;
        assert!(app.mouse.seek_drag.is_none());
        app.queue.current = Some(track);
        app.queue.entries[0].item.kind = "stations".into();
        commands.try_iter().for_each(drop);
        app.mouse_seek(track, Rect::new(10, 2, 101, 1), 60);
        assert!(commands.try_recv().is_err());
        Ok(())
    }
}
