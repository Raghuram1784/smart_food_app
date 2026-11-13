from pathlib import Path
from PIL import Image,ImageOps
for name in ['dosa','idli','biryani','paneer']:
 p=Path(f'assets/images/food/{name}.jpg'); im=Image.open(p)
 if min(im.size) < 1600:
  raise ValueError('Run fetch_assets.ps1 first: full source images are required; do not recrop bundled derivatives.')
 ImageOps.fit(im,(1800,1100),centering=(.5,.55)).save(f'assets/images/restaurants/{name}.jpg',quality=86,optimize=True)
 ImageOps.fit(im,(800,800),centering=(.5,.55)).save(f'assets/images/categories/{name}.jpg',quality=85,optimize=True)
 if name=='dosa':ImageOps.fit(im,(1800,1100),centering=(.5,.55)).save('assets/images/hero/dosa.jpg',quality=88,optimize=True)
 ImageOps.fit(im,(1400,1400),centering=(.5,.55)).save(p,quality=88,optimize=True)
