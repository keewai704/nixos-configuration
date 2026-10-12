{ lib, nvidiaPackages }:
nvidiaPackages.mkDriver (lib.importJSON ./sources.json).nvidia
