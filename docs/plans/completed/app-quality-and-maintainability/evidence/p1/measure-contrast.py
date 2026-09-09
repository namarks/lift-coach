import collections, json, pathlib, struct, zlib
root=pathlib.Path(__file__).resolve().parent
def pixels(path):
 data=path.read_bytes(); pos=8; packed=b''
 while pos<len(data):
  size=struct.unpack('>I',data[pos:pos+4])[0]; name=data[pos+4:pos+8]; body=data[pos+8:pos+8+size];pos+=size+12
  if name==b'IHDR': w,h,depth,kind,_,_,interlace=struct.unpack('>IIBBBBB',body)
  if name==b'IDAT':packed+=body
 assert depth==8 and kind in (2,6) and interlace==0,(depth,kind,interlace)
 bpp=3 if kind==2 else 4; stride=w*bpp; raw=zlib.decompress(packed);previous=bytearray(stride);allpixels=[]
 for y in range(h):
  offset=y*(stride+1);mode=raw[offset];row=bytearray(raw[offset+1:offset+1+stride])
  for i in range(stride):
   a=row[i-bpp] if i>=bpp else 0;b=previous[i];c=previous[i-bpp] if i>=bpp else 0
   if mode==1:v=a
   elif mode==2:v=b
   elif mode==3:v=(a+b)//2
   elif mode==4:
    p=a+b-c;pa,pb,pc=abs(p-a),abs(p-b),abs(p-c);v=a if pa<=pb and pa<=pc else b if pb<=pc else c
   else:v=0
   row[i]=(row[i]+v)%256
  allpixels.extend(tuple(row[i:i+3]) for i in range(0,stride,bpp));previous=row
 return collections.Counter(allpixels)
def luminance(rgb):
 parts=[v/255 for v in rgb];parts=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in parts]
 return sum(a*b for a,b in zip(parts,(.2126,.7152,.0722)))
result={}
for name,file in [('empty-guidance','contrast-empty-guidance.png'),('load-error','contrast-load-error.png'),('working-set-count','contrast-working-set-count.png')]:
 counts=pixels(root/file); foreground=max(counts,key=luminance); background=max((rgb for rgb in counts if max(rgb)<40),key=luminance)
 result[name]={'brightest_glyph_pixel':foreground,'brightest_dark_reference_pixel':background,'core_pixel_contrast':round((luminance(foreground)+.05)/(luminance(background)+.05),2),'foreground_pixel_count':counts[foreground]}
print(json.dumps(result,indent=2))
(root/'contrast-measurements.json').write_text(json.dumps(result,indent=2)+'\n')
