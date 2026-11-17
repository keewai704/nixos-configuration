{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  discordPresence = pkgs.writers.writePython3Bin "genshin-discord-presence" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./discord-presence.py);

  command = "${lib.getExe discordPresence} & %command% -screen-width 5120 -screen-height 2160 -screen-fullscreen 1";
in
{
  imports = [ inputs.aagl.nixosModules.default ];

  nix.settings = inputs.aagl.nixConfig;

  programs.anime-game-launcher.enable = true;

  home-manager.users.keewai =
    { config, ... }:
    {
      xdg.dataFile.anime-game-launcher.source = config.lib.file.mkOutOfStoreSymlink "/mnt/data/Games/anime-game-launcher";

      home.activation.animeGameLauncherCommand =
        inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ]
          ''
            config="${config.xdg.dataHome}/anime-game-launcher/config.json"
            if [ -s "$config" ]; then
              merged="$(mktemp "$config.XXXXXX")"
              ${lib.getExe pkgs.jq} --arg command ${lib.escapeShellArg command} \
                'if .game.command == null or (.game.command | contains("genshin-discord-presence")) then .game.command = $command else . end
                  | .game.enhancements.fps_unlocker.config.fps |= ([., 120] | min)' \
                "$config" > "$merged"
              run mv "$merged" "$config"
            fi
          '';
    };
}
