{ pkgs, ... }:
let
  wine4office = pkgs.callPackage ../../../pkgs/wine4office { };
  applications = {
    word = {
      name = "Microsoft Word";
      executable = "WINWORD.EXE";
      icon = "x-office-document";
      category = "WordProcessor";
      mimeTypes = [
        "application/msword"
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      ];
    };
    excel = {
      name = "Microsoft Excel";
      executable = "EXCEL.EXE";
      icon = "x-office-spreadsheet";
      category = "Spreadsheet";
      mimeTypes = [
        "application/vnd.ms-excel"
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      ];
    };
    powerpoint = {
      name = "Microsoft PowerPoint";
      executable = "POWERPNT.EXE";
      icon = "x-office-presentation";
      category = "Presentation";
      mimeTypes = [
        "application/vnd.ms-powerpoint"
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      ];
    };
  };

  launchers = pkgs.lib.mapAttrs (
    name: application:
    pkgs.writeShellApplication {
      name = "microsoft365-${name}";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        export WINEPREFIX="''${WINEPREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/microsoft365/prefix}"
        executable="$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/${application.executable}"
        if [[ ! -f "$executable" ]]; then
          printf '%s\n' 'Microsoft 365 is not installed in this Wine environment.' >&2
          exit 1
        fi
        ${wine4office}/bin/wine4office-setup-printer
        arguments=()
        for file in "$@"; do
          file=$(realpath -e -- "$file")
          arguments+=("$(${wine4office}/bin/wine4office winepath -w "$file")")
        done
        exec ${wine4office}/bin/wine4office "$executable" ${
          pkgs.lib.optionalString (name == "word") "/q"
        } "''${arguments[@]}"
      '';
    }
  ) applications;
in
{
  home.packages = [ wine4office ] ++ pkgs.lib.attrValues launchers;

  xdg.desktopEntries = pkgs.lib.mapAttrs' (
    name: application:
    pkgs.lib.nameValuePair "microsoft365-${name}" {
      inherit (application) name icon;
      exec = "${launchers.${name}}/bin/microsoft365-${name} %F";
      terminal = false;
      categories = [
        "Office"
        application.category
      ];
      mimeType = application.mimeTypes;
    }
  ) applications;
}
