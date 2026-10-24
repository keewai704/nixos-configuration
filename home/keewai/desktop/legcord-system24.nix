{ fonts }:

''
  html body {
    --font: "${fonts.monospace.name}", "${fonts.sansSerif.name}", monospace;
    --code-font: var(--font);
    --top-bar-height: var(--gap);
    --top-bar-button-position: titlebar;
    --legcord-controls-width: calc(6 * var(--window-control-size));
    font-weight: 400;
    letter-spacing: normal;
  }

  #app-mount .trailing_c38106 {
    anchor-name: --system24-toolbar;
    margin-right: 0;
    padding-right: calc(var(--legcord-controls-width) + 2 * var(--space-xs));
  }

  #app-mount .trailing_c38106 > a[href="https://support.discord.com"] {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
  }

  #app-mount .base__5e434 {
    --top-bar-right-margin: calc((32px + var(--space-xs)) * (var(--button-count, 1) + 1) + var(--legcord-controls-width) + 2 * var(--space-xs));
  }

  #legcordNavControls #window-controls-container {
    position: fixed;
    position-anchor: --system24-toolbar;
    top: anchor(top);
    right: calc(anchor(right) + var(--space-xs));
    width: var(--legcord-controls-width);
    height: 32px;
    line-height: 32px;
    z-index: 1001;
  }

  #legcordNavControls #window-controls-container > :is(#minimize, #maximize, #quit) {
    display: grid;
    place-items: center;
    width: calc(2 * var(--window-control-size));

    > div {
      display: block;
      width: var(--window-control-size);
      height: var(--window-control-size);
      mask-size: 100% 100%;
    }
  }

  #app-mount :is(.container__133bf, .container_f391e3, .homeWrapper__0920e, .container__01ae2, .container_fb64c9) > .container__9293f {
    border-bottom: var(--border-thickness) solid var(--border-subtle);

    &:hover {
      border-bottom-color: var(--border-hover);
    }
  }
''
