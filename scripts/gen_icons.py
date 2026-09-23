#!/usr/bin/env python3
"""Sinh toan bo icon/logo cua app tu assets/base/images/tdc_logo.png."""
import os
import shutil
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'assets/base/images/tdc_logo.png')
WHITE = (255, 255, 255, 255)

# Bbox noi dung thuc cua logo (bo phan trong suot thua)
CONTENT_BOX = (66, 71, 1757, 889)
SUNBURST_BOX = (958, 72, 1756, 443)

master = Image.open(SRC).convert('RGBA')
logo = master.crop(CONTENT_BOX)
sun = master.crop(SUNBURST_BOX)

written = []

# Fastlane (REPLACE_ASSETS) copy de len project tu assets/base/release/icons/*,
# nen phai ghi ca vao day, khong thi build qua Fastlane se tra icon ve Mattermost.
REL_ANDROID = 'assets/base/release/icons/android'
REL_IOS = 'assets/base/release/icons/ios'


def save(im, path, keep_alpha=True, also=None):
    if also:
        save(im, also, keep_alpha)
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    if keep_alpha:
        im.save(full, 'PNG')
    else:
        # iOS app icon khong duoc co alpha
        bg = Image.new('RGB', im.size, (255, 255, 255))
        bg.paste(im, (0, 0), im if im.mode == 'RGBA' else None)
        bg.save(full, 'PNG')
    written.append(path)


def fitted(src, canvas, frac):
    """Thu src vua trong canvas vuong, chiem `frac` chieu rong, can giua."""
    w = max(1, int(round(canvas * frac)))
    h = max(1, int(round(w * src.height / src.width)))
    if h > canvas * frac:
        h = max(1, int(round(canvas * frac)))
        w = max(1, int(round(h * src.width / src.height)))
    return src.resize((w, h), Image.LANCZOS), w, h


def square(canvas, frac, bg=None, circle_bg=False, src=None):
    src = src if src is not None else logo
    im = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    if circle_bg:
        d = ImageDraw.Draw(im)
        d.ellipse((0, 0, canvas - 1, canvas - 1), fill=bg or WHITE)
    elif bg:
        im.paste(bg, (0, 0, canvas, canvas))
    r, w, h = fitted(src, canvas, frac)
    im.paste(r, ((canvas - w) // 2, (canvas - h) // 2), r)
    return im


# ---------------------------------------------------------------- Android icon
# Legacy icon: nen trang day, logo 88% chieu rong
for dpi, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    save(square(size, 0.88, bg=WHITE),
         f'android/app/src/main/res/mipmap-{dpi}/ic_launcher.png',
         also=f'{REL_ANDROID}/mipmap-{dpi}/ic_launcher.png')
    # Icon tron: logo phai nam gon trong duong tron -> 62%
    save(square(size, 0.62, bg=WHITE, circle_bg=True),
         f'android/app/src/main/res/mipmap-{dpi}/ic_launcher_round.png',
         also=f'{REL_ANDROID}/mipmap-{dpi}/ic_launcher_round.png')

# Adaptive icon: canvas 108dp, safe zone la duong tron 66dp o giua.
# Logo ti le 2.07:1 vua khit trong duong tron do khi rong ~54% canvas -> khong bao gio bi cat.
for dpi, size in [('mdpi', 108), ('hdpi', 162), ('xhdpi', 216), ('xxhdpi', 324), ('xxxhdpi', 432)]:
    save(square(size, 0.54),
         f'android/app/src/main/res/mipmap-{dpi}/ic_launcher_foreground.png',
         also=f'{REL_ANDROID}/mipmap-{dpi}/ic_launcher_foreground.png')
    save(Image.new('RGBA', (size, size), WHITE),
         f'android/app/src/main/res/mipmap-{dpi}/ic_launcher_background.png',
         also=f'{REL_ANDROID}/mipmap-{dpi}/ic_launcher_background.png')

# ------------------------------------------- Android notification icon (status bar)
# Android to lai icon status bar thanh don sac -> chi giu silhouette trang cua mat troi.
sun_mask = sun.getchannel('A').point(lambda a: 255 if a > 40 else 0)
sun_white = Image.new('RGBA', sun.size, (255, 255, 255, 0))
sun_white.putalpha(sun_mask)
sun_white.paste((255, 255, 255), (0, 0) + sun.size, sun_mask)
sun_white.putalpha(sun_mask)
for dpi, size in [('mdpi', 22), ('hdpi', 33), ('xhdpi', 44), ('xxhdpi', 66), ('xxxhdpi', 88)]:
    save(square(size, 0.92, src=sun_white),
         f'android/app/src/main/res/mipmap-{dpi}/ic_notification.png',
         also=f'{REL_ANDROID}/mipmap-{dpi}/ic_notification.png')

# ------------------------------------------------------------- Android splash
for dpi, size in [('mdpi', 96), ('hdpi', 192), ('xhdpi', 288), ('xxhdpi', 384), ('xxxhdpi', 480)]:
    im = square(size, 0.94)
    save(im, f'android/app/src/main/res/drawable-{dpi}/splash.png')
    save(im, f'android/app/src/main/res/drawable-night-{dpi}/splash.png')
    # Splash luon nen trang -> dung chung background sang cho ca dark mode
    light_bg = os.path.join(ROOT, f'android/app/src/main/res/drawable-{dpi}/splash_background.png')
    night_bg = os.path.join(ROOT, f'android/app/src/main/res/drawable-night-{dpi}/splash_background.png')
    if os.path.exists(light_bg):
        shutil.copyfile(light_bg, night_bg)
        written.append(f'android/app/src/main/res/drawable-night-{dpi}/splash_background.png (copy tu light)')

# ----------------------------------------------------------------- iOS AppIcon
IOS = 'ios/Mattermost/Images.xcassets/AppIcon.appiconset'
for name, size in [
    ('20.png', 20), ('20@2x.png', 40), ('20@3x.png', 60),
    ('29.png', 29), ('29@2x.png', 58), ('29@3x.png', 87),
    ('40.png', 40), ('40@2x.png', 80), ('40@3x.png', 120),
    ('76.png', 76), ('76@2x.png', 152), ('83.5@2x.png', 167),
    ('Icon-60@2x.png', 120), ('Icon-60@3x.png', 180),
    ('iTunesArtwork@2x.png', 1024),
]:
    save(square(size, 0.84, bg=WHITE), f'{IOS}/{name}', keep_alpha=False,
         also=f'{REL_IOS}/{name}')

# -------------------------------------------------------------- iOS SplashIcon
SPLASH = 'ios/Mattermost/Images.xcassets/SplashIcon.imageset'
for suffix, size in [('', 300), ('@2x', 600), ('@3x', 900)]:
    im = square(size, 0.94)
    save(im, f'{SPLASH}/SplashIcon{suffix}.png')
    save(im, f'{SPLASH}/SplashIcon_Dark{suffix}.png')

# ------------------------------------------------- Asset dung chung trong app JS
save(square(152, 0.86, bg=WHITE), 'assets/base/images/icon.png')
save(square(667, 0.90, bg=WHITE), 'assets/base/images/logo.png')

print(f'Da ghi {len(written)} file:')
for p in written:
    print(' ', p)
