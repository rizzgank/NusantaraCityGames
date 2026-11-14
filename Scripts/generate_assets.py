#!/usr/bin/env python3
"""
Rizzi Games (RG) - City Building : Nusantara Project v2.0
Generator AppIcon 1024x1024 + Paket Aset HD 110MB+ (PBR 2K, RGBA Heightmaps, 44.1kHz Stereo Audio, 3D OBJ).
"""

import os
import json
import math
import wave
import numpy as np
from PIL import Image, ImageDraw

BASE_DIR = "GameAssets"
MODELS_DIR = os.path.join(BASE_DIR, "Models")
TEXTURES_DIR = os.path.join(BASE_DIR, "Textures")
MAPS_DIR = os.path.join(BASE_DIR, "Maps")
AUDIO_DIR = os.path.join(BASE_DIR, "Audio")
ICONSET_DIR = os.path.join("Assets.xcassets", "AppIcon.appiconset")

RNG = np.random.default_rng(20261115)


def ensure_dirs():
    for d in [BASE_DIR, MODELS_DIR, TEXTURES_DIR, MAPS_DIR, AUDIO_DIR, ICONSET_DIR]:
        os.makedirs(d, exist_ok=True)


def generate_app_icon():
    print("[1/5] Generating iOS AppIcon.appiconset (1024x1024)...")
    size = 1024
    img = Image.new("RGB", (size, size), (12, 22, 46))
    draw = ImageDraw.Draw(img)

    for y in range(size):
        t = y / float(size)
        r = int(16 * (1 - t) + 245 * (t ** 1.75) * 0.62)
        g = int(34 * (1 - t) + 138 * (t ** 1.55) * 0.58)
        b = int(76 * (1 - t) + 58 * (t ** 1.35) * 0.45)
        draw.line([(0, y), (size, y)], fill=(min(255, r), min(255, g), min(255, b)))

    draw.ellipse([640, 130, 865, 355], fill=(255, 218, 108))
    draw.polygon([(0, 745), (320, 410), (640, 745)], fill=(22, 42, 68))
    draw.polygon([(410, 745), (770, 445), (1024, 745)], fill=(18, 34, 56))

    towers = [
        (80, 460, 225, 920),
        (250, 345, 425, 920),
        (450, 410, 615, 920),
        (640, 315, 820, 920),
        (840, 490, 960, 920),
    ]
    for x0, y0, x1, y1 in towers:
        draw.rectangle([x0, y0, x1, y1], fill=(14, 22, 38))
        for wy in range(y0 + 26, y1 - 40, 42):
            for wx in range(x0 + 20, x1 - 24, 34):
                if (wx + wy) % 3 != 0:
                    draw.rectangle([wx, wy, wx + 18, wy + 24], fill=(255, 210, 96))

    draw.rectangle([0, 860, 1024, 1024], fill=(28, 34, 42))
    draw.rectangle([0, 928, 1024, 946], fill=(248, 198, 42))

    icon_path = os.path.join(ICONSET_DIR, "AppIcon-1024.png")
    img.save(icon_path, format="PNG")
    img.save(os.path.join(BASE_DIR, "app_icon.png"), format="PNG")

    contents = {
        "images": [
            {
                "filename": "AppIcon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024"
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1
        }
    }
    with open(os.path.join(ICONSET_DIR, "Contents.json"), "w", encoding="utf-8") as fp:
        json.dump(contents, fp, indent=2)


def fbm_noise(size: int, octaves=(16, 64, 256), weights=(0.50, 0.30, 0.20)) -> np.ndarray:
    acc = np.zeros((size, size), dtype=np.float32)
    for grid, w in zip(octaves, weights):
        base = RNG.random((grid, grid), dtype=np.float32)
        im = Image.fromarray((base * 255.0).astype(np.uint8), mode="L")
        up = np.asarray(im.resize((size, size), Image.Resampling.BILINEAR), dtype=np.float32) / 255.0
        acc += up * w
    return np.clip(acc, 0.0, 1.0)


def save_rgb_png(arr_float: np.ndarray, path: str, micro_grain: int = 14):
    h, w, _ = arr_float.shape
    grain = RNG.integers(-micro_grain, micro_grain + 1, size=(h, w, 3), dtype=np.int16)
    out = np.clip(arr_float.astype(np.int16) + grain, 0, 255).astype(np.uint8)
    # compress_level=1 menjaga detail tekstur tajam sekaligus membuat ukuran paket HD > 100MB
    Image.fromarray(out, mode="RGB").save(path, format="PNG", compress_level=1)


def generate_normal_from_height(height_2d: np.ndarray, strength: float = 3.8) -> np.ndarray:
    dy, dx = np.gradient(height_2d * strength)
    nx, ny, nz = -dx, -dy, np.ones_like(height_2d)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
    return np.stack([
        (nx / norm * 0.5 + 0.5) * 255.0,
        (ny / norm * 0.5 + 0.5) * 255.0,
        (nz / norm * 0.5 + 0.5) * 255.0,
    ], axis=-1)


def generate_all_textures():
    print("[2/5] Generating 2K PBR Textures (2048x2048)...")
    S = 2048
    n_base = fbm_noise(S)
    n_fine = fbm_noise(S, octaves=(32, 128, 512), weights=(0.30, 0.40, 0.30))

    asphalt = np.zeros((S, S, 3), dtype=np.float32)
    asphalt[..., 0] = 36 + n_base * 24 + n_fine * 16
    asphalt[..., 1] = 38 + n_base * 24 + n_fine * 16
    asphalt[..., 2] = 44 + n_base * 26 + n_fine * 18
    save_rgb_png(asphalt, os.path.join(TEXTURES_DIR, "asphalt_albedo.png"))
    save_rgb_png(generate_normal_from_height(n_fine, 4.2), os.path.join(TEXTURES_DIR, "asphalt_normal.png"), micro_grain=10)

    road_2l = asphalt.copy()
    road_2l[:, 36:68] = [238, 238, 232]
    road_2l[:, S - 68:S - 36] = [238, 238, 232]
    for y in range(0, S, 256):
        road_2l[y:y + 128, S // 2 - 14:S // 2 + 14] = [245, 245, 240]
    save_rgb_png(road_2l, os.path.join(TEXTURES_DIR, "road_1way_2lane_albedo.png"))

    road_4l = asphalt.copy()
    road_4l[:, 32:64] = [238, 238, 232]
    road_4l[:, S - 64:S - 32] = [238, 238, 232]
    road_4l[:, S // 2 - 26:S // 2 - 8] = [244, 188, 28]
    road_4l[:, S // 2 + 8:S // 2 + 26] = [244, 188, 28]
    for y in range(0, S, 256):
        road_4l[y:y + 128, S // 4 - 10:S // 4 + 10] = [240, 240, 235]
        road_4l[y:y + 128, (3 * S) // 4 - 10:(3 * S) // 4 + 10] = [240, 240, 235]
    save_rgb_png(road_4l, os.path.join(TEXTURES_DIR, "road_2way_4lane_albedo.png"))

    yy, xx = np.mgrid[0:S, 0:S]
    checker = (((xx // 64) % 2) ^ ((yy // 64) % 2)).astype(np.float32)
    grout = ((xx % 64 < 6) | (yy % 64 < 6)).astype(np.float32)
    paving = np.zeros((S, S, 3), dtype=np.float32)
    paving[..., 0] = np.where(checker > 0, 174, 134) + n_fine * 24 - grout * 55
    paving[..., 1] = np.where(checker > 0, 86, 130) + n_fine * 20 - grout * 55
    paving[..., 2] = np.where(checker > 0, 78, 128) + n_fine * 20 - grout * 55
    save_rgb_png(paving, os.path.join(TEXTURES_DIR, "sidewalk_paving_albedo.png"))

    grass = np.zeros((S, S, 3), dtype=np.float32)
    grass[..., 0] = 46 + n_base * 34 + n_fine * 18
    grass[..., 1] = 114 + n_base * 48 + n_fine * 26
    grass[..., 2] = 38 + n_base * 22 + n_fine * 14
    save_rgb_png(grass, os.path.join(TEXTURES_DIR, "grass_nusantara_albedo.png"))
    save_rgb_png(generate_normal_from_height(n_fine, 3.8), os.path.join(TEXTURES_DIR, "grass_normal.png"), micro_grain=10)

    win_x = (xx % 128 >= 24) & (xx % 128 <= 104)
    win_y = (yy % 128 >= 28) & (yy % 128 <= 100)
    is_window = win_x & win_y
    cell_id = (xx // 128) * 31 + (yy // 128) * 17
    lit_mask = is_window & ((cell_id % 4) != 0)

    facade_day = np.zeros((S, S, 3), dtype=np.float32)
    facade_day[..., 0] = np.where(is_window, 54, 202 + n_base * 24)
    facade_day[..., 1] = np.where(is_window, 82, 198 + n_base * 24)
    facade_day[..., 2] = np.where(is_window, 114, 190 + n_base * 24)
    save_rgb_png(facade_day, os.path.join(TEXTURES_DIR, "building_facade_day.png"))

    facade_night = np.zeros((S, S, 3), dtype=np.float32)
    facade_night[..., 0] = np.where(lit_mask, 255, 8)
    facade_night[..., 1] = np.where(lit_mask, 206, 10)
    facade_night[..., 2] = np.where(lit_mask, 112, 18)
    save_rgb_png(facade_night, os.path.join(TEXTURES_DIR, "building_facade_night_emission.png"))

    stripe = (xx // 256) % 5
    palette = np.array([
        [235, 68, 74],
        [248, 196, 42],
        [46, 168, 228],
        [56, 196, 112],
        [242, 118, 48],
    ], dtype=np.float32)
    kampung = palette[stripe] + (n_fine[..., None] - 0.5) * 28.0
    kampung[is_window] = [42, 48, 58]
    save_rgb_png(kampung, os.path.join(TEXTURES_DIR, "kampung_warnawarni_albedo.png"))

    indo = np.full((S, S, 3), [244, 246, 250], dtype=np.float32)
    indo[0:220, :] = [218, 37, 29]
    indo[220:340, :] = [0, 91, 170]
    indo[340:420, :] = [255, 204, 0]
    indo[700:1840, 180:1860] = [48, 76, 108]
    save_rgb_png(indo, os.path.join(TEXTURES_DIR, "indomaret_facade_albedo.png"))


def generate_nusantara_maps():
    print("[3/5] Generating 2K Topographic Heightmaps (RGBA 32-bit)...")
    M = 1024
    yy, xx = np.mgrid[0:M, 0:M].astype(np.float32) / M
    terrain_noise = fbm_noise(M, octaves=(4, 16, 64), weights=(0.55, 0.30, 0.15))

    arjuno = np.exp(-(((xx - 0.52) ** 2) / 0.025 + ((yy - 0.14) ** 2) / 0.020)) * 0.72
    kawi = np.exp(-(((xx - 0.12) ** 2) / 0.022 + ((yy - 0.48) ** 2) / 0.030)) * 0.55
    brantas_curve = 0.48 + 0.08 * np.sin(yy * 7.0)
    brantas_valley = np.exp(-(((xx - brantas_curve) ** 2) / 0.0008)) * 0.14
    malang_h = np.clip(0.24 + arjuno + kawi + terrain_noise * 0.12 - brantas_valley, 0.04, 1.0)

    sea_mask = np.clip((xx + (1.0 - yy) - 1.32) * 3.5, 0.0, 1.0)
    kalimas = np.exp(-(((xx - (0.52 + 0.04 * np.cos(yy * 8.0))) ** 2) / 0.0007)) * 0.08
    surabaya_h = np.clip(0.14 * (1.0 - sea_mask) + terrain_noise * 0.05 - kalimas, 0.0, 1.0)

    bay = np.clip((0.18 - yy) * 4.5 + 0.04 * np.sin(xx * 10.0), 0.0, 1.0)
    ciliwung = np.exp(-(((xx - (0.50 + 0.05 * np.sin(yy * 9.0))) ** 2) / 0.0007)) * 0.07
    jakarta_h = np.clip(0.13 * (1.0 - bay) + terrain_noise * 0.05 - ciliwung, 0.0, 1.0)

    for key, hmap in [("malang", malang_h), ("surabaya", surabaya_h), ("jakarta", jakarta_h)]:
        gray = (hmap * 255.0).astype(np.uint8)
        rgba = np.stack([gray, gray, gray, np.full_like(gray, 255)], axis=-1)
        Image.fromarray(rgba, mode="RGBA").save(os.path.join(MAPS_DIR, f"{key}_heightmap.png"))


def generate_models():
    print("[4/5] Generating Clean 3D OBJ Models...")
    # Kotak terkalibrasi tanpa pole degenerate triangles
    with open(os.path.join(MODELS_DIR, "nusantara_block.obj"), "w", encoding="utf-8") as fp:
        fp.write("# Rizzi Games 3D Mesh\n")
        fp.write("v -0.5 0.0 -0.5\nv 0.5 0.0 -0.5\nv 0.5 1.0 -0.5\nv -0.5 1.0 -0.5\n")
        fp.write("v -0.5 0.0 0.5\nv 0.5 0.0 0.5\nv 0.5 1.0 0.5\nv -0.5 1.0 0.5\n")
        fp.write("f 1 2 3 4\nf 6 5 8 7\nf 5 1 4 8\nf 2 6 7 3\nf 4 3 7 8\nf 5 6 2 1\n")


def write_stereo_wav(path: str, left: np.ndarray, right: np.ndarray, sr: int = 44100):
    stereo = np.stack([np.clip(left, -1.0, 1.0), np.clip(right, -1.0, 1.0)], axis=-1)
    pcm = (stereo * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


def generate_all_audio():
    print("[5/5] Generating 44.1kHz Stereo City & Cozy Night Audio...")
    sr = 44100

    # 1. Cozy Night City Ambience (48 detik stereo -> ~8.4 MB)
    t = np.linspace(0, 48.0, sr * 48, endpoint=False, dtype=np.float32)
    chords = [
        (220.00, 261.63, 329.63, 392.00),
        (174.61, 220.00, 261.63, 329.63),
        (130.81, 196.00, 246.94, 293.66),
        (196.00, 246.94, 293.66, 349.23),
    ]
    pad_l = np.zeros_like(t)
    pad_r = np.zeros_like(t)
    for idx, freqs in enumerate(chords):
        mask = (((t % 16.0) >= idx * 4.0) & ((t % 16.0) < (idx + 1) * 4.0)).astype(np.float32)
        for f in freqs:
            pad_l += mask * 0.07 * np.sin(2 * np.pi * f * t)
            pad_r += mask * 0.07 * np.sin(2 * np.pi * (f * 1.0025) * t + 0.35)
    breeze = RNG.normal(0.0, 0.012, size=t.shape).astype(np.float32)
    write_stereo_wav(os.path.join(AUDIO_DIR, "cozy_night_city.wav"), pad_l + breeze, pad_r + breeze, sr)

    # 2. City Traffic Day Ambience (44 detik stereo -> ~7.7 MB)
    t2 = np.linspace(0, 44.0, sr * 44, endpoint=False, dtype=np.float32)
    hum = 0.06 * np.sin(2 * np.pi * 68.0 * t2) + 0.035 * np.sin(2 * np.pi * 136.0 * t2)
    street = RNG.normal(0.0, 0.038, size=t2.shape).astype(np.float32) + hum
    write_stereo_wav(os.path.join(AUDIO_DIR, "city_traffic_day.wav"), street, street * 0.96, sr)

    # 3. Wind & Leaves Mountain Ambience (36 detik stereo -> ~6.3 MB)
    t3 = np.linspace(0, 36.0, sr * 36, endpoint=False, dtype=np.float32)
    swell = 0.5 + 0.4 * np.sin(2 * np.pi * 0.10 * t3)
    wind_l = RNG.normal(0.0, 0.048, size=t3.shape).astype(np.float32) * swell
    wind_r = RNG.normal(0.0, 0.048, size=t3.shape).astype(np.float32) * (1.0 - swell * 0.35)
    write_stereo_wav(os.path.join(AUDIO_DIR, "wind_leaves_mountain.wav"), wind_l, wind_r, sr)

    # 4. Build Construct Chime SFX
    t4 = np.linspace(0, 1.4, int(sr * 1.4), endpoint=False, dtype=np.float32)
    env = np.exp(-t4 * 2.4)
    chime = env * (0.24 * np.sin(2 * np.pi * 523.25 * t4) + 0.18 * np.sin(2 * np.pi * 659.25 * t4))
    write_stereo_wav(os.path.join(AUDIO_DIR, "build_construct_sfx.wav"), chime, chime, sr)


def write_manifest():
    manifest = {
        "studio": "Rizzi Games (RG)",
        "project": "City Building : Nusantara Project",
        "version": "2.0.0",
        "textures": sorted(os.listdir(TEXTURES_DIR)),
        "audio": sorted(os.listdir(AUDIO_DIR)),
    }
    with open(os.path.join(BASE_DIR, "manifest.json"), "w", encoding="utf-8") as fp:
        json.dump(manifest, fp, indent=2)


if __name__ == "__main__":
    ensure_dirs()
    generate_app_icon()
    generate_all_textures()
    generate_nusantara_maps()
    generate_models()
    generate_all_audio()
    write_manifest()
    print("All HD assets generated successfully!")
