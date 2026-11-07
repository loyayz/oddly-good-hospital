"""Read the pinned Godot 4.7.2 standalone, unencrypted PCK v4 format.

Format reference: Godot 4.7.2 core/io/{file_access_pack,pck_packer}.cpp.
This reader never extracts or executes packed content. Unknown flags fail closed.
"""
import hashlib
from pathlib import Path, PurePosixPath
import struct


def resource_path(raw):
    text=raw.rstrip(b'\0').decode('utf-8',errors='strict')
    if text.startswith('res://'):text=text[6:]
    if not text or '\\' in text or ':' in text or any(ord(c)<32 for c in text):
        raise ValueError('Invalid PCK resource path')
    if text.startswith('/') or any(part in ('','.','..') for part in text.split('/')):
        raise ValueError('Noncanonical PCK resource path: '+text)
    return text


def forbidden_resource(path):
    """Allow only this project's explicitly identified runtime resource classes."""
    exact={'project.binary','.godot/global_script_class_cache.cfg','.godot/extension_list.cfg','.godot/uid_cache.bin',
           'docs/data/content-catalog.json','docs/data/balance.json','docs/data/clinical-layouts.json','docs/data/starter-layout.json',
           'assets/fonts/OFL.txt','assets/models/stage01-production.json','assets/gags/stage01-gags.json',
           'assets/models/import_vertex_colours.gdc','assets/models/import_vertex_colours.gd.remap',
           'game/content/schema100.json','game/platform/windows/oddly_good_platform.gdextension'}
    if path in exact:return False
    if path.startswith('content/core/'):
        return PurePosixPath(path).suffix not in {'.json','.csv','.translation'}
    if path.startswith('game/') and not path.startswith('game/platform/'):
        return not path.endswith(('.gdc','.gd.remap','.gdshader','.gdshaderinc','.tscn.remap','.tres.remap','.scn','.res'))
    if path.startswith(('assets/models/','assets/gags/','assets/fonts/')):
        return not path.endswith(('.glb','.glb.import','.otf.import','.ttf.import'))
    if path.startswith('.godot/imported/'):
        return PurePosixPath(path).suffix not in {'.scn','.fontdata','.ctex','.translation','.res'}
    if path.startswith('.godot/exported/'):
        return PurePosixPath(path).suffix not in {'.scn','.res'}
    return True


def read_pck(path):
    path=Path(path);total=path.stat().st_size
    with path.open('rb') as f:
        def read(n):
            result=f.read(n)
            if len(result)!=n:raise ValueError('Truncated PCK')
            return result
        def unpack(fmt):return struct.unpack(fmt,read(struct.calcsize(fmt)))
        magic,version,major,minor,patch,flags,base,directory=unpack('<6I2Q')
        if (magic,version,major,minor,patch)!=(0x43504447,4,4,7,2):
            raise ValueError('Requires Godot 4.7.2 standalone PCK v4')
        if flags!=2:raise ValueError('Encrypted, sparse or unknown PCK flags are unsupported')
        if base<104 or directory<base or directory>total-4:raise ValueError('Invalid PCK directory/data bounds')
        f.seek(directory);count=unpack('<I')[0]
        if count>100000 or count>(total-directory-4)//40:raise ValueError('Invalid PCK file count')
        entries=[];seen=set();ranges=[]
        for _ in range(count):
            length=unpack('<I')[0]
            if not 0<length<=65536 or length%4:raise ValueError('Invalid PCK path length')
            name=resource_path(read(length))
            if name in seen:raise ValueError('Duplicate PCK resource: '+name)
            seen.add(name)
            offset,size=unpack('<2Q');md5=read(16).hex();file_flags=unpack('<I')[0]
            if file_flags:raise ValueError('Encrypted, removed, delta or unknown PCK file flags')
            absolute=base+offset
            if absolute<base or absolute>directory or size>directory-absolute:raise ValueError('PCK content outside data section: '+name)
            if size:ranges.append((absolute,absolute+size,name))
            entries.append({'path':name,'offset':absolute,'bytes':size,'md5':md5})
        if f.tell()!=total:raise ValueError('Unexpected bytes after PCK directory')
        ranges.sort()
        for left,right in zip(ranges,ranges[1:]):
            if left[1]>right[0]:raise ValueError('Overlapping PCK contents')
        for item in entries:
            f.seek(item['offset']);remaining=item['bytes'];md5=hashlib.md5(usedforsecurity=False);sha=hashlib.sha256()
            while remaining:
                data=read(min(1048576,remaining));remaining-=len(data);md5.update(data);sha.update(data)
            if md5.hexdigest()!=item['md5']:raise ValueError('PCK content checksum mismatch: '+item['path'])
            item['sha256']=sha.hexdigest()
    return {'format':4,'engine_version':'4.7.2','bytes':total,'resource_count':count,'files':entries,'forbidden_resources':[item['path'] for item in entries if forbidden_resource(item['path'])]}
