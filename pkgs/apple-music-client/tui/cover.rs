use anyhow::{Context, Result, bail};
use image::{DynamicImage, ImageReader, Limits, Rgba};
use ratatui::layout::Rect;
use ratatui_image::protocol::{
    ImageSource, StatefulProtocol, StatefulProtocolType, halfblocks::Halfblocks,
    kitty::StatefulKitty,
};
use siora::{artwork, model::MusicItem};
use std::{
    fs,
    io::{self, IsTerminal, Write},
    path::Path,
    time::{Duration, Instant},
};

#[derive(Clone, Copy)]
pub enum Role {
    Selected,
    Playing,
}

#[derive(Clone, Copy)]
pub struct Graphics {
    font_size: (u16, u16),
    kitty: bool,
}

impl Graphics {
    pub fn from_terminal() -> Self {
        let font_size = crossterm::terminal::window_size()
            .ok()
            .and_then(|size| {
                if size.columns == 0 || size.rows == 0 {
                    return None;
                }
                let font = (size.width / size.columns, size.height / size.rows);
                (font.0 > 0 && font.1 > 0).then_some(font)
            })
            .unwrap_or((10, 20));
        Self {
            font_size,
            kitty: std::env::var("TERM").is_ok_and(|term| term == "xterm-kitty")
                && std::env::var_os("TMUX").is_none(),
        }
    }

    #[cfg(test)]
    pub fn text(font_size: (u16, u16)) -> Self {
        Self {
            font_size,
            kitty: false,
        }
    }

    fn image(self, image: DynamicImage) -> StatefulProtocol {
        let protocol = if self.kitty {
            StatefulProtocolType::Kitty(StatefulKitty::new(rand::random::<u32>().max(1), false))
        } else {
            StatefulProtocolType::Halfblocks(Halfblocks::default())
        };
        StatefulProtocol::new(
            ImageSource::new(image, self.font_size, Rgba([0, 0, 0, 0])),
            self.font_size,
            protocol,
        )
    }
}

pub struct Covers {
    pub selected: Slot,
    pub playing: Slot,
    graphics: Graphics,
}

impl Covers {
    pub fn new(graphics: Graphics) -> Self {
        Self {
            selected: Slot::default(),
            playing: Slot::default(),
            graphics,
        }
    }

    pub fn slot(&mut self, role: Role) -> &mut Slot {
        match role {
            Role::Selected => &mut self.selected,
            Role::Playing => &mut self.playing,
        }
    }

    pub fn finish(&mut self, role: Role, key: &str, result: Result<Option<DynamicImage>>) {
        let graphics = self.graphics;
        self.slot(role).finish(key, result, graphics);
    }

    pub fn resize(&mut self) {
        let Ok(size) = crossterm::terminal::window_size() else {
            return;
        };
        if size.columns == 0 || size.rows == 0 {
            return;
        }
        let font_size = (size.width / size.columns, size.height / size.rows);
        if font_size.0 == 0 || font_size.1 == 0 || font_size == self.graphics.font_size {
            return;
        }
        self.graphics.font_size = font_size;
        for slot in [&mut self.selected, &mut self.playing] {
            slot.clear_image();
            slot.settled = false;
        }
    }

    pub fn square(&self, area: Rect, rows: u16) -> Rect {
        let (width, height) = self.graphics.font_size;
        let pixels = u32::from(area.width) * u32::from(width);
        let rows = rows
            .min(area.height)
            .min((pixels / u32::from(height.max(1))) as u16);
        let columns = (u32::from(rows) * u32::from(height) / u32::from(width.max(1))) as u16;
        Rect::new(area.x, area.y, columns.min(area.width), rows)
    }
}

pub struct Slot {
    pub image: Option<StatefulProtocol>,
    pub message: &'static str,
    wanted: Option<(String, MusicItem)>,
    pending: Option<String>,
    settled: bool,
    changed: Instant,
}

impl Default for Slot {
    fn default() -> Self {
        Self {
            image: None,
            message: "No cover",
            wanted: None,
            pending: None,
            settled: true,
            changed: Instant::now(),
        }
    }
}

impl Slot {
    pub fn select(&mut self, item: Option<&MusicItem>) {
        let wanted = item.and_then(|item| key(item).map(|key| (key, item.clone())));
        if wanted.as_ref().map(|(key, _)| key) == self.wanted.as_ref().map(|(key, _)| key) {
            return;
        }
        self.clear_image();
        self.settled = wanted.is_none();
        self.message = if wanted.is_some() {
            "Loading cover…"
        } else {
            "No cover"
        };
        self.wanted = wanted;
        self.changed = Instant::now();
    }

    pub fn request(&mut self, now: Instant) -> Option<(String, MusicItem)> {
        if self.settled
            || self.pending.is_some()
            || now.duration_since(self.changed) < Duration::from_millis(100)
        {
            return None;
        }
        let (key, item) = self.wanted.clone()?;
        self.pending = Some(key.clone());
        Some((key, item))
    }

    pub fn retry_later(&mut self) {
        self.pending = None;
        self.changed = Instant::now();
    }

    fn finish(&mut self, key: &str, result: Result<Option<DynamicImage>>, graphics: Graphics) {
        if self.pending.as_deref() != Some(key) {
            return;
        }
        self.pending = None;
        if self.wanted.as_ref().map(|(key, _)| key.as_str()) != Some(key) {
            return;
        }
        self.settled = true;
        match result {
            Ok(Some(image)) => {
                self.image = Some(graphics.image(image));
                self.message = "";
            }
            Ok(None) => self.message = "No cover",
            Err(_) => self.message = "Cover unavailable",
        }
    }

    pub fn check_encoding(&mut self) {
        if self
            .image
            .as_mut()
            .and_then(StatefulProtocol::last_encoding_result)
            .is_some_and(|result| result.is_err())
        {
            self.clear_image();
            self.message = "Cover unavailable";
        }
    }

    fn clear_image(&mut self) {
        if let Some(image) = self.image.take()
            && let StatefulProtocolType::Kitty(kitty) = image.protocol_type()
            && io::stdout().is_terminal()
        {
            let _ = write!(
                io::stdout(),
                "\x1b_Ga=d,d=I,i={},q=2\x1b\\",
                kitty.unique_id
            );
        }
    }
}

impl Drop for Slot {
    fn drop(&mut self) {
        self.clear_image();
    }
}

fn key(item: &MusicItem) -> Option<String> {
    item.artwork_url(512).or_else(|| {
        item.local_path
            .as_ref()
            .map(|path| path.to_string_lossy().into_owned())
    })
}

pub fn load(mut item: MusicItem, cache: &Path) -> Result<Option<DynamicImage>> {
    if item.artwork.is_some() {
        item.local_path = None;
    } else if let Some(path) = &item.local_path {
        let path = fs::canonicalize(path)?;
        if path.parent() != Some(fs::canonicalize(cache)?.as_path()) {
            bail!("Cover source must be in the music cache");
        }
        item.local_path = Some(path);
    }
    artwork::cached_artwork(&item, cache)?
        .map(|path| decode(&path))
        .transpose()
}

fn decode(path: &Path) -> Result<DynamicImage> {
    if fs::metadata(path)?.len() > 5 * 1024 * 1024 {
        bail!("Cover exceeds 5 MiB");
    }
    let mut reader = ImageReader::open(path)?.with_guessed_format()?;
    let mut limits = Limits::default();
    limits.max_image_width = Some(512);
    limits.max_image_height = Some(512);
    limits.max_alloc = Some(16 * 1024 * 1024);
    reader.limits(limits);
    reader.decode().context("Invalid cover image")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(id: &str) -> MusicItem {
        MusicItem {
            id: id.into(),
            kind: "songs".into(),
            artwork: Some(format!("https://is1-ssl.mzstatic.com/{id}/{{w}}x{{h}}.jpg")),
            ..Default::default()
        }
    }

    #[test]
    fn coalesces_selection_and_discards_late_cover_without_repainting_old_art() {
        let graphics = Graphics::text((8, 16));
        let mut slot = Slot::default();
        slot.select(Some(&item("first")));
        let (first, _) = slot
            .request(Instant::now() + Duration::from_secs(1))
            .unwrap();
        slot.select(Some(&item("second")));
        slot.select(Some(&item("latest")));
        assert!(
            slot.request(Instant::now() + Duration::from_secs(1))
                .is_none()
        );
        slot.finish(&first, Ok(Some(DynamicImage::new_rgb8(2, 2))), graphics);
        assert!(slot.image.is_none());
        let (latest, _) = slot
            .request(Instant::now() + Duration::from_secs(1))
            .unwrap();
        assert!(latest.contains("latest"));
        slot.finish(&latest, Ok(Some(DynamicImage::new_rgb8(2, 2))), graphics);
        assert!(slot.image.is_some());
        slot.select(None);
        assert!(slot.image.is_none());
    }

    #[test]
    fn missing_and_failed_covers_do_not_loop_requests() {
        let mut slot = Slot::default();
        slot.select(Some(&MusicItem::default()));
        assert!(
            slot.request(Instant::now() + Duration::from_secs(1))
                .is_none()
        );
        slot.select(Some(&item("bad")));
        let (key, _) = slot
            .request(Instant::now() + Duration::from_secs(1))
            .unwrap();
        slot.finish(
            &key,
            Err(anyhow::anyhow!("offline")),
            Graphics::text((8, 16)),
        );
        assert!(
            slot.request(Instant::now() + Duration::from_secs(1))
                .is_none()
        );
        assert_eq!(slot.message, "Cover unavailable");
    }

    #[test]
    fn image_dimensions_are_bounded_and_square_matches_cells() -> Result<()> {
        let root = tempfile::tempdir()?;
        let path = root.path().join("cover.jpg");
        DynamicImage::new_rgb8(513, 10).save(&path)?;
        assert!(decode(&path).is_err());
        DynamicImage::new_rgb8(512, 512).save(&path)?;
        assert_eq!(decode(&path)?.width(), 512);
        let covers = Covers::new(Graphics::text((8, 16)));
        assert_eq!(
            covers.square(Rect::new(2, 3, 20, 8), 6),
            Rect::new(2, 3, 12, 6)
        );
        Ok(())
    }
}
