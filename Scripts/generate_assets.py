#!/usr/bin/env python3
import os
import json
import wave
import numpy as np
from PIL import Image, ImageDraw

BASE_DIR = "GameAssets"
TEXTURES_DIR = os.path.join(BASE_DIR, "Textures")
MAPS_DIR = os.path.join(BASE_DIR, "Maps")
AUDIO_DIR = os.path.join(BASE_DIR, "Audio")
ICONSET_DIR = os.path.join("Assets.xcassets", "AppIcon.appiconset")
RNG = np.random.default_rng(20261115)


def ensure_dirs():
    for d in [BASE_DIR, TEXTURES_DIR, MAPS_DIR, AUDIO_DIR, ICONSET_DIR]:
        os.makedirs(d, exist_ok=True)


def generate_app_icon():
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

    towers = [(80, 460, 225, 920), (250, 345, 425, 920), (450, 410, 615, 920), (640, 315, 820, 920), (840, 490, 960, 920)]
    for x0, y0, x1, y1 in towers:
        draw.rectangle([x0, y0, x1, y1], fill=(14, 22, 38))
        for wy in range(y0 + 26, y1 - 40, 42):
            for wx in range(x0 + 20, x1 - 24, 34):
                if (wx + wy) % 3 != 0:
                    draw.rectangle([wx, wy, wx + 18, wy + 24], fill=(255, 210, 96))

    draw.rectangle([0, 860, 1024, 1024], fill=(28, 34, 42))
    draw.rectangle([0, 928, 1024, 946], fill=(248, 198, 42))

    img.save(os.path.join(ICONSET_DIR, "AppIcon-1024.png"), format="PNG")
    contents = {
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1}
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


def save_rgb_png(arr_float: np.ndarray, path: str, micro_grain: int = 10):
    h, w, _ = arr_float.shape
    grain = RNG.integers(-micro_grain, micro_grain + 1, size=(h, w, 3), dtype=np.int16)
    out = np.clip(arr_float.astype(np.int16) + grain, 0, 255).astype(np.uint8)
    Image.fromarray(out, mode="RGB").save(path, format="PNG", compress_level=6)


def generate_textures():
    S = 1024
    n_base = fbm_noise(S, octaves=(8, 32, 128))
    n_fine = fbm_noise(S, octaves=(16, 64, 256))
    yy, xx = np.mgrid[0:S, 0:S]

    asphalt = np.zeros((S, S, 3), dtype=np.float32)
    asphalt[..., 0] = 36 + n_base * 20 + n_fine * 12
    asphalt[..., 1] = 38 + n_base * 20 + n_fine * 12
    asphalt[..., 2] = 44 + n_base * 22 + n_fine * 14

    road_2l = asphalt.copy()
    road_2l[:, 18:34] = [238, 238, 232]
    road_2l[:, S - 34:S - 18] = [238, 238, 232]
    for y in range(0, S, 128):
        road_2l[y:y + 64, S // 2 - 7:S // 2 + 7] = [245, 245, 240]
    save_rgb_png(road_2l, os.path.join(TEXTURES_DIR, "road_2lane_albedo.png"))

    road_4l = asphalt.copy()
    road_4l[:, 16:32] = [238, 238, 232]
    road_4l[:, S - 32:S - 16] = [238, 238, 232]
    road_4l[:, S // 2 - 14:S // 2 - 4] = [244, 188, 28]
    road_4l[:, S // 2 + 4:S // 2 + 14] = [244, 188, 28]
    for y in range(0, S, 128):
        road_4l[y:y + 64, S // 4 - 5:S // 4 + 5] = [240, 240, 235]
        road_4l[y:y + 64, (3 * S) // 4 - 5:(3 * S) // 4 + 5] = [240, 240, 235]
    save_rgb_png(road_4l, os.path.join(TEXTURES_DIR, "road_4lane_albedo.png"))

    checker = (((xx // 32) % 2) ^ ((yy // 32) % 2)).astype(np.float32)
    grout = ((xx % 32 < 3) | (yy % 32 < 3)).astype(np.float32)
    paving = np.zeros((S, S, 3), dtype=np.float32)
    paving[..., 0] = np.where(checker > 0, 174, 134) + n_fine * 20 - grout * 50
    paving[..., 1] = np.where(checker > 0, 86, 130) + n_fine * 18 - grout * 50
    paving[..., 2] = np.where(checker > 0, 78, 128) + n_fine * 18 - grout * 50
    save_rgb_png(paving, os.path.join(TEXTURES_DIR, "sidewalk_paving_albedo.png"))

    grass = np.zeros((S, S, 3), dtype=np.float32)
    grass[..., 0] = 44 + n_base * 30 + n_fine * 16
    grass[..., 1] = 112 + n_base * 46 + n_fine * 24
    grass[..., 2] = 36 + n_base * 20 + n_fine * 12
    save_rgb_png(grass, os.path.join(TEXTURES_DIR, "grass_nusantara_albedo.png"))

    win_x = (xx % 64 >= 12) & (xx % 64 <= 52)
    win_y = (yy % 64 >= 14) & (yy % 64 <= 50)
    is_window = win_x & win_y
    cell_id = (xx // 64) * 31 + (yy // 64) * 17
    lit_mask = is_window & ((cell_id % 4) != 0)

    facade_day = np.zeros((S, S, 3), dtype=np.float32)
    facade_day[..., 0] = np.where(is_window, 54, 202 + n_base * 22)
    facade_day[..., 1] = np.where(is_window, 82, 198 + n_base * 22)
    facade_day[..., 2] = np.where(is_window, 114, 190 + n_base * 22)
    save_rgb_png(facade_day, os.path.join(TEXTURES_DIR, "building_facade_day.png"))

    facade_night = np.zeros((S, S, 3), dtype=np.float32)
    facade_night[..., 0] = np.where(lit_mask, 255, 8)
    facade_night[..., 1] = np.where(lit_mask, 206, 10)
    facade_night[..., 2] = np.where(lit_mask, 112, 18)
    save_rgb_png(facade_night, os.path.join(TEXTURES_DIR, "building_facade_night_emission.png"))

    stripe = (xx // 128) % 5
    palette = np.array([[235, 68, 74], [248, 196, 42], [46, 168, 228], [56, 196, 112], [242, 118, 48]], dtype=np.float32)
    kampung = palette[stripe] + (n_fine[..., None] - 0.5) * 24.0
    kampung[is_window] = [42, 48, 58]
    save_rgb_png(kampung, os.path.join(TEXTURES_DIR, "kampung_warnawarni_albedo.png"))

    indo = np.full((S, S, 3), [244, 246, 250], dtype=np.float32)
    indo[0:110, :] = [218, 37, 29]
    indo[110:170, :] = [0, 91, 170]
    indo[170:210, :] = [255, 204, 0]
    indo[350:920, 90:930] = [48, 76, 108]
    save_rgb_png(indo, os.path.join(TEXTURES_DIR, "indomaret_facade_albedo.png"))


def write_stereo_wav(path: str, left: np.ndarray, right: np.ndarray, sr: int = 22050):
    stereo = np.stack([np.clip(left, -1.0, 1.0), np.clip(right, -1.0, 1.0)], axis=-1)
    pcm = (stereo * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


def generate_audio():
    sr = 22050
    t = np.linspace(0, 24.0, sr * 24, endpoint=False, dtype=np.float32)
    chords = [(220.0, 261.63, 329.63), (174.61, 220.0, 261.63), (130.81, 196.0, 246.94), (196.0, 246.94, 293.66)]
    pad_l = np.zeros_like(t)
    pad_r = np.zeros_like(t)
    for idx, freqs in enumerate(chords):
        mask = (((t % 12.0) >= idx * 3.0) & ((t % 12.0) < (idx + 1) * 3.0)).astype(np.float32)
        for f in freqs:
            pad_l += mask * 0.07 * np.sin(2 * np.pi * f * t)
            pad_r += mask * 0.07 * np.sin(2 * np.pi * (f * 1.002) * t + 0.3)
    write_stereo_wav(os.path.join(AUDIO_DIR, "cozy_night_city.wav"), pad_l, pad_r, sr)

    t2 = np.linspace(0, 20.0, sr * 20, endpoint=False, dtype=np.float32)
    day_amb = RNG.normal(0.0, 0.025, size=t2.shape).astype(np.float32) + 0.04 * np.sin(2 * np.pi * 68.0 * t2)
    write_stereo_wav(os.path.join(AUDIO_DIR, "city_traffic_day.wav"), day_amb, day_amb * 0.95, sr)

    t3 = np.linspace(0, 0.8, int(sr * 0.8), endpoint=False, dtype=np.float32)
    chime = np.exp(-t3 * 3.2) * (0.22 * np.sin(2 * np.pi * 523.25 * t3) + 0.16 * np.sin(2 * np.pi * 659.25 * t3))
    write_stereo_wav(os.path.join(AUDIO_DIR, "build_construct_sfx.wav"), chime, chime, sr)


if __name__ == "__main__":
    ensure_dirs()
    generate_app_icon()
    generate_textures()
    generate_audio()
    print("HD Assets & AppIcon generated cleanly!")
