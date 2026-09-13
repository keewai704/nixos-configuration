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
        navigation(frame, app, panels[0]);
        browse(frame, app, panels[1]);
        if app.panel.is_some() {
            panel(frame, app, panels[2]);
        }
    } else if area.width >= 100 {
        let panels = Layout::horizontal([Constraint::Length(18), Constraint::Min(1)]).split(body);
        navigation(frame, app, panels[0]);
        if app.focus == Focus::Panel && app.panel.is_some() {
            panel(frame, app, panels[1]);
        } else {
            browse(frame, app, panels[1]);
        }
    } else {
        match app.focus {
            Focus::Navigation => navigation(frame, app, body),
            Focus::Panel if app.panel.is_some() => panel(frame, app, body),
            _ => browse(frame, app, body),
        }
    }
    player(frame, app, layout[2]);
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
    overlay(frame, app, body);
    if let Some(input) = &app.input {
        app.mouse.clear();
        input_box(frame, input, body, &mut app.mouse);
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

fn navigation(frame: &mut Frame, app: &mut App, area: Rect) {
    let items = browse::NAV.iter().map(|(name, _)| ListItem::new(*name));
    frame.render_stateful_widget(
        List::new(items)
            .block(block("Browse", app.focus == Focus::Navigation))
            .highlight_style(highlight())
            .highlight_symbol("› "),
        area,
        &mut app.nav,
    );
    let inner = block("", false).inner(area);
    app.mouse.pane(inner, MousePane::Navigation);
    for index in app.nav.offset()..browse::NAV.len() {
        let row = index - app.nav.offset();
        if row >= inner.height as usize {
            break;
        }
        app.mouse.hit(
            Rect::new(inner.x, inner.y + row as u16, inner.width, 1),
            MouseAction::Navigate(index),
        );
    }
}

fn browse(frame: &mut Frame, app: &mut App, area: Rect) {
    let area = selected_cover(frame, app, area);
    let rows = Layout::vertical([Constraint::Length(1), Constraint::Min(1)]).split(area);
    buttons(
        frame,
        &mut app.mouse,
        rows[0],
        vec![
            ("Type".into(), MouseAction::Selected(KeyCode::Char('t'))),
            ("Sort".into(), MouseAction::Selected(KeyCode::Char('o'))),
            ("Filter".into(), MouseAction::Selected(KeyCode::Char('/'))),
            ("More".into(), MouseAction::Selected(KeyCode::Char('m'))),
        ],
    );
    let area = rows[1];
    let loading = if app.pending_page.is_some() {
        " · loading…"
    } else {
        ""
    };
    let title = format!(
        " {} · {}/{} loaded · {}{} ",
        browse::KINDS[app.page.kind],
        app.page.visible.len(),
        app.page.items.len(),
        ["original", "title", "artist", "album"][app.page.sort],
        loading
    );
    let mut outer = block(title, app.focus == Focus::Browse);
    if !app.page.filter.is_empty() {
        outer = outer.title_bottom(format!(
            " / {} · loaded items only ",
            clean(&app.page.filter)
        ));
    }
    if app.page.visible.is_empty() {
        frame.render_widget(Paragraph::new(if app.pending_page.is_some() { "Loading…" }
            else if !app.page.filter.is_empty() { "No loaded items match this filter. / edits the filter." }
            else { "No items. Ctrl+f searches Apple Music.\nTab opens navigation; :login connects your library." })
            .block(outer).wrap(Wrap { trim: false }), area);
        app.mouse.pane(area, MousePane::Browse(1));
        return;
    }
    let current = app.queue.current().map(|entry| entry.item.key());
    let compact = area.width < 60;
    let album_column = area.width >= 95 && !app.page.album;
    let rows = app
        .page
        .visible
        .iter()
        .map(|&index| {
            let item = &app.page.items[index];
            let playing = current.as_ref().is_some_and(|key| *key == item.key())
                && (app.loaded || app.preparing);
            let mark = if playing {
                "▶"
            } else if app.store.data.favorites.contains(&item.key()) {
                "♥"
            } else {
                ""
            };
            let label = if item.kind == "stations" {
                "LIVE".into()
            } else if playable(item) && item.duration > 0. {
                clock(item.duration)
            } else if playable(item) {
                "—".into()
            } else {
                item.kind.trim_start_matches("library-").into()
            };
            let title = if compact {
                format!("{}\n{}", clean(&item.title), clean(&item.artist))
            } else {
                clean(&item.title)
            };
            let mut cells = vec![Cell::from(mark), Cell::from(title)];
            if !compact {
                cells.push(Cell::from(clean(&item.artist)));
            }
            if album_column {
                cells.push(Cell::from(clean(&item.album)));
            }
            cells.push(Cell::from(label));
            Row::new(cells)
                .height(if compact { 2 } else { 1 })
                .style(if playing {
                    Style::default().fg(ACCENT)
                } else {
                    Style::default()
                })
        })
        .collect::<Vec<_>>();
    let mut widths = vec![Constraint::Length(2), Constraint::Min(12)];
    let mut titles = vec!["", "Title"];
    if !compact {
        widths.push(Constraint::Percentage(26));
        titles.push("Artist");
    }
    if album_column {
        widths.push(Constraint::Percentage(22));
        titles.push("Album");
    }
    widths.push(Constraint::Length(9));
    titles.push("Time/type");
    let table = Table::new(rows, widths)
        .header(Row::new(titles).style(Style::default().fg(Color::DarkGray)))
        .block(outer)
        .row_highlight_style(highlight())
        .highlight_symbol("› ");
    frame.render_stateful_widget(table, area, &mut app.page.table);
    let inner = block("", false).inner(area);
    let height = if compact { 2 } else { 1 };
    let count = inner.height.saturating_sub(1) / height;
    app.mouse
        .pane(inner, MousePane::Browse(usize::from(count.max(1))));
    for (row, &index) in app
        .page
        .visible
        .iter()
        .skip(app.page.table.offset())
        .take(count as usize)
        .enumerate()
    {
        app.mouse.hit(
            Rect::new(
                inner.x,
                inner.y + 1 + row as u16 * height,
                inner.width,
                height,
            ),
            MouseAction::BrowseRow(app.page.items[index].key()),
        );
    }
}

fn selected_cover(frame: &mut Frame, app: &mut App, area: Rect) -> Rect {
    let Some(item) = app.page.item() else {
        return area;
    };
    if area.height < 15 {
        return area;
    }
    let sections = Layout::vertical([Constraint::Length(7), Constraint::Min(1)]).split(area);
    let border = block("Selected", app.focus == Focus::Browse);
    let inner = border.inner(sections[0]);
    let image_area = app.covers.square(inner, inner.height);
    let text_area = Rect::new(
        inner.x + image_area.width + 2,
        inner.y,
        inner.width.saturating_sub(image_area.width + 2),
        inner.height,
    );
    let details = vec![
        Line::styled(
            clean(&item.title),
            Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
        ),
        Line::raw(clean(&item.artist)),
        Line::raw(clean(&item.album)),
        Line::styled(
            clean(item.kind.trim_start_matches("library-")),
            Style::default().fg(Color::DarkGray),
        ),
    ];
    frame.render_widget(border, sections[0]);
    frame.render_widget(Paragraph::new(details), text_area);
    if text_area.height > 0 {
        buttons(
            frame,
            &mut app.mouse,
            Rect::new(text_area.x, text_area.bottom() - 1, text_area.width, 1),
            vec![
                (
                    if playable(item) { "Play" } else { "Open" }.into(),
                    MouseAction::Selected(KeyCode::Enter),
                ),
                ("Next".into(), MouseAction::Selected(KeyCode::Char('E'))),
                ("Add".into(), MouseAction::Selected(KeyCode::Char('e'))),
                ("Actions".into(), MouseAction::Selected(KeyCode::Char('a'))),
            ],
        );
    }
    if app.overlay.is_none() && app.input.is_none() {
        draw_cover(frame, &mut app.covers.selected, image_area);
    }
    sections[1]
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

fn panel(frame: &mut Frame, app: &mut App, area: Rect) {
    match app.panel {
        Some(Panel::Queue) => {
            let items = app
                .queue
                .entries
                .iter()
                .map(|entry| {
                    let current = Some(entry.id) == app.queue.current;
                    ListItem::new(vec![
                        Line::from(format!(
                            "{} {}",
                            if current { "▶" } else { " " },
                            clean(&entry.item.title)
                        )),
                        Line::styled(
                            format!(
                                "  {} · {}",
                                clean(&entry.item.artist),
                                if entry.manual {
                                    "Added".into()
                                } else {
                                    clean(&entry.origin)
                                }
                            ),
                            Style::default().fg(Color::DarkGray),
                        ),
                    ])
                    .style(if current {
                        Style::default().fg(ACCENT)
                    } else {
                        Style::default()
                    })
                })
                .collect::<Vec<_>>();
            app.queue_list.select(app.queue.index(app.queue.selected));
            let title = format!(
                " Queue · {} · Autoplay {} ",
                items.len(),
                if app.station.is_some() {
                    "station"
                } else {
                    "off"
                }
            );
            let border = block(title, app.focus == Focus::Panel);
            let inner = border.inner(area);
            frame.render_widget(border, area);
            buttons(
                frame,
                &mut app.mouse,
                Rect::new(inner.x, inner.y, inner.width, 1),
                vec![
                    ("Up".into(), MouseAction::QueueMove(-1)),
                    ("Down".into(), MouseAction::QueueMove(1)),
                    ("Remove".into(), MouseAction::QueueRemove),
                    ("Undo".into(), MouseAction::QueueUndo),
                ],
            );
            let list_area = Rect::new(
                inner.x,
                inner.y + 1,
                inner.width,
                inner.height.saturating_sub(1),
            );
            frame.render_stateful_widget(
                List::new(items)
                    .highlight_style(highlight())
                    .highlight_symbol("› "),
                list_area,
                &mut app.queue_list,
            );
            let rows = (list_area.height / 2).max(1);
            app.mouse.pane(list_area, MousePane::Queue(rows as usize));
            for (row, entry) in app
                .queue
                .entries
                .iter()
                .skip(app.queue_list.offset())
                .take(rows as usize)
                .enumerate()
            {
                app.mouse.hit(
                    Rect::new(
                        list_area.x,
                        list_area.y + row as u16 * 2,
                        list_area.width,
                        2,
                    ),
                    MouseAction::QueueRow(entry.id),
                );
            }
        }
        Some(Panel::Lyrics) => {
            app.mouse.pane(area, MousePane::Text);
            let name = app
                .queue
                .current()
                .map(|entry| clean(&entry.item.title))
                .unwrap_or_default();
            let position = app.snapshot["position"].as_f64().unwrap_or(0.);
            let lines = lyric_lines(&app.lyrics);
            let active = lines
                .iter()
                .enumerate()
                .filter(|(_, (time, _))| time.is_some_and(|time| time <= position))
                .map(|(index, _)| index)
                .next_back();
            let text = if lines.is_empty() {
                Text::raw("No Apple Music lyrics available for this track.")
            } else {
                Text::from(
                    lines
                        .iter()
                        .enumerate()
                        .map(|(index, (_, line))| {
                            Line::styled(
                                clean(line),
                                if Some(index) == active {
                                    Style::default().fg(ACCENT).add_modifier(Modifier::BOLD)
                                } else {
                                    Style::default()
                                },
                            )
                        })
                        .collect::<Vec<_>>(),
                )
            };
            let offset = if app.panel_scroll == 0 {
                active.unwrap_or(0).saturating_sub(4).min(u16::MAX as usize) as u16
            } else {
                app.panel_scroll
            };
            frame.render_widget(
                Paragraph::new(text)
                    .block(block(
                        format!(" Lyrics · playing: {name} · Apple Music "),
                        app.focus == Focus::Panel,
                    ))
                    .scroll((offset, 0))
                    .wrap(Wrap { trim: false }),
                area,
            );
        }
        Some(Panel::Details) => {
            app.mouse.pane(area, MousePane::Text);
            let item = app.page.item();
            let mut details = item
                .map(item_details)
                .unwrap_or_else(|| "Select an item in the browser".into());
            details.push_str(&format!(
                "\n\nNow playing · {}\nRequested: {}\nMeasured source: {}\nOutput: {}\nDevice: {}",
                app.queue
                    .current()
                    .map(|entry| clean(&entry.item.title))
                    .unwrap_or_else(|| "none".into()),
                app.store.data.preferences.quality,
                source_text(&app.source),
                clean(&app.snapshot["output"].to_string()),
                clean(app.snapshot["device"].as_str().unwrap_or("unknown"))
            ));
            frame.render_widget(
                Paragraph::new(details)
                    .block(block("Selected item details", app.focus == Focus::Panel))
                    .scroll((app.panel_scroll, 0))
                    .wrap(Wrap { trim: false }),
                area,
            );
        }
        None => {}
    }
    if area.width >= 4 {
        buttons(
            frame,
            &mut app.mouse,
            Rect::new(area.right() - 3, area.y, 3, 1),
            vec![("x".into(), MouseAction::Key(KeyCode::Esc))],
        );
    }
}

fn player(frame: &mut Frame, app: &mut App, area: Rect) {
    let area = if app.queue.current().is_some() && area.width >= 60 {
        let cover_area = app.covers.square(area, 4);
        draw_cover(frame, &mut app.covers.playing, cover_area);
        Rect::new(
            area.x + cover_area.width + 2,
            area.y,
            area.width.saturating_sub(cover_area.width + 2),
            area.height,
        )
    } else {
        area
    };
    let rows = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Length(1),
    ])
    .split(area);
    let title = app
        .queue
        .current()
        .map(|entry| {
            format!(
                "{} — {}",
                clean(&entry.item.title),
                clean(&entry.item.artist)
            )
        })
        .unwrap_or_else(|| "Nothing playing".into());
    let state = if app.preparing {
        "Preparing"
    } else if !app.loaded {
        "Stopped"
    } else if app.snapshot["paused"] == true {
        "Paused"
    } else {
        "Playing"
    };
    frame.render_widget(
        Paragraph::new(format!("{state}: {title}")).style(Style::default().fg(ACCENT)),
        rows[0],
    );
    let duration = app.snapshot["duration"].as_f64().unwrap_or(0.);
    let position = app.snapshot["position"].as_f64().unwrap_or(0.);
    let ratio = if duration > 0. && duration.is_finite() && position.is_finite() {
        (position / duration).clamp(0., 1.)
    } else {
        0.
    };
    let label = if app.is_radio() {
        "LIVE".into()
    } else {
        format!("{} / {}", clock(position), clock(duration))
    };
    let label_width = label.width() as u16;
    frame.render_widget(
        LineGauge::default()
            .ratio(ratio)
            .label(label)
            .filled_style(Style::default().fg(ACCENT)),
        rows[1],
    );
    if app.loaded
        && !app.is_radio()
        && duration > 0.
        && let Some(track) = app.queue.current
    {
        app.mouse.hit(
            Rect::new(
                rows[1].x + label_width + 1,
                rows[1].y,
                rows[1].width.saturating_sub(label_width + 1),
                1,
            ),
            MouseAction::Seek(track),
        );
    }
    let x = buttons(
        frame,
        &mut app.mouse,
        rows[2],
        vec![
            ("-".into(), MouseAction::Key(KeyCode::Char('-'))),
            (
                format!("Volume {:.0}%", app.store.data.preferences.volume),
                MouseAction::Volume,
            ),
            ("+".into(), MouseAction::Key(KeyCode::Char('+'))),
            (
                format!(
                    "Shuffle {}",
                    if app.store.data.preferences.shuffle {
                        "ON"
                    } else {
                        "OFF"
                    }
                ),
                MouseAction::Key(KeyCode::Char('s')),
            ),
            (
                format!("Repeat {}", app.store.data.preferences.repeat),
                MouseAction::Key(KeyCode::Char('r')),
            ),
        ],
    );
    frame.render_widget(
        Paragraph::new(source_text(&app.source)),
        Rect::new(x, rows[2].y, rows[2].right().saturating_sub(x), 1),
    );
    buttons(
        frame,
        &mut app.mouse,
        rows[3],
        vec![
            ("Prev".into(), MouseAction::Key(KeyCode::Char('p'))),
            (
                if app.loaded && app.snapshot["paused"] != true {
                    "Pause"
                } else {
                    "Play"
                }
                .into(),
                MouseAction::Key(KeyCode::Char(' ')),
            ),
            ("Next".into(), MouseAction::Key(KeyCode::Char('n'))),
            ("Stop".into(), MouseAction::Stop),
            ("Queue".into(), MouseAction::Key(KeyCode::Char('q'))),
            ("Lyrics".into(), MouseAction::Key(KeyCode::Char('l'))),
        ],
    );
}

fn popup(area: Rect, width: u16, height: u16) -> Rect {
    let width = width.min(area.width);
    let height = height.min(area.height);
    Rect::new(
        area.x + (area.width - width) / 2,
        area.y + (area.height - height) / 2,
        width,
        height,
    )
}

fn overlay(frame: &mut Frame, app: &mut App, body: Rect) {
    let Some(overlay) = &mut app.overlay else {
        return;
    };
    app.mouse.clear();
    let area = popup(body, 90, body.height);
    frame.render_widget(Clear, area);
    match overlay {
        Overlay::Help => {
            let mut lines = vec![Line::styled("Keys", Style::default().fg(ACCENT))];
            lines.extend(
                controls::BINDINGS
                    .iter()
                    .map(|(key, description)| Line::raw(format!("{key:18} {description}"))),
            );
            lines.push(Line::raw(""));
            lines.push(Line::styled("Commands (:)", Style::default().fg(ACCENT)));
            lines.extend(controls::COMMANDS.iter().map(|command| Line::raw(*command)));
            frame.render_widget(
                Paragraph::new(lines)
                    .block(block("Help · ↑↓ Scroll · Esc Close", true))
                    .scroll((app.panel_scroll, 0)),
                area,
            );
        }
        Overlay::Actions(item, _, state) => {
            menu(
                frame,
                &mut app.mouse,
                controls::ACTIONS.iter().map(|s| (*s).into()).collect(),
                format!("Actions · {}", clean(&item.title)),
                state,
                area,
            );
        }
        Overlay::Settings(state) => {
            let prefs = &app.store.data.preferences;
            let values = [
                "".into(),
                "".into(),
                "".into(),
                prefs.quality.clone(),
                prefs.device.clone(),
                prefs.crossfade_seconds.to_string(),
                if prefs.passthrough { "on" } else { "off" }.into(),
                if prefs.eq_enabled { "on" } else { "off" }.into(),
                prefs.cache_limit_mb.to_string(),
                prefs.storefront.clone(),
            ];
            menu(
                frame,
                &mut app.mouse,
                controls::SETTINGS
                    .iter()
                    .zip(values)
                    .map(|(name, value)| format!("{name}  {value}"))
                    .collect(),
                format!("Settings · {}", clean(&app.account)),
                state,
                area,
            );
        }
        Overlay::Replace(_, _, _, state) => menu(
            frame,
            &mut app.mouse,
            vec![
                "Keep manual additions".into(),
                "Replace queue including manual additions".into(),
                "Cancel".into(),
            ],
            "Start another selection?".into(),
            state,
            area,
        ),
        Overlay::RemoveDownload(item, state) => menu(
            frame,
            &mut app.mouse,
            vec!["Cancel".into(), "Remove cached download".into()],
            format!("Remove download · {}", clean(&item.title)),
            state,
            area,
        ),
        Overlay::Devices(devices, state) => menu(
            frame,
            &mut app.mouse,
            devices
                .iter()
                .map(|value| {
                    format!(
                        "{} · {}",
                        clean(value["name"].as_str().unwrap_or("")),
                        clean(value["description"].as_str().unwrap_or(""))
                    )
                })
                .collect(),
            "Output device · Enter Select".into(),
            state,
            area,
        ),
        Overlay::Playlists(item, page) => {
            let rows = page
                .visible
                .iter()
                .map(|&index| Row::new([clean(&page.items[index].title)]));
            frame.render_stateful_widget(
                Table::new(rows, [Constraint::Min(1)])
                    .block(block(
                        format!("Add {} to playlist", clean(&item.title)),
                        true,
                    ))
                    .row_highlight_style(highlight()),
                area,
                &mut page.table,
            );
            let inner = block("", false).inner(area);
            for index in page.table.offset()..page.visible.len() {
                let row = index - page.table.offset();
                if row >= inner.height as usize {
                    break;
                }
                app.mouse.hit(
                    Rect::new(inner.x, inner.y + row as u16, inner.width, 1),
                    MouseAction::MenuRow(index),
                );
            }
        }
        Overlay::Text(title, text) => frame.render_widget(
            Paragraph::new(
                text.lines()
                    .map(|line| Line::raw(clean(line)))
                    .collect::<Vec<_>>(),
            )
            .block(block(clean(title), true))
            .scroll((app.panel_scroll, 0))
            .wrap(Wrap { trim: false }),
            area,
        ),
    }
    buttons(
        frame,
        &mut app.mouse,
        Rect::new(area.right().saturating_sub(3), area.y, 3, 1),
        vec![("x".into(), MouseAction::Key(KeyCode::Esc))],
    );
}
fn menu(
    frame: &mut Frame,
    mouse: &mut mouse::Mouse,
    items: Vec<String>,
    title: String,
    state: &mut ListState,
    area: Rect,
) {
    let count = items.len();
    frame.render_stateful_widget(
        List::new(items.into_iter().map(ListItem::new))
            .block(block(format!("{title} · Esc Close"), true))
            .highlight_style(highlight())
            .highlight_symbol("› "),
        area,
        state,
    );
    let inner = block("", false).inner(area);
    for index in state.offset()..count {
        let row = index - state.offset();
        if row >= inner.height as usize {
            break;
        }
        mouse.hit(
            Rect::new(inner.x, inner.y + row as u16, inner.width, 1),
            MouseAction::MenuRow(index),
        );
    }
}

fn input_box(frame: &mut Frame, input: &Input, body: Rect, mouse: &mut mouse::Mouse) {
    let (title, hint) = match &input.kind {
        InputKind::Search(library) => (
            format!(
                "Search · {} [switch scope]",
                if *library {
                    "My Library"
                } else {
                    "Apple Music"
                }
            ),
            "Ctrl+l Scope · Enter Search · Esc Cancel",
        ),
        InputKind::Filter(_) => (
            "Filter loaded items".into(),
            "Enter Keep · Esc Restore · queue is unchanged",
        ),
        InputKind::Command => ("Command".into(), "Enter Run · Esc Cancel"),
        InputKind::Username => ("Apple ID".into(), "Enter Continue · Esc Cancel"),
        InputKind::Password(_) => (
            "Password".into(),
            "Hidden; never saved by Siora · Enter Sign in · Esc Cancel",
        ),
        InputKind::Code => ("Two-factor code".into(), "Enter Verify · Esc Cancel"),
        InputKind::Setting(name) => (
            format!("Set {name}"),
            "Enter Save · Esc Cancel · ? lists commands",
        ),
        InputKind::PlaylistName(queue) => (
            if *queue {
                "Save queue as playlist"
            } else {
                "Create playlist"
            }
            .into(),
            "Enter Create · Esc Cancel",
        ),
    };
    let is_command = matches!(input.kind, InputKind::Command);
    let area = popup(body, 86, if is_command { body.height.min(16) } else { 5 });
    frame.render_widget(Clear, area);
    let outer = block(title, true).title_bottom(hint);
    let inner = outer.inner(area);
    frame.render_widget(outer, area);
    if matches!(input.kind, InputKind::Search(_)) {
        mouse.hit(
            Rect::new(area.x, area.y, area.width.saturating_sub(3), 1),
            MouseAction::SearchScope,
        );
    }
    buttons(
        frame,
        mouse,
        Rect::new(area.right().saturating_sub(3), area.y, 3, 1),
        vec![("x".into(), MouseAction::Key(KeyCode::Esc))],
    );
    if inner.width == 0 || inner.height == 0 {
        return;
    }
    let text = if input.masked() {
        "•".repeat(input.text.chars().count())
    } else {
        clean(&input.text)
    };
    let cursor_width = if input.masked() {
        input.text[..input.cursor].chars().count()
    } else {
        input.text[..input.cursor].width()
    };
    let offset = cursor_width
        .saturating_sub(inner.width.saturating_sub(1) as usize)
        .min(u16::MAX as usize) as u16;
    frame.render_widget(
        Paragraph::new(text).scroll((0, offset)),
        Rect::new(inner.x, inner.y, inner.width, 1),
    );
    mouse.hit(
        Rect::new(inner.x, inner.y, inner.width, 1),
        MouseAction::Caret(offset),
    );
    frame.set_cursor_position((
        inner.x + (cursor_width.saturating_sub(offset as usize) as u16).min(inner.width - 1),
        inner.y,
    ));
    if is_command && inner.height > 2 {
        let prefix = input.text.trim();
        let lines: Vec<_> = controls::COMMANDS
            .iter()
            .filter(|command| command.starts_with(prefix))
            .map(|command| Line::raw(*command))
            .collect();
        frame.render_widget(
            Paragraph::new(lines).style(Style::default().fg(Color::DarkGray)),
            Rect::new(
                inner.x,
                inner.y + 2,
                inner.width,
                inner.height.saturating_sub(3),
            ),
        );
    }
    if inner.height > 1 {
        buttons(
            frame,
            mouse,
            Rect::new(inner.x, inner.bottom() - 1, inner.width, 1),
            vec![
                ("OK".into(), MouseAction::Key(KeyCode::Enter)),
                ("Cancel".into(), MouseAction::Key(KeyCode::Esc)),
            ],
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
    use ratatui::backend::TestBackend;

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
