{ config, pkgs, ... }:
{
  xdg.configFile = {
    "millennium/quick.css".source = config.lib.stylix.colors {
      template = pkgs.writeText "millennium.css.mustache" ''
        :root {
          --st-accent-1: {{base0D-rgb-r}}, {{base0D-rgb-g}}, {{base0D-rgb-b}} !important;
          --st-accent-2: {{base0E-rgb-r}}, {{base0E-rgb-g}}, {{base0E-rgb-b}} !important;
          --st-background: {{base00-rgb-r}}, {{base00-rgb-g}}, {{base00-rgb-b}} !important;
          --st-color-1: {{base00-rgb-r}}, {{base00-rgb-g}}, {{base00-rgb-b}} !important;
          --st-color-2: {{base01-rgb-r}}, {{base01-rgb-g}}, {{base01-rgb-b}} !important;
          --st-color-3: {{base00-rgb-r}}, {{base00-rgb-g}}, {{base00-rgb-b}} !important;
          --st-color-4: {{base01-rgb-r}}, {{base01-rgb-g}}, {{base01-rgb-b}} !important;
          --st-color-5: {{base02-rgb-r}}, {{base02-rgb-g}}, {{base02-rgb-b}} !important;
          --st-color-6: {{base03-rgb-r}}, {{base03-rgb-g}}, {{base03-rgb-b}} !important;
          --st-blue: {{base0D-rgb-r}}, {{base0D-rgb-g}}, {{base0D-rgb-b}} !important;
          --st-blue-hover: var(--st-blue) !important;
          --st-green: {{base0B-rgb-r}}, {{base0B-rgb-g}}, {{base0B-rgb-b}} !important;
          --st-green-hover: var(--st-green) !important;
          --st-red: {{base08-rgb-r}}, {{base08-rgb-g}}, {{base08-rgb-b}} !important;
          --st-red-hover: var(--st-red) !important;
          --st-yellow: {{base0A-rgb-r}}, {{base0A-rgb-g}}, {{base0A-rgb-b}} !important;
          --st-yellow-hover: var(--st-yellow) !important;
        }
        :root * {
          font-family: "${config.stylix.fonts.sansSerif.name}", sans-serif !important;
        }

        :root body .DialogBody > .Panel,
        :root body .DialogBody .DialogControlsSection > .Panel {
          padding: 12px !important;
          margin-bottom: 12px !important;
          border-radius: var(--st-border-radius);
          background-color: rgb(var(--st-color-2));
        }
        body .DialogBody .eKmEXJCm_lgme24Fp_HWt ._2tALpM7z8naXJ35Pp5fNAG > :is(._2VcTlXFC64Jtg9gvtT6cmY, ._1W1to_azoBRG95oNAFpf9Q) {
          padding: 0 !important;
          background: none !important;
        }
        body .DialogBody .eKmEXJCm_lgme24Fp_HWt ._1W1to_azoBRG95oNAFpf9Q {
          margin-top: 6px;
        }
        body .DialogBody :is(.DialogSubHeader, .SettingsDialogSubHeader) {
          padding: 12px 0 6px;
          background: none;
        }
        :root ._9Ql-oVe_j8E-vsDdyVdWo.aIeh3X5T2M074RLW1qn6_ ._2bl0iQ9xigbq4Zd1NI6NZl {
          background-color: rgb(var(--st-color-5)) !important;
        }
        :root ._9Ql-oVe_j8E-vsDdyVdWo.aIeh3X5T2M074RLW1qn6_ ._1PQppcgkuXQAiFPar9AGi- {
          background-color: rgb(var(--st-color-6));
        }
      '';
      extension = ".css";
    };
  };
}
