use super::*;

pub(super) const COMMANDS: &[&str] = &[
    "login",
    "connect",
    "code",
    "settings",
    "devices",
    "quality aac|lossless|hires|atmos",
    "device auto|pipewire|alsa/…",
    "crossfade 0..12",
    "passthrough on|off",
    "eq off|gain1,gain2,…,gain10",
    "cache-limit 256..1048576",
    "storefront jp",
    "playlist-new NAME",
    "queue-save NAME",
    "cancel-download",
    "stop",
    "quit",
];

impl App {
    pub(super) fn run_command(&mut self, text: &str) -> Result<()> {
        let (command, value) = text
            .trim()
            .split_once(char::is_whitespace)
            .unwrap_or((text.trim(), ""));
        match command {
            "quit" => self.quit = true,
            "stop" => self.stop(),
            "login" => self.connect_authentication(Some(LoginPrompt::Account))?,
            "connect" => self.connect_authentication(None)?,
            "code" => self.connect_authentication(Some(LoginPrompt::Code))?,
            "settings" => {
                self.overlay = Some(Overlay::Settings(
                    ListState::default().with_selected(Some(0)),
                ))
            }
            "devices" => self.spawn_job(ShutdownBehavior::Detach, || {
                Job::Devices(player::Mpv::new("null", false).and_then(|mut mpv| mpv.devices()))
            })?,
            "playlist-new" | "queue-save" => {
                let queue = command == "queue-save";
                if value.is_empty() {
                    self.input = Some(Input::new(InputKind::PlaylistName(queue), String::new()));
                } else {
                    self.create_playlist(value.into(), queue)?;
                }
            }
            "cancel-download" => {
                self.download_cancel.store(true, Ordering::Release);
                self.status = "Cancelling download…".into();
            }
            "quality" | "device" | "crossfade" | "passthrough" | "eq" | "cache-limit"
            | "storefront" => self.setting(command, value.trim())?,
            "" => {}
            _ => bail!("Unknown command: {command}. Use ? for help."),
        }
        Ok(())
    }
}
