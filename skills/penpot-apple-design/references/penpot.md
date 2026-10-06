# Penpot workflow

## Connect the existing environment

The desktop configuration uses [Penpot Cloud](https://design.penpot.app/) and
the local `penpot-mcp` and `penpot-mcp-plugin` user services. Their source is
[penpot-mcp.nix](/home/keewai/nixos-configuration/home/keewai/desktop/penpot-mcp.nix);
the package is [pkgs/penpot-mcp](/home/keewai/nixos-configuration/pkgs/penpot-mcp/default.nix).
Read those sources if the deployed endpoints differ from the values below.
Other hosts may have this skill without the desktop services.

| Connection | Local endpoint |
| --- | --- |
| Plugin manifest | `http://localhost:4400/manifest.json` |
| Agent MCP transport | `http://localhost:4401/mcp` |
| Plugin WebSocket | `ws://localhost:4402` |

The configured `penpot` MCP already bridges stdio to the HTTP transport. Do not
start a second server or install an npm copy to use it. With a signed-in Penpot
session, open the intended design file, install the manifest URL through the
Plugin Manager when absent, launch the MCP plugin, and connect it. Keep that
plugin open in the target file. Installing the plugin alone does not connect the
editor. See [plugin installation](https://help.penpot.app/user-guide/plugins-integrations/).

For a failed connection, inspect the user services and manifest response first:

```sh
systemctl --user status penpot-mcp.service penpot-mcp-plugin.service
curl --fail http://localhost:4400/manifest.json
```

Then check the plugin's connection state and any browser local-network prompt.
Use the browser's normal permission flow for this trusted local endpoint; do
not disable browser security or widen the services' loopback bindings. An HTTP
response from `/mcp` alone does not prove the plugin is connected. Retry after
correcting an observed cause; stop repeating the same failed call and report
the missing login, service, or plugin connection. Never claim canvas changes
when only the MCP transport was reachable.

## Inspect before editing

1. Read the Penpot MCP `high_level_overview` once per context. Use
   `penpot_api_info` for the types/members needed by the next operation; the
   installed API is authoritative over remembered examples.
2. Identify the file, page, selection, and relevant boards. Preserve selection
   references in `storage` immediately, and retain stable IDs so a changing
   selection cannot redirect later edits. Scope searches to the intended page.
3. Use `penpotUtils.getPages()`, `shapeStructure`, and the provided shape search
   helpers to inspect structure; enumerate connected libraries, local components,
   available fonts, and tokens before creating duplicates.
4. Use `export_shape` to inspect the relevant board. Respect existing file and
   library boundaries; modify only the authorized design. A component edit can
   affect instances outside the current screen.

For data-only reads, return concise JSON rather than complete document dumps.
Use `execute_code` for supported canvas/API changes, `import_image` for local
raster assets, and the documented SVG path for vectors. The current tool catalog
defines arguments; do not guess them from a different MCP implementation.

## Build reusable screens

Create boards for the requested viewport and states, with semantic layer names.
Use Flex/Grid for adaptive relationships. When converting an existing board to
Flex, use the overview's order-preserving helper. Change layout gaps, padding,
and sizing rules rather than fighting layout-controlled child coordinates.

Use the Assets panel for components, colors, and typographies. Shared libraries
are connected through Assets/Libraries; reuse their main components and create
instances in screens. Define variants for meaningful axes such as size, state,
and appearance. Edit a main component only when its consumers should change;
detach an instance only when it intentionally becomes independent.
See [assets](https://help.penpot.app/user-guide/design-systems/assets/),
[libraries](https://help.penpot.app/user-guide/design-systems/libraries/), and
[components](https://help.penpot.app/user-guide/design-systems/components/).

Use semantic [design tokens](https://help.penpot.app/user-guide/design-systems/design-tokens/)
for repeated color, spacing, typography, and radius decisions. Organize shared
values and appearance overrides into sets/themes, then bind tokens to explicit
shape properties. Check that the intended sets/theme are active. API changes
to a controlled raw property can remove its token binding; verify bindings after
edits. Use Penpot's supported JSON import/export for interchange and inspect
the installed schema before generating a token file.

Prototype the requested paths through the Prototype panel: set a flow start,
connect board transitions and overlays, and check them in View mode. Exported
PNGs cannot validate these interactions. See
[prototyping](https://help.penpot.app/user-guide/prototyping-testing/prototyping/).

## Verify and hand off

Inspect an exported board after material edits. Check clipping, text bounds,
font substitution, contrast, icon alignment, resizing, and component/token
links relevant to the change. Account for asynchronous layout and font updates
before measuring. For app design, apply the platform checks in
[Apple assets](apple-assets.md).

Use Inspect or the documented markup/style API for web measurements and
CSS/HTML/SVG references; translate platform behavior separately for native code.
Export suitable SVG or scaled raster layers for production assets. Export a
`.penpot` file when an editable backup or transfer is requested; choose the
shared-library export option that preserves the needed dependencies. See
[file export](https://help.penpot.app/user-guide/export-import/export-import-files/).
Report the actual design identifiers, assets, preview evidence, and any remaining
conversion or runtime limitations.
