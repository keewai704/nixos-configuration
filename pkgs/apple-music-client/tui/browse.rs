use anyhow::{Result, bail};
use ratatui::widgets::TableState;
use serde_json::Value;
use siora::{discovery, model::MusicItem};
use std::collections::HashSet;

pub const NAV: &[(&str, &str)] = &[
    ("Home", "home"),
    ("New", "new"),
    ("Radio", "radio"),
    ("Songs", "library-songs"),
    ("Albums", "library-albums"),
    ("Artists", "library-artists"),
    ("Playlists", "library-playlists"),
    ("Favorites", "favorites"),
    ("Recent", "recent"),
    ("Downloads", "downloads"),
];
pub const KINDS: &[&str] = &[
    "all",
    "songs",
    "albums",
    "artists",
    "playlists",
    "music-videos",
];

#[derive(Clone, Default)]
pub struct Page {
    pub title: String,
    pub items: Vec<MusicItem>,
    pub next: Option<String>,
    pub search: Option<(String, bool)>,
    pub filter: String,
    pub kind: usize,
    pub sort: usize,
    pub visible: Vec<usize>,
    pub table: TableState,
    pub selected: Option<String>,
    pub album: bool,
    pub pages: Value,
}

impl Page {
    pub fn new(title: impl Into<String>, items: Vec<MusicItem>) -> Self {
        let mut page = Self {
            title: title.into(),
            items,
            ..Self::default()
        };
        page.refresh();
        page
    }

    pub fn refresh(&mut self) {
        let filter = self.filter.to_lowercase();
        let kind = KINDS[self.kind];
        self.visible = self
            .items
            .iter()
            .enumerate()
            .filter(|(_, item)| {
                (kind == "all" || item.kind.trim_start_matches("library-") == kind)
                    && format!("{} {} {}", item.title, item.artist, item.album)
                        .to_lowercase()
                        .contains(&filter)
            })
            .map(|(index, _)| index)
            .collect();
        match self.sort {
            1 => self
                .visible
                .sort_by_cached_key(|&i| self.items[i].title.to_lowercase()),
            2 => self
                .visible
                .sort_by_cached_key(|&i| self.items[i].artist.to_lowercase()),
            3 => self
                .visible
                .sort_by_cached_key(|&i| self.items[i].album.to_lowercase()),
            _ => {}
        }
        let selected = self.selected.as_ref().and_then(|key| {
            self.visible
                .iter()
                .position(|&i| self.items[i].key() == *key)
        });
        self.table
            .select(selected.or_else(|| (!self.visible.is_empty()).then_some(0)));
        self.remember_selection();
    }

    pub fn move_by(&mut self, delta: isize) {
        if self.visible.is_empty() {
            return;
        }
        let index = self
            .table
            .selected()
            .unwrap_or(0)
            .saturating_add_signed(delta)
            .min(self.visible.len() - 1);
        self.table.select(Some(index));
        self.remember_selection();
    }

    pub fn item(&self) -> Option<&MusicItem> {
        self.table
            .selected()
            .and_then(|i| self.visible.get(i))
            .and_then(|&i| self.items.get(i))
    }

    fn remember_selection(&mut self) {
        self.selected = self.item().map(MusicItem::key);
    }

    pub fn select_visible(&mut self, index: usize) {
        self.table.select(
            (!self.visible.is_empty()).then_some(index.min(self.visible.len().saturating_sub(1))),
        );
        self.remember_selection();
    }

    pub fn select_key(&mut self, key: &str) -> bool {
        let Some(index) = self
            .visible
            .iter()
            .position(|&index| self.items[index].key() == key)
        else {
            return false;
        };
        self.select_visible(index);
        true
    }

    pub fn scroll(&mut self, delta: isize, rows: usize) {
        let rows = rows.max(1);
        let start = self
            .table
            .offset()
            .saturating_add_signed(delta)
            .min(self.visible.len().saturating_sub(rows));
        *self.table.offset_mut() = start;
        if let Some(selected) = self.table.selected() {
            self.select_visible(
                selected.clamp(
                    start,
                    (start + rows)
                        .saturating_sub(1)
                        .min(self.visible.len().saturating_sub(1)),
                ),
            );
        }
    }

    pub fn append(&mut self, other: Page) {
        let mut seen: HashSet<_> = self.items.iter().map(MusicItem::key).collect();
        self.items.extend(
            other
                .items
                .into_iter()
                .filter(|item| seen.insert(item.key())),
        );
        if self.search.is_some() && other.search.is_some() && other.kind > 0 {
            let kind = KINDS[other.kind];
            let library = self.search.as_ref().is_some_and(|(_, library)| *library);
            let key = if library {
                format!("library-{kind}")
            } else {
                kind.into()
            };
            self.pages["results"][key]["next"] =
                other.next.clone().map(Value::String).unwrap_or(Value::Null);
        } else {
            self.next = other.next;
        }
        self.refresh();
    }

    pub fn next_url(&self) -> Option<String> {
        if self.search.is_some() {
            if self.kind == 0 {
                return None;
            }
            let kind = KINDS[self.kind];
            let library = self.search.as_ref().is_some_and(|(_, library)| *library);
            let key = if library {
                format!("library-{kind}")
            } else {
                kind.into()
            };
            self.pages["results"][key]["next"]
                .as_str()
                .map(str::to_owned)
        } else {
            self.next.clone()
        }
    }
}

pub fn api_page(title: impl Into<String>, value: Value) -> Page {
    let mut page = Page::new(title, resources(&value));
    page.next = value["next"].as_str().map(str::to_owned);
    page.pages = value;
    page
}

pub fn public_page(route: &str, storefront: &str) -> Result<Page> {
    let page = discovery::fetch(route, storefront)?;
    let mut seen = HashSet::new();
    let items = page
        .shelves
        .into_iter()
        .flat_map(|shelf| shelf.items)
        .map(|card| card.item)
        .filter(|item| seen.insert(item.key()))
        .collect();
    let album = page
        .resource
        .as_ref()
        .is_some_and(|item| item.kind.contains("albums"));
    let mut result = Page::new(page.title, items);
    result.album = album;
    Ok(result)
}

pub fn resources(value: &Value) -> Vec<MusicItem> {
    fn walk(value: &Value, items: &mut Vec<MusicItem>) {
        match value {
            Value::Array(values) => values.iter().for_each(|v| walk(v, items)),
            Value::Object(map) => {
                if let Some(item) = MusicItem::from_resource(value)
                    && item.is_apple_music()
                {
                    items.push(item);
                    return;
                }
                for (key, value) in map {
                    if !matches!(
                        key.as_str(),
                        "attributes" | "meta" | "artwork" | "playParams"
                    ) {
                        walk(value, items);
                    }
                }
            }
            _ => {}
        }
    }
    let mut result = Vec::new();
    walk(value, &mut result);
    let mut seen = HashSet::new();
    result.retain(|item| seen.insert(item.key()));
    result
}

pub fn validate_url(value: &str) -> Result<String> {
    let url = reqwest::Url::parse(value)?;
    if url.scheme() != "https"
        || url.host_str() != Some("music.apple.com")
        || !url.username().is_empty()
        || url.password().is_some()
        || url.port().is_some()
    {
        bail!("Use an HTTPS music.apple.com URL");
    }
    Ok(url.into())
}

pub fn playable(item: &MusicItem) -> bool {
    item.is_song()
        || matches!(
            item.kind.as_str(),
            "stations" | "music-videos" | "library-music-videos"
        )
}

pub fn clean(value: &str) -> String {
    value
        .chars()
        .filter(|ch| {
            !ch.is_control() && !matches!(*ch, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
        })
        .collect()
}

pub fn clock(seconds: f64) -> String {
    let seconds = seconds.max(0.0) as u64;
    format!("{}:{:02}", seconds / 60, seconds % 60)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(id: &str, title: &str) -> MusicItem {
        MusicItem {
            id: id.into(),
            title: title.into(),
            kind: "songs".into(),
            ..Default::default()
        }
    }

    #[test]
    fn filter_sort_and_append_preserve_identity_without_editing_source() {
        let mut page = Page::new("Album", vec![song("1", "夜に駆ける"), song("2", "群青")]);
        page.move_by(1);
        page.sort = 1;
        page.refresh();
        assert_eq!(page.item().unwrap().id, "2");
        page.filter = "群".into();
        page.refresh();
        assert_eq!(page.visible.len(), 1);
        page.append(Page::new(
            "",
            vec![song("2", "duplicate"), song("3", "群像")],
        ));
        assert_eq!(page.items.len(), 3);
        assert_eq!(page.item().unwrap().id, "2");
        let saved = page.clone();
        page.move_by(1);
        assert_eq!(saved.item().unwrap().id, "2");
        assert_eq!(saved.filter, "群");
    }

    #[test]
    fn terminal_text_and_external_links_cannot_inject_controls() {
        assert_eq!(clean("a\x1b\n\r\u{202e}b"), "ab");
        for url in [
            "file:///tmp/a",
            "https://music.apple.com.evil.test/",
            "https://x@music.apple.com/",
            "https://music.apple.com:8080/",
        ] {
            assert!(validate_url(url).is_err());
        }
        assert!(validate_url("https://music.apple.com/jp/album/a/123?i=456").is_ok());
    }

    #[test]
    fn search_pagination_tracks_each_resource_type() {
        let mut page = api_page(
            "Search",
            serde_json::json!({"results":{"songs":{"next":"/songs?page=2"},"albums":{"next":"/albums?page=2"}}}),
        );
        page.search = Some(("test".into(), false));
        assert!(page.next_url().is_none());
        page.kind = 1;
        assert_eq!(page.next_url().as_deref(), Some("/songs?page=2"));
        let mut next = Page::new("", vec![]);
        next.search = page.search.clone();
        next.kind = 1;
        page.kind = 2;
        page.append(next);
        assert_eq!(page.next_url().as_deref(), Some("/albums?page=2"));
        page.kind = 1;
        assert!(page.next_url().is_none());
        page.kind = 2;
        assert_eq!(page.next_url().as_deref(), Some("/albums?page=2"));
    }

    #[test]
    fn wheel_scroll_changes_viewport_without_changing_the_collection() {
        let mut page = Page::new(
            "Songs",
            (0..30).map(|id| song(&id.to_string(), "song")).collect(),
        );
        page.select_visible(8);
        page.scroll(3, 10);
        assert_eq!(page.table.offset(), 3);
        assert_eq!(page.item().unwrap().id, "8");
        page.scroll(20, 10);
        assert_eq!(page.table.offset(), 20);
        assert_eq!(page.item().unwrap().id, "20");
        assert_eq!(page.items.len(), 30);
    }
}
