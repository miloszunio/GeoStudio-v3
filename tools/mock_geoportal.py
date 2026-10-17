import math, io, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
from PIL import Image, ImageDraw, ImageFilter
import random

CX, CY = 637382.0, 486757.0   # E, N
def rect(cx, cy, w, h, rot):
    pts=[]
    for x,y in [(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)]:
        a=math.radians(rot); pts.append((cx+x*math.cos(a)-y*math.sin(a), cy+x*math.sin(a)+y*math.cos(a)))
    return pts
BUILDINGS = [
  {"id":"B1","ring":rect(CX,CY,10,6,20),"floors":1},
  {"id":"B2","ring":rect(CX+30,CY+12,14,8,-35),"floors":3},
  {"id":"B3","ring":[(CX-40,CY-20),(CX-20,CY-20),(CX-20,CY-8),(CX-30,CY-8),(CX-30,CY+4),(CX-40,CY+4)],"floors":2},
  {"id":"B4","ring":rect(CX-8,CY+30,8,8,5),"floors":1},
]
def gml(bbox_en):
    out=['<?xml version="1.0" encoding="UTF-8"?>','<wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0" xmlns:gml="http://www.opengis.net/gml/3.2" xmlns:ewns="http://xyz" numberReturned="%d">'%len(BUILDINGS)]
    minx,miny,maxx,maxy=bbox_en
    for b in BUILDINGS:
        xs=[p[0] for p in b["ring"]]; ys=[p[1] for p in b["ring"]]
        if max(xs)<minx or min(xs)>maxx or max(ys)<miny or min(ys)>maxy: continue
        ring=b["ring"]+[b["ring"][0]]
        pos=" ".join("%.2f %.2f"%(y,x) for x,y in ring)   # official EPSG:2180 axis order: N E
        out.append('<wfs:member><ewns:budynki gml:id="%s"><ewns:geometria><gml:Polygon srsName="urn:ogc:def:crs:EPSG::2180"><gml:exterior><gml:LinearRing><gml:posList srsDimension="2">%s</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></ewns:geometria><ewns:idBudynku>%s</ewns:idBudynku><ewns:liczbaKondygnacji>%d</ewns:liczbaKondygnacji><ewns:rodzajWgKST>m</ewns:rodzajWgKST></ewns:budynki></wfs:member>'%(b["id"],pos,b["id"],b["floors"]))
    out.append('</wfs:FeatureCollection>')
    return "\n".join(out).encode()

class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a): sys.stderr.write("MOCK "+(fmt%a)+"\n")
    def do_GET(self):
        u=urlparse(self.path); q={k.lower():v[0] for k,v in parse_qs(u.query).items()}
        if u.path.startswith("/wms"):
            if q.get("request","").lower()=="getcapabilities":
                body=b'<WMS_Capabilities><Layer><Name>Raster</Name></Layer></WMS_Capabilities>'; ct="text/xml"
            else:
                w,h=int(q["width"]),int(q["height"]); minx,miny,maxx,maxy=[float(v) for v in q["bbox"].split(",")]
                random.seed(1)
                im=Image.effect_noise((w,h),30).convert("RGB")
                base=Image.new("RGB",(w,h),(86,110,70)); im=Image.blend(base,im,0.25)
                d=ImageDraw.Draw(im)
                def px(x,y): return ((x-minx)/(maxx-minx)*w,(maxy-y)/(maxy-miny)*h)
                for b in BUILDINGS:
                    d.polygon([px(*p) for p in b["ring"]],fill=(150,70,60))
                buf=io.BytesIO(); im.save(buf,"JPEG",quality=85); body=buf.getvalue(); ct="image/jpeg"
        elif u.path.startswith("/geocode"):
            import json
            body=json.dumps([{"display_name":"Nowa Wieś, gmina Test, wielkopolskie","lat":"52.0146","lon":"16.2156"},{"display_name":"Nowa Wieś Wielka, kujawsko-pomorskie","lat":"52.9","lon":"18.2"}]).encode(); ct="application/json"
        elif u.path.startswith("/wfs"):
            if q.get("request","").lower()=="getcapabilities":
                body=b'<WFS_Capabilities><FeatureType><Name>ewns:budynki</Name></FeatureType></WFS_Capabilities>'; ct="text/xml"
            else:
                v=[float(t) for t in q["bbox"].split(",")[:4]]
                # URN CRS request -> (miny,minx,maxy,maxx); EPSG:2180 short -> (minx,miny,maxx,maxy)
                bb=(v[1],v[0],v[3],v[2]) if "urn" in q.get("srsname","") else tuple(v)
                tn=q.get("typenames","")
                body=gml(bb) if tn=="ewns:budynki" else b'<ows:ExceptionReport xmlns:ows="http://www.opengis.net/ows/1.1"><ows:Exception exceptionCode="InvalidParameterValue"/></ows:ExceptionReport>'
                ct="text/xml"
        else:
            self.send_response(404); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Type",ct); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
HTTPServer(("127.0.0.1",8765),H).serve_forever()
