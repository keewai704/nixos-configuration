use super::*;

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

pub(super) fn draw(frame: &mut Frame, app: &mut App, body: Rect) {
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
            lines.extend(commands::COMMANDS.iter().map(|command| Line::raw(*command)));
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
                item_actions::ACTIONS.iter().map(|s| (*s).into()).collect(),
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
                settings::SETTINGS
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

pub(super) fn input_box(frame: &mut Frame, input: &Input, body: Rect, mouse: &mut mouse::Mouse) {
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
        let lines: Vec<_> = commands::COMMANDS
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
