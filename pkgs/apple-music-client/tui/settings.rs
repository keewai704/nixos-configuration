use super::{App, Input, InputKind};
use anyhow::{Context, Result, anyhow, bail};
use serde_json::json;
use siora::{library::Preferences, player};

pub(super) const SETTINGS: &[&str] = &[
    "Sign in",
    "Reconnect",
    "Two-factor code",
    "Audio quality",
    "Output device",
    "Crossfade seconds",
    "Atmos passthrough",
    "Equalizer",
    "Cache limit (MB)",
    "Storefront",
];

impl App {
    pub(super) fn open_setting(&mut self, index: usize) -> Result<()> {
        match index {
            0 => self.run_command("login")?,
            1 => self.run_command("connect")?,
            2 => self.run_command("code")?,
            4 => self.run_command("devices")?,
            _ => {
                let prefs = &self.store.data.preferences;
                let (name, value) = match index {
                    3 => ("quality", prefs.quality.clone()),
                    5 => ("crossfade", prefs.crossfade_seconds.to_string()),
                    6 => (
                        "passthrough",
                        if prefs.passthrough { "on" } else { "off" }.into(),
                    ),
                    7 => (
                        "eq",
                        if prefs.eq_enabled {
                            prefs
                                .eq_gains
                                .iter()
                                .map(f64::to_string)
                                .collect::<Vec<_>>()
                                .join(",")
                        } else {
                            "off".into()
                        },
                    ),
                    8 => ("cache-limit", prefs.cache_limit_mb.to_string()),
                    _ => ("storefront", prefs.storefront.clone()),
                };
                self.input = Some(Input::new(InputKind::Setting(name), value));
            }
        }
        Ok(())
    }

    pub(super) fn setting(&mut self, name: &str, value: &str) -> Result<()> {
        let old = self.store.data.preferences.clone();
        let mut prefs = old.clone();
        match name {
            "quality" => {
                player::quality_name(value)?;
                prefs.quality = value.into();
            }
            "device" => {
                if value.is_empty() || value.len() > 256 || value.chars().any(char::is_control) {
                    bail!("Invalid output device");
                }
                prefs.device = value.into();
            }
            "crossfade" => {
                prefs.crossfade_seconds = value.parse().context("Crossfade must be 0–12 seconds")?
            }
            "passthrough" => {
                prefs.passthrough = match value {
                    "on" => true,
                    "off" => false,
                    _ => bail!("Use on or off"),
                }
            }
            "cache-limit" => {
                prefs.cache_limit_mb = value
                    .parse()
                    .context("Cache limit must be 256–1048576 MB")?
            }
            "storefront" => {
                if value.len() != 2 || !value.bytes().all(|ch| ch.is_ascii_alphabetic()) {
                    bail!("Use a two-letter storefront such as jp or us");
                }
                prefs.storefront = value.to_ascii_lowercase();
            }
            "eq" => {
                prefs.eq_enabled = value != "off";
                if prefs.eq_enabled {
                    let gains = value
                        .split(',')
                        .map(str::parse)
                        .collect::<std::result::Result<Vec<f64>, _>>()?;
                    prefs.eq_gains = gains.try_into().map_err(|_| {
                        anyhow!("Enter ten comma-separated gains (-12 to 12 dB), or off")
                    })?;
                }
            }
            _ => bail!("Unknown setting"),
        }
        if prefs.passthrough
            && (!prefs.device.starts_with("alsa/hdmi:")
                || prefs.quality != "atmos"
                || prefs.eq_enabled
                || prefs.crossfade_seconds != 0.)
        {
            bail!(
                "Passthrough requires quality atmos, an alsa/hdmi: device, EQ off, and crossfade 0"
            );
        }
        if prefs.crossfade_seconds > 0. && (prefs.device.starts_with("alsa/") || prefs.passthrough)
        {
            bail!("Crossfade requires a shared output such as auto or pipewire");
        }
        self.store.data.preferences = prefs;
        if let Err(error) = self.store.save() {
            self.store.data.preferences = old;
            return Err(error);
        }
        if name == "device" || name == "passthrough" {
            if let Some(id) = self.queue.current {
                self.play(id)?;
            }
        } else if name == "storefront" {
            if self.api.is_some() {
                self.connect_authentication(None)?;
            }
        } else {
            if name == "eq" && self.loaded {
                self.command(json!([
                    "set_property",
                    "af",
                    eq_filter(&self.store.data.preferences)
                ]));
            }
            self.schedule_next()?;
        }
        self.status = format!("Saved {name}; quality applies to the next prepared track");
        Ok(())
    }
}

fn eq_filter(prefs: &Preferences) -> String {
    if !prefs.eq_enabled {
        return String::new();
    }
    [
        31., 62., 125., 250., 500., 1000., 2000., 4000., 8000., 16000.,
    ]
    .iter()
    .zip(prefs.eq_gains)
    .map(|(frequency, gain)| format!("equalizer=f={frequency}:t=o:w=1:g={gain}"))
    .collect::<Vec<_>>()
    .join(",")
}
