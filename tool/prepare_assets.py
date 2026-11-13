from pathlib import Path
from PIL import Image,ImageOps,ImageDraw
root=Path('.')
canvas=Image.new('RGB',(800,600))
for i,name in enumerate(['burger','pasta','pizza','salad']):
 p=Path(f'assets/images/food/{name}.jpg')
 im=Image.open(p); im.save(p,quality=88,optimize=True)
 im.save(f'assets/images/restaurants/{p.name}',quality=85,optimize=True)
 ImageOps.fit(im,(600,600)).save(f'assets/images/categories/{p.name}',quality=85)
 tile=ImageOps.fit(im,(400,300)); canvas.paste(tile,((i%2)*400,(i//2)*300)); ImageDraw.Draw(canvas).text(((i%2)*400+10,(i//2)*300+10),p.stem,fill='white')
Image.open('assets/images/food/pizza.jpg').save('assets/images/hero/pizza.jpg',quality=88)
canvas.save('docs/contact-sheet.jpg')
