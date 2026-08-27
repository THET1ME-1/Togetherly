import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

FDIR=os.path.expanduser('~/.local/share/fonts/togetherly')
W,H=1240,1560; M=46
LIGHT=(240,233,216); DARK=(38,34,28)

def font(n,s,v=None):
    f=ImageFont.truetype(os.path.join(FDIR,n),s)
    if v:
        try: f.set_variation_by_name(v)
        except Exception: pass
    return f

def lum(a,box):
    x0,y0,x1,y1=[int(v) for v in box]
    p=a[max(y0,0):min(y1,H), max(x0,0):min(x1,W)]
    return p.mean() if p.size else 128

def pick(a,box,th=138):
    return DARK if lum(a,box)>th else LIGHT

def build(src, title, code, caption, out):
    im=Image.open(src).convert('RGB'); sw,sh=im.size
    k=max(W/sw,H/sh); im=im.resize((round(sw*k),round(sh*k)),Image.LANCZOS); sw,sh=im.size
    p=im.crop(((sw-W)//2,(sh-H)//2,(sw-W)//2+W,(sh-H)//2+H))
    g=np.array(p.convert('L')).astype(float)
    d=ImageDraw.Draw(p)

    # рамка: каждая сторона красится по своей яркости
    def side(box):
        x0,y0,x1,y1=box
        return DARK if g[y0:y1,x0:x1].mean()>138 else LIGHT
    cT=side((M,M-6,W-M,M+6)); cB=side((M,H-M-6,W-M,H-M+6))
    cL=side((M-6,M,M+6,H-M)); cR=side((W-M-6,M,W-M+6,H-M))
    d.line([M,M,W-M-1,M],fill=cT,width=3)
    d.line([M,H-M-1,W-M-1,H-M-1],fill=cB,width=3)
    d.line([M,M,M,H-M-1],fill=cL,width=3)
    d.line([W-M-1,M,W-M-1,H-M-1],fill=cR,width=3)
    for (x,y,ch,cv) in [(M,M,cT,cL),(W-M-1,M,cT,cR),(M,H-M-1,cB,cL),(W-M-1,H-M-1,cB,cR)]:
        d.line([x-18,y,x+18,y],fill=ch,width=3)
        d.line([x,y-18,x,y+18],fill=cv,width=3)

    f_code=font('Unbounded.ttf',104,'Bold')
    f_ttl =font('Unbounded.ttf',78,'Bold')
    f_cap =font('Onest.ttf',26,'Medium')

    cx,cy=M+40,M+34
    cw=d.textlength(code,font=f_code)
    d.text((cx,cy),code,font=f_code,fill=pick(g,(cx,cy,cx+cw,cy+110)))

    ty=H-M-210; tw=d.textlength(title,font=f_ttl)
    tc=pick(g,(M+40,ty,M+40+tw,ty+84))
    d.text((M+40,ty),title,font=f_ttl,fill=tc)

    ky=H-M-110; kw=d.textlength(caption,font=f_cap)
    kc=pick(g,(M+44,ky,M+44+kw,ky+34))
    d.text((M+44,ky),caption,font=f_cap,
           fill=kc if kc==DARK else (228,221,204))

    a=np.array(p).astype(np.int16)
    a+=np.random.default_rng(7).integers(-6,7,(H,W))[:,:,None]
    Image.fromarray(np.clip(a,0,255).astype('uint8')).save(out)
    nm=lambda c:'тёмн' if c==DARK else 'светл'
    print(out,'| рамка В%s Н%s Л%s П%s'%(nm(cT),nm(cB),nm(cL),nm(cR)),
          '| номер',nm(pick(g,(cx,cy,cx+cw,cy+110))),'| заголовок',nm(tc))

if __name__=='__main__':
    build(*sys.argv[1:6])
