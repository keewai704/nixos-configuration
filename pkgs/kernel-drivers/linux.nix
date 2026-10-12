{
  lib,
  buildLinux,
  fetchurl,
  llvmPackages_22,
  overrideCC,
  ...
}@args:
let
  source = (lib.importJSON ./sources.json).linux;
in
buildLinux (
  args
  // {
    pname = "linux-mainline";
    inherit (source) version;
    modDirVersion = lib.versions.pad 3 source.version;
    src = fetchurl { inherit (source) url hash; };

    stdenv = overrideCC llvmPackages_22.stdenv (
      llvmPackages_22.clang.override { bintools = llvmPackages_22.bintools; }
    );

    extraMakeFlags = [ "KCFLAGS=-O3" ] ++ (args.extraMakeFlags or [ ]);

    structuredExtraConfig = with lib.kernel; {
      CC_OPTIMIZE_FOR_PERFORMANCE = yes;
      LTO_NONE = no;
      LTO_CLANG_FULL = no;
      LTO_CLANG_THIN = yes;
      RUST = lib.mkForce (option no);
      NOVA_CORE = lib.mkForce (option no);
      DRM_NOVA = lib.mkForce (option no);
      DRM_PANIC_SCREEN_QR_CODE = lib.mkForce (option no);
      HZ_1000 = yes;
      HZ = freeform "1000";
      PREEMPT = lib.mkForce yes;
      PREEMPT_LAZY = lib.mkForce no;
      PREEMPT_DYNAMIC = yes;
      TRANSPARENT_HUGEPAGE_ALWAYS = lib.mkForce yes;
      TRANSPARENT_HUGEPAGE_MADVISE = lib.mkForce no;
    };
  }
  // (args.argsOverride or { })
)
