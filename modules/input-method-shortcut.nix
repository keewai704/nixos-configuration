{
  services.keyd = {
    enable = true;
    keyboards.input-method = {
      ids = [ "*" ];
      settings = {
        alt.grave = "f13";
        altgr.grave = "f13";
        "alt+control".grave = "A-C-grave";
        "alt+shift".grave = "A-S-grave";
        "alt+meta".grave = "A-M-grave";
        "altgr+control".grave = "G-C-grave";
        "altgr+shift".grave = "G-S-grave";
        "altgr+meta".grave = "G-M-grave";
        "alt+altgr".grave = "A-G-grave";
      };
    };
  };
}
