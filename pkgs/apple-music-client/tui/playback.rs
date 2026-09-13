use super::{App, Job, Overlay, ShutdownBehavior, Station};
use anyhow::{Context, Result, bail};
use ratatui::widgets::ListState;
use serde_json::{Value, json};
use siora::{
    audio_output::AudioCommand,
    model::MusicItem,
    player::{self, PreparedTrack},
};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

impl App {
    pub(super) fn play_context(&mut self, item: MusicItem) -> Result<()> {
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

    pub(super) fn replace_queue(
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

    pub(super) fn cancel_prefetch(&mut self) {
        self.prefetch_cancel.store(true, Ordering::Release);
        self.prefetch_cancel = Arc::new(AtomicBool::new(false));
        self.prefetch_generation += 1;
        self.prefetched_track = None;
        let _ = self
            .audio_commands
            .send(AudioCommand::ClearNext(self.playback_generation));
    }

    pub(super) fn play(&mut self, id: u64) -> Result<()> {
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
        self.playback_cancel.store(true, Ordering::Release);
        self.playback_cancel = Arc::new(AtomicBool::new(false));
        self.cancel_prefetch();
        self.playback_generation += 1;
        let generation = self.playback_generation;
        self.audio_commands.send(AudioCommand::Stop(generation))?;
        self.queue.current = Some(id);
        self.preparing = false;
        self.loaded = false;
        self.playback_snapshot = json!({});
        self.playback_source = Value::Null;
        self.lyrics.clear();
        if entry.item.kind == "stations" {
            self.spawn_job(ShutdownBehavior::Detach, move || {
                Job::Radio(generation, siora::radio::station_stream_url(&entry.item.id))
            })?;
        } else {
            let auth = self.authentication_endpoints()?;
            let item = self.cached(entry.item);
            let prefs = self.store.data.preferences.clone();
            let cache = self.download_directory.clone();
            let cancel = self.playback_cancel.clone();
            self.spawn_job(ShutdownBehavior::Wait, move || {
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

    pub(super) fn cached(&self, mut item: MusicItem) -> MusicItem {
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

    pub(super) fn prepared(&mut self, id: u64, quality: &str, track: &PreparedTrack) -> Result<()> {
        if let Some(entry) = self.queue.entries.iter_mut().find(|entry| entry.id == id) {
            entry.item.local_path = Some(track.path.clone());
            entry.item.cached_quality = Some(quality.into());
            self.store.upsert(entry.item.clone());
        }
        self.save()
    }

    pub(super) fn schedule_next(&mut self) -> Result<()> {
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
        let auth = self.authentication_endpoints()?;
        let (generation, serial) = (self.playback_generation, self.prefetch_generation);
        let (prefs, cache, cancel) = (
            self.store.data.preferences.clone(),
            self.download_directory.clone(),
            self.prefetch_cancel.clone(),
        );
        self.spawn_job(ShutdownBehavior::Wait, move || {
            Job::Prefetched(
                generation,
                serial,
                id,
                prefs.quality.clone(),
                player::prepare(&item, &prefs, &cache, &cancel, &auth),
            )
        })
    }

    pub(super) fn is_radio(&self) -> bool {
        self.queue
            .current()
            .is_some_and(|entry| entry.item.kind == "stations")
    }

    pub(super) fn stop(&mut self) {
        self.playback_cancel.store(true, Ordering::Release);
        self.cancel_prefetch();
        self.playback_generation += 1;
        let _ = self
            .audio_commands
            .send(AudioCommand::Stop(self.playback_generation));
        self.loaded = false;
        self.preparing = false;
        self.queue.current = None;
        self.station = None;
        self.playback_snapshot = json!({});
        self.playback_source = Value::Null;
        self.lyrics.clear();
        self.status = "Stopped".into();
    }

    pub(super) fn next(&mut self, automatic: bool) -> Result<()> {
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

    pub(super) fn previous(&mut self) -> Result<()> {
        if !self.is_radio() && self.playback_snapshot["position"].as_f64().unwrap_or(0.) > 3. {
            self.command(json!(["seek", 0, "absolute"]));
            self.schedule_next()
        } else if let Some(index) = self.queue.index(self.queue.current) {
            self.play(self.queue.entries[index.saturating_sub(1)].id)
        } else {
            Ok(())
        }
    }

    pub(super) fn command(&self, command: Value) {
        let _ = self.audio_commands.send(AudioCommand::Command(command));
    }

    pub(super) fn pause(&mut self) -> Result<()> {
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

    pub(super) fn start_station(&mut self, item: MusicItem) -> Result<()> {
        let api = self.authenticated_api()?;
        if self.station.as_ref().is_some_and(|station| station.busy) {
            bail!("Station is loading");
        }
        self.station_serial += 1;
        let serial = self.station_serial;
        let seed = item.clone();
        self.spawn_job(ShutdownBehavior::Detach, move || {
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

    pub(super) fn fetch_station(&mut self, initial: bool) -> Result<()> {
        let api = self.authenticated_api()?;
        let Some(station) = &self.station else {
            return Ok(());
        };
        if station.busy {
            return Ok(());
        }
        let (serial, id) = (station.serial, station.item.id.clone());
        self.spawn_job(ShutdownBehavior::Detach, move || {
            Job::Station(serial, initial, api.station_tracks(&id))
        })?;
        if let Some(station) = &mut self.station {
            station.busy = true;
        }
        Ok(())
    }

    pub(super) fn volume(&mut self, value: f64) -> Result<()> {
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
}
