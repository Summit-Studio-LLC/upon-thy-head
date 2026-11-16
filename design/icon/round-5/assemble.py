import json, subprocess, re
from pathlib import Path

ROOT = Path(__file__).parent
FONT = '/System/Library/Fonts/Supplemental/Arial.ttf'
records = json.loads((ROOT/'generation-record.json').read_text())
def run(*args):
    return subprocess.check_output(['magick', *map(str,args)], text=True).strip()

checks=[]
for item in records:
    name=item['id']; src=item['source']; flat=name.startswith('F') or int(name[1:])>=9
    # Inspect source before any threshold. Counts complement visual inspection;
    # they cannot establish whether a drawing is flat by themselves.
    stats=run(src,'-colorspace','Gray','-format','%[fx:mean]','info:')
    bound='25%' if flat or int(name[1:])>=5 else '2%'
    bbox=run(src,'-colorspace','Gray','-threshold',bound,'-format','%@','info:')
    w,h,x,y=map(int,re.match(r'(\d+)x(\d+)\+(\d+)\+(\d+)',bbox).groups())
    sw,sh=map(int,run(src,'-format','%w %h','info:').split())
    scale=min(1024/sw,1024/sh,716/w,716/h)
    # Resizing/centering only. No redraw, contours, or new icon geometry.
    nw,nh=round(sw*scale),round(sh*scale)
    ox=round(512-(x+w/2)*scale); oy=round(512-(y+h/2)*scale)
    dst=ROOT/(name+'.png')
    args=[src,'-resize',f'{nw}x{nh}!','-background','black','-gravity','NorthWest',
          '-splice',f'{max(0,ox)}x{max(0,oy)}','-gravity','NorthWest','-extent','1024x1024']
    if flat: args+=['-colorspace','Gray','-threshold','50%','-type','bilevel']
    else: args+=['-black-threshold','2%']
    args+=[dst]
    run(*args)
    final=run(dst,'-format','%wx%h colors=%k','info:')
    if flat:
        assert run(dst,'-format','%k','info:')=='2', name
        assert run(dst,'-format','%[fx:minima] %[fx:maxima]','info:')=='0 1', name
    assert run(dst,'-format','%w %h','info:')=='1024 1024',name
    checks.append(f'{name}: source {sw}x{sh}, source mean={stats}, source threshold-{bound} bbox={bbox}; final {final}; flat={flat}')

# All drawing commands below are presentation furniture for contact sheets only.
# Finished icon PNGs above are never drawn into.
def label(args,text,x,y,size=24):
    args.extend(['-font',FONT,'-pointsize',str(size),'-fill','#111111','-gravity','NorthWest','-annotate',f'+{x}+{y}',text])
def place(args,path,x,y,size):
    args.extend(['(',str(path),'-resize',f'{size}x{size}',')','-geometry',f'+{x}+{y}','-composite'])
def rounded(args,path,x,y,size):
    radius=round(size*.23)
    args.extend(['(',str(path),'-resize',f'{size}x{size}','(', '-size',f'{size}x{size}',
                 'xc:black','-fill','white','-draw',f'roundrectangle 0,0 {size-1},{size-1} {radius},{radius}',
                 ')','-alpha','off','-compose','CopyOpacity','-composite',')',
                 '-compose','Over','-geometry',f'+{x}+{y}','-composite'])

hands=['-size','2140x1180','xc:#808080']
for i in range(10):
    x=30+(i%5)*420; y=20+(i//5)*450
    place(hands,ROOT/f'F{i+1}.png',x,y,400)
    label(hands,f'F{i+1}',x+180,y+405)
label(hands,'Actual pixels: 60 / 29',30,931,20)
for i in range(10):
    x=30+i*210
    label(hands,f'F{i+1}',x,971,20)
    rounded(hands,ROOT/f'F{i+1}.png',x,1010,60)
    rounded(hands,ROOT/f'F{i+1}.png',x+82,1041,29)
    label(hands,'60',x+16,1083,16); label(hands,'29',x+83,1083,16)
hands.append(str(ROOT/'sheet-hands.png'));run(*hands)

crowns=['-size','1720x1620','xc:#808080']
for i in range(12):
    x=30+(i%4)*420; y=20+(i//4)*450
    place(crowns,ROOT/f'G{i+1}.png',x,y,400)
    label(crowns,f'G{i+1}',x+180,y+405)
label(crowns,'Flat marks / actual pixels: 120 / 60 / 29',30,1372,20)
for i in range(4):
    x=30+i*420; name=f'G{i+9}'
    rounded(crowns,ROOT/(name+'.png'),x,1420,120)
    rounded(crowns,ROOT/(name+'.png'),x+150,1480,60)
    rounded(crowns,ROOT/(name+'.png'),x+240,1511,29)
    label(crowns,name,x,1555,20)
    for dx,s in [(65,120),(150,60),(240,29)]:label(crowns,str(s),x+dx,1555,16)
crowns.append(str(ROOT/'sheet-crown.png'));run(*crowns)
(ROOT/'pixel-check.txt').write_text('\n'.join(checks)+'\n')
print('\n'.join(checks))
