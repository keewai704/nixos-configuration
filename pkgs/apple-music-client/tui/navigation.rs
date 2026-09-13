use super::browse::{self, Page, api_page, playable, public_page};
use super::{App, Focus, Job, Panel};
use anyhow::{Context, Result, bail};
use siora::model::MusicItem;

impl App {
    pub(super) fn fetch(
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

    pub(super) fn show_page(&mut self, page: Page) {
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

    pub(super) fn back(&mut self) {
        self.request += 1;
        self.pending_page = None;
        if let Some(page) = self.history.pop() {
            self.page = page;
        }
        self.focus = Focus::Browse;
    }

    pub(super) fn navigate(&mut self, index: usize) -> Result<()> {
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

    pub(super) fn search(&mut self, term: String, library: bool) -> Result<()> {
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

    pub(super) fn open_url(&mut self, url: String) -> Result<()> {
        let url = browse::validate_url(&url)?;
        let storefront = self.store.data.preferences.storefront.clone();
        self.fetch(false, move || public_page(&url, &storefront))
    }

    pub(super) fn open_item(&mut self, item: MusicItem) -> Result<()> {
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

    pub(super) fn load_more(&mut self) -> Result<()> {
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

    pub(super) fn selected_item(&self) -> Result<MusicItem> {
        if self.focus == Focus::Panel && self.panel == Some(Panel::Queue) {
            self.queue.selected().map(|entry| entry.item.clone())
        } else {
            self.page.item().cloned()
        }
        .context("Select an item first")
    }
}
