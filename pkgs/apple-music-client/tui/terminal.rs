use super::*;
use crossterm::{
    SynchronizedUpdate,
    cursor::{Hide, Show},
    event::{
        self, DisableBracketedPaste, DisableMouseCapture, EnableBracketedPaste, EnableMouseCapture,
        Event as TerminalEvent, KeyEventKind,
    },
    execute,
    terminal::{
        EndSynchronizedUpdate, EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode,
        enable_raw_mode,
    },
};
use ratatui::{Terminal, backend::CrosstermBackend};
use std::io::{self, IsTerminal, Write};

pub fn run(store: LibraryStore, cache: PathBuf, no_auth: bool, url: Option<String>) -> Result<()> {
    let stop = Arc::new(AtomicBool::new(false));
    for signal in [
        signal_hook::consts::SIGTERM,
        signal_hook::consts::SIGHUP,
        signal_hook::consts::SIGINT,
    ] {
        signal_hook::flag::register(signal, stop.clone())?;
    }
    let previous_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        restore_terminal();
        previous_hook(info);
    }));
    enable_raw_mode()?;
    let _guard = TerminalGuard;
    execute!(
        io::stdout(),
        EnterAlternateScreen,
        EnableBracketedPaste,
        EnableMouseCapture,
        Hide
    )?;
    let graphics = cover::Graphics::from_terminal();
    let mut terminal = Terminal::new(CrosstermBackend::new(TerminalOutput(io::stdout())))?;
    let mut app = App::new(store, cache, no_auth, graphics);
    if let Some(url) = url {
        app.open_url(url)?;
    }
    let interaction = (|| -> Result<()> {
        while !app.quit && !stop.load(Ordering::Relaxed) {
            if !terminal_connected() {
                break;
            }
            io::stdout().sync_update(|_| {
                if let Err(error) = app.poll() {
                    app.status = format!("{error:#}");
                }
                terminal
                    .draw(|frame| render::draw(frame, &mut app))
                    .map(|_| ())
            })??;
            if event::poll(Duration::from_millis(60))? {
                if !terminal_connected() {
                    break;
                }
                let result = match event::read()? {
                    TerminalEvent::Key(key) if key.kind != KeyEventKind::Release => app.key(key),
                    TerminalEvent::Mouse(event) => app.mouse_event(event),
                    TerminalEvent::Paste(value) => {
                        if let Some(input) = &mut app.input {
                            input.insert(&value);
                        }
                        app.preview_filter();
                        Ok(())
                    }
                    TerminalEvent::Resize(_, _) => {
                        app.covers.resize();
                        Ok(())
                    }
                    _ => Ok(()),
                };
                if let Err(error) = result {
                    app.status = format!("{error:#}");
                }
            }
        }
        Ok(())
    })();
    if app.library_dirty {
        app.store.save()?;
    }
    if terminal_connected() {
        interaction
    } else {
        Ok(())
    }
}

fn terminal_connected() -> bool {
    io::stdin().is_terminal() && io::stdout().is_terminal()
}

struct TerminalOutput(io::Stdout);

impl Write for TerminalOutput {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        match self.0.write(bytes) {
            Err(_) if !self.0.is_terminal() => Ok(bytes.len()),
            result => result,
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        match self.0.flush() {
            Err(_) if !self.0.is_terminal() => Ok(()),
            result => result,
        }
    }
}

struct TerminalGuard;
impl Drop for TerminalGuard {
    fn drop(&mut self) {
        restore_terminal();
    }
}

fn restore_terminal() {
    let _ = disable_raw_mode();
    let _ = execute!(
        io::stdout(),
        EndSynchronizedUpdate,
        DisableBracketedPaste,
        DisableMouseCapture,
        LeaveAlternateScreen,
        Show
    );
}
