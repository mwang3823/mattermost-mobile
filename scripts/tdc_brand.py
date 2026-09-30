"""Nguon anh thuong hieu TDChat dung chung cho gen_icons.py va gen_release_splash.py."""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'assets/base/images/tdchat_icon.png')
SRC_TRANSPARENT = os.path.join(ROOT, 'assets/base/images/tdchat_logo_transparent.png')

# Icon day du (nen navy) va logo da tach nen
master = Image.open(SRC).convert('RGB')
cutout = Image.open(SRC_TRANSPARENT).convert('RGBA')

# Mau nen xanh navy cua icon goc (trung binh vien anh)
_px = np.array(master).astype(np.float32)
BG = tuple(int(round(v)) for v in np.concatenate([
    _px[:6].reshape(-1, 3), _px[-6:].reshape(-1, 3), _px[:, :6].reshape(-1, 3), _px[:, -6:].reshape(-1, 3),
]).mean(0))


def _square(im):
    """Cat sat noi dung roi dem thanh hinh vuong trong suot, can giua."""
    im = im.crop(im.getbbox())
    side = max(im.size)
    sq = Image.new(im.mode, (side, side), 0)
    sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    return sq


# Logo tach nen cat sat bien (vuong)
logo = _square(cutout)
silhouette = _square(cutout.getchannel('A').point(lambda a: 255 if a > 128 else 0).filter(ImageFilter.GaussianBlur(1)))


def _resize(im, size):
    return im.resize((size, size), Image.LANCZOS)


def rounded(size, radius=0.2235):
    """Icon vuong bo goc (goc trong suot) - dung cho splash va logo trong app."""
    big = size * 4
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=int(big * radius), fill=255)
    im = _resize(master.convert('RGBA'), size)
    im.putalpha(_resize(mask, size))
    return im


def on_canvas(src, canvas, frac, bg=None, circle=False):
    """Dat src (vuong) vao giua canvas vuong, chiem `frac` chieu rong."""
    im = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    if circle:
        big = canvas * 4
        mask = Image.new('L', (big, big), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, big - 1, big - 1), fill=255)
        im = Image.new('RGBA', (canvas, canvas), bg)
        im.putalpha(_resize(mask, canvas))
    elif bg:
        im.paste(bg, (0, 0, canvas, canvas))
    w = max(1, int(round(canvas * frac)))
    off = (canvas - w) // 2
    layer = Image.new('RGBA', im.size, (0, 0, 0, 0))
    layer.paste(_resize(src, w), (off, off))
    return Image.alpha_composite(im, layer)


def white_mask(size, frac):
    """Silhouette trang tren nen trong suot (icon thong bao Android)."""
    w = max(1, int(round(size * frac)))
    a = Image.new('L', (size, size), 0)
    a.paste(_resize(silhouette, w), ((size - w) // 2, (size - w) // 2))
    im = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    im.putalpha(a)
    return im
