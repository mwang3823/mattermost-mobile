#!/usr/bin/env python3
"""Sinh toan bo icon/logo cua app tu assets/base/images/tdchat_icon.png va tdchat_logo_transparent.png."""
import os
import shutil

from PIL import Image

from tdc_brand import BG, ROOT, logo, master, on_canvas, rounded, white_mask

NAVY = BG + (255,)

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
    # iOS app icon khong duoc co alpha
    (im if keep_alpha else im.convert('RGB')).save(full, 'PNG')
    written.append(path)


# ---------------------------------------------------------------- Android icon
for dpi, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    save(rounded(size, radius=0.18),
         f'android/app/src/main/res/mipmap-{dpi}/ic_launcher.png',
         also=f'{REL_ANDROID}/mipmap-{dpi}/ic_launcher.png')
    save(on_canvas(logo, size, 0.72, bg=NAVY, circle=True),
         f'android/app/src/main/res/mipmap-{dpi}/ic_launcher_round.png',
         also=f'{REL_ANDROID}/mipmap-{dpi}/ic_launcher_round.png')

# Adaptive icon: canvas 108dp, launcher chi hien vung 72dp o giua
# -> logo tach nen rong ~56dp (vua trong safe zone), nen la mau navy dac.
for dpi, size in [('mdpi', 108), ('hdpi', 162), ('xhdpi', 216), ('xxhdpi', 324), ('xxxhdpi', 432)]:
    save(on_canvas(logo, size, 56 / 108),
         f'android/app/src/main/res/mipmap-{dpi}/ic_launcher_foreground.png',
         also=f'{REL_ANDROID}/mipmap-{dpi}/ic_launcher_foreground.png')
    save(Image.new('RGBA', (size, size), NAVY),
         f'android/app/src/main/res/mipmap-{dpi}/ic_launcher_background.png',
         also=f'{REL_ANDROID}/mipmap-{dpi}/ic_launcher_background.png')

# ------------------------------------------- Android notification icon (status bar)
# Android to lai icon status bar thanh don sac -> chi giu silhouette trang cua khung chat.
for dpi, size in [('mdpi', 22), ('hdpi', 33), ('xhdpi', 44), ('xxhdpi', 66), ('xxxhdpi', 88)]:
    save(white_mask(size, 0.92),
         f'android/app/src/main/res/mipmap-{dpi}/ic_notification.png',
         also=f'{REL_ANDROID}/mipmap-{dpi}/ic_notification.png')

# ------------------------------------------------------------- Android splash
# launch_screen.xml ve splash trong o 216dp
for dpi, size in [('mdpi', 216), ('hdpi', 324), ('xhdpi', 432), ('xxhdpi', 648), ('xxxhdpi', 864)]:
    im = on_canvas(rounded(size), size, 0.6)
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
    save(master.resize((size, size), Image.LANCZOS), f'{IOS}/{name}', keep_alpha=False,
         also=f'{REL_IOS}/{name}')

# -------------------------------------------------------------- iOS SplashIcon
SPLASH = 'ios/Mattermost/Images.xcassets/SplashIcon.imageset'
for suffix, size in [('', 300), ('@2x', 600), ('@3x', 900)]:
    im = on_canvas(rounded(size), size, 0.6)
    save(im, f'{SPLASH}/SplashIcon{suffix}.png')
    save(im, f'{SPLASH}/SplashIcon_Dark{suffix}.png')

# ------------------------------------------------- Asset dung chung trong app JS
save(master.convert('RGBA').resize((152, 152), Image.LANCZOS), 'assets/base/images/icon.png')
save(rounded(667), 'assets/base/images/logo.png')
save(rounded(512), 'assets/base/images/tdc_logo.png')

print(f'Da ghi {len(written)} file:')
for p in written:
    print(' ', p)
