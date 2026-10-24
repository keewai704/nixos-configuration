{ lib }:
with lib.kernel;
{
  LOCALVERSION = lib.mkForce (freeform "-cachyos-citrus");
  LOCALVERSION_AUTO = lib.mkForce no;
  MAXSMP = lib.mkForce no;
  NR_CPUS = lib.mkForce (freeform "32");

  SCHED_CLASS_EXT = yes;
  BPF = yes;
  BPF_SYSCALL = yes;
  BPF_JIT = yes;
  BPF_JIT_ALWAYS_ON = yes;
  BPF_JIT_DEFAULT_ON = yes;
  DEBUG_INFO_BTF = yes;
  DEBUG_INFO_BTF_MODULES = yes;

  HYPERVISOR_GUEST = lib.mkForce no;
  XEN = lib.mkForce no;
  HYPERV = lib.mkForce no;

  DRM_I915 = lib.mkForce no;
  DRM_XE = lib.mkForce no;
  DRM_RADEON = lib.mkForce no;
  DRM_NOUVEAU = lib.mkForce no;
  NOVA_CORE = lib.mkForce no;

  SND_SOC = lib.mkForce no;
  SND_FIREWIRE = lib.mkForce no;
  MEDIA_PCI_SUPPORT = lib.mkForce no;
  MEDIA_ANALOG_TV_SUPPORT = lib.mkForce no;
  MEDIA_DIGITAL_TV_SUPPORT = lib.mkForce no;
  MEDIA_RADIO_SUPPORT = lib.mkForce no;
  MEDIA_SDR_SUPPORT = lib.mkForce no;
  DVB_CORE = lib.mkForce no;

  SCSI_LOWLEVEL = lib.mkForce no;
  ATA_SFF = lib.mkForce no;
  INFINIBAND = lib.mkForce no;
  COMEDI = lib.mkForce no;
  HAMRADIO = lib.mkForce no;
  CAN = lib.mkForce no;
  ATM = lib.mkForce no;
  ISDN = lib.mkForce no;
  NFC = lib.mkForce no;
  WWAN = lib.mkForce no;
  PARPORT = lib.mkForce no;
  PCMCIA = lib.mkForce no;
  FIREWIRE = lib.mkForce no;
  STAGING = lib.mkForce no;
}
// lib.genAttrs (map (vendor: "NET_VENDOR_${vendor}") [
  "3COM"
  "ADAPTEC"
  "AGERE"
  "ALACRITECH"
  "ALIBABA"
  "AMAZON"
  "AMD"
  "AQUANTIA"
  "ARC"
  "ASIX"
  "ATHEROS"
  "BROADCOM"
  "BROCADE"
  "CADENCE"
  "CAVIUM"
  "CHELSIO"
  "CISCO"
  "CORTINA"
  "DAVICOM"
  "DEC"
  "DLI"
  "DLINK"
  "EMULEX"
  "ENGLEDER"
  "EZCHIP"
  "FARADAY"
  "FUNGIBLE"
  "GOOGLE"
  "HISILICON"
  "HUAWEI"
  "I825XX"
  "IBM"
  "JME"
  "LITEX"
  "MARVELL"
  "MELLANOX"
  "MICREL"
  "MICROCHIP"
  "MICROSEMI"
  "MICROSOFT"
  "MYRI"
  "NATSEMI"
  "NETERION"
  "NETRONOME"
  "NI"
  "NS"
  "NVIDIA"
  "OKI"
  "PACKET_ENGINES"
  "PENSANDO"
  "QLOGIC"
  "QUALCOMM"
  "RDC"
  "REALTEK"
  "RENESAS"
  "ROCKER"
  "SAMSUNG"
  "SEEQ"
  "SILAN"
  "SIS"
  "SMSC"
  "SOCIONEXT"
  "STMICRO"
  "SUN"
  "SYNOPSYS"
  "TEHUTI"
  "TI"
  "VERTEXCOM"
  "VIA"
  "WANGXUN"
  "WIZNET"
  "XILINX"
  "XIRCOM"
]) (_: lib.mkForce no)
