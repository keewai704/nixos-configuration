{ fonts }:
''
  :root {
    --st-accent-1: {{colors.primary.default.rgb_csv}} !important;
    --st-accent-2: {{colors.tertiary.default.rgb_csv}} !important;
    --st-background: {{colors.surface.default.rgb_csv}} !important;
    --st-color-1: {{colors.surface.default.rgb_csv}} !important;
    --st-color-2: {{colors.surface_container.default.rgb_csv}} !important;
    --st-color-3: {{colors.surface.default.rgb_csv}} !important;
    --st-color-4: {{colors.surface_container.default.rgb_csv}} !important;
    --st-color-5: {{colors.outline_variant.default.rgb_csv}} !important;
    --st-color-6: {{colors.outline.default.rgb_csv}} !important;
    --st-blue: {{colors.terminal_normal_blue.default.rgb_csv}} !important;
    --st-blue-hover: var(--st-blue) !important;
    --st-green: {{colors.terminal_normal_green.default.rgb_csv}} !important;
    --st-green-hover: var(--st-green) !important;
    --st-red: {{colors.terminal_normal_red.default.rgb_csv}} !important;
    --st-red-hover: var(--st-red) !important;
    --st-yellow: {{colors.terminal_normal_yellow.default.rgb_csv}} !important;
    --st-yellow-hover: var(--st-yellow) !important;
  }
  :root * {
    font-family: "${fonts.sansSerif.name}", sans-serif !important;
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
''
