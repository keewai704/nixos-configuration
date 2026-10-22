{
  lib,
  buildLinux,
  fetchurl,
  linuxManualConfig,
  llvmPackages_22,
  overrideCC,
  writeText,
  localModules ? [ ],
  localModuleDirectories ? [ ],
  ...
}@args:
let
  source = (lib.importJSON ./sources.json).linux;
  kernel = buildLinux (
    args
    // {
      pname = "linux-mainline";
      inherit (source) version;
      modDirVersion = lib.versions.pad 3 source.version;
      src = fetchurl { inherit (source) url hash; };

      stdenv = overrideCC llvmPackages_22.stdenv (
        llvmPackages_22.clang.override { inherit (llvmPackages_22) bintools; }
      );

      extraMakeFlags = [
        "KCFLAGS=-O3"
      ]
      ++ (args.extraMakeFlags or [ ]);

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
        DEBUG_INFO_DWARF5 = yes;
        DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT = lib.mkForce no;
        MEM_ALLOC_PROFILING = lib.mkForce no;
        MEM_ALLOC_PROFILING_ENABLED_BY_DEFAULT = lib.mkForce (option no);
        RCU_EXPERT = yes;
        RCU_CPU_STALL_TIMEOUT = freeform "60";
        RCU_LAZY_DEFAULT_OFF = yes;
        RCU_TRACE = no;
        TRANSPARENT_HUGEPAGE_ALWAYS = lib.mkForce yes;
        TRANSPARENT_HUGEPAGE_MADVISE = lib.mkForce no;
        TRANSPARENT_HUGEPAGE_SHMEM_HUGE_ADVISE = yes;
        TRANSPARENT_HUGEPAGE_SHMEM_HUGE_NEVER = no;
        TRANSPARENT_HUGEPAGE_TMPFS_HUGE_ADVISE = yes;
        TRANSPARENT_HUGEPAGE_TMPFS_HUGE_NEVER = no;
      };
    }
    // (args.argsOverride or { })
  );
  moduleList = writeText "kernel-local-modules" (
    "Module Size Used by\n" + lib.concatMapStrings (name: "${name} 0 0\n") localModules
  );
in
if localModules == [ ] then
  kernel
else
  linuxManualConfig {
    inherit (kernel)
      pname
      version
      src
      modDirVersion
      stdenv
      kernelPatches
      features
      config
      extraMakeFlags
      ;
    randstructSeed = args.randstructSeed or "";
    configfile = kernel.configfile.overrideAttrs (previous: {
      buildPhase = previous.buildPhase + ''
        make $makeFlags -C . O="$buildRoot" \
          LSMOD=${moduleList} \
          LMC_KEEP=${lib.escapeShellArg (lib.concatStringsSep ":" localModuleDirectories)} \
          localmodconfig </dev/null
      '';
    });
  }
