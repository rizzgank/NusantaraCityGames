#!/usr/bin/env python3
import os
import json
import numpy as np
from PIL import Image, ImageDraw

BASE_DIR = "GameAssets"
TEXTURES_DIR = os.path.join(BASE_DIR, "Textures")
MAPS_DIR = os.path.join(BASE_DIR, "Maps")
ICONSET_DIR = os.path.join("Assets.xcassets", "AppIcon.appiconset")

def ensure_dirs():
    for d in [BASE_DIR, TEXTURES_DIR, MAPS_DIR, ICONSET_DIR]:
        os.makedirs(d, exist_ok=True)

def generate_app_icon():
    img = Image.new("RGB", (1024, 1024), (12, 22, 46))
    draw = ImageDraw.Draw(img)
    draw.ellipse([640, 130, 865, 355], fill=(255, 218, 108))
    draw.polygon([(0, 745), (320, 410), (640, 745)], fill=(22, 42, 68))
    draw.polygon([(410, 745), (770, 445), (1024, 745)], fill=(18, 34, 56))
    img.save(os.path.join(ICONSET_DIR, "AppIcon-1024.png"), format="PNG")
    contents = {"images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(ICONSET_DIR, "Contents.json"), "w", encoding="utf-8") as fp:
        json.dump(contents, fp, indent=2)

def generate_textures():
    S = 1024
    arr = np.full((S, S, 3), [40, 42, 48], dtype=np.uint8)
    Image.fromarray(arr, mode="RGB").save(os.path.join(TEXTURES_DIR, "asphalt_albedo.png"), compress_level=6)
    grass = np.full((S, S, 3), [48, 110, 52], dtype=np.uint8)
    Image.fromarray(grass, mode="RGB").save(os.path.join(TEXTURES_DIR, "grass_albedo.png"), compress_level=6)

def generate_maps():
    M = 512
    gray = np.full((M, M), 120, dtype=np.uint8)
    rgba = np.stack([gray, gray, gray, np.full_like(gray, 255)], axis=-1)
    for m in ["malang", "surabaya", "jakarta"]:
        Image.fromarray(rgba, mode="RGBA").save(os.path.join(MAPS_DIR, f"{m}_heightmap.png"), compress_level=6)

if __name__ == "__main__":
    ensure_dirs()
    generate_app_icon()
    generate_textures()
    generate_maps()
    print("HD Assets generated!")
