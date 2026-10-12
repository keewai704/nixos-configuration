{ colors, fonts }:
let
  rgb =
    slot:
    colors."${slot}-rgb"
      or "${colors."${slot}-rgb-r"}, ${colors."${slot}-rgb-g"}, ${colors."${slot}-rgb-b"}";
in
''
  :root {
    --st-accent-1: ${rgb "base0D"} !important;
    --st-accent-2: ${rgb "base0E"} !important;
    --st-background: ${rgb "base00"} !important;
    --st-color-1: ${rgb "base00"} !important;
    --st-color-2: ${rgb "base01"} !important;
    --st-color-3: ${rgb "base00"} !important;
    --st-color-4: ${rgb "base01"} !important;
    --st-color-5: ${rgb "base02"} !important;
    --st-color-6: ${rgb "base03"} !important;
    --st-blue: ${rgb "base0D"} !important;
    --st-blue-hover: var(--st-blue) !important;
    --st-green: ${rgb "base0B"} !important;
    --st-green-hover: var(--st-green) !important;
    --st-red: ${rgb "base08"} !important;
    --st-red-hover: var(--st-red) !important;
    --st-yellow: ${rgb "base0A"} !important;
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
