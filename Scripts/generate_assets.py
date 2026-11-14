#!/usr/bin/env python3
import os
import json
import wave
import numpy as np
from PIL import Image, ImageDraw

BASE_DIR = "GameAssets"
TEXTURES_DIR = os.path.join(BASE_DIR, "Textures")
AUDIO_DIR = os.path.join(BASE_DIR, "Audio")
ICONSET_DIR = os.path.join("Assets.xcassets", "AppIcon.appiconset")
RNG = np.random.default_rng(20261116)


def ensure_dirs():
    for d in [BASE_DIR, TEXTURES_DIR, AUDIO_DIR, ICONSET_DIR]:
        os.makedirs(d, exist_ok=True)


def generate_app_icon():
    size = 1024
    img = Image.new("RGB", (size, size), (12, 22, 46))
    draw = ImageDraw.Draw(img)

    for y in range(size):
        t = y / float(size)
        r = int(14 * (1 - t) + 248 * (t ** 1.7) * 0.65)
        g = int(30 * (1 - t) + 142 * (t ** 1.5) * 0.60)
        b = int(74 * (1 - t) + 56 * (t ** 1.3) * 0.45)
        draw.line([(0, y), (size, y)], fill=(min(255, r), min(255, g), min(255, b)))

    draw.ellipse([640, 125, 870, 355], fill=(255, 222, 112))
    draw.polygon([(0, 745), (320, 395), (640, 745)], fill=(20, 42, 66))
    draw.polygon([(410, 745), (775, 435), (1024, 745)], fill=(16, 34, 54))

    towers = [(75, 455, 225, 920), (248, 340, 425, 920), (448, 405, 615, 920), (638, 310, 822, 920), (840, 485, 962, 920)]
    for x0, y0, x1, y1 in towers:
        draw.rectangle([x0, y0, x1, y1], fill=(13, 21, 36))
        for wy in range(y0 + 26, y1 - 40, 40):
            for wx in range(x0 + 20, x1 - 24, 34):
                if (wx + wy) % 3 != 0:
                    draw.rectangle([wx, wy, wx + 18, wy + 24], fill=(255, 212, 96))

    draw.rectangle([0, 860, 1024, 1024], fill=(26, 32, 40))
    draw.rectangle([0, 928, 1024, 946], fill=(248, 198, 42))

    img.save(os.path.join(ICONSET_DIR, "AppIcon-1024.png"), format="PNG")
    contents = {
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1}
    }
    with open(os.path.join(ICONSET_DIR, "Contents.json"), "w", encoding="utf-8") as fp:
        json.dump(contents, fp, indent=2)


def generate_sky_domes():
    W, H = 1024, 512
    yy, xx = np.mgrid[0:H, 0:W]
    v = yy.astype(np.float32) / float(H)
    above = v <= 0.52
    t_up = np.clip(v / 0.52, 0.0, 1.0)

    # 1. Day Sky Panorama with Volumetric Clouds
    cloud_n = fbm_noise_rect(W, H, octaves=(8, 24, 64))
    day = np.zeros((H, W, 3), dtype=np.float32)
    day[..., 0] = np.where(above, 36 * (1 - t_up) + 185 * (t_up ** 1.6), 72)
    day[..., 1] = np.where(above, 122 * (1 - t_up) + 222 * (t_up ** 1.4), 96)
    day[..., 2] = np.where(above, 226 * (1 - t_up) + 248 * (t_up ** 1.2), 112)
    cloud_mask = np.clip((cloud_n - 0.52) * 2.8, 0.0, 1.0) * np.where(above, 1.0 - (t_up ** 3), 0.0)
    day[..., 0] = day[..., 0] * (1 - cloud_mask * 0.75) + 252 * (cloud_mask * 0.75)
    day[..., 1] = day[..., 1] * (1 - cloud_mask * 0.75) + 252 * (cloud_mask * 0.75)
    day[..., 2] = day[..., 2] * (1 - cloud_mask * 0.75) + 255 * (cloud_mask * 0.75)
    sun_d = np.sqrt(((xx - 720.0) / 1.4) ** 2 + (yy - 165.0) ** 2)
    sun_glow = np.exp(-sun_d / 38.0) * 140.0
    day = np.clip(day + sun_glow[..., None] * np.array([1.0, 0.94, 0.78]), 0, 255)
    Image.fromarray(day.astype(np.uint8), mode="RGB").save(os.path.join(TEXTURES_DIR, "sky_day_equirect.png"), format="PNG")

    # 2. Golden Hour Sunset Panorama
    sunset = np.zeros((H, W, 3), dtype=np.float32)
    sunset[..., 0] = np.where(above, 28 * (1 - t_up) + 252 * (t_up ** 1.5), 48)
    sunset[..., 1] = np.where(above, 42 * (1 - t_up) + 148 * (t_up ** 1.7), 38)
    sunset[..., 2] = np.where(above, 96 * (1 - t_up) + 92 * (t_up ** 1.2), 52)
    sun_d2 = np.sqrt(((xx - 760.0) / 1.6) ** 2 + (yy - 235.0) ** 2)
    glow2 = np.exp(-sun_d2 / 52.0) * 160.0
    sunset = np.clip(sunset + glow2[..., None] * np.array([1.0, 0.72, 0.35]), 0, 255)
    Image.fromarray(sunset.astype(np.uint8), mode="RGB").save(os.path.join(TEXTURES_DIR, "sky_sunset_equirect.png"), format="PNG")

    # 3. Starry Night Panorama
    night = np.zeros((H, W, 3), dtype=np.float32)
    night[..., 0] = np.where(above, 6 * (1 - t_up) + 22 * t_up, 8)
    night[..., 1] = np.where(above, 10 * (1 - t_up) + 32 * t_up, 10)
    night[..., 2] = np.where(above, 26 * (1 - t_up) + 58 * t_up, 18)
    for _ in range(420):
        sx = int(RNG.integers(0, W))
        sy = int(RNG.integers(10, int(H * 0.46)))
        b = float(RNG.integers(150, 255))
        night[sy, sx] = [b, b, min(255.0, b * 1.05)]
    Image.fromarray(night.astype(np.uint8), mode="RGB").save(os.path.join(TEXTURES_DIR, "sky_night_equirect.png"), format="PNG")


def fbm_noise_rect(w: int, h: int, octaves=(16, 64, 256), weights=(0.50, 0.30, 0.20)) -> np.ndarray:
    acc = np.zeros((h, w), dtype=np.float32)
    for grid, weight in zip(octaves, weights):
        base = RNG.random((grid, grid), dtype=np.float32)
        im = Image.fromarray((base * 255.0).astype(np.uint8), mode="L")
        up = np.asarray(im.resize((w, h), Image.Resampling.BILINEAR), dtype=np.float32) / 255.0
        acc += up * weight
    return np.clip(acc, 0.0, 1.0)


def fbm_noise(size: int, octaves=(16, 64, 256), weights=(0.50, 0.30, 0.20)) -> np.ndarray:
    return fbm_noise_rect(size, size, octaves, weights)


def save_rgb_png(arr_float: np.ndarray, path: str, micro_grain: int = 7):
    h, w, _ = arr_float.shape
    grain = RNG.integers(-micro_grain, micro_grain + 1, size=(h, w, 3), dtype=np.int16)
    out = np.clip(arr_float.astype(np.int16) + grain, 0, 255).astype(np.uint8)
    Image.fromarray(out, mode="RGB").save(path, format="PNG", compress_level=6)


def generate_normal_from_height(height_2d: np.ndarray, strength: float = 4.2) -> np.ndarray:
    dy, dx = np.gradient(height_2d * strength)
    nx, ny, nz = -dx, -dy, np.ones_like(height_2d)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
    return np.stack([
        (nx / norm * 0.5 + 0.5) * 255.0,
        (ny / norm * 0.5 + 0.5) * 255.0,
        (nz / norm * 0.5 + 0.5) * 255.0,
    ], axis=-1)


def generate_foliage_texture(path: str, base_rgb: tuple, highlight_rgb: tuple, pine_shape: bool = False):
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx = S // 2
    for i in range(340):
        t = i / 340.0
        if pine_shape:
            y = int(38 + t * 420)
            half_w = int(18 + t * 192)
            x = int(cx + RNG.integers(-half_w, half_w + 1))
            r = int(RNG.integers(12, 28))
        else:
            ang = RNG.uniform(0, 2 * np.pi)
            rad = np.sqrt(RNG.uniform(0, 1)) * 212
            x = int(cx + np.cos(ang) * rad)
            y = int(245 + np.sin(ang) * rad * 0.88)
            r = int(RNG.integers(15, 36))
        mix = RNG.uniform(0.0, 1.0)
        col = (
            int(base_rgb[0] * (1 - mix) + highlight_rgb[0] * mix),
            int(base_rgb[1] * (1 - mix) + highlight_rgb[1] * mix),
            int(base_rgb[2] * (1 - mix) + highlight_rgb[2] * mix),
            248,
        )
        draw.ellipse([x - r, y - r, x + r, y + r], fill=col)

    img.save(path, format="PNG")


def generate_textures():
    S = 1024
    n_base = fbm_noise(S, octaves=(8, 32, 128))
    n_fine = fbm_noise(S, octaves=(16, 64, 256))
    yy, xx = np.mgrid[0:S, 0:S]

    # 1. Asphalt & Roads (2-Lane & Wide 4-Lane Boulevard)
    asphalt = np.zeros((S, S, 3), dtype=np.float32)
    asphalt[..., 0] = 34 + n_base * 16 + n_fine * 10
    asphalt[..., 1] = 36 + n_base * 16 + n_fine * 10
    asphalt[..., 2] = 42 + n_base * 18 + n_fine * 12
    save_rgb_png(generate_normal_from_height(n_fine, 4.2), os.path.join(TEXTURES_DIR, "asphalt_normal.png"), micro_grain=4)

    # 2-Lane Road: Clear yellow/white center line at S//2, left lane centered at S//4
    road_2l = asphalt.copy()
    road_2l[:, 14:30] = [240, 240, 234]
    road_2l[:, S - 30:S - 14] = [240, 240, 234]
    for y in range(0, S, 128):
        road_2l[y:y + 68, S // 2 - 8:S // 2 + 8] = [248, 204, 42]
    save_rgb_png(road_2l, os.path.join(TEXTURES_DIR, "road_2lane_albedo.png"))

    # Wide 4-Lane Arterial Boulevard: Double yellow center divider + 2 lanes each direction
    road_4l = asphalt.copy()
    road_4l[:, 12:28] = [242, 242, 236]
    road_4l[:, S - 28:S - 12] = [242, 242, 236]
    road_4l[:, S // 2 - 16:S // 2 - 5] = [248, 192, 32]
    road_4l[:, S // 2 + 5:S // 2 + 16] = [248, 192, 32]
    for y in range(0, S, 128):
        road_4l[y:y + 64, S // 4 - 6:S // 4 + 6] = [244, 244, 240]
        road_4l[y:y + 64, (3 * S) // 4 - 6:(3 * S) // 4 + 6] = [244, 244, 240]
    save_rgb_png(road_4l, os.path.join(TEXTURES_DIR, "road_4lane_albedo.png"))

    # Intersection with Zebra Crossings
    inter = asphalt.copy()
    for stripe_x in range(180, 844, 72):
        inter[38:145, stripe_x:stripe_x + 36] = [244, 244, 240]
        inter[S - 145:S - 38, stripe_x:stripe_x + 36] = [244, 244, 240]
    for stripe_y in range(180, 844, 72):
        inter[stripe_y:stripe_y + 36, 38:145] = [244, 244, 240]
        inter[stripe_y:stripe_y + 36, S - 145:S - 38] = [244, 244, 240]
    save_rgb_png(inter, os.path.join(TEXTURES_DIR, "road_intersection_albedo.png"))

    # 2. Sidewalk Paving
    checker = (((xx // 32) % 2) ^ ((yy // 32) % 2)).astype(np.float32)
    grout = ((xx % 32 < 3) | (yy % 32 < 3)).astype(np.float32)
    paving = np.zeros((S, S, 3), dtype=np.float32)
    paving[..., 0] = np.where(checker > 0, 176, 136) + n_fine * 18 - grout * 46
    paving[..., 1] = np.where(checker > 0, 94, 134) + n_fine * 16 - grout * 46
    paving[..., 2] = np.where(checker > 0, 84, 132) + n_fine * 16 - grout * 46
    save_rgb_png(paving, os.path.join(TEXTURES_DIR, "sidewalk_paving_albedo.png"))

    # 3. Ultra-Detailed Tropical Grass & Mountain Rock Strata Normal
    grass = np.zeros((S, S, 3), dtype=np.float32)
    blade_streaks = np.sin(xx * 0.45 + n_fine * 6.0) * 8.0
    grass[..., 0] = 52 + n_base * 28 + n_fine * 16 + blade_streaks * 0.5
    grass[..., 1] = 118 + n_base * 42 + n_fine * 22 + blade_streaks
    grass[..., 2] = 44 + n_base * 20 + n_fine * 12
    save_rgb_png(grass, os.path.join(TEXTURES_DIR, "grass_nusantara_albedo.png"))
    save_rgb_png(generate_normal_from_height(n_fine, 4.4), os.path.join(TEXTURES_DIR, "grass_normal.png"), micro_grain=4)

    # Multi-layered Water Ripples Normal
    wave_h = np.sin(xx * 0.08 + n_base * 5.0) * 0.5 + np.cos(yy * 0.11 + n_fine * 4.0) * 0.5
    save_rgb_png(generate_normal_from_height(wave_h, 3.6), os.path.join(TEXTURES_DIR, "water_normal.png"), micro_grain=3)

    # 4. Terracotta Roof Tiles
    tile_wave = np.sin((xx / 16.0) * np.pi) * 18.0
    row_step = ((yy % 32) < 4).astype(np.float32) * 34.0
    roof = np.zeros((S, S, 3), dtype=np.float32)
    roof[..., 0] = 180 + n_base * 20 + tile_wave - row_step
    roof[..., 1] = 76 + n_base * 14 + tile_wave * 0.5 - row_step
    roof[..., 2] = 52 + n_base * 10 - row_step * 0.6
    save_rgb_png(roof, os.path.join(TEXTURES_DIR, "roof_terracotta_albedo.png"))

    # 5. Residential & High-Rise Glass Curtain Wall Facades
    win_x = (xx % 64 >= 10) & (xx % 64 <= 54)
    win_y = (yy % 64 >= 12) & (yy % 64 <= 52)
    is_window = win_x & win_y
    cell_id = (xx // 64) * 31 + (yy // 64) * 17
    lit_mask = is_window & ((cell_id % 4) != 0)

    house_wall = np.zeros((S, S, 3), dtype=np.float32)
    house_wall[..., 0] = np.where(is_window, 44, 236 + n_base * 12)
    house_wall[..., 1] = np.where(is_window, 68, 228 + n_base * 12)
    house_wall[..., 2] = np.where(is_window, 94, 212 + n_base * 12)
    house_wall[yy > 820, :] = [110, 114, 120]
    save_rgb_png(house_wall, os.path.join(TEXTURES_DIR, "house_wall_albedo.png"))

    facade_day = np.zeros((S, S, 3), dtype=np.float32)
    facade_day[..., 0] = np.where(is_window, 38, 196 + n_base * 18)
    facade_day[..., 1] = np.where(is_window, 76, 198 + n_base * 18)
    facade_day[..., 2] = np.where(is_window, 118, 200 + n_base * 18)
    save_rgb_png(facade_day, os.path.join(TEXTURES_DIR, "building_facade_day.png"))

    facade_night = np.zeros((S, S, 3), dtype=np.float32)
    facade_night[..., 0] = np.where(lit_mask, 255, 4)
    facade_night[..., 1] = np.where(lit_mask, 210, 6)
    facade_night[..., 2] = np.where(lit_mask, 118, 14)
    save_rgb_png(facade_night, os.path.join(TEXTURES_DIR, "building_facade_night_emission.png"))

    # 6. School / Civic Facade
    school = np.zeros((S, S, 3), dtype=np.float32)
    school[..., 0] = np.where(is_window, 48, 238 + n_base * 12)
    school[..., 1] = np.where(is_window, 72, 232 + n_base * 12)
    school[..., 2] = np.where(is_window, 96, 212 + n_base * 12)
    school[yy % 128 < 14, :] = [168, 62, 42]
    save_rgb_png(school, os.path.join(TEXTURES_DIR, "school_facade_albedo.png"))

    # 7. Kampung Warna-Warni
    stripe = (xx // 128) % 5
    palette = np.array([[228, 74, 78], [242, 192, 52], [54, 162, 218], [62, 188, 112], [236, 120, 56]], dtype=np.float32)
    kampung = palette[stripe] + (n_fine[..., None] - 0.5) * 20.0
    kampung[is_window] = [42, 48, 58]
    save_rgb_png(kampung, os.path.join(TEXTURES_DIR, "kampung_warnawarni_albedo.png"))

    # 8. Indomaret & Alfamart Franchises
    indo = np.full((S, S, 3), [246, 248, 252], dtype=np.float32)
    indo[0:105, :] = [218, 37, 29]
    indo[105:165, :] = [0, 91, 170]
    indo[165:205, :] = [255, 204, 0]
    indo[340:920, 80:940] = [44, 74, 108]
    save_rgb_png(indo, os.path.join(TEXTURES_DIR, "indomaret_facade_albedo.png"))

    alfa = np.full((S, S, 3), [248, 246, 244], dtype=np.float32)
    alfa[0:115, :] = [214, 30, 38]
    alfa[115:165, :] = [252, 198, 22]
    alfa[165:205, :] = [18, 72, 158]
    alfa[340:920, 80:940] = [48, 72, 104]
    save_rgb_png(alfa, os.path.join(TEXTURES_DIR, "alfamart_facade_albedo.png"))

    # 9. Alpha-Cutout Foliage Textures
    generate_foliage_texture(os.path.join(TEXTURES_DIR, "tree_tropical_foliage.png"), (30, 104, 38), (82, 176, 70), pine_shape=False)
    generate_foliage_texture(os.path.join(TEXTURES_DIR, "tree_pine_foliage.png"), (20, 78, 34), (54, 138, 64), pine_shape=True)
    generate_foliage_texture(os.path.join(TEXTURES_DIR, "tree_tabebuya_foliage.png"), (214, 96, 140), (252, 174, 204), pine_shape=False)


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
    day_amb = RNG.normal(0.0, 0.022, size=t2.shape).astype(np.float32) + 0.035 * np.sin(2 * np.pi * 68.0 * t2)
    write_stereo_wav(os.path.join(AUDIO_DIR, "city_traffic_day.wav"), day_amb, day_amb * 0.95, sr)

    t3 = np.linspace(0, 0.8, int(sr * 0.8), endpoint=False, dtype=np.float32)
    chime = np.exp(-t3 * 3.2) * (0.20 * np.sin(2 * np.pi * 523.25 * t3) + 0.14 * np.sin(2 * np.pi * 659.25 * t3))
    write_stereo_wav(os.path.join(AUDIO_DIR, "build_construct_sfx.wav"), chime, chime, sr)


if __name__ == "__main__":
    ensure_dirs()
    generate_app_icon()
    generate_sky_domes()
    generate_textures()
    generate_audio()
    print("v6.0 Ultra-HD PBR Textures, Volumetric Sky Domes, Alfamart/Indomaret & Audio generated!")
