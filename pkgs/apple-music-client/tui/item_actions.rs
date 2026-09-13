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

impl App {
    pub(super) fn item_action(&mut self, item: MusicItem, index: usize) -> Result<()> {
        match index {
            0 => self.open_item(item)?,
            1 | 2 => self.enqueue(item, index == 1)?,
            3 | 4 => {
                let api = self.authenticated_api()?;
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
                let api = self.authenticated_api()?;
                let target = item.clone();
                self.spawn_job(ShutdownBehavior::Detach, move || {
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
                let api = self.authenticated_api()?;
                self.spawn_job(ShutdownBehavior::Detach, move || {
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
                let api = self.authenticated_api()?;
                self.spawn_job(ShutdownBehavior::Detach, move || {
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

    pub(super) fn enqueue(&mut self, item: MusicItem, next: bool) -> Result<()> {
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
        let api = self.authenticated_api()?;
        self.spawn_job(ShutdownBehavior::Detach, move || {
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
        let auth = self.authentication_endpoints()?;
        let (prefs, cache) = (
            self.store.data.preferences.clone(),
            self.download_directory.clone(),
        );
        self.download_cancel = Arc::new(AtomicBool::new(false));
        let cancel = self.download_cancel.clone();
        self.spawn_job(ShutdownBehavior::Wait, move || {
            let result = player::prepare(&item, &prefs, &cache, &cancel, &auth);
            Job::Download(item, prefs.quality, result)
        })?;
        self.downloading = true;
        self.status = "Downloading… :cancel-download cancels".into();
        Ok(())
    }

    pub(super) fn remove_download(&mut self, item: MusicItem) -> Result<()> {
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
                .prefetched_track
                .as_ref()
                .is_some_and(|ready| ready.track.path == path)
        {
            bail!("Stop playback and pending downloads before removing this file");
        }
        self.cancel_prefetch();
        player::remove_cached_track(&self.download_directory, &path)?;
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

    pub(super) fn create_playlist(&mut self, name: String, queue: bool) -> Result<()> {
        let api = self.authenticated_api()?;
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
        self.spawn_job(ShutdownBehavior::Detach, move || {
            Job::Mutation(
                api.create_playlist(&name, "", &tracks)
                    .map(|_| format!("Created playlist: {name}")),
            )
        })
    }
}
