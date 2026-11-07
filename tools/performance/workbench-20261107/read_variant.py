"""Read-only strict subset of Godot4 store_var, rejecting unsupported variant flags/types.
No object deserialization or code execution. Each decoded top-level value retains its exact byte span.
"""
import struct,json,sys,hashlib
from pathlib import Path
class Decoder:
 def __init__(self,data):self.data=data;self.i=0;self.types=set();self.spans={}
 def take(self,n):
  if n<0 or self.i+n>len(self.data):raise ValueError('truncated input')
  out=self.data[self.i:self.i+n];self.i+=n;return out
 def u32(self):return struct.unpack('<I',self.take(4))[0]
 def value(self,depth=0):
  if depth>100:raise ValueError('excessive nesting')
  header=self.u32();kind=header&0xffff;flags=header>>16;self.types.add((kind,flags))
  if kind==0 and flags==0:return None
  if kind==1 and flags==0:
   n=self.u32()
   if n not in (0,1):raise ValueError('invalid bool')
   return bool(n)
  if kind in (2,3) and flags in (0,1):
   fmt={2:('i','q'),3:('f','d')}[kind][flags];return struct.unpack('<'+fmt,self.take(8 if flags else 4))[0]
  if kind in (4,21) and flags==0:
   n=self.u32();text=self.take(n).decode('utf-8');self.take((-n)%4);return text
  if kind==27 and flags==0:
   n=self.u32()&0x7fffffff;out={}
   if n>1000000:raise ValueError('oversized dictionary')
   for _ in range(n):
    key=self.value(depth+1);start=self.i;val=self.value(depth+1)
    if key in out:raise ValueError('duplicate dictionary key')
    out[key]=val
    if depth==0:self.spans[key]=(start,self.i)
   return out
  if kind==28 and flags in (0,1):
   if flags:
    builtin=self.u32()
    if builtin not in (1,2,3,4,21):raise ValueError('unsupported typed-array builtin '+str(builtin))
   n=self.u32()&0x7fffffff
   if n>10000000:raise ValueError('oversized array')
   return [self.value(depth+1) for _ in range(n)]
  raise ValueError('unsupported Godot variant type/flags %s at %s'%((kind,flags),self.i-4))
def decode(path):
 raw=Path(path).read_bytes();d=Decoder(raw);n=d.u32()
 if n!=len(raw)-4:raise ValueError('store_var byte length mismatch')
 value=d.value()
 if d.i!=len(raw):raise ValueError('trailing bytes')
 return value,d
if __name__=='__main__':
 value,d=decode(sys.argv[1]);out=Path(sys.argv[2])
 if out.exists():raise FileExistsError(out)
 out.write_text(json.dumps(value,ensure_ascii=False,indent=2))
 print(json.dumps({'input_sha256':hashlib.sha256(d.data).hexdigest(),'decoded_bytes':d.i,'types':sorted(d.types),'top_level_spans':d.spans,'output':str(out)}))
