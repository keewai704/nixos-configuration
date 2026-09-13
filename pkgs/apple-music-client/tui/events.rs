use super::{App, Input, InputKind, Job, LoginPrompt, Overlay, Ready, cover};
use anyhow::{Context, Result, anyhow, bail};
use ratatui::widgets::ListState;
use serde_json::json;
use siora::{
    apple_music::LoginState,
    audio_output::{AudioCommand, AudioEvent},
    mpris::{self, MediaCommand},
};
use std::time::Instant;

impl App {
    pub(super) fn poll(&mut self) -> Result<()> {
        if self
            .runtime
            .as_mut()
            .is_some_and(|runtime| !runtime.is_running().unwrap_or(false))
        {
            self.runtime = None;
            self.auth_failed("認証ヘルパーが終了しました。ライブラリの取り込み状態を確認し、:connect で再起動してください。".into(), false);
        }
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
        self.poll_covers();
        Ok(())
    }

    pub(super) fn poll_covers(&mut self) {
        self.covers.selected.select(self.page.item());
        self.covers
            .playing
            .select(self.queue.current().map(|entry| &entry.item));
        for role in [cover::Role::Playing, cover::Role::Selected] {
            if let Some((key, item)) = self.covers.slot(role).request(Instant::now()) {
                let cache = self.cache.clone();
                if self
                    .job(true, move || {
                        Job::Cover(role, key, cover::load(item, &cache))
                    })
                    .is_err()
                {
                    self.covers.slot(role).retry_later();
                }
            }
        }
    }

    pub(super) fn handle_job(&mut self, job: Job) -> Result<()> {
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
            Job::Connected(generation, prompt, result) if generation == self.auth_generation => {
                self.auth_busy = false;
                match result {
                    Ok((state, api)) => {
                        self.api = api;
                        self.auth_ready = true;
                        self.auth_problem = None;
                        if state.authenticated {
                            self.account = "Connected".into();
                            self.status = "Apple Music connected".into();
                        } else if state.needs_code {
                            self.account = "Two-factor code required".into();
                            self.status =
                                "2段階認証コードが必要です。:code を実行してください。".into();
                            if prompt.is_some() {
                                self.input = Some(Input::new(InputKind::Code, String::new()));
                            }
                        } else {
                            self.account = "Ready to sign in".into();
                            self.status =
                                "認証ヘルパーに接続しました。:login でサインインできます。".into();
                            match prompt {
                                Some(LoginPrompt::Account) => {
                                    self.input =
                                        Some(Input::new(InputKind::Username, String::new()))
                                }
                                Some(LoginPrompt::Code) => self.status =
                                    "2段階認証待ちではありません。先に :login を実行してください。"
                                        .into(),
                                None => {}
                            }
                        }
                    }
                    Err(error) => {
                        self.auth_failed(error.to_string(), prompt.is_some());
                        return Err(error);
                    }
                }
            }
            Job::Login(generation, result) if generation == self.auth_generation => {
                self.auth_busy = false;
                let state = match result {
                    Ok(state) => state,
                    Err(error) => {
                        self.account = "Sign-in failed".into();
                        return Err(error);
                    }
                };
                match state {
                    LoginState::Authenticated => self.connect(None)?,
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
            Job::Cover(role, key, result) => self.covers.finish(role, &key, result),
            _ => {}
        }
        Ok(())
    }

    pub(super) fn media_command(&mut self, command: MediaCommand) -> Result<()> {
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

    pub(super) fn publish(&mut self) {
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
