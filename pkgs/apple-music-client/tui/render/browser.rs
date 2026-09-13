use super::*;

pub(super) fn navigation(frame: &mut Frame, app: &mut App, area: Rect) {
    let items = browse::NAV.iter().map(|(name, _)| ListItem::new(*name));
    frame.render_stateful_widget(
        List::new(items)
            .block(block("Browse", app.focus == Focus::Navigation))
            .highlight_style(highlight())
            .highlight_symbol("› "),
        area,
        &mut app.navigation_list,
    );
    let inner = block("", false).inner(area);
    app.mouse.pane(inner, MousePane::Navigation);
    for index in app.navigation_list.offset()..browse::NAV.len() {
        let row = index - app.navigation_list.offset();
        if row >= inner.height as usize {
            break;
        }
        app.mouse.hit(
            Rect::new(inner.x, inner.y + row as u16, inner.width, 1),
            MouseAction::Navigate(index),
        );
    }
}

pub(super) fn draw(frame: &mut Frame, app: &mut App, area: Rect) {
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
        let empty_message = if app.pending_page.is_some() {
            "Loading…"
        } else if !app.page.filter.is_empty() {
            "No loaded items match this filter. / edits the filter."
        } else {
            "No items. Ctrl+f searches Apple Music.\nTab opens navigation; :login connects your library."
        };
        frame.render_widget(
            Paragraph::new(empty_message)
                .block(outer)
                .wrap(Wrap { trim: false }),
            area,
        );
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
