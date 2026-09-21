#!/usr/bin/env python3
"""
Renders the CodeCaps 3D teal brand icon directly from the master Usage Monitor
client icon, transforming the orange brand hue to CodeCaps's signature rich teal
(#0B6B5D) while preserving the 3D embossed circuit traces, circular sync arrows,
and glossy white plate.
"""

import sys
from pathlib import Path
import numpy as np
from PIL import Image

def render_teal_icon(source_path: Path, output_dir: Path):
    img = Image.open(source_path).convert('RGB')
    data = np.array(img, dtype=np.float32) / 255.0

    r, g, b = data[:, :, 0], data[:, :, 1], data[:, :, 2]
    maxc = np.maximum(np.maximum(r, g), b)
    minc = np.minimum(np.minimum(r, g), b)
    v = maxc
    deltac = maxc - minc

    s = np.zeros_like(v)
    mask = maxc > 0
    s[mask] = deltac[mask] / maxc[mask]

    h = np.zeros_like(v)
    rc, gc, bc = np.zeros_like(v), np.zeros_like(v), np.zeros_like(v)
    nonzero_delta = deltac > 1e-5

    rc[nonzero_delta] = (maxc[nonzero_delta] - r[nonzero_delta]) / deltac[nonzero_delta]
    gc[nonzero_delta] = (maxc[nonzero_delta] - g[nonzero_delta]) / deltac[nonzero_delta]
    bc[nonzero_delta] = (maxc[nonzero_delta] - b[nonzero_delta]) / deltac[nonzero_delta]

    mask_r = (r == maxc) & nonzero_delta
    mask_g = (g == maxc) & nonzero_delta & ~mask_r
    mask_b = (b == maxc) & nonzero_delta & ~mask_r & ~mask_g

    h[mask_r] = (bc[mask_r] - gc[mask_r]) / 6.0
    h[mask_g] = (2.0 + rc[mask_g] - bc[mask_g]) / 6.0
    h[mask_b] = (4.0 + gc[mask_b] - rc[mask_b]) / 6.0
    h = h % 1.0

    # Rich Brand Teal (#0B6B5D)
    target_h = 0.489
    target_s_scale = 1.12
    target_v_scale = 0.65

    new_h = h.copy()
    new_s = s.copy()
    new_v = v.copy()

    h_dist = np.abs(new_h - 0.08)
    h_dist = np.minimum(h_dist, 1.0 - h_dist)

    weight = np.clip(1.0 - h_dist / 0.12, 0.0, 1.0) * np.clip((new_s - 0.10) / 0.20, 0.0, 1.0)

    new_h = (1.0 - weight) * new_h + weight * target_h
    new_s = np.clip(new_s * (1.0 + (target_s_scale - 1.0) * weight), 0.0, 1.0)
    new_v = np.clip(new_v * (1.0 + (target_v_scale - 1.0) * weight), 0.0, 1.0)

    i = np.floor(new_h * 6.0).astype(int)
    f = (new_h * 6.0) - i
    p = new_v * (1.0 - new_s)
    q = new_v * (1.0 - new_s * f)
    t = new_v * (1.0 - new_s * (1.0 - f))
    i = i % 6

    out_r = np.zeros_like(new_v)
    out_g = np.zeros_like(new_v)
    out_b = np.zeros_like(new_v)

    m0 = (i == 0); out_r[m0], out_g[m0], out_b[m0] = new_v[m0], t[m0], p[m0]
    m1 = (i == 1); out_r[m1], out_g[m1], out_b[m1] = q[m1], new_v[m1], p[m1]
    m2 = (i == 2); out_r[m2], out_g[m2], out_b[m2] = p[m2], new_v[m2], t[m2]
    m3 = (i == 3); out_r[m3], out_g[m3], out_b[m3] = p[m3], q[m3], new_v[m3]
    m4 = (i == 4); out_r[m4], out_g[m4], out_b[m4] = t[m4], p[m4], new_v[m4]
    m5 = (i == 5); out_r[m5], out_g[m5], out_b[m5] = new_v[m5], p[m5], q[m5]

    rgb = np.stack([out_r, out_g, out_b], axis=-1)
    rgb = np.clip(rgb * 255.0, 0, 255).astype(np.uint8)
    master = Image.fromarray(rgb)

    # Master 1024x1024
    output_1024 = output_dir / "assets" / "icon-1024.png"
    master.save(output_1024, format="PNG")
    print(f"Saved {output_1024}")

    # AppIcon for iOS Companion
    ios_icon = output_dir / "ios" / "CodeCapsCompanion" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
    master.save(ios_icon, format="PNG")
    print(f"Saved {ios_icon}")

    # 512x512
    output_512 = output_dir / "assets" / "icon-512.png"
    master.resize((512, 512), Image.Resampling.LANCZOS).save(output_512, format="PNG")
    print(f"Saved {output_512}")

    # 192x192
    output_192 = output_dir / "docs" / "icon-192.png"
    master.resize((192, 192), Image.Resampling.LANCZOS).save(output_192, format="PNG")
    print(f"Saved {output_192}")

if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parent.parent
    src = Path("/Users/jay/Code/Usage-Monitor/public/brand/icon-1024.png")
    if len(sys.argv) > 1:
        src = Path(sys.argv[1])
    render_teal_icon(src, repo_root)
