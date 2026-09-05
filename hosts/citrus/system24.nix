{ colors, fonts }:

''
  @import url("https://refact0r.github.io/system24/build/system24.css");

  /* Use System24's own variables so its layout and component styles stay intact. */
  html:root {
    --text-0: #${colors.base00};
    --text-1: #${colors.base05};
    --text-2: #${colors.base05};
    --text-3: #${colors.base04};
    --text-4: #${colors.base04};
    --text-5: #${colors.base03};
    --bg-1: #${colors.base02};
    --bg-2: #${colors.base01};
    --bg-3: color-mix(in srgb, #${colors.base00}, black 15%);
    --bg-4: #${colors.base00};
    --hover: color-mix(in srgb, var(--text-3), transparent 90%);
    --active: color-mix(in srgb, var(--text-3), transparent 80%);
    --active-2: color-mix(in srgb, var(--text-3), transparent 70%);
    --border: #${colors.base02};
    --accent-1: var(--blue-1);
    --accent-2: var(--blue-2);
    --accent-3: var(--blue-3);
    --accent-4: var(--blue-4);
    --accent-5: var(--blue-5);

    --red-1: color-mix(in srgb, var(--red-2), white 15%);
    --red-2: #${colors.base08};
    --red-3: color-mix(in srgb, var(--red-2), var(--bg-4) 10%);
    --red-4: color-mix(in srgb, var(--red-2), var(--bg-4) 20%);
    --red-5: color-mix(in srgb, var(--red-2), var(--bg-4) 30%);
    --green-1: color-mix(in srgb, var(--green-2), white 15%);
    --green-2: #${colors.base0B};
    --green-3: color-mix(in srgb, var(--green-2), var(--bg-4) 10%);
    --green-4: color-mix(in srgb, var(--green-2), var(--bg-4) 20%);
    --green-5: color-mix(in srgb, var(--green-2), var(--bg-4) 30%);
    --blue-1: color-mix(in srgb, var(--blue-2), white 15%);
    --blue-2: #${colors.base0D};
    --blue-3: color-mix(in srgb, var(--blue-2), var(--bg-4) 10%);
    --blue-4: color-mix(in srgb, var(--blue-2), var(--bg-4) 20%);
    --blue-5: color-mix(in srgb, var(--blue-2), var(--bg-4) 30%);
    --yellow-1: color-mix(in srgb, var(--yellow-2), white 15%);
    --yellow-2: #${colors.base0A};
    --yellow-3: color-mix(in srgb, var(--yellow-2), var(--bg-4) 10%);
    --yellow-4: color-mix(in srgb, var(--yellow-2), var(--bg-4) 20%);
    --yellow-5: color-mix(in srgb, var(--yellow-2), var(--bg-4) 30%);
    --purple-1: color-mix(in srgb, var(--purple-2), white 15%);
    --purple-2: #${colors.base0E};
    --purple-3: color-mix(in srgb, var(--purple-2), var(--bg-4) 10%);
    --purple-4: color-mix(in srgb, var(--purple-2), var(--bg-4) 20%);
    --purple-5: color-mix(in srgb, var(--purple-2), var(--bg-4) 30%);
  }

  html body {
    --font: "${fonts.monospace.name}", "${fonts.sansSerif.name}", monospace;
    --code-font: var(--font);
    /* Keep Discord's toolbar clear of Legcord's 30px overlay controls. */
    --top-bar-height: 36px;
    --top-bar-button-position: off;
    font-weight: 400;
    letter-spacing: normal;
  }

  /* Midnight removes the bottom border from these otherwise framed headers. */
  #app-mount :is(.container__133bf, .container_f391e3, .homeWrapper__0920e, .container__01ae2, .container_fb64c9) > .container__9293f {
    border-bottom: var(--border-thickness) solid var(--border-subtle);

    &:hover {
      border-bottom-color: var(--border-hover);
    }
  }
''
