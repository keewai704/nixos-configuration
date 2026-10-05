{
  lib,
  python3Packages,
  fetchPypi,
  grim,
  wtype,
  hyprland,
  systemd,
  imagemagick,
  wl-clipboard,
}:
python3Packages.buildPythonApplication rec {
  pname = "hypruse";
  version = "0.11.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-E5EhoPiLXTf3TW5YTlKmkhdZOy5C/evKchzCnvnpZOA=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = [ python3Packages.mcp ];

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];

  disabledTests = [
    "test_the_checkout_carries_the_skill_and_it_is_well_formed"
    "test_main_path_prints_the_packaged_directory"
    "test_never_settles_times_out_with_last_frame"
  ];

  makeWrapperArgs = [
    "--suffix"
    "PATH"
    ":"
    (lib.makeBinPath [
      grim
      wtype
      hyprland
      systemd
      imagemagick
      wl-clipboard
    ])
  ];

  pythonImportsCheck = [ "hypruse" ];

  meta = {
    description = "Computer use MCP server for Hyprland";
    homepage = "https://github.com/IlyasKhallouki/hypruse";
    license = lib.licenses.mit;
    mainProgram = "hypruse";
    platforms = lib.platforms.linux;
  };
}
