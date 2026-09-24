{ pkgs, ... }:
let
  officeRunner = pkgs.callPackage ../../../pkgs/wine4office-runner { };
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
        bottle="''${XDG_DATA_HOME:-$HOME/.local/share}/bottles/bottles/Microsoft365"
        executable="$bottle/drive_c/Program Files/Microsoft Office/root/Office16/${application.executable}"
        if [[ ! -f "$bottle/bottle.yml" || ! -f "$executable" ]]; then
          printf '%s\n' 'Microsoft 365 is not installed in the Microsoft365 bottle.' >&2
          exit 1
        fi
        arguments=()
        for file in "$@"; do
          file=$(realpath -e -- "$file")
          arguments+=("Z:''${file//\//\\}")
        done
        exec ${pkgs.bottles}/bin/bottles-cli run -b Microsoft365 -e "$executable" -- ${
          pkgs.lib.optionalString (name == "word") "/q"
        } "''${arguments[@]}"
      '';
    }
  ) applications;
in
{
  home.packages = [ pkgs.bottles ] ++ pkgs.lib.attrValues launchers;

  xdg.dataFile."bottles/runners/wine4office-${officeRunner.version}/bin".source =
    "${officeRunner}/bin";

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
