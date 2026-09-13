use super::browse::playable;
use rand::seq::SliceRandom;
use siora::model::MusicItem;

#[derive(Clone)]
pub struct Entry {
    pub id: u64,
    pub item: MusicItem,
    pub origin: String,
    pub manual: bool,
}

#[derive(Default)]
pub struct Queue {
    pub entries: Vec<Entry>,
    pub current: Option<u64>,
    pub selected: Option<u64>,
    serial: u64,
    undo: Option<(Vec<Entry>, Option<u64>)>,
}

impl Queue {
    pub fn index(&self, id: Option<u64>) -> Option<usize> {
        id.and_then(|id| self.entries.iter().position(|entry| entry.id == id))
    }

    pub fn current(&self) -> Option<&Entry> {
        self.index(self.current)
            .and_then(|index| self.entries.get(index))
    }

    pub fn selected(&self) -> Option<&Entry> {
        self.index(self.selected)
            .and_then(|index| self.entries.get(index))
    }

    fn entry(&mut self, item: MusicItem, origin: &str, manual: bool) -> Entry {
        self.serial += 1;
        Entry {
            id: self.serial,
            item,
            origin: origin.into(),
            manual,
        }
    }

    pub fn manual_upcoming(&self) -> Vec<Entry> {
        self.entries
            .iter()
            .skip(self.index(self.current).map_or(0, |i| i + 1))
            .filter(|entry| entry.manual)
            .cloned()
            .collect()
    }

    pub fn replace(
        &mut self,
        items: Vec<MusicItem>,
        selected: &str,
        origin: &str,
        keep: bool,
        shuffle: bool,
    ) -> Option<u64> {
        let manual = if keep {
            self.manual_upcoming()
        } else {
            Vec::new()
        };
        let entries = items
            .into_iter()
            .filter(playable)
            .map(|item| self.entry(item, origin, false))
            .collect();
        self.entries = entries;
        let index = self
            .entries
            .iter()
            .position(|entry| entry.item.key() == selected)?;
        self.current = Some(self.entries[index].id);
        if shuffle {
            self.entries[index + 1..].shuffle(&mut rand::rng());
        }
        self.entries.splice(index + 1..index + 1, manual);
        self.selected = self.current;
        self.undo = None;
        self.current
    }

    pub fn add(&mut self, item: MusicItem, next: bool) -> Option<u64> {
        if !playable(&item) {
            return None;
        }
        self.remember();
        let entry = self.entry(item, "Added", true);
        let id = entry.id;
        let index = if next {
            self.index(self.current).map_or(0, |i| i + 1)
        } else {
            self.entries.len()
        };
        self.entries.insert(index, entry);
        self.selected.get_or_insert(id);
        Some(id)
    }

    pub fn append_station(&mut self, items: Vec<MusicItem>, origin: &str) {
        for item in items {
            if playable(&item) {
                let entry = self.entry(item, origin, false);
                self.entries.push(entry);
            }
        }
        if let Some(index) = self.index(self.current)
            && index > 100
        {
            self.entries.drain(..index - 100);
        }
        self.repair_selection();
    }

    pub fn move_cursor(&mut self, delta: isize) {
        if self.entries.is_empty() {
            return;
        }
        let index = self
            .index(self.selected)
            .unwrap_or(0)
            .saturating_add_signed(delta)
            .min(self.entries.len() - 1);
        self.selected = Some(self.entries[index].id);
    }

    pub fn reorder(&mut self, delta: isize) -> bool {
        let Some(index) = self.index(self.selected) else {
            return false;
        };
        let target = index.saturating_add_signed(delta);
        let first = self.index(self.current).map_or(0, |i| i + 1);
        if index < first || target < first || target >= self.entries.len() || target == index {
            return false;
        }
        self.remember();
        self.entries.swap(index, target);
        true
    }

    pub fn remove(&mut self) -> bool {
        let Some(index) = self.index(self.selected) else {
            return false;
        };
        if self.selected == self.current {
            return false;
        }
        self.remember();
        self.entries.remove(index);
        self.selected = self
            .entries
            .get(index.min(self.entries.len().saturating_sub(1)))
            .map(|entry| entry.id);
        true
    }

    pub fn shuffle(&mut self) {
        self.remember();
        let first = self.index(self.current).map_or(0, |i| i + 1);
        self.entries[first..].shuffle(&mut rand::rng());
    }

    pub fn undo(&mut self) -> bool {
        let Some((entries, current)) = self.undo.take() else {
            return false;
        };
        if current != self.current {
            return false;
        }
        self.entries = entries;
        self.repair_selection();
        true
    }

    pub fn next(&self, repeat: &str, automatic: bool) -> Option<u64> {
        let Some(index) = self.index(self.current) else {
            return self.entries.first().map(|entry| entry.id);
        };
        if automatic && repeat == "one" {
            return self.current;
        }
        self.entries
            .get(index + 1)
            .or_else(|| (repeat == "all").then(|| self.entries.first()).flatten())
            .map(|entry| entry.id)
    }

    fn remember(&mut self) {
        self.undo = Some((self.entries.clone(), self.current));
    }

    fn repair_selection(&mut self) {
        if self.index(self.selected).is_none() {
            self.selected = self
                .current
                .or_else(|| self.entries.first().map(|entry| entry.id));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(id: &str) -> MusicItem {
        MusicItem {
            id: id.into(),
            kind: "songs".into(),
            title: id.into(),
            ..Default::default()
        }
    }

    #[test]
    fn duplicate_tracks_have_independent_queue_identity_and_edits() {
        let mut queue = Queue::default();
        let first = queue.add(song("1"), false).unwrap();
        let second = queue.add(song("1"), false).unwrap();
        assert_ne!(first, second);
        queue.current = Some(first);
        queue.selected = Some(second);
        assert!(queue.remove());
        assert_eq!(queue.current, Some(first));
        assert!(queue.undo());
        assert_eq!(queue.entries.len(), 2);
        queue.selected = queue.current;
        assert!(!queue.remove());
    }

    #[test]
    fn replace_preserves_manual_entries_and_actual_next_order() {
        let mut queue = Queue::default();
        queue.replace(vec![song("1"), song("2")], "songs:1", "Album", false, false);
        let manual = queue.add(song("3"), true).unwrap();
        assert_eq!(queue.next("off", false), Some(manual));
        queue.replace(
            vec![song("4"), song("5")],
            "songs:4",
            "New album",
            true,
            false,
        );
        assert_eq!(queue.next("off", false), Some(manual));
        assert_eq!(
            queue
                .entries
                .iter()
                .map(|entry| entry.item.id.as_str())
                .collect::<Vec<_>>(),
            ["4", "3", "5"]
        );
        queue.selected = Some(manual);
        assert!(queue.reorder(1));
        assert_eq!(queue.next("off", false), Some(queue.entries[1].id));
        assert!(!queue.reorder(-2));
    }

    #[test]
    fn automatic_advance_keeps_cursor_and_invalidates_old_undo() {
        let mut queue = Queue::default();
        queue.replace(vec![song("1"), song("2")], "songs:1", "Album", false, false);
        queue.add(song("3"), false);
        let cursor = queue.selected;
        let next = queue.next("off", true);
        assert_eq!(queue.next("one", true), queue.current);
        queue.current = next;
        assert_eq!(queue.selected, cursor);
        assert!(!queue.undo());
    }
}
