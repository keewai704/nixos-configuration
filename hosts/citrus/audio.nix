{
  hardware.bluetooth = {
    enable = true;
    settings.General = {
      Experimental = true;
      KernelExperimental = "6fbaf188-05e0-496a-9885-d6ddfdb4e03e";
    };
  };

  services = {
    blueman.enable = true;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.extraConfig."51-inzone-le-audio" = {
        "monitor.bluez.rules" = [
          {
            matches = [ { "device.name" = "bluez_card.88_92_CC_D0_86_D2"; } ];
            actions.update-props."bluez5.bap.preset" = "48_4_1";
          }
        ];
      };
    };
  };

  security.rtkit.enable = true;
}
