"""NekoVPN icon: a ginger cat head, drawn once as geometry and emitted as an
Android VectorDrawable (adaptive foreground) and as rasters (legacy mipmaps,
TV, banner, in-app icon). Geometry lives in a 240x240 viewport; the adaptive
safe zone is the circle r=73 around (120,120)."""
import math
from PIL import Image, ImageDraw, ImageFont

ORANGE = '#F57C1F'
BG = '#FAFAFA'
HEAD = (120, 132, 56, 46)                     # cx, cy, rx, ry
EARS = [[(70, 118), (80, 62), (110, 92)], [(170, 118), (160, 62), (130, 92)]]
EYES = [(100, 134, 7, 10), (140, 134, 7, 10)]
NOSE = [(113, 149), (127, 149), (120, 157)]

def ell_path(cx, cy, rx, ry):
    return (f'M{cx - rx},{cy} a{rx},{ry} 0 1,0 {2 * rx},0 '
            f'a{rx},{ry} 0 1,0 {-2 * rx},0 z')

def poly_path(pts):
    return 'M' + ' L'.join(f'{x},{y}' for x, y in pts) + ' z'

def vector_xml(tv=False):
    # The TV foreground keeps upstream's <group> transform, which
    # test/android_tv_launcher_icon_test.dart reads; identity here.
    face = ' '.join([ell_path(*HEAD)] + [ell_path(*e) for e in EYES] + [poly_path(NOSE)])
    ears = ' '.join(poly_path(e) for e in EARS)
    paths = (f'    <path\n        android:fillColor="{ORANGE}"\n'
             f'        android:pathData="{ears}" />\n'
             f'    <path\n        android:fillColor="{ORANGE}"\n'
             f'        android:fillType="evenOdd"\n'
             f'        android:pathData="{face}" />\n')
    if tv:
        indented = ''.join('    ' + line + '\n' for line in paths.splitlines())
        body = ('    <group\n        android:scaleX="1"\n        android:scaleY="1"\n'
                '        android:translateX="0"\n        android:translateY="0">\n'
                f'{indented}    </group>\n')
    else:
        body = paths
    return f'''<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="240"
    android:viewportHeight="240">
{body}</vector>
'''

def draw_cat(size, scale=1.0, offset=(0, 0), ss=4):
    """RGBA layer with the cat; the 240-unit geometry scaled to `size`."""
    S = size * ss
    k = S / 240 * scale
    ox, oy = offset[0] * ss, offset[1] * ss
    c = lambda x, y: (ox + (x - 120) * k + S / 2, oy + (y - 120) * k + S / 2)
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for ear in EARS:
        d.polygon([c(*p) for p in ear], fill=ORANGE)
    cx, cy, rx, ry = HEAD
    x0, y0 = c(cx - rx, cy - ry); x1, y1 = c(cx + rx, cy + ry)
    d.ellipse([x0, y0, x1, y1], fill=ORANGE)
    for ex, ey, erx, ery in EYES:
        a0, b0 = c(ex - erx, ey - ery); a1, b1 = c(ex + erx, ey + ery)
        d.ellipse([a0, b0, a1, b1], fill=(0, 0, 0, 0))
    d.polygon([c(*p) for p in NOSE], fill=(0, 0, 0, 0))
    return layer.resize((size, size), Image.LANCZOS)

def legacy(size, round_):
    ss = 4
    S = size * ss
    base = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(base)
    m = S * 0.04
    if round_:
        d.ellipse([m, m, S - m, S - m], fill=BG)
    else:
        d.rounded_rectangle([m, m, S - m, S - m], radius=S * 0.2, fill=BG)
    base = base.resize((size, size), Image.LANCZOS)
    cat = draw_cat(size, scale=1.25)
    return Image.alpha_composite(base, cat)

def tv(size):
    im = Image.new('RGBA', (size, size), BG)
    return Image.alpha_composite(im, draw_cat(size, scale=1.25)).convert('RGB')

def banner(w=320, h=180):
    im = Image.new('RGBA', (w, h), BG)
    im.alpha_composite(draw_cat(150, scale=1.3), (0, 15))
    d = ImageDraw.Draw(im)
    path = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
    x0, right, size = 132, 12, 40
    while size > 10:
        font = ImageFont.truetype(path, size)
        if font.getlength('NekoVPN') <= w - x0 - right:
            break
        size -= 1
    d.text((x0, h / 2), 'NekoVPN', fill='#3A2A1E', font=font, anchor='lm')
    return im

if __name__ == '__main__':
    # python3 tool/neko/icons.py android/app/src/main/res assets/images/icon.png
    import sys
    res = sys.argv[1]
    open(f'{res}/drawable/ic_launcher_foreground.xml', 'w').write(vector_xml())
    open(f'{res}/drawable/ic_launcher_foreground_tv.xml', 'w').write(vector_xml(tv=True))
    for dpi, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        legacy(px, False).save(f'{res}/mipmap-{dpi}/ic_launcher.webp', 'WEBP', lossless=True)
        legacy(px, True).save(f'{res}/mipmap-{dpi}/ic_launcher_round.webp', 'WEBP', lossless=True)
    for dpi, px in (('mdpi', 80), ('hdpi', 120), ('xhdpi', 160), ('xxhdpi', 240), ('xxxhdpi', 320)):
        tv(px).save(f'{res}/mipmap-television-{dpi}/ic_launcher.webp', 'WEBP', lossless=True)
    banner().save(f'{res}/mipmap-xhdpi/ic_banner.png')
    draw_cat(550, scale=1.3).save(sys.argv[2])
    print('generated')
