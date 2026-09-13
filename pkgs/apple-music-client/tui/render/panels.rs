use super::*;

pub(super) fn draw(frame: &mut Frame, app: &mut App, area: Rect) {
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
            let position = app.playback_snapshot["position"].as_f64().unwrap_or(0.);
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
                source_text(&app.playback_source),
                clean(&app.playback_snapshot["output"].to_string()),
                clean(
                    app.playback_snapshot["device"]
                        .as_str()
                        .unwrap_or("unknown")
                )
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
