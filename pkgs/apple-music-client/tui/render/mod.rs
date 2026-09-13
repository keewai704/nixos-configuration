mod browser;
mod dialogs;
mod panels;
mod player_bar;

use super::*;
use browse::{clean, clock};
use mouse::{Action as MouseAction, Pane as MousePane};
use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span, Text},
    widgets::{
        Block, Borders, Cell, Clear, LineGauge, List, ListItem, Paragraph, Row, Table, Wrap,
    },
};
use ratatui_image::StatefulImage;
use unicode_width::UnicodeWidthStr;

const ACCENT: Color = Color::Cyan;

pub(super) fn draw(frame: &mut Frame, app: &mut App) {
    app.mouse.clear();
    let area = frame.area();
    if area.width < 30 || area.height < 10 {
        frame.render_widget(
            Paragraph::new("Siora · enlarge terminal\nCtrl+c to quit"),
            area,
        );
        return;
    }
    let layout = Layout::vertical([
        Constraint::Length(1),
        Constraint::Min(1),
        Constraint::Length(4),
        Constraint::Length(2),
        Constraint::Length(1),
    ])
    .split(area);
    let header = Layout::horizontal([Constraint::Min(1), Constraint::Length(44)]).split(layout[0]);
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(
                " Siora  ",
                Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
            ),
            Span::raw(clean(&app.page.title)),
            Span::styled(
                format!("  [{}]", clean(&app.account)),
                Style::default().fg(Color::Yellow),
            ),
        ])),
        header[0],
    );
    buttons(
        frame,
        &mut app.mouse,
        header[1],
        vec![
            ("<".into(), MouseAction::Key(KeyCode::Backspace)),
            ("Browse".into(), MouseAction::Navigation),
            ("Search".into(), MouseAction::Search),
            ("Settings".into(), MouseAction::Key(KeyCode::Char(','))),
            ("?".into(), MouseAction::Key(KeyCode::Char('?'))),
            ("Quit".into(), MouseAction::Quit),
        ],
    );
    let body = layout[1];
    if area.width >= 140 {
        let panels = Layout::horizontal([
            Constraint::Length(18),
            Constraint::Min(40),
            Constraint::Length(if app.panel.is_some() { 38 } else { 0 }),
        ])
        .split(body);
        browser::navigation(frame, app, panels[0]);
        browser::draw(frame, app, panels[1]);
        if app.panel.is_some() {
            panels::draw(frame, app, panels[2]);
        }
    } else if area.width >= 100 {
        let panels = Layout::horizontal([Constraint::Length(18), Constraint::Min(1)]).split(body);
        browser::navigation(frame, app, panels[0]);
        if app.focus == Focus::Panel && app.panel.is_some() {
            panels::draw(frame, app, panels[1]);
        } else {
            browser::draw(frame, app, panels[1]);
        }
    } else {
        match app.focus {
            Focus::Navigation => browser::navigation(frame, app, body),
            Focus::Panel if app.panel.is_some() => panels::draw(frame, app, body),
            _ => browser::draw(frame, app, body),
        }
    }
    player_bar::draw(frame, app, layout[2]);
    frame.render_widget(
        Paragraph::new(clean(&app.status))
            .style(Style::default().fg(Color::Yellow))
            .wrap(Wrap { trim: false }),
        layout[3],
    );
    let hint = if app.focus == Focus::Panel && app.panel == Some(Panel::Queue) {
        "Enter Play · d Delete · J/K Move · u Undo · q Close · Tab Focus"
    } else if app.focus == Focus::Navigation {
        "↑↓ Move · Enter Open · Tab Focus · Ctrl+f Search · ? Help"
    } else {
        "Click Select · Double-click Open/play · Right-click Actions · ? Help"
    };
    frame.render_widget(
        Paragraph::new(hint).style(Style::default().fg(ACCENT)),
        layout[4],
    );
    dialogs::draw(frame, app, body);
    if let Some(input) = &app.input {
        app.mouse.clear();
        dialogs::input_box(frame, input, body, &mut app.mouse);
    }
}

fn buttons(
    frame: &mut Frame,
    mouse: &mut mouse::Mouse,
    area: Rect,
    items: Vec<(String, MouseAction)>,
) -> u16 {
    let mut x = area.x;
    let mut spans = Vec::new();
    for (label, action) in items {
        let label = format!("[{label}]");
        let width = label.width() as u16;
        if x.saturating_add(width) <= area.right() {
            mouse.hit(Rect::new(x, area.y, width, 1), action);
        }
        spans.push(Span::styled(
            label,
            Style::default()
                .fg(ACCENT)
                .add_modifier(Modifier::UNDERLINED),
        ));
        spans.push(Span::raw(" "));
        x = x.saturating_add(width + 1);
    }
    frame.render_widget(Paragraph::new(Line::from(spans)), area);
    x.min(area.right())
}

fn block(title: impl Into<Line<'static>>, active: bool) -> Block<'static> {
    Block::default()
        .borders(Borders::ALL)
        .title(title)
        .border_style(Style::default().fg(if active { ACCENT } else { Color::DarkGray }))
}

fn highlight() -> Style {
    Style::default().add_modifier(Modifier::REVERSED)
}

fn draw_cover(frame: &mut Frame, cover: &mut cover::Slot, area: Rect) {
    if area.is_empty() {
        return;
    }
    if let Some(image) = &mut cover.image {
        frame.render_stateful_widget(StatefulImage::default(), area, image);
        cover.check_encoding();
    } else {
        frame.render_widget(
            Paragraph::new(cover.message)
                .style(Style::default().fg(Color::DarkGray))
                .wrap(Wrap { trim: false }),
            area,
        );
    }
}

pub(super) fn item_details(item: &MusicItem) -> String {
    format!(
        "Title: {}\nArtist: {}\nAlbum: {}\nType: {}\nDuration: {}\nGenre: {}\nCatalog formats: {}\nExplicit: {}\n{}",
        clean(&item.title),
        clean(&item.artist),
        clean(&item.album),
        clean(&item.kind),
        clock(item.duration),
        clean(&item.genre),
        clean(&item.audio_variants.join(", ")),
        item.explicit,
        clean(
            item.url
                .as_deref()
                .unwrap_or("No Apple Music link available")
        )
    )
}

fn source_text(source: &Value) -> String {
    if source["live"] == true {
        return "LIVE · broadcaster quality".into();
    }
    let Some(codec) = source["codec"].as_str() else {
        return "Measured source: unknown".into();
    };
    let rate = source["sample_rate"].as_u64().unwrap_or(0);
    let bits = source["bits"].as_u64().unwrap_or(0);
    let mut fields = vec![clean(codec)];
    if source["atmos"] == true {
        fields.push("Atmos".into());
    }
    if bits > 0 {
        fields.push(format!("{bits} bit"));
    }
    if rate > 0 {
        fields.push(format!("{:.1} kHz", rate as f64 / 1000.));
    }
    fields.join(" · ")
}

fn lyric_lines(lyrics: &str) -> Vec<(Option<f64>, String)> {
    let mut result = Vec::new();
    for line in lyrics.lines() {
        let mut rest = line;
        let mut times = Vec::new();
        while let Some(value) = rest.strip_prefix('[') {
            let Some((stamp, remaining)) = value.split_once(']') else {
                break;
            };
            if let Some((minutes, seconds)) = stamp.split_once(':')
                && let (Ok(minutes), Ok(seconds)) = (minutes.parse::<u32>(), seconds.parse::<f64>())
                && seconds.is_finite()
                && (0.0..60.0).contains(&seconds)
            {
                times.push(minutes as f64 * 60. + seconds);
            }
            rest = remaining;
        }
        if rest.is_empty() {
            continue;
        }
        if times.is_empty() {
            result.push((None, rest.into()));
        } else {
            result.extend(times.into_iter().map(|time| (Some(time), rest.into())));
        }
    }
    if result.iter().all(|(time, _)| time.is_some()) {
        result.sort_by(|left, right| left.0.unwrap().total_cmp(&right.0.unwrap()));
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::{Terminal, backend::TestBackend};

    #[test]
    fn layouts_keep_player_and_essential_controls_at_80_columns() -> Result<()> {
        let root = tempfile::tempdir()?;
        let store = LibraryStore::open(root.path().join("apple-music.json"))?;
        let mut app = App::new(
            store,
            root.path().join("downloads"),
            true,
            cover::Graphics::text((10, 20)),
        );
        app.page = Page::new(
            "日本語 Album",
            vec![MusicItem {
                id: "1".into(),
                kind: "songs".into(),
                title: "夜に駆ける".into(),
                artist: "YOASOBI".into(),
                ..Default::default()
            }],
        );
        for (width, height) in [(80, 24), (110, 30), (160, 40), (40, 12)] {
            let mut terminal = Terminal::new(TestBackend::new(width, height))?;
            for focus in [Focus::Browse, Focus::Navigation, Focus::Panel] {
                app.focus = focus;
                app.panel = Some(Panel::Queue);
                terminal.draw(|frame| draw(frame, &mut app))?;
                let content: String = terminal
                    .backend()
                    .buffer()
                    .content
                    .iter()
                    .map(|cell| cell.symbol())
                    .collect();
                assert!(content.contains("Nothing playing"));
                assert!(content.contains("Volume"));
                assert!(!content.contains("secret"));
            }
        }
        Ok(())
    }

    #[test]
    fn password_never_appears_in_rendered_buffer() -> Result<()> {
        let root = tempfile::tempdir()?;
        let mut app = App::new(
            LibraryStore::open(root.path().join("state.json"))?,
            root.path().join("downloads"),
            true,
            cover::Graphics::text((10, 20)),
        );
        app.input = Some(Input::new(
            InputKind::Password("name".into()),
            "secret-password".into(),
        ));
        let mut terminal = Terminal::new(TestBackend::new(80, 24))?;
        terminal.draw(|frame| draw(frame, &mut app))?;
        let content: String = terminal
            .backend()
            .buffer()
            .content
            .iter()
            .map(|cell| cell.symbol())
            .collect();
        assert!(!content.contains("secret-password"));
        assert!(content.contains("••••"));
        Ok(())
    }

    #[test]
    fn lyrics_use_real_timestamps_and_never_claim_requested_quality() {
        let lines = lyric_lines("[ar:Name]\n[00:02.00][00:20.50]line\n[00:10.00]second");
        assert_eq!(
            lines,
            [
                (Some(2.), "line".into()),
                (Some(10.), "second".into()),
                (Some(20.5), "line".into())
            ]
        );
        assert_eq!(source_text(&Value::Null), "Measured source: unknown");
        assert!(source_text(&json!({"codec":"aac","sample_rate":44100})).contains("aac"));
    }
}
