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
RNG = np.random.default_rng(20261118)


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


def save_rgb_png(arr_float: np.ndarray, path: str, micro_grain: int = 5):
    h, w, _ = arr_float.shape
    grain = RNG.integers(-micro_grain, micro_grain + 1, size=(h, w, 3), dtype=np.int16)
    out = np.clip(arr_float.astype(np.int16) + grain, 0, 255).astype(np.uint8)
    Image.fromarray(out, mode="RGB").save(path, format="PNG", compress_level=6)


def save_gray_png(arr_float: np.ndarray, path: str):
    out = np.clip(arr_float, 0, 255).astype(np.uint8)
    Image.fromarray(out, mode="L").save(path, format="PNG", compress_level=6)


def generate_normal_from_height(height_2d: np.ndarray, strength: float = 4.2) -> np.ndarray:
    dy, dx = np.gradient(height_2d * strength)
    nx, ny, nz = -dx, -dy, np.ones_like(height_2d)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
    return np.stack([
        (nx / norm * 0.5 + 0.5) * 255.0,
        (ny / norm * 0.5 + 0.5) * 255.0,
        (nz / norm * 0.5 + 0.5) * 255.0,
    ], axis=-1)


def generate_sky_domes():
    W, H = 1024, 512
    yy, xx = np.mgrid[0:H, 0:W]
    v = yy.astype(np.float32) / float(H)
    above = v <= 0.52
    t_up = np.clip(v / 0.52, 0.0, 1.0)

    cloud_n = fbm_noise_rect(W, H, octaves=(8, 24, 64))
    day = np.zeros((H, W, 3), dtype=np.float32)
    day[..., 0] = np.where(above, 36 * (1 - t_up) + 184 * (t_up ** 1.55), 86)
    day[..., 1] = np.where(above, 134 * (1 - t_up) + 226 * (t_up ** 1.35), 118)
    day[..., 2] = np.where(above, 240 * (1 - t_up) + 252 * (t_up ** 1.15), 134)
    cloud_mask = np.clip((cloud_n - 0.50) * 3.0, 0.0, 1.0) * np.where(above, 1.0 - (t_up ** 3.2), 0.0)
    day[..., 0] = day[..., 0] * (1 - cloud_mask * 0.80) + 254 * (cloud_mask * 0.80)
    day[..., 1] = day[..., 1] * (1 - cloud_mask * 0.80) + 254 * (cloud_mask * 0.80)
    day[..., 2] = day[..., 2] * (1 - cloud_mask * 0.80) + 255 * (cloud_mask * 0.80)
    sun_d = np.sqrt(((xx - 720.0) / 1.4) ** 2 + (yy - 145.0) ** 2)
    sun_glow = np.exp(-sun_d / 36.0) * 155.0
    day = np.clip(day + sun_glow[..., None] * np.array([1.0, 0.95, 0.82]), 0, 255)
    Image.fromarray(day.astype(np.uint8), mode="RGB").save(os.path.join(TEXTURES_DIR, "sky_day_equirect.png"), format="PNG")

    sunset = np.zeros((H, W, 3), dtype=np.float32)
    sunset[..., 0] = np.where(above, 26 * (1 - t_up) + 254 * (t_up ** 1.5), 54)
    sunset[..., 1] = np.where(above, 44 * (1 - t_up) + 154 * (t_up ** 1.7), 44)
    sunset[..., 2] = np.where(above, 102 * (1 - t_up) + 96 * (t_up ** 1.2), 58)
    sun_d2 = np.sqrt(((xx - 760.0) / 1.6) ** 2 + (yy - 235.0) ** 2)
    glow2 = np.exp(-sun_d2 / 52.0) * 165.0
    sunset = np.clip(sunset + glow2[..., None] * np.array([1.0, 0.72, 0.35]), 0, 255)
    Image.fromarray(sunset.astype(np.uint8), mode="RGB").save(os.path.join(TEXTURES_DIR, "sky_sunset_equirect.png"), format="PNG")

    night = np.zeros((H, W, 3), dtype=np.float32)
    night[..., 0] = np.where(above, 6 * (1 - t_up) + 22 * t_up, 8)
    night[..., 1] = np.where(above, 10 * (1 - t_up) + 32 * t_up, 10)
    night[..., 2] = np.where(above, 28 * (1 - t_up) + 62 * t_up, 20)
    for _ in range(440):
        sx = int(RNG.integers(0, W))
        sy = int(RNG.integers(10, int(H * 0.46)))
        b = float(RNG.integers(160, 255))
        night[sy, sx] = [b, b, min(255.0, b * 1.05)]
    Image.fromarray(night.astype(np.uint8), mode="RGB").save(os.path.join(TEXTURES_DIR, "sky_night_equirect.png"), format="PNG")


def generate_foliage_texture(path: str, base_rgb: tuple, highlight_rgb: tuple, pine_shape: bool = False):
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx = S // 2
    for i in range(380):
        t = i / 380.0
        if pine_shape:
            y = int(34 + t * 428)
            half_w = int(14 + t * 196)
            x = int(cx + RNG.integers(-half_w, half_w + 1))
            r = int(RNG.integers(12, 26))
        else:
            ang = RNG.uniform(0, 2 * np.pi)
            rad = np.sqrt(RNG.uniform(0, 1)) * 218
            x = int(cx + np.cos(ang) * rad)
            y = int(244 + np.sin(ang) * rad * 0.88)
            r = int(RNG.integers(14, 34))
        mix = RNG.uniform(0.0, 1.0)
        col = (
            int(base_rgb[0] * (1 - mix) + highlight_rgb[0] * mix),
            int(base_rgb[1] * (1 - mix) + highlight_rgb[1] * mix),
            int(base_rgb[2] * (1 - mix) + highlight_rgb[2] * mix),
            252,
        )
        draw.ellipse([x - r, y - r, x + r, y + r], fill=col)
    img.save(path, format="PNG")


def generate_grass_tuft_texture(path: str):
    S = 256
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for b in range(42):
        bx = int(RNG.integers(36, S - 36))
        lean = int(RNG.integers(-48, 49))
        top_y = int(RNG.integers(24, 130))
        green = int(RNG.integers(118, 188))
        red = int(green * 0.48)
        blue = int(green * 0.34)
        draw.polygon(
            [(bx - 5, S), (bx + 5, S), (bx + lean + 2, top_y), (bx + lean - 2, top_y)],
            fill=(red, green, blue, 248),
        )
    img.save(path, format="PNG")


def generate_textures():
    S = 1024
    n_base = fbm_noise(S, octaves=(8, 32, 128))
    n_fine = fbm_noise(S, octaves=(16, 64, 256))
    yy, xx = np.mgrid[0:S, 0:S]

    # 1. Realistic Asphalt with Aggregate Patches, Tar Seams & Indonesian Black-White Curbs
    asphalt = np.zeros((S, S, 3), dtype=np.float32)
    tar_patch = ((n_base > 0.62) & (n_base < 0.72)).astype(np.float32) * -10.0
    asphalt[..., 0] = 46 + n_base * 15 + n_fine * 9 + tar_patch
    asphalt[..., 1] = 48 + n_base * 15 + n_fine * 9 + tar_patch
    asphalt[..., 2] = 53 + n_base * 16 + n_fine * 10 + tar_patch
    save_rgb_png(generate_normal_from_height(n_fine, 4.2), os.path.join(TEXTURES_DIR, "asphalt_normal.png"), micro_grain=3)

    # Indonesian Black-White Painted Kanstin Curbs along road edges
    kanstin_white = ((yy // 64) % 2 == 0)
    road_2l = asphalt.copy()
    road_2l[:, 0:32] = np.where(kanstin_white[:, 0:32, None], [225, 226, 228], [32, 34, 38])
    road_2l[:, S - 32:S] = np.where(kanstin_white[:, S - 32:S, None], [225, 226, 228], [32, 34, 38])
    road_2l[:, 35:47] = [238, 238, 234]
    road_2l[:, S - 47:S - 35] = [238, 238, 234]
    for y in range(0, S, 128):
        road_2l[y:y + 68, S // 2 - 7:S // 2 + 7] = [248, 206, 46]
    save_rgb_png(road_2l, os.path.join(TEXTURES_DIR, "road_2lane_albedo.png"))

    road_4l = asphalt.copy()
    road_4l[:, 0:28] = np.where(kanstin_white[:, 0:28, None], [225, 226, 228], [32, 34, 38])
    road_4l[:, S - 28:S] = np.where(kanstin_white[:, S - 28:S, None], [225, 226, 228], [32, 34, 38])
    road_4l[:, 31:43] = [240, 240, 236]
    road_4l[:, S - 43:S - 31] = [240, 240, 236]
    road_4l[:, S // 2 - 16:S // 2 - 5] = [248, 194, 34]
    road_4l[:, S // 2 + 5:S // 2 + 16] = [248, 194, 34]
    for y in range(0, S, 128):
        road_4l[y:y + 64, S // 4 - 5:S // 4 + 5] = [240, 240, 236]
        road_4l[y:y + 64, (3 * S) // 4 - 5:(3 * S) // 4 + 5] = [240, 240, 236]
    save_rgb_png(road_4l, os.path.join(TEXTURES_DIR, "road_4lane_albedo.png"))

    inter = asphalt.copy()
    for stripe_x in range(180, 844, 72):
        inter[38:145, stripe_x:stripe_x + 36] = [242, 242, 238]
        inter[S - 145:S - 38, stripe_x:stripe_x + 36] = [242, 242, 238]
    for stripe_y in range(180, 844, 72):
        inter[stripe_y:stripe_y + 36, 38:145] = [242, 242, 238]
        inter[stripe_y:stripe_y + 36, S - 145:S - 38] = [242, 242, 238]
    save_rgb_png(inter, os.path.join(TEXTURES_DIR, "road_intersection_albedo.png"))

    # 2. Architectural Sidewalk Paving
    checker = (((xx // 32) % 2) ^ ((yy // 32) % 2)).astype(np.float32)
    grout = ((xx % 32 < 3) | (yy % 32 < 3)).astype(np.float32)
    paving = np.zeros((S, S, 3), dtype=np.float32)
    paving[..., 0] = np.where(checker > 0, 196, 178) + n_fine * 12 - grout * 36
    paving[..., 1] = np.where(checker > 0, 194, 176) + n_fine * 12 - grout * 36
    paving[..., 2] = np.where(checker > 0, 188, 172) + n_fine * 12 - grout * 36
    save_rgb_png(paving, os.path.join(TEXTURES_DIR, "sidewalk_paving_albedo.png"))

    # 3. High-Detail Tropical Meadow Grass + Flowing River Surface with Whitewater Foam Streaks
    grass = np.zeros((S, S, 3), dtype=np.float32)
    blade_streaks = np.sin(xx * 0.65 + n_fine * 8.0) * 8.0
    wildflower = ((n_fine > 0.86) & ((xx + yy) % 19 == 0)).astype(np.float32) * 55.0
    grass[..., 0] = 66 + n_base * 28 + n_fine * 15 + blade_streaks * 0.4 + wildflower
    grass[..., 1] = 144 + n_base * 38 + n_fine * 18 + blade_streaks + wildflower * 0.8
    grass[..., 2] = 52 + n_base * 18 + n_fine * 10
    save_rgb_png(grass, os.path.join(TEXTURES_DIR, "grass_nusantara_albedo.png"))
    save_rgb_png(generate_normal_from_height(n_fine, 3.8), os.path.join(TEXTURES_DIR, "grass_normal.png"), micro_grain=3)

    # Flowing River Texture (Deep turquoise current + organic white foam streaks!)
    stream_wave = np.sin(xx * 0.08 + n_base * 6.0) * 0.5 + np.cos(yy * 0.035 + n_fine * 4.5) * 0.5
    foam = np.clip((stream_wave + n_fine * 0.65 - 0.82) * 5.2, 0.0, 1.0)
    river_col = np.zeros((S, S, 3), dtype=np.float32)
    river_col[..., 0] = 18 + n_base * 18 + foam * 215
    river_col[..., 1] = 104 + n_base * 32 + foam * 138
    river_col[..., 2] = 142 + n_base * 28 + foam * 106
    save_rgb_png(river_col, os.path.join(TEXTURES_DIR, "river_water_albedo.png"), micro_grain=2)
    save_rgb_png(generate_normal_from_height(stream_wave, 4.4), os.path.join(TEXTURES_DIR, "water_normal.png"), micro_grain=2)

    # 4. Terracotta Roof Tiles + Red Brick Construction Texture
    tile_wave = np.sin((xx / 16.0) * np.pi) * 20.0
    row_step = ((yy % 32) < 4).astype(np.float32) * 36.0
    roof_h = (np.sin((xx / 16.0) * np.pi) * 0.5 + 0.5) - ((yy % 32) < 4).astype(np.float32) * 0.4
    roof = np.zeros((S, S, 3), dtype=np.float32)
    roof[..., 0] = 188 + n_base * 18 + tile_wave - row_step
    roof[..., 1] = 82 + n_base * 12 + tile_wave * 0.5 - row_step
    roof[..., 2] = 56 + n_base * 10 - row_step * 0.6
    save_rgb_png(roof, os.path.join(TEXTURES_DIR, "roof_terracotta_albedo.png"))
    save_rgb_png(generate_normal_from_height(roof_h, 4.5), os.path.join(TEXTURES_DIR, "roof_normal.png"), micro_grain=2)

    brick_row = (yy // 24)
    brick_shift = (brick_row % 2) * 32
    mortar = ((yy % 24 < 3) | (((xx + brick_shift) % 64) < 3)).astype(np.float32)
    brick = np.zeros((S, S, 3), dtype=np.float32)
    brick[..., 0] = np.where(mortar > 0, 152, 178 + n_fine * 24)
    brick[..., 1] = np.where(mortar > 0, 150, 76 + n_fine * 16)
    brick[..., 2] = np.where(mortar > 0, 146, 54 + n_fine * 14)
    save_rgb_png(brick, os.path.join(TEXTURES_DIR, "brick_construction_albedo.png"), micro_grain=3)

    # 5. Architectural Curtain-Wall Glass & Concrete Mullions
    win_x = (xx % 64 >= 8) & (xx % 64 <= 56)
    win_y = (yy % 64 >= 10) & (yy % 64 <= 54)
    is_window = win_x & win_y
    mullion_bar = (xx % 32 >= 30) | (yy % 32 >= 30)
    glass_pane = is_window & (~mullion_bar)

    cell_id = (xx // 64) * 31 + (yy // 64) * 17
    lit_mask = glass_pane & ((cell_id % 4) != 0)

    pane_v = ((yy % 64).astype(np.float32)) / 64.0
    facade_day = np.zeros((S, S, 3), dtype=np.float32)
    facade_day[..., 0] = np.where(glass_pane, 48 + pane_v * 34 + n_base * 12, 214 + n_base * 16)
    facade_day[..., 1] = np.where(glass_pane, 98 + pane_v * 46 + n_base * 14, 216 + n_base * 16)
    facade_day[..., 2] = np.where(glass_pane, 154 + pane_v * 52 + n_base * 16, 220 + n_base * 16)
    save_rgb_png(facade_day, os.path.join(TEXTURES_DIR, "building_facade_day.png"), micro_grain=3)

    metal_map = np.where(glass_pane, 215.0, 18.0)
    rough_map = np.where(glass_pane, 24.0 + n_fine * 14.0, 195.0 + n_fine * 24.0)
    save_gray_png(metal_map, os.path.join(TEXTURES_DIR, "building_facade_metalness.png"))
    save_gray_png(rough_map, os.path.join(TEXTURES_DIR, "building_facade_roughness.png"))

    recess_h = np.where(glass_pane, 0.25, 0.85)
    save_rgb_png(generate_normal_from_height(recess_h, 4.5), os.path.join(TEXTURES_DIR, "building_facade_normal.png"), micro_grain=2)

    facade_night = np.zeros((S, S, 3), dtype=np.float32)
    facade_night[..., 0] = np.where(lit_mask, 255, 6)
    facade_night[..., 1] = np.where(lit_mask, 214, 10)
    facade_night[..., 2] = np.where(lit_mask, 124, 18)
    save_rgb_png(facade_night, os.path.join(TEXTURES_DIR, "building_facade_night_emission.png"), micro_grain=2)

    # 6. Residential House Plaster & Ceramic Base
    house_wall = np.zeros((S, S, 3), dtype=np.float32)
    house_wall[..., 0] = np.where(glass_pane, 48, 244 + n_base * 10)
    house_wall[..., 1] = np.where(glass_pane, 76, 238 + n_base * 10)
    house_wall[..., 2] = np.where(glass_pane, 106, 224 + n_base * 10)
    house_wall[yy > 840, :] = [132, 134, 138]
    save_rgb_png(house_wall, os.path.join(TEXTURES_DIR, "house_wall_albedo.png"), micro_grain=3)

    # 7. School / Civic Facade
    school = np.zeros((S, S, 3), dtype=np.float32)
    school[..., 0] = np.where(glass_pane, 52, 244 + n_base * 10)
    school[..., 1] = np.where(glass_pane, 78, 238 + n_base * 10)
    school[..., 2] = np.where(glass_pane, 104, 220 + n_base * 10)
    school[yy % 128 < 14, :] = [176, 66, 46]
    save_rgb_png(school, os.path.join(TEXTURES_DIR, "school_facade_albedo.png"), micro_grain=3)

    # 8. Kampung Warna-Warni
    stripe = (xx // 128) % 5
    palette = np.array([[228, 74, 78], [242, 192, 52], [54, 162, 218], [62, 188, 112], [236, 120, 56]], dtype=np.float32)
    kampung = palette[stripe] + (n_fine[..., None] - 0.5) * 16.0
    kampung[glass_pane] = [44, 54, 68]
    save_rgb_png(kampung, os.path.join(TEXTURES_DIR, "kampung_warnawarni_albedo.png"), micro_grain=3)

    # 9. Indomaret & Alfamart Franchises
    indo = np.full((S, S, 3), [248, 250, 254], dtype=np.float32)
    indo[0:105, :] = [218, 37, 29]
    indo[105:165, :] = [0, 91, 170]
    indo[165:205, :] = [255, 204, 0]
    indo[320:940, 70:950] = [52, 92, 136]
    save_rgb_png(indo, os.path.join(TEXTURES_DIR, "indomaret_facade_albedo.png"), micro_grain=2)

    alfa = np.full((S, S, 3), [250, 248, 246], dtype=np.float32)
    alfa[0:115, :] = [214, 30, 38]
    alfa[115:165, :] = [252, 198, 22]
    alfa[165:205, :] = [18, 72, 158]
    alfa[320:940, 70:950] = [56, 88, 130]
    save_rgb_png(alfa, os.path.join(TEXTURES_DIR, "alfamart_facade_albedo.png"), micro_grain=2)

    # 10. Alpha-Cutout Foliage & 3D Meadow Grass Tufts
    generate_foliage_texture(os.path.join(TEXTURES_DIR, "tree_tropical_foliage.png"), (34, 112, 42), (88, 184, 76), pine_shape=False)
    generate_foliage_texture(os.path.join(TEXTURES_DIR, "tree_pine_foliage.png"), (22, 84, 36), (58, 146, 68), pine_shape=True)
    generate_foliage_texture(os.path.join(TEXTURES_DIR, "tree_tabebuya_foliage.png"), (218, 102, 146), (254, 180, 210), pine_shape=False)
    generate_grass_tuft_texture(os.path.join(TEXTURES_DIR, "grass_tuft_cutout.png"))


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
    print("v8.0 Living Realism PBR Textures, River Foam, 3D Grass Tufts & Audio generated!")
