{
  fetchFromGitHub,
  lib,
  sassc,
  stdenvNoCC,
  writeText,
}:

let
  indexTheme = writeText "Tokyonight-Dark-index.theme" ''
    [Desktop Entry]
    Type=X-GNOME-Metatheme
    Name=Tokyonight-Dark
    Comment=Tokyo Night dark GTK theme
    Encoding=UTF-8

    [X-GNOME-Metatheme]
    GtkTheme=Tokyonight-Dark
  '';
in
stdenvNoCC.mkDerivation {
  pname = "tokyonight-gtk-theme";
  version = "0-unstable-2025-10-23";

  src = fetchFromGitHub {
    owner = "Fausto-Korpsvart";
    repo = "Tokyonight-GTK-Theme";
    rev = "6c340e058e84c1975a038a8e5d1e384477225dc0";
    hash = "sha256-7H2n9wTaW8Db1RejWK071ITV1j5KIuzfql0Tx9WT6zM=";
  };

  strictDeps = true;

  nativeBuildInputs = [ sassc ];

  dontConfigure = true;
  dontBuild = true;

  postPatch = ''
    # The Sass entry points expect the installer's generated working copy.
    cp themes/src/sass/_tweaks.scss themes/src/sass/_tweaks-temp.scss
  '';

  installPhase = ''
    runHook preInstall

    # The upstream installer always emits GTK2 and desktop-shell themes. Build
    # only the GTK versions enabled on citrus-vm so no Murrine dependency leaks
    # into the runtime closure.
    themeDir="$out/share/themes/Tokyonight-Dark"
    install -d "$themeDir/gtk-3.0/assets" "$themeDir/gtk-4.0/assets"

    cp -a themes/src/assets/gtk/assets/. "$themeDir/gtk-3.0/assets/"
    cp -a themes/src/assets/gtk/scalable "$themeDir/gtk-3.0/assets/scalable"
    cp -a themes/src/assets/gtk/scalable/. "$themeDir/gtk-4.0/assets/"

    install -m644 themes/src/assets/gtk/thumbnails/thumbnail-Dark.png \
      "$themeDir/gtk-3.0/thumbnail.png"
    install -m644 themes/src/assets/gtk/thumbnails/thumbnail-Dark.png \
      "$themeDir/gtk-4.0/thumbnail.png"

    sassc -M -t expanded themes/src/main/gtk-3.0/gtk-Dark.scss \
      "$themeDir/gtk-3.0/gtk.css"
    # Upstream GTK3 CSS names these scale assets as SVGs, but ships PNGs.
    sed -i -E \
      '/assets\/scale-(horz|vert)-marks-(before|after)-slider/ s/\.svg/\.png/g' \
      "$themeDir/gtk-3.0/gtk.css"
    # GTK3 rejects the GTK4-only border-spacing property that upstream emits
    # for the shared dropdown selector.
    sed -i '/^  border-spacing: 6px;$/d' "$themeDir/gtk-3.0/gtk.css"
    install -m644 themes/src/assets/gtk/scalable/cursor-handle-symbolic.svg \
      "$themeDir/gtk-3.0/assets/cursor-handle-symbolic.svg"
    cp "$themeDir/gtk-3.0/gtk.css" "$themeDir/gtk-3.0/gtk-dark.css"

    sassc -M -t expanded themes/src/main/gtk-4.0/gtk-Dark.scss \
      "$themeDir/gtk-4.0/gtk.css"
    cp "$themeDir/gtk-4.0/gtk.css" "$themeDir/gtk-4.0/gtk-dark.css"

    install -m644 ${indexTheme} "$themeDir/index.theme"

    runHook postInstall
  '';

  meta = {
    description = "Tokyo Night dark GTK3 and GTK4 theme";
    homepage = "https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
