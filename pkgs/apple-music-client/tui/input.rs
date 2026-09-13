use super::*;

pub(super) enum InputKind {
    Search(bool),
    Filter(String),
    Command,
    Username,
    Password(String),
    Code,
    Setting(&'static str),
    PlaylistName(bool),
}

pub(super) struct Input {
    pub(super) kind: InputKind,
    pub(super) text: String,
    pub(super) cursor: usize,
}

impl Input {
    pub(super) fn new(kind: InputKind, text: String) -> Self {
        let cursor = text.len();
        Self { kind, text, cursor }
    }

    pub(super) fn insert(&mut self, text: &str) {
        let text = browse::clean(text);
        if self.text.len() + text.len() <= 4096 {
            self.text.insert_str(self.cursor, &text);
            self.cursor += text.len();
        }
    }

    pub(super) fn previous(&self) -> usize {
        self.text[..self.cursor]
            .char_indices()
            .next_back()
            .map_or(0, |(index, _)| index)
    }

    pub(super) fn next(&self) -> usize {
        self.text[self.cursor..]
            .chars()
            .next()
            .map_or(self.cursor, |ch| self.cursor + ch.len_utf8())
    }

    pub(super) fn masked(&self) -> bool {
        matches!(self.kind, InputKind::Password(_) | InputKind::Code)
    }
}

impl App {
    pub(super) fn input_key(&mut self, key: KeyEvent) -> Result<()> {
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
                let auth = self.authentication_endpoints()?;
                let generation = self.auth_generation;
                self.spawn_job(ShutdownBehavior::Detach, move || {
                    Job::Login(
                        generation,
                        apple_music::sign_in(&auth.http, &username, &text, None),
                    )
                })?;
                self.auth_busy = true;
                self.account = "Signing in…".into();
            }
            InputKind::Code => {
                let auth = self.authentication_endpoints()?;
                let generation = self.auth_generation;
                self.spawn_job(ShutdownBehavior::Detach, move || {
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
