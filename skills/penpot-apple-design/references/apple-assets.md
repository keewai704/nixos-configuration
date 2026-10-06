# Apple assets and platform handoff

## Refresh the inventory

Start at [Apple Design Resources](https://developer.apple.com/design/resources/)
and the relevant [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/).
Follow Apple's current download links rather than guessing versioned CDN URLs.
Record the observed release, stable/beta label when provided, source URL, check
date, supported OS, license, and any conversion used. Match the project's
minimum OS; availability in a new kit does not imply availability on older OSes.
If upstream is unavailable, label the inventory unverified rather than current.

Official pages checked on 2026-10-06 listed the following. Recheck at use time.

| Resource | Observed release or contents | Use in the workflow |
| --- | --- | --- |
| [iOS/iPadOS UI kit](https://developer.apple.com/design/resources/#ios-apps) | iOS 27 and iPadOS 27; Figma and Sketch | Reference native controls and layouts; import permitted exports into Penpot. |
| [macOS UI kit](https://developer.apple.com/design/resources/#macos-apps) | macOS 27; Figma and Sketch | Reference desktop windows, toolbars, menus, and controls. |
| [SF Symbols](https://developer.apple.com/sf-symbols/) | SF Symbols 27 | Choose native symbol names, weights, scales, rendering modes, and deployment availability. |
| [Fonts](https://developer.apple.com/fonts/) | SF Pro, SF Mono, New York, and language-specific families | Use permitted mockup fonts; prefer platform text styles in native code. |
| [Icon Composer](https://developer.apple.com/icon-composer/) | Layered icon authoring for Apple platforms | Prepare separate source layers in Penpot, then finish and preview on macOS. |
| [Design Resources](https://developer.apple.com/design/resources/) | App icon templates, product bezels, technology badges, and feature templates | Fetch only the resources needed for the actual app or marketing deliverable. |

## Choose assets for the destination

For native Apple apps, prefer the official kit for the supported OS and native
controls in the implementation. Preserve symbol names and text-style roles in
the handoff so the implementation can adapt to appearance, locale, and scale.

For Apple-inspired web or Linux apps, use the project's existing licensed font
and icon system. When none exists, [Inter](https://rsms.me/inter/) and
[Lucide](https://lucide.dev/license) are candidates; verify the selected release's
license and retain required notices. Inter does not provide Japanese glyphs:
choose and verify a suitable CJK fallback already available to the project.
Match hierarchy, spacing, and interaction quality without presenting the result
as an official Apple kit.

Apple downloads are not general-purpose redistributable assets. The
[San Francisco license](https://developer.apple.com/fonts/) limits its use to
specified Apple-platform UI mockups and restricts embedding, redistribution, and
network availability. Check each package's current terms before use. Do not
upload Apple font files to a Penpot cloud/team library, commit them, convert them
to webfonts, or bundle them into an app without permission covering that use.
For native shipping text, use the OS font APIs. In Penpot, inspect available
fonts and use a disclosed substitute when the permitted font is unavailable.

Check [SF Symbols usage](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
and the downloaded license, including restrictions attached to individual
symbols. Prefer `Image(systemName:)` or the corresponding native API in Apple
apps. An exported SVG does not acquire a broader license. Use original artwork
for brand/app icons and an appropriately licensed icon library for non-Apple
targets. Device bezels and technology badges also have their own usage rules;
follow the linked rules for the requested marketing or integration use.

## Bring assets into Penpot

Apple's listed Figma/Sketch kits are source formats, not native Penpot libraries.
Do not install another design editor merely to satisfy this workflow. Prefer
an existing permitted SVG/PNG export or build the needed native Penpot components
from the documented measurements. If an authorized Figma session is available,
the [Penpot migration guide](https://help.penpot.app/user-guide/first-steps/migration-guide/)
describes a one-time Penpot Exporter path for components, styles, variables, and
layouts. A full kit migration requires access and permission for the source.

Import a representative component first. SVG is useful for editable vectors;
PNG is useful for fixed visual references. Inspect fonts, masks, gradients,
effects, scale, and layout after conversion. Rebuild reusable components and
tokens where the export loses their relationships. Keep asset provenance with
the design; label community kits as community-maintained and check their OS
version instead of assuming they match Apple's current release.

## Design for each platform

Use the current HIG for [layout](https://developer.apple.com/design/human-interface-guidelines/layout),
[typography](https://developer.apple.com/design/human-interface-guidelines/typography),
[accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility),
and [materials](https://developer.apple.com/design/human-interface-guidelines/materials).

- iPhone: design in logical points, distinguish safe areas from content bounds,
  and check text scaling, keyboard appearance, touch targets, and navigation.
- iPad: specify behavior at narrow and wide window widths, including sidebar
  collapse, multitasking, keyboard shortcuts, and pointer interaction. A scaled
  phone screenshot is not an adaptive layout specification.
- Mac: specify resizing limits, toolbar/sidebar behavior, menus, focus, keyboard
  commands, and pointer states. Preserve platform window controls and conventions.
- Across targets: include light/dark appearance, long localized strings,
  accessibility text sizes, focus/disabled/error states, and reduced motion or
  transparency where relevant to the UI being delivered.

Treat Liquid Glass as platform behavior, not a generic blur pasted over every
surface. Use the current material guidance and native controls for shipping
Apple apps. Penpot can document layering and static appearance, but a preview
does not verify dynamic refraction, scrolling, contrast adaptation, or motion.
Document older-OS and accessibility fallbacks; check them in the implementation.

## Export for implementation

Keep editable vectors and separate icon layers in the design. Icon Composer and
Xcode require a supported Mac; Linux can prepare source assets but cannot
validate the final layered icon or an Apple app build. Follow the current
[Icon Composer resources](https://developer.apple.com/icon-composer/)
and [app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons)
for layer formats, appearance variants, and target requirements. Do not bake the
OS mask or runtime glass effects into every source layer.

For raster assets, state logical dimensions and export scale; for native app
assets, describe the intended asset-catalog mapping and appearance variants.
For web handoff, use licensed SVG/raster assets and map semantic tokens to CSS.
Preserve native-control, SF Symbol, and typography roles separately from static
illustrations. Record which visual and device checks actually ran.
