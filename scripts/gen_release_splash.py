#!/usr/bin/env python3
"""Cap nhat splash screen dung cho RELEASE build (Fastlane copy tu dist/assets/release/splash_screen)."""
import os
import shutil
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, 'assets/base/release/splash_screen')
CONTENT_BOX = (66, 71, 1757, 889)
logo = Image.open(os.path.join(ROOT, 'assets/base/images/tdc_logo.png')).convert('RGBA').crop(CONTENT_BOX)

def square(canvas, frac, bg=None):
    im = Image.new('RGBA', (canvas, canvas), bg or (0, 0, 0, 0))
    w = int(round(canvas * frac)); h = int(round(w * logo.height / logo.width))
    r = logo.resize((w, h), Image.LANCZOS)
    im.paste(r, ((canvas - w) // 2, (canvas - h) // 2), r)
    return im

n = 0
for dpi, size in [('mdpi',216),('hdpi',324),('xhdpi',432),('xxhdpi',648),('xxxhdpi',864)]:
    im = square(size, 0.94)
    for d in (f'android/drawable-{dpi}', f'android/drawable-night-{dpi}'):
        p = os.path.join(BASE, d, 'splash.png')
        if os.path.isdir(os.path.dirname(p)):
            im.save(p); n += 1
    light = os.path.join(BASE, f'android/drawable-{dpi}/splash_background.png')
    night = os.path.join(BASE, f'android/drawable-night-{dpi}/splash_background.png')
    if os.path.exists(light) and os.path.exists(night):
        shutil.copyfile(light, night); n += 1

for suffix, size in [('',300),('@2x',600),('@3x',900)]:
    im = square(size, 0.94)
    im.save(os.path.join(BASE, f'ios/SplashIcon.imageset/SplashIcon{suffix}.png')); n += 1
    im.save(os.path.join(BASE, f'ios/SplashIcon.imageset/SplashIcon_Dark{suffix}.png')); n += 1

square(667, 0.90, bg=(255,255,255,255)).save(os.path.join(BASE, 'ios/splash.png')); n += 1

# splash luon nen trang -> dark mode dung cung mau
p = os.path.join(BASE, 'android/values-night/colors.xml')
s = open(p).read().replace('<color name="splashscreen_bg">#090A0B</color>',
                           '<color name="splashscreen_bg">#FFFFFF</color>')
open(p, 'w').write(s); n += 1
print(f'Da cap nhat {n} file trong assets/base/release/splash_screen')
