#!/usr/bin/env python3
"""
Rizzi Games (RG) - City Building : Nusantara Project
Automated AppIcon, 3D Model (.obj), HD PBR Texture (.png), Topographic Heightmap,
and Stereo Audio Generator for GitHub Actions iOS Build (100MB+ Target).
"""

import os
import json
import math
import wave
import numpy as np
from PIL import Image, ImageDraw

BASE_DIR = "Resources"
MODELS_DIR = os.path.join(BASE_DIR, "Models")
TEXTURES_DIR = os.path.join(BASE_DIR, "Textures")
MAPS_DIR = os.path.join(BASE_DIR, "Maps")
AUDIO_DIR = os.path.join(BASE_DIR, "Audio")
XCASSETS_DIR = "Assets.xcassets"
APPICON_DIR = os.path.join(XCASSETS_DIR, "AppIcon.appiconset")

RNG = np.random.default_rng(20261114)


def ensure_dirs():
    for d in [BASE_DIR, MODELS_DIR, TEXTURES_DIR, MAPS_DIR, AUDIO_DIR, XCASSETS_DIR, APPICON_DIR]:
        os.makedirs(d, exist_ok=True)


# ==============================================================================
# 0. iOS HOME SCREEN APP ICON GENERATOR
# ==============================================================================

def generate_app_icon():
    print("[0/4] Generating iOS AppIcon.appiconset...")
    size = 1024
    img = Image.new("RGB", (size, size), (14, 24, 48))
    draw = ImageDraw.Draw(img)

    for y in range(size):
        t = y / float(size)
        r = int(18 * (1 - t) + 235 * (t ** 1.8) * 0.55)
        g = int(32 * (1 - t) + 128 * (t ** 1.6) * 0.55)
        b = int(68 * (1 - t) + 64 * (t ** 1.4) * 0.45)
        draw.line([(0, y), (size, y)], fill=(min(255, r), min(255, g), min(255, b)))

    draw.ellipse([650, 140, 860, 350], fill=(255, 214, 102))
    draw.polygon([(0, 740), (310, 420), (620, 740)], fill=(26, 44, 68))
    draw.polygon([(420, 740), (760, 460), (1024, 740)], fill=(20, 36, 58))

    towers = [
        (90, 470, 230, 920),
        (255, 360, 425, 920),
        (450, 420, 610, 920),
        (635, 330, 815, 920),
        (835, 500, 955, 920),
    ]
    for x0, y0, x1, y1 in towers:
        draw.rectangle([x0, y0, x1, y1], fill=(16, 24, 40))
        for wy in range(y0 + 28, y1 - 40, 44):
            for wx in range(x0 + 22, x1 - 24, 36):
                if (wx + wy) % 3 != 0:
                    draw.rectangle([wx, wy, wx + 18, wy + 24], fill=(255, 206, 94))

    draw.rectangle([0, 860, 1024, 1024], fill=(32, 38, 46))
    draw.rectangle([0, 928, 1024, 944], fill=(245, 195, 45))

    for px_size, fname in [(120, "icon_120.png"), (180, "icon_180.png"), (1024, "icon_1024.png")]:
        resized = img.resize((px_size, px_size), Image.Resampling.LANCZOS)
        resized.save(os.path.join(APPICON_DIR, fname), format="PNG")

    with open(os.path.join(XCASSETS_DIR, "Contents.json"), "w", encoding="utf-8") as fp:
        json.dump({"info": {"author": "xcode", "version": 1}}, fp, indent=2)

    appicon_contents = {
        "images": [
            {"filename": "icon_120.png", "idiom": "iphone", "scale": "2x", "size": "60x60"},
            {"filename": "icon_180.png", "idiom": "iphone", "scale": "3x", "size": "60x60"},
            {"filename": "icon_1024.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(APPICON_DIR, "Contents.json"), "w", encoding="utf-8") as fp:
        json.dump(appicon_contents, fp, indent=2)


# ==============================================================================
# 1. HD PBR TEXTURE GENERATOR (1408x1408 -> ~110MB Total IPA)
# ==============================================================================

def fbm_noise(size: int, octaves=(8, 32, 128, 352), weights=(0.45, 0.30, 0.15, 0.10)) -> np.ndarray:
    acc = np.zeros((size, size), dtype=np.float32)
    for grid, w in zip(octaves, weights):
        base = RNG.random((grid, grid), dtype=np.float32)
        img = Image.fromarray((base * 255.0).astype(np.uint8), mode="L")
        up = np.asarray(img.resize((size, size), Image.Resampling.BILINEAR), dtype=np.float32) / 255.0
        acc += up * w
    return np.clip(acc, 0.0, 1.0)


def save_rgb_png(arr_float: np.ndarray, path: str, micro_grain: int = 8):
    h, w, _ = arr_float.shape
    grain = RNG.integers(-micro_grain, micro_grain + 1, size=(h, w, 3), dtype=np.int16)
    out = np.clip(arr_float.astype(np.int16) + grain, 0, 255).astype(np.uint8)
    Image.fromarray(out, mode="RGB").save(path, format="PNG", compress_level=6)


def generate_normal_from_height(height_2d: np.ndarray, strength: float = 3.5) -> np.ndarray:
    dy, dx = np.gradient(height_2d * strength)
    nx = -dx
    ny = -dy
    nz = np.ones_like(height_2d)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
    rgb = np.stack([(nx / norm * 0.5 + 0.5) * 255.0,
                    (ny / norm * 0.5 + 0.5) * 255.0,
                    (nz / norm * 0.5 + 0.5) * 255.0], axis=-1)
    return rgb


def generate_all_textures():
    print("[1/4] Generating HD (1408x1408) PBR Textures...")
    S = 1408
    n_base = fbm_noise(S)
    n_fine = fbm_noise(S, octaves=(22, 88, 352, 704), weights=(0.2, 0.3, 0.3, 0.2))

    asphalt = np.zeros((S, S, 3), dtype=np.float32)
    asphalt[..., 0] = 36 + n_base * 22 + n_fine * 14
    asphalt[..., 1] = 38 + n_base * 22 + n_fine * 14
    asphalt[..., 2] = 43 + n_base * 24 + n_fine * 15
    save_rgb_png(asphalt, os.path.join(TEXTURES_DIR, "asphalt_albedo.png"), micro_grain=10)
    save_rgb_png(generate_normal_from_height(n_fine, 4.0), os.path.join(TEXTURES_DIR, "asphalt_normal.png"), micro_grain=6)

    rough = np.repeat(((0.35 + n_base * 0.45) * 255.0)[..., None], 3, axis=-1)
    save_rgb_png(rough, os.path.join(TEXTURES_DIR, "asphalt_roughness.png"), micro_grain=8)

    road_1w2l = asphalt.copy()
    road_1w2l[:, 28:52] = [235, 235, 230]
    road_1w2l[:, S - 52:S - 28] = [235, 235, 230]
    for y in range(0, S, 176):
        road_1w2l[y:y + 88, S // 2 - 11:S // 2 + 11] = [245, 245, 240]
    save_rgb_png(road_1w2l, os.path.join(TEXTURES_DIR, "road_1way_2lane_albedo.png"), micro_grain=8)

    road_2w4l = asphalt.copy()
    road_2w4l[:, 26:48] = [235, 235, 230]
    road_2w4l[:, S - 48:S - 26] = [235, 235, 230]
    road_2w4l[:, S // 2 - 18:S // 2 - 5] = [240, 185, 30]
    road_2w4l[:, S // 2 + 5:S // 2 + 18] = [240, 185, 30]
    for y in range(0, S, 176):
        road_2w4l[y:y + 88, S // 4 - 8:S // 4 + 8] = [240, 240, 235]
        road_2w4l[y:y + 88, (3 * S) // 4 - 8:(3 * S) // 4 + 8] = [240, 240, 235]
    save_rgb_png(road_2w4l, os.path.join(TEXTURES_DIR, "road_2way_4lane_albedo.png"), micro_grain=8)

    yy, xx = np.mgrid[0:S, 0:S]
    tile_x = (xx // 44) % 2
    tile_y = (yy // 44) % 2
    checker = (tile_x ^ tile_y).astype(np.float32)
    grout = ((xx % 44 < 3) | (yy % 44 < 3)).astype(np.float32)
    paving = np.zeros((S, S, 3), dtype=np.float32)
    paving[..., 0] = np.where(checker > 0, 168, 128) + n_fine * 24 - grout * 55
    paving[..., 1] = np.where(checker > 0, 82, 126) + n_fine * 20 - grout * 55
    paving[..., 2] = np.where(checker > 0, 74, 124) + n_fine * 20 - grout * 55
    save_rgb_png(paving, os.path.join(TEXTURES_DIR, "sidewalk_paving_albedo.png"), micro_grain=9)
    save_rgb_png(generate_normal_from_height(1.0 - grout * 0.6 + n_fine * 0.3, 4.5),
                 os.path.join(TEXTURES_DIR, "sidewalk_normal.png"), micro_grain=6)

    bikelane = np.zeros((S, S, 3), dtype=np.float32)
    bikelane[..., 0] = 34 + n_fine * 20
    bikelane[..., 1] = 138 + n_fine * 28
    bikelane[..., 2] = 74 + n_fine * 20
    bikelane[:, 16:36] = [245, 245, 245]
    bikelane[:, S - 36:S - 16] = [245, 245, 245]
    save_rgb_png(bikelane, os.path.join(TEXTURES_DIR, "bikelane_albedo.png"), micro_grain=8)

    grass = np.zeros((S, S, 3), dtype=np.float32)
    grass[..., 0] = 44 + n_base * 34 + n_fine * 18
    grass[..., 1] = 108 + n_base * 48 + n_fine * 26
    grass[..., 2] = 36 + n_base * 22 + n_fine * 14
    save_rgb_png(grass, os.path.join(TEXTURES_DIR, "grass_nusantara_albedo.png"), micro_grain=10)
    save_rgb_png(generate_normal_from_height(n_fine, 3.8), os.path.join(TEXTURES_DIR, "grass_normal.png"), micro_grain=6)

    soil = np.zeros((S, S, 3), dtype=np.float32)
    soil[..., 0] = 104 + n_base * 36 + n_fine * 20
    soil[..., 1] = 74 + n_base * 28 + n_fine * 16
    soil[..., 2] = 52 + n_base * 20 + n_fine * 12
    save_rgb_png(soil, os.path.join(TEXTURES_DIR, "soil_mountain_albedo.png"), micro_grain=10)
    save_rgb_png(generate_normal_from_height(n_fine, 4.2), os.path.join(TEXTURES_DIR, "soil_normal.png"), micro_grain=6)

    pinus = np.stack([24 + n_fine * 25, 76 + n_base * 40 + n_fine * 24, 34 + n_fine * 20], axis=-1)
    save_rgb_png(pinus, os.path.join(TEXTURES_DIR, "foliage_pinus_albedo.png"), micro_grain=10)

    trembesi = np.stack([42 + n_fine * 30, 118 + n_base * 45 + n_fine * 25, 44 + n_fine * 22], axis=-1)
    save_rgb_png(trembesi, os.path.join(TEXTURES_DIR, "foliage_trembesi_albedo.png"), micro_grain=10)

    blossom_mask = (n_fine > 0.56).astype(np.float32)
    tabebuya = np.zeros((S, S, 3), dtype=np.float32)
    tabebuya[..., 0] = np.where(blossom_mask > 0, 242, 48) + n_fine * 18
    tabebuya[..., 1] = np.where(blossom_mask > 0, 156, 114) + n_fine * 18
    tabebuya[..., 2] = np.where(blossom_mask > 0, 196, 48) + n_fine * 18
    save_rgb_png(tabebuya, os.path.join(TEXTURES_DIR, "foliage_tabebuya_albedo.png"), micro_grain=10)

    win_x = (xx % 88 >= 16) & (xx % 88 <= 72)
    win_y = (yy % 88 >= 18) & (yy % 88 <= 70)
    is_window = win_x & win_y
    cell_id = (xx // 88) * 31 + (yy // 88) * 17
    lit_mask = is_window & ((cell_id % 5) != 0)

    facade_day = np.zeros((S, S, 3), dtype=np.float32)
    facade_day[..., 0] = np.where(is_window, 55, 198 + n_base * 24)
    facade_day[..., 1] = np.where(is_window, 78, 194 + n_base * 24)
    facade_day[..., 2] = np.where(is_window, 105, 186 + n_base * 24)
    save_rgb_png(facade_day, os.path.join(TEXTURES_DIR, "building_facade_day.png"), micro_grain=7)

    facade_night = np.zeros((S, S, 3), dtype=np.float32)
    warm_tone = (cell_id % 3)
    facade_night[..., 0] = np.where(lit_mask, 255, 8)
    facade_night[..., 1] = np.where(lit_mask, np.where(warm_tone == 0, 214, 185), 10)
    facade_night[..., 2] = np.where(lit_mask, np.where(warm_tone == 0, 128, 92), 18)
    save_rgb_png(facade_night, os.path.join(TEXTURES_DIR, "building_facade_night_emission.png"), micro_grain=6)

    stripe = (xx // 176) % 5
    palette = np.array([
        [235, 68, 74],
        [248, 196, 42],
        [46, 168, 228],
        [56, 196, 112],
        [242, 118, 48],
    ], dtype=np.float32)
    kampung = palette[stripe] + (n_fine[..., None] - 0.5) * 28.0
    kampung[is_window] = [42, 48, 58]
    save_rgb_png(kampung, os.path.join(TEXTURES_DIR, "kampung_warnawarni_albedo.png"), micro_grain=8)

    indo = np.full((S, S, 3), [242, 244, 248], dtype=np.float32)
    indo[0:150, :] = [218, 37, 29]
    indo[150:235, :] = [0, 91, 170]
    indo[235:285, :] = [255, 204, 0]
    indo[480:1270, 125:1280] = [48, 76, 108]
    save_rgb_png(indo, os.path.join(TEXTURES_DIR, "indomaret_facade_albedo.png"), micro_grain=7)


# ==============================================================================
# 2. HIGH-DETAIL 3D MESH GENERATOR (.OBJ)
# ==============================================================================

class ObjBuilder:
    def __init__(self):
        self.vertices = []
        self.uvs = []
        self.normals = []
        self.groups = []
        self.current_group = "default"

    def set_group(self, name: str):
        self.current_group = name

    def add_box(self, cx: float, cy: float, cz: float, sx: float, sy: float, sz: float):
        hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
        corners = [
            (cx - hx, cy - hy, cz - hz),
            (cx + hx, cy - hy, cz - hz),
            (cx + hx, cy + hy, cz - hz),
            (cx - hx, cy + hy, cz - hz),
            (cx - hx, cy - hy, cz + hz),
            (cx + hx, cy - hy, cz + hz),
            (cx + hx, cy + hy, cz + hz),
            (cx - hx, cy + hy, cz + hz),
        ]
        faces = [
            ((0, 1, 2, 3), (0, 0, -1)),
            ((5, 4, 7, 6), (0, 0, 1)),
            ((4, 0, 3, 7), (-1, 0, 0)),
            ((1, 5, 6, 2), (1, 0, 0)),
            ((3, 2, 6, 7), (0, 1, 0)),
            ((4, 5, 1, 0), (0, -1, 0)),
        ]
        uv_quad = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        for idxs, norm in faces:
            self._emit_quad([corners[i] for i in idxs], uv_quad, norm)

    def add_cylinder(self, cx: float, y0: float, cz: float, r_bottom: float, r_top: float, height: float, segs: int = 16):
        y1 = y0 + height
        for i in range(segs):
            a0 = (2.0 * math.pi * i) / segs
            a1 = (2.0 * math.pi * (i + 1)) / segs
            c0, s0 = math.cos(a0), math.sin(a0)
            c1, s1 = math.cos(a1), math.sin(a1)
            p0 = (cx + c0 * r_bottom, y0, cz + s0 * r_bottom)
            p1 = (cx + c1 * r_bottom, y0, cz + s1 * r_bottom)
            p2 = (cx + c1 * r_top, y1, cz + s1 * r_top)
            p3 = (cx + c0 * r_top, y1, cz + s0 * r_top)
            nx, nz = math.cos((a0 + a1) * 0.5), math.sin((a0 + a1) * 0.5)
            uvs = [(i / segs, 0.0), ((i + 1) / segs, 0.0), ((i + 1) / segs, 1.0), (i / segs, 1.0)]
            self._emit_quad([p0, p1, p2, p3], uvs, (nx, 0.15, nz))

    def add_icosphere(self, cx: float, cy: float, cz: float, rx: float, ry: float, rz: float, rings: int = 8, sectors: int = 14):
        for r in range(rings):
            v0 = r / rings
            v1 = (r + 1) / rings
            phi0 = (v0 - 0.5) * math.pi
            phi1 = (v1 - 0.5) * math.pi
            for s in range(sectors):
                u0 = s / sectors
                u1 = (s + 1) / sectors
                th0 = u0 * 2.0 * math.pi
                th1 = u1 * 2.0 * math.pi

                def pt(phi, th):
                    x = math.cos(phi) * math.cos(th)
                    y = math.sin(phi)
                    z = math.cos(phi) * math.sin(th)
                    return (cx + x * rx, cy + y * ry, cz + z * rz), (x, y, z)

                p0, n0 = pt(phi0, th0)
                p1, _ = pt(phi0, th1)
                p2, _ = pt(phi1, th1)
                p3, _ = pt(phi1, th0)
                self._emit_quad([p0, p1, p2, p3], [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], n0)

    def _emit_quad(self, pts, uvs, norm):
        base_v = len(self.vertices) + 1
        base_vt = len(self.uvs) + 1
        base_vn = len(self.normals) + 1
        for p, uv in zip(pts, uvs):
            self.vertices.append(p)
            self.uvs.append(uv)
        self.normals.append(norm)
        f1 = f"{base_v}/{base_vt}/{base_vn} {base_v+1}/{base_vt+1}/{base_vn} {base_v+2}/{base_vt+2}/{base_vn}"
        f2 = f"{base_v}/{base_vt}/{base_vn} {base_v+2}/{base_vt+2}/{base_vn} {base_v+3}/{base_vt+3}/{base_vn}"
        self.groups.append((self.current_group, f1))
        self.groups.append((self.current_group, f2))

    def write(self, path: str):
        lines = ["# Rizzi Games Procedural High-Detail 3D Asset\n"]
        for x, y, z in self.vertices:
            lines.append(f"v {x:.4f} {y:.4f} {z:.4f}\n")
        for u, v in self.uvs:
            lines.append(f"vt {u:.4f} {v:.4f}\n")
        for nx, ny, nz in self.normals:
            lines.append(f"vn {nx:.4f} {ny:.4f} {nz:.4f}\n")
        last_g = None
        for g, f in self.groups:
            if g != last_g:
                lines.append(f"g {g}\n")
                last_g = g
            lines.append(f"f {f}\n")
        with open(path, "w", encoding="utf-8") as fp:
            fp.writelines(lines)


def generate_all_models():
    print("[2/4] Generating High-Detail 3D Models (.obj)...")

    pinus = ObjBuilder()
    pinus.set_group("trunk")
    pinus.add_cylinder(0, 0, 0, 0.28, 0.08, 6.2, segs=18)
    for tier in range(6):
        y = 1.6 + tier * 0.78
        rad = 1.95 - tier * 0.26
        pinus.set_group("branches")
        for b in range(5):
            ang = b * (2 * math.pi / 5) + tier * 0.5
            bx, bz = math.cos(ang) * (rad * 0.45), math.sin(ang) * (rad * 0.45)
            pinus.add_box(bx, y, bz, rad * 0.7, 0.08, 0.08)
        pinus.set_group("leaves")
        pinus.add_cylinder(0, y - 0.1, 0, rad, rad * 0.15, 1.15, segs=20)
    pinus.write(os.path.join(MODELS_DIR, "tree_pinus_malang.obj"))

    trembesi = ObjBuilder()
    trembesi.set_group("trunk")
    trembesi.add_cylinder(0, 0, 0, 0.42, 0.24, 3.2, segs=18)
    trembesi.set_group("branches")
    for b in range(6):
        ang = b * (math.pi / 3.0)
        trembesi.add_box(math.cos(ang) * 0.9, 3.1, math.sin(ang) * 0.9, 1.8, 0.14, 0.14)
    trembesi.set_group("leaves")
    trembesi.add_icosphere(0, 4.1, 0, 3.2, 1.35, 3.2, rings=10, sectors=18)
    for b in range(6):
        ang = b * (math.pi / 3.0)
        trembesi.add_icosphere(math.cos(ang) * 1.9, 3.85, math.sin(ang) * 1.9, 1.5, 0.85, 1.5, rings=8, sectors=14)
    trembesi.write(os.path.join(MODELS_DIR, "tree_trembesi_surabaya.obj"))

    tabebuya = ObjBuilder()
    tabebuya.set_group("trunk")
    tabebuya.add_cylinder(0, 0, 0, 0.22, 0.12, 2.8, segs=16)
    tabebuya.set_group("leaves")
    tabebuya.add_icosphere(0, 3.5, 0, 2.1, 1.4, 2.1, rings=10, sectors=16)
    tabebuya.write(os.path.join(MODELS_DIR, "tree_tabebuya_surabaya.obj"))

    motor = ObjBuilder()
    motor.set_group("wheels")
    motor.add_cylinder(0, 0.28, 0.62, 0.28, 0.28, 0.12, segs=16)
    motor.add_cylinder(0, 0.28, -0.62, 0.28, 0.28, 0.12, segs=16)
    motor.set_group("body")
    motor.add_box(0, 0.56, 0.0, 0.34, 0.36, 1.35)
    motor.add_box(0, 0.95, 0.42, 0.64, 0.12, 0.16)
    motor.set_group("headlight")
    motor.add_box(0, 0.88, 0.54, 0.16, 0.14, 0.08)
    motor.set_group("rider")
    motor.add_box(0, 1.08, -0.05, 0.36, 0.52, 0.26)
    motor.add_icosphere(0, 1.48, 0.02, 0.16, 0.18, 0.18, rings=8, sectors=12)
    motor.write(os.path.join(MODELS_DIR, "vehicle_motor.obj"))

    car = ObjBuilder()
    car.set_group("body")
    car.add_box(0, 0.52, 0.0, 1.78, 0.58, 4.15)
    car.set_group("cabin")
    car.add_box(0, 1.02, -0.22, 1.56, 0.52, 2.45)
    car.set_group("wheels")
    for wx in (-0.84, 0.84):
        for wz in (-1.28, 1.28):
            car.add_cylinder(wx, 0.32, wz, 0.32, 0.32, 0.22, segs=16)
    car.set_group("headlight")
    car.add_box(-0.62, 0.56, 2.08, 0.32, 0.16, 0.06)
    car.add_box(0.62, 0.56, 2.08, 0.32, 0.16, 0.06)
    car.write(os.path.join(MODELS_DIR, "vehicle_mobil.obj"))

    bike = ObjBuilder()
    bike.set_group("wheels")
    bike.add_cylinder(0, 0.34, 0.58, 0.34, 0.34, 0.06, segs=16)
    bike.add_cylinder(0, 0.34, -0.58, 0.34, 0.34, 0.06, segs=16)
    bike.set_group("body")
    bike.add_box(0, 0.64, 0.0, 0.10, 0.38, 1.12)
    bike.add_box(0, 0.96, 0.44, 0.54, 0.08, 0.10)
    bike.set_group("rider")
    bike.add_box(0, 1.14, -0.04, 0.34, 0.50, 0.24)
    bike.add_icosphere(0, 1.52, 0.04, 0.15, 0.17, 0.17, rings=8, sectors=12)
    bike.write(os.path.join(MODELS_DIR, "vehicle_sepeda.obj"))

    ped = ObjBuilder()
    ped.set_group("legs")
    ped.add_box(-0.11, 0.42, 0, 0.14, 0.84, 0.16)
    ped.add_box(0.11, 0.42, 0, 0.14, 0.84, 0.16)
    ped.set_group("torso")
    ped.add_box(0, 1.12, 0, 0.38, 0.56, 0.22)
    ped.set_group("arms")
    ped.add_box(-0.26, 1.10, 0, 0.12, 0.52, 0.14)
    ped.add_box(0.26, 1.10, 0, 0.12, 0.52, 0.14)
    ped.set_group("head")
    ped.add_icosphere(0, 1.56, 0, 0.14, 0.16, 0.15, rings=8, sectors=12)
    ped.write(os.path.join(MODELS_DIR, "npc_pedestrian.obj"))

    for fname in ["building_house.obj", "building_kampung_warnawarni.obj"]:
        house = ObjBuilder()
        house.set_group("walls")
        house.add_box(0, 1.6, 0, 4.4, 3.2, 4.8)
        house.set_group("roof")
        house.add_box(0, 3.55, 0, 4.9, 0.75, 5.3)
        house.add_box(0, 4.10, 0, 3.4, 0.45, 3.8)
        house.write(os.path.join(MODELS_DIR, fname))

    indo = ObjBuilder()
    indo.set_group("walls")
    indo.add_box(0, 2.2, 0, 6.8, 4.4, 5.6)
    indo.set_group("canopy")
    indo.add_box(0, 3.9, 3.1, 7.2, 0.95, 1.1)
    indo.write(os.path.join(MODELS_DIR, "building_indomaret.obj"))

    tower = ObjBuilder()
    tower.set_group("walls")
    tower.add_box(0, 9.0, 0, 6.4, 18.0, 6.4)
    tower.add_box(0, 19.2, 0, 4.2, 2.4, 4.2)
    tower.write(os.path.join(MODELS_DIR, "building_highrise.obj"))

    edu_specs = [
        ("edu_sd.obj", 8.0, 3.4, 6.0, False),
        ("edu_smp.obj", 10.0, 6.4, 7.0, False),
        ("edu_sma.obj", 12.0, 9.2, 8.0, False),
        ("edu_universitas.obj", 16.0, 12.5, 12.0, True),
    ]
    for fname, w, h, d, has_dome in edu_specs:
        edu = ObjBuilder()
        edu.set_group("walls")
        edu.add_box(0, h * 0.5, 0, w, h, d)
        edu.set_group("roof")
        edu.add_box(0, h + 0.4, 0, w + 0.6, 0.8, d + 0.6)
        if has_dome:
            edu.add_icosphere(0, h + 1.8, 0, 2.6, 2.0, 2.6, rings=10, sectors=16)
        edu.write(os.path.join(MODELS_DIR, fname))

    basecamp = ObjBuilder()
    basecamp.set_group("walls")
    basecamp.add_box(0, 1.8, 0, 5.4, 3.6, 4.2)
    basecamp.set_group("roof")
    basecamp.add_box(0, 4.0, 0, 6.0, 0.9, 4.8)
    basecamp.set_group("gate")
    basecamp.add_box(-2.2, 2.2, 3.2, 0.4, 4.4, 0.4)
    basecamp.add_box(2.2, 2.2, 3.2, 0.4, 4.4, 0.4)
    basecamp.add_box(0, 4.2, 3.2, 5.2, 0.5, 0.5)
    basecamp.write(os.path.join(MODELS_DIR, "landmark_arjuno_basecamp.obj"))

    lamp = ObjBuilder()
    lamp.set_group("pole")
    lamp.add_cylinder(0, 0, 0, 0.12, 0.07, 4.6, segs=12)
    lamp.add_box(0.45, 4.55, 0, 0.95, 0.08, 0.08)
    lamp.set_group("bulb")
    lamp.add_box(0.85, 4.46, 0, 0.28, 0.10, 0.18)
    lamp.write(os.path.join(MODELS_DIR, "prop_streetlight.obj"))


# ==============================================================================
# 3. NUSANTARA REALISTIC TOPOGRAPHIC MAPS (MALANG, SURABAYA, JAKARTA)
# ==============================================================================

def generate_nusantara_maps():
    print("[3/4] Generating Nusantara Topographic Heightmaps (Malang, Surabaya, Jakarta)...")
    M = 1024
    yy, xx = np.mgrid[0:M, 0:M].astype(np.float32) / M
    terrain_noise = fbm_noise(M, octaves=(4, 16, 64, 256), weights=(0.5, 0.25, 0.15, 0.10))

    arjuno = np.exp(-(((xx - 0.52) ** 2) / 0.025 + ((yy - 0.14) ** 2) / 0.020)) * 0.72
    kawi = np.exp(-(((xx - 0.12) ** 2) / 0.022 + ((yy - 0.48) ** 2) / 0.030)) * 0.55
    semeru_east = np.exp(-(((xx - 0.92) ** 2) / 0.025 + ((yy - 0.62) ** 2) / 0.035)) * 0.60
    brantas_curve = 0.48 + 0.08 * np.sin(yy * 7.0)
    brantas_valley = np.exp(-(((xx - brantas_curve) ** 2) / 0.0008)) * 0.14
    malang_h = np.clip(0.24 + arjuno + kawi + semeru_east + terrain_noise * 0.12 - brantas_valley, 0.04, 1.0)

    sea_mask = np.clip((xx + (1.0 - yy) - 1.32) * 3.5, 0.0, 1.0)
    kalimas = np.exp(-(((xx - (0.52 + 0.04 * np.cos(yy * 8.0))) ** 2) / 0.0007)) * 0.08
    south_hills = np.clip((yy - 0.78) * 1.4, 0.0, 0.35)
    surabaya_h = np.clip(0.14 * (1.0 - sea_mask) + south_hills + terrain_noise * 0.05 - kalimas, 0.0, 1.0)

    bay = np.clip((0.18 - yy) * 4.5 + 0.04 * np.sin(xx * 10.0), 0.0, 1.0)
    ciliwung = np.exp(-(((xx - (0.50 + 0.05 * np.sin(yy * 9.0))) ** 2) / 0.0007)) * 0.07
    south_slope = np.clip((yy - 0.55) * 0.55, 0.0, 0.32)
    jakarta_h = np.clip(0.13 * (1.0 - bay) + south_slope + terrain_noise * 0.05 - ciliwung, 0.0, 1.0)

    maps = {
        "malang": (malang_h, {
            "id": "malang",
            "name": "Kota Malang & Lereng Arjuno",
            "elevationScale": 42.0,
            "dominantTrees": ["tree_pinus_malang", "tree_trembesi_surabaya"],
            "landmarks": [{"name": "Gunung Arjuno", "gridX": 33, "gridZ": 9}],
            "startingWeather": "Sejuk Berkabus Pagi (19°C)"
        }),
        "surabaya": (surabaya_h, {
            "id": "surabaya",
            "name": "Kota Surabaya & Selat Madura",
            "elevationScale": 18.0,
            "dominantTrees": ["tree_trembesi_surabaya", "tree_tabebuya_surabaya"],
            "landmarks": [{"name": "Tepi Sungai Kali Mas", "gridX": 33, "gridZ": 32}],
            "startingWeather": "Cerah Pesisir (31°C)"
        }),
        "jakarta": (jakarta_h, {
            "id": "jakarta",
            "name": "DKI Jakarta & Teluk Utara",
            "elevationScale": 22.0,
            "dominantTrees": ["tree_trembesi_surabaya", "tree_tabebuya_surabaya"],
            "landmarks": [{"name": "Koridor Sudirman - Ciliwung", "gridX": 32, "gridZ": 36}],
            "startingWeather": "Cerah Berawan (30°C)"
        }),
    }

    for key, (hmap, meta) in maps.items():
        Image.fromarray((hmap * 255.0).astype(np.uint8), mode="L").save(
            os.path.join(MAPS_DIR, f"{key}_heightmap.png")
        )
        with open(os.path.join(MAPS_DIR, f"{key}_meta.json"), "w", encoding="utf-8") as fp:
            json.dump(meta, fp, indent=2)


# ==============================================================================
# 4. STEREO AMBIENT & COZY NIGHT CITY AUDIO GENERATOR (.WAV)
# ==============================================================================

def write_stereo_wav(path: str, left: np.ndarray, right: np.ndarray, sr: int = 32000):
    stereo = np.stack([np.clip(left, -1.0, 1.0), np.clip(right, -1.0, 1.0)], axis=-1)
    pcm = (stereo * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


def generate_all_audio():
    print("[4/4] Generating Stereo City & Cozy Night Audio (.wav)...")
    sr = 32000

    t = np.linspace(0, 32.0, sr * 32, endpoint=False, dtype=np.float32)
    chords = [
        (220.00, 261.63, 329.63, 392.00),
        (174.61, 220.00, 261.63, 329.63),
        (130.81, 196.00, 246.94, 293.66),
        (196.00, 246.94, 293.66, 349.23),
    ]
    pad_l = np.zeros_like(t)
    pad_r = np.zeros_like(t)
    for idx, freqs in enumerate(chords):
        mask = ((t >= idx * 8.0) & (t < (idx + 1) * 8.0)).astype(np.float32)
        for f in freqs:
            pad_l += mask * 0.08 * np.sin(2 * np.pi * f * t)
            pad_r += mask * 0.08 * np.sin(2 * np.pi * (f * 1.003) * t + 0.4)
    breeze = RNG.normal(0.0, 0.015, size=t.shape).astype(np.float32)
    write_stereo_wav(os.path.join(AUDIO_DIR, "cozy_night_city.wav"), pad_l + breeze, pad_r + breeze, sr)

    t2 = np.linspace(0, 26.0, sr * 26, endpoint=False, dtype=np.float32)
    hum = 0.07 * np.sin(2 * np.pi * 68.0 * t2) + 0.04 * np.sin(2 * np.pi * 136.0 * t2)
    street_noise_l = RNG.normal(0.0, 0.045, size=t2.shape).astype(np.float32) + hum
    street_noise_r = RNG.normal(0.0, 0.045, size=t2.shape).astype(np.float32) + hum
    write_stereo_wav(os.path.join(AUDIO_DIR, "city_traffic_day.wav"), street_noise_l, street_noise_r, sr)

    t3 = np.linspace(0, 24.0, sr * 24, endpoint=False, dtype=np.float32)
    swell = 0.5 + 0.4 * np.sin(2 * np.pi * 0.12 * t3)
    wind_l = RNG.normal(0.0, 0.055, size=t3.shape).astype(np.float32) * swell
    wind_r = RNG.normal(0.0, 0.055, size=t3.shape).astype(np.float32) * (1.0 - swell * 0.4)
    write_stereo_wav(os.path.join(AUDIO_DIR, "wind_leaves_mountain.wav"), wind_l, wind_r, sr)

    t4 = np.linspace(0, 16.0, sr * 16, endpoint=False, dtype=np.float32)
    chant = 0.09 * np.sin(2 * np.pi * 190.0 * t4) * (np.sin(2 * np.pi * 1.5 * t4) > 0).astype(np.float32)
    crowd_l = RNG.normal(0.0, 0.06, size=t4.shape).astype(np.float32) + chant
    crowd_r = RNG.normal(0.0, 0.06, size=t4.shape).astype(np.float32) + chant
    write_stereo_wav(os.path.join(AUDIO_DIR, "citizen_demo_crowd.wav"), crowd_l, crowd_r, sr)

    t5 = np.linspace(0, 4.0, sr * 4, endpoint=False, dtype=np.float32)
    env = np.exp(-t5 * 1.8)
    chime = env * (0.22 * np.sin(2 * np.pi * 523.25 * t5) + 0.18 * np.sin(2 * np.pi * 659.25 * t5))
    write_stereo_wav(os.path.join(AUDIO_DIR, "build_construct_sfx.wav"), chime, chime, sr)


def write_manifest():
    manifest = {
        "studio": "Rizzi Games (RG)",
        "project": "City Building : Nusantara Project",
        "modelsCount": len(os.listdir(MODELS_DIR)),
        "texturesCount": len(os.listdir(TEXTURES_DIR)),
        "maps": ["malang", "surabaya", "jakarta"],
        "audioCount": len(os.listdir(AUDIO_DIR)),
    }
    with open(os.path.join(BASE_DIR, "manifest.json"), "w", encoding="utf-8") as fp:
        json.dump(manifest, fp, indent=2)
    print("Asset generation complete:", json.dumps(manifest))


if __name__ == "__main__":
    ensure_dirs()
    generate_app_icon()
    generate_all_textures()
    generate_all_models()
    generate_nusantara_maps()
    generate_all_audio()
    write_manifest()
