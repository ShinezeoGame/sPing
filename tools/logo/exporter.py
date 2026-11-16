"""Exporte les PNG et les icônes des systèmes à partir des SVG de `docs/logo`.

Utilisation, depuis la racine du dépôt (nécessite `pip install cairosvg pillow`) :

    python3 tools/logo/exporter.py

Fichiers produits :

    docs/logo/sping-logo-1024.png                          logo pour le README
    assets/branding/logo.png                               logo de l'en-tête de l'application
    windows/runner/resources/app_icon.ico                  icône de l'application Windows
    android/app/src/main/res/mipmap-*/ic_launcher.png      icône Android classique
    android/…/mipmap-*/ic_launcher_foreground.png          couche avant de l'icône adaptative
"""

import io

import cairosvg
from PIL import Image

LOGO = 'docs/logo/sping-logo.svg'
PETIT = 'docs/logo/sping-logo-petit.svg'
AVANT_PLAN = 'docs/logo/sping-icone-avant-plan.svg'


def rendu(svg, taille):
    png = cairosvg.svg2png(url=svg, output_width=taille, output_height=taille)
    return Image.open(io.BytesIO(png)).convert('RGBA')


rendu(LOGO, 1024).save('docs/logo/sping-logo-1024.png', optimize=True)
rendu(LOGO, 256).save('assets/branding/logo.png', optimize=True)

# Icône Windows : une image par taille, la variante au trait renforcé pour les plus petites.
TAILLES = [16, 20, 24, 32, 40, 48, 64, 128, 256]
images = [rendu(PETIT if taille <= 32 else LOGO, taille) for taille in TAILLES]
images[-1].save(
    'windows/runner/resources/app_icon.ico',
    format='ICO',
    sizes=[(taille, taille) for taille in TAILLES],
    append_images=images[:-1],
    bitmap_format='bmp',
)

# Android : une taille par densité d'écran (icône classique 48 dp, couche adaptative 108 dp).
DENSITES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for nom, facteur in DENSITES.items():
    dossier = f'android/app/src/main/res/mipmap-{nom}'
    rendu(LOGO, round(48 * facteur)).save(f'{dossier}/ic_launcher.png', optimize=True)
    rendu(AVANT_PLAN, round(108 * facteur)).save(f'{dossier}/ic_launcher_foreground.png', optimize=True)
print('PNG et icônes exportés')
