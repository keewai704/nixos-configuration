use super::*;

impl App {
    pub(super) fn authentication_endpoints(&self) -> Result<Endpoints> {
        if !self.auth_ready {
            bail!(
                "{}",
                self.auth_problem.as_deref().unwrap_or(
                    "認証ヘルパーが未接続です。:connect または :login を実行してください。"
                )
            );
        }
        let runtime = self.auth_runtime.as_ref().context(
            "Authentication helper unavailable; start Siora without --no-auth after importing the Apple Music runtime",
        )?;
        Ok(runtime.endpoints().clone())
    }

    pub(super) fn authenticated_api(&self) -> Result<AppleMusic> {
        self.api
            .clone()
            .context("Sign in with :login or reconnect with :connect")
    }

    pub(super) fn handle_auth_failure(&mut self, message: String, show: bool) {
        self.auth_generation += 1;
        self.auth_busy = false;
        self.auth_ready = false;
        self.api = None;
        self.auth_problem = Some(message.clone());
        self.account = "Auth unavailable".into();
        self.status = message.clone();
        if self.input.as_ref().is_some_and(|input| {
            matches!(
                input.kind,
                InputKind::Username | InputKind::Password(_) | InputKind::Code
            )
        }) {
            self.input = None;
        }
        if show {
            self.panel_scroll = 0;
            self.overlay = Some(Overlay::Text(
                "Apple Musicの認証セットアップ".into(),
                message,
            ));
        }
    }

    pub(super) fn connect_authentication(&mut self, prompt: Option<LoginPrompt>) -> Result<()> {
        if self.auth_busy {
            bail!("Authentication is already in progress");
        }
        let restart = self
            .auth_runtime
            .as_mut()
            .is_none_or(|runtime| !runtime.is_running().unwrap_or(false));
        if restart {
            self.auth_runtime = None;
            match AuthRuntime::spawn() {
                Ok(runtime) => self.auth_runtime = Some(runtime),
                Err(error) => {
                    self.handle_auth_failure(error.to_string(), prompt.is_some());
                    return Err(error);
                }
            }
        }
        let auth = self
            .auth_runtime
            .as_ref()
            .context("認証ヘルパーがありません。")?
            .endpoints()
            .clone();
        self.auth_generation += 1;
        let generation = self.auth_generation;
        self.auth_ready = false;
        let storefront = self.store.data.preferences.storefront.clone();
        self.spawn_job(ShutdownBehavior::Detach, move || {
            Job::Connected(
                generation,
                prompt,
                (|| {
                    let state = if restart {
                        auth_service::wait_ready(&auth)?
                    } else {
                        auth_service::status(&auth.http)?
                    };
                    let api = if state.authenticated {
                        Some(AppleMusic::from_wrapper(&auth.http, &storefront)?)
                    } else {
                        None
                    };
                    Ok((state, api))
                })(),
            )
        })?;
        self.auth_busy = true;
        self.account = "Connecting…".into();
        Ok(())
    }
}
