import struct
import sys
import time

SMU = "/sys/kernel/ryzen_smu_drv/"
SET_CORE = 0x6
GET_CORE = 0xD5


def rsmu(cmd, arg):
    with open(SMU + "smu_args", "wb") as f:
        f.write(struct.pack("<6I", arg, 0, 0, 0, 0, 0))
    with open(SMU + "rsmu_cmd", "wb") as f:
        f.write(struct.pack("<I", cmd))
    for _ in range(200):
        with open(SMU + "rsmu_cmd", "rb") as f:
            status = struct.unpack("<I", f.read(4))[0]
        if status:
            break
        time.sleep(0.005)
    if status != 1:
        raise RuntimeError(f"SMU command {cmd:#x} returned {status:#x}")
    with open(SMU + "smu_args", "rb") as f:
        return struct.unpack("<I", f.read(4))[0]


def margin_arg(margin):
    return ((0x100000 if margin < 0 else 0) + margin) & 0xFFFF


def read_margin(core):
    value = rsmu(GET_CORE, core << 20) & 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


for _ in range(100):
    try:
        open(SMU + "rsmu_cmd", "rb").close()
        break
    except FileNotFoundError:
        time.sleep(0.1)

margins = [int(v) for v in sys.argv[1:]]
for core, margin in enumerate(margins):
    if not -50 <= margin <= 0:
        raise ValueError(f"core {core}: margin {margin} out of range")
    rsmu(SET_CORE, (core << 20) | margin_arg(margin))

applied = [read_margin(core) for core in range(len(margins))]
if applied != margins:
    raise RuntimeError(f"expected {margins}, SMU reports {applied}")
print("Curve Optimizer:", " ".join(f"{m:+d}" for m in applied))
