{ config, ... }:
{
  home.sessionVariables.TYPESAFE_API_KEY_FILE = "${config.xdg.configHome}/typesafe/api-key";
}
