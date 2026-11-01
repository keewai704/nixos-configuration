import argparse
import ctypes
import json
import math
import sys
import types
import wave
from pathlib import Path

import av
import numpy as np
import torch
import torch.nn.functional as F
from safetensors.torch import load_file
from torch import nn

UPSTREAM = Path("@upstream@")
WEIGHTS = "@weights@"
SCAN = ctypes.CDLL("@scan@")
SAMPLE_RATE = 16000
CHUNK_SECONDS = 5
HOP_PORTION = 0.5


def pointer(tensor, offset=0):
    return ctypes.c_void_p(tensor.data_ptr() + offset * tensor.element_size())


class Mamba(nn.Module):
    def __init__(self, d_model, d_state=16, d_conv=4, expand=2):
        super().__init__()
        d_inner = expand * d_model
        self.dt_rank = math.ceil(d_model / 16)
        self.d_state = d_state
        self.in_proj = nn.Linear(d_model, 2 * d_inner, bias=False)
        self.conv1d = nn.Conv1d(d_inner, d_inner, d_conv, groups=d_inner, padding=d_conv - 1)
        self.x_proj = nn.Linear(d_inner, self.dt_rank + 2 * d_state, bias=False)
        self.dt_proj = nn.Linear(self.dt_rank, d_inner)
        self.A_log = nn.Parameter(torch.empty(d_inner, d_state))
        self.D = nn.Parameter(torch.empty(d_inner))
        self.out_proj = nn.Linear(d_inner, d_model, bias=False)

    def forward(self, hidden):
        batch, length, _ = hidden.shape
        channels = self.D.shape[0]
        xz = self.in_proj(hidden.contiguous())
        x = torch.empty(batch, length, channels)
        SCAN.causal_conv(
            pointer(xz),
            ctypes.c_long(xz.shape[-1]),
            pointer(self.conv1d.weight),
            pointer(self.conv1d.bias),
            pointer(x),
            *(ctypes.c_long(n) for n in (batch, length, channels, self.conv1d.kernel_size[0])),
        )
        x_dbl = self.x_proj(x)
        delta = F.linear(x_dbl[..., : self.dt_rank], self.dt_proj.weight).contiguous()
        a = -torch.exp(self.A_log)
        y = torch.empty_like(x)
        SCAN.selective_scan(
            pointer(x),
            pointer(delta),
            pointer(self.dt_proj.bias),
            pointer(x_dbl, self.dt_rank),
            ctypes.c_long(x_dbl.shape[-1]),
            pointer(xz, channels),
            ctypes.c_long(xz.shape[-1]),
            pointer(a),
            pointer(self.D),
            pointer(y),
            *(ctypes.c_long(n) for n in (batch, length, channels, self.d_state)),
        )
        return self.out_proj(y)


def load_model():
    mamba_ssm = types.ModuleType("mamba_ssm")
    mamba_ssm.Mamba = Mamba
    sys.modules["mamba_ssm"] = mamba_ssm
    sys.path.insert(0, str(UPSTREAM))
    from models import generator_SEMamba_time_d4, stfts

    cfg = json.loads((UPSTREAM / "config.json").read_text())
    model = generator_SEMamba_time_d4.SEMamba(cfg)
    model.load_state_dict(load_file(WEIGHTS), strict=True)
    return model.eval(), cfg, stfts


def read_audio(path):
    resampler = av.AudioResampler(format="flt", layout="mono", rate=SAMPLE_RATE)
    frames = []
    with av.open(str(path)) as container:
        for frame in container.decode(audio=0):
            frames.extend(resampler.resample(frame))
        frames.extend(resampler.resample(None))
    return torch.from_numpy(np.concatenate([f.to_ndarray() for f in frames], axis=1))


def scaled(value, cfg):
    value = round(value * SAMPLE_RATE // cfg["stft_cfg"]["sampling_rate"])
    return value + value % 2


def enhance(model, cfg, stfts, audio):
    n_fft, hop, win = (scaled(cfg["stft_cfg"][k], cfg) for k in ("n_fft", "hop_size", "win_size"))
    compress = cfg["model_cfg"]["compress_factor"]
    chunk = int(CHUNK_SECONDS * SAMPLE_RATE)
    stride = int(HOP_PORTION * chunk)
    window = torch.hann_window(chunk).clamp(min=1e-7)
    enhanced = torch.zeros_like(audio)
    weight = torch.zeros_like(audio)
    count = max(1, math.ceil((audio.shape[1] - chunk) / stride) + 1)
    for i in range(count):
        part = slice(i * stride, i * stride + chunk) if i < count - 1 else slice(-chunk, None)
        noisy = audio[:, part]
        mag, pha, _ = stfts.mag_phase_stft(noisy, n_fft, hop, win, compress, center=True, addeps=False)
        amp, phase, _ = model(mag, pha)
        silent = (torch.expm1(F.relu(amp)) == 0).float().mean(1) > 0.5
        amp[:, :, silent[0]] = 0
        clean = stfts.mag_phase_istft(amp, phase, n_fft, hop, win, compress)
        clean = F.pad(clean, (0, max(0, noisy.shape[1] - clean.shape[1])), value=1e-8)[:, : noisy.shape[1]]
        enhanced[:, part] += clean * window[: clean.shape[1]]
        weight[:, part] += window[: clean.shape[1]]
    return enhanced / weight


def write_wav(path, audio):
    pcm = (audio.clamp(-1, 1) * 32767).round().to(torch.int16).numpy()
    with open(path, "xb") as file, wave.open(file, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(pcm.astype("<i2").tobytes())


def main():
    parser = argparse.ArgumentParser(description="Denoise speech with NVIDIA NemotronLabs RE-USE on CPU into 16 kHz mono WAV.")
    parser.add_argument("input", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    output = args.output_dir / f"{args.input.stem}.wav"
    if output.exists():
        sys.exit(f"{output} already exists")
    audio = read_audio(args.input)
    model, cfg, stfts = load_model()
    with torch.inference_mode():
        clean = enhance(model, cfg, stfts, audio)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_wav(output, clean[0])
    print(output)


if __name__ == "__main__":
    main()
