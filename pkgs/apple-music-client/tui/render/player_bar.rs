use super::*;

pub(super) fn draw(frame: &mut Frame, app: &mut App, area: Rect) {
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
    } else if app.playback_snapshot["paused"] == true {
        "Paused"
    } else {
        "Playing"
    };
    frame.render_widget(
        Paragraph::new(format!("{state}: {title}")).style(Style::default().fg(ACCENT)),
        rows[0],
    );
    let duration = app.playback_snapshot["duration"].as_f64().unwrap_or(0.);
    let position = app.playback_snapshot["position"].as_f64().unwrap_or(0.);
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
        Paragraph::new(source_text(&app.playback_source)),
        Rect::new(x, rows[2].y, rows[2].right().saturating_sub(x), 1),
    );
    buttons(
        frame,
        &mut app.mouse,
        rows[3],
        vec![
            ("Prev".into(), MouseAction::Key(KeyCode::Char('p'))),
            (
                if app.loaded && app.playback_snapshot["paused"] != true {
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
