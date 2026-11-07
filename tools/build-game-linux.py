#!/usr/bin/env python3
"""Offline Linux release export with fail-closed dependency/license manifests."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

spec=importlib.util.spec_from_file_location('linux_build',Path(__file__).parent/'linux/build.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
pck_spec=importlib.util.spec_from_file_location('linux_pck',Path(__file__).parent/'linux/pck.py')
pck=importlib.util.module_from_spec(pck_spec);pck_spec.loader.exec_module(pck)
COMPONENTS={'project','godot','sqlite','rapidjson','boost','scip','soplex','minizip-ng','zlib','gmp','mpfr','compiler-runtime','glibc'}


def select_template(preset, template, root):
    blocks=re.split(r'(?=\[preset\.\d+\]\n)',preset)
    selected=[v for v in blocks if 'name="Linux x86_64 Release"' in v]
    if len(selected)!=1 or 'platform="Linux"' not in selected[0]:
        raise ValueError('Linux x86_64 Release export preset missing or ambiguous')
    custom=re.search(r'custom_template/release="([^"]*)"',selected[0])
    if custom and custom.group(1):
        path=Path(custom.group(1))
        if not path.is_absolute(): path=root/path
        if path.resolve()!=template.resolve(): raise ValueError('Preset overrides verified release template')
    return template


def source_identity(root):
    records={}
    for directory,dirs,files in os.walk(root):
        dirs[:]=sorted(d for d in dirs if d not in {'.git','.godot','.cache','.build','__pycache__'})
        for name in sorted(files):
            path=Path(directory)/name
            if path.suffix=='.pyc': continue
            if path.is_symlink(): raise ValueError('Source symlink needs explicit review: '+str(path))
            rel=path.relative_to(root).as_posix()
            item=b.record(path)
            if path.suffix=='.import':
                # Keep intentional importer settings, not generated remap/cache paths.
                text=path.read_text()
                match=re.search(r'^\[params\]\s*\n(.*?)(?=^\[|\Z)',text,re.M|re.S)
                params=match.group(1).strip() if match else ''
                remap=re.search(r'^\[remap\]\s*\n(.*?)(?=^\[|\Z)',text,re.M|re.S)
                settings=[line.strip() for line in (remap.group(1) if remap else '').splitlines() if re.match(r'(importer|type|uid)=',line.strip())]
                item['import_params']='\n'.join(settings)+'\n'+params
            records[rel]=item
    return records


def verify_sources(before,after,allow_import=False):
    changed=[];generated=[]
    for name in sorted(set(before)|set(after)):
        old=before.get(name);new=after.get(name)
        if old and new and old['sha256']==new['sha256']: continue
        permitted=False
        if allow_import and new:
            path=Path(name)
            base=name.rsplit('.',1)[0]
            if path.suffix=='.import' and base in before and base in after and before[base]['sha256']==after[base]['sha256']:
                permitted=not old or old.get('import_params')==new.get('import_params')
            elif not old and path.suffix=='.uid' and base in before and Path(base).suffix in {'.gd','.gdshader','.gdextension','.cs'}:
                permitted=base in after and before[base]['sha256']==after[base]['sha256']
            elif path.suffix=='.translation' and path.parent.as_posix()=='content/core/locale':
                # Godot CSV importer emits <csv stem>.<locale>.translation.
                csv=path.with_name(path.stem.rsplit('.',1)[0]+'.csv').as_posix()
                permitted=csv in before and csv in after and before[csv]['sha256']==after[csv]['sha256']
        (generated if permitted else changed).append(name)
    if changed: raise ValueError('Source changed during build: '+', '.join(changed[:20]))
    return generated


def run_stage(name,command,output,env,plan):
    log=output/(name+'.log')
    with log.open('w') as stream:
        result=subprocess.run(command,env=env,stdout=stream,stderr=subprocess.STDOUT,text=True)
    text=log.read_text(errors='replace')
    errors=[line for line in text.splitlines() if re.search(r'(^|\s)(ERROR:|SCRIPT ERROR:|Parse Error:)',line)]
    status={'name':name,'command':command,'exit_code':result.returncode,'errors':errors,'log':b.record(log),'passed':result.returncode==0 and not errors}
    plan.setdefault('stages',[]).append(status)
    b.write_json(output/'package-manifest.json',plan)
    if not status['passed']: raise ValueError(name+' failed; see '+str(log))


def build_commands(godot,root,output):
    return [
        ('content-check',[sys.executable,str(root/'tools/compile-content.py'),'--check']),
        ('import',[str(godot),'--headless','--path',str(root),'--editor','--import','--quit']),
        ('export',[str(godot),'--headless','--path',str(root),'--export-release','Linux x86_64 Release',str(output.resolve()/'OddlyGoodHospital.x86_64')])]

def validate_distribution_component(name,component):
    if name in ('gmp','mpfr','compiler-runtime','glibc'):
        if component.get('distribution') not in ('bundled','system'): raise ValueError('Explicit component distribution mode required: '+name)
        runtime_exception=(name=='compiler-runtime' and component.get('source_obligation')=='runtime-library-exception' and component.get('license_basis'))
        if component['distribution']=='bundled' and not component.get('sources') and not runtime_exception:
            raise ValueError('Bundled component corresponding source/build materials required: '+name)
        if component['distribution']=='system' and not component.get('requirement'):
            raise ValueError('System component runtime requirement missing: '+name)



def state_paths(requested,source,output,data_home):
    state=(requested if requested is not None else output.with_name(output.name+'.state')).resolve()
    for label,boundary in [('source',source),('output',output),('template data-home',data_home)]:
        boundary=boundary.resolve()
        if state==boundary or state.is_relative_to(boundary) or boundary.is_relative_to(state):
            raise ValueError('Build state must not overlap '+label+': '+str(state))
    if state.exists(): raise ValueError('Build state directory must be new: '+str(state))
    return {'root':str(state),'HOME':str(state/'home'),'XDG_CONFIG_HOME':str(state/'config'),'XDG_CACHE_HOME':str(state/'cache'),'XDG_DATA_HOME':str(data_home.resolve())}


def audit_public_paths(files,forbidden_roots,exempt=()):
    """Reject our local build paths in selected public payload bytes, streaming."""
    patterns=[str(root).encode() for root in forbidden_roots if str(root)]
    if not patterns:return
    overlap=max(map(len,patterns))-1
    exempt={Path(x).resolve() for x in exempt}
    for path in files:
        path=Path(path)
        if path.resolve() in exempt:continue
        tail=b''
        with path.open('rb') as stream:
            for chunk in iter(lambda:stream.read(1048576),b''):
                data=tail+chunk
                if any(pattern in data for pattern in patterns):raise ValueError('Local build path leaked into public payload: '+str(path))
                tail=data[-overlap:] if overlap else b''

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot',type=Path,required=True)
    p.add_argument('--native-manifest',type=Path,required=True)
    p.add_argument('--distribution-inputs',type=Path,required=True,help='Explicit licenses, source artifacts and ELF runtime resolutions; see tools/linux/README.md')
    p.add_argument('--data-home',type=Path,required=True,help='XDG_DATA_HOME with godot/export_templates/4.7.2.stable')
    p.add_argument('--state-dir',type=Path,help='New isolated writable state directory outside source/output/template data-home; defaults to output-name.state beside output')
    p.add_argument('--template-sha256',required=True,help='Independently verified Linux release template hash')
    p.add_argument('--output',type=Path,required=True,help='New empty release directory')
    p.add_argument('--dry-run',action='store_true')
    a=p.parse_args()
    plan=None
    try:
        if b.digest(a.godot)!=b.ENGINE_SHA or b.run([a.godot,'--version'])!=b.ENGINE_VERSION:
            raise ValueError('Pinned Godot 4.7.2 engine required')
        native=json.loads(a.native_manifest.read_text())
        if native['status']!='built': raise ValueError('Successful native build manifest required')
        native_path=b.checked(native['artifact'])
        for item in native['sources']: b.checked(item)
        template=a.data_home/'godot/export_templates/4.7.2.stable/linux_release.x86_64'
        if b.digest(template)!=a.template_sha256: raise ValueError('Release template hash mismatch')
        cfg=json.loads(a.distribution_inputs.read_text())
        if set(cfg['components'])!=COMPONENTS: raise ValueError('Distribution components must be exactly: '+', '.join(sorted(COMPONENTS)))
        # Source obligations depend on actual distribution, not mere system linkage.
        for name,component in cfg['components'].items():
            if not component.get('licenses'): raise ValueError('License/notice files missing: '+name)
            for item in component['licenses']: b.checked(item)
            for item in component.get('sources',[]): b.checked(item)
            validate_distribution_component(name,component)
        resolutions=cfg['elf_dependencies']
        for needed in native['needed']:
            if needed not in resolutions: raise ValueError('Unresolved ELF dependency: '+needed)
        for soname,item in resolutions.items():
            if not re.fullmatch(r'[A-Za-z0-9_.+-]+',soname): raise ValueError('Invalid SONAME')
            path=b.checked(item)
            component=cfg['components'].get(item.get('component'))
            if component is None: raise ValueError('ELF dependency component mapping missing: '+soname)
            if item['mode']=='bundle' and component.get('distribution')=='system': raise ValueError('Bundled ELF conflicts with system-only component: '+soname)
            if item['mode'] not in ('bundle','system'): raise ValueError('Runtime mode must be bundle/system')
            if item['mode']=='system' and not item.get('requirement'): raise ValueError('System dependency requires documented runtime requirement')
            elf=b.run(['readelf','-d',path])
            names=re.findall(r'\(SONAME\).*\[(.*?)\]',elf)
            if names and names!=[soname]: raise ValueError('Runtime SONAME mismatch: '+soname)
            for transitive in re.findall(r'\(NEEDED\).*\[(.*?)\]',elf):
                if transitive not in resolutions: raise ValueError('Unresolved transitive ELF dependency: '+transitive)
        select_template((b.ROOT/'export_presets.cfg').read_text(),template,b.ROOT)
        if a.output.exists(): raise ValueError('Output must not exist; avoid stale release files')
        if a.output.resolve().is_relative_to(b.ROOT.resolve()): raise ValueError('Release output must be outside source tree')
        state=state_paths(a.state_dir,b.ROOT,a.output,a.data_home)
        commands=build_commands(a.godot,b.ROOT,a.output)
        initial_sources=source_identity(b.ROOT)
        plan={'status':'planned','commands':commands,'build_environment':state,'source_before':initial_sources,'engine':b.record(a.godot),'template':b.record(template),'native_manifest':b.record(a.native_manifest),'distribution_inputs':cfg,'limitations':['Linux export and ELF inspection do not substitute for target-host gameplay/rendering acceptance.']}
        if a.dry_run:
            print(json.dumps(plan,indent=2));return
        a.output.mkdir(parents=True)
        write=b.write_json
        write(a.output/'package-manifest.json',plan)
        env=os.environ.copy()
        Path(state['root']).mkdir(parents=True,exist_ok=False)
        for key in ('HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME'):
            Path(state[key]).mkdir()
            env[key]=state[key]
        env['XDG_DATA_HOME']=state['XDG_DATA_HOME']
        run_stage(*commands[0],a.output,env,plan)
        verify_sources(initial_sources,source_identity(b.ROOT))
        run_stage(*commands[1],a.output,env,plan)
        imported_sources=source_identity(b.ROOT)
        plan['generated_import_changes']=verify_sources(initial_sources,imported_sources,allow_import=True)
        plan['source_after_import']=imported_sources
        write(a.output/'package-manifest.json',plan)
        run_stage(*commands[2],a.output,env,plan)
        plan['source_after_export']=source_identity(b.ROOT)
        verify_sources(imported_sources,plan['source_after_export'])
        pack_files=list(a.output.glob('*.pck'))
        if len(pack_files)!=1:raise ValueError('Expected exactly one standalone PCK')
        pack_inventory=pck.read_pck(pack_files[0])
        write(a.output/'pck-resources.json',pack_inventory)
        plan['pck_inventory']=b.record(a.output/'pck-resources.json')
        if pack_inventory['forbidden_resources']:raise ValueError('Forbidden release resources: '+', '.join(pack_inventory['forbidden_resources'][:20]))
        exported=list(a.output.rglob(native_path.name))
        if len(exported)!=1 or b.digest(exported[0])!=native['artifact']['sha256']:
            raise ValueError('Exported native extension absent, duplicated or stale')
        for soname,item in resolutions.items():
            if item['mode']=='bundle':
                destination=exported[0].parent/soname
                shutil.copyfile(b.checked(item),destination)
                if b.digest(destination)!=item['sha256']:raise ValueError('Bundled runtime changed during copy: '+soname)
        for name,component in cfg['components'].items():
            for kind in ('licenses','sources'):
                for index,item in enumerate(component.get(kind,[])):
                    dest=a.output/kind/name/(str(index)+'-'+Path(item['path']).name)
                    dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(b.checked(item),dest)
                    if b.digest(dest)!=item['sha256']:raise ValueError('Distribution input changed during copy: '+str(dest))
        # Inspect all ELF files, including the actual exported Godot template.
        elf_files=[]
        for path in sorted(a.output.rglob('*')):
            if not path.is_file(): continue
            with path.open('rb') as f: magic=f.read(4)
            if magic==b'\x7fELF':
                dynamic=b.run(['readelf','-d',path]); needed=re.findall(r'\(NEEDED\).*\[(.*?)\]',dynamic)
                missing=set(needed)-set(resolutions)
                if missing: raise ValueError('Exported ELF has unresolved dependencies: '+', '.join(sorted(missing)))
                elf_files.append({'path':str(path.relative_to(a.output)),'dynamic':dynamic,'needed':needed,'version_requirements':b.run(['readelf','--version-info',path])})
        requirements=a.output/'RUNTIME-REQUIREMENTS.txt'
        requirements.write_text('Oddly Good Hospital: Linux release candidate\n\nThis candidate has only been headless-validated on a Debian 13 host. Graphical display, audio/input and successful save/restore are not accepted yet. Non-initial or incomplete cgroup views cause the production save memory check to refuse saving; do not assume this cloud container supports normal saves.\n\n'+json.dumps(cfg.get('runtime_requirements',{}),indent=2,ensure_ascii=False)+'\n')
        public=[a.output/'OddlyGoodHospital.x86_64',pack_files[0],exported[0],requirements]
        public += [x for x in sorted((a.output/'licenses').rglob('*')) if x.is_file()]
        public += [exported[0].parent/name for name,item in resolutions.items() if item['mode']=='bundle']
        # Corresponding-source artifacts accompany any bundled LGPL components.
        public += [x for x in sorted((a.output/'sources').rglob('*')) if x.is_file()] if (a.output/'sources').exists() else []
        if b.digest(a.output/'OddlyGoodHospital.x86_64')!=a.template_sha256:
            raise ValueError('Exported executable differs from verified official standalone template')
        local_roots=[b.ROOT.resolve(),a.output.resolve(),a.data_home.resolve(),state['root'],a.native_manifest.resolve().parent,Path(native['cache_manifest']['path']).parent,native['dependency_provenance']['cache'],'/workspace/']
        audit_public_paths(public,local_roots,exempt=[a.output/'OddlyGoodHospital.x86_64'])
        plan['public_path_audit']={'passed':True,'scope':'All selected public payload bytes except the exact verified official engine template','forbidden_roots':[str(x) for x in local_roots]}
        public_records=[]
        for file in sorted(set(public)):
            item=b.record(file);public_records.append({'path':file.relative_to(a.output).as_posix(),'sha256':item['sha256'],'bytes':item['bytes']})
        write(a.output/'public-release-files.json',{'schema':1,'files':public_records,'note':'Only these payload files belong in the player candidate archive. Exclude build logs, package-manifest, PCK inventory and other internal evidence.'})
        verify_sources(imported_sources,source_identity(b.ROOT))
        plan.update(status='exported',elf=elf_files,artifacts=[b.record(x)|{'relative_path':str(x.relative_to(a.output))} for x in sorted(a.output.rglob('*')) if x.is_file() and x.name!='package-manifest.json'])
        write(a.output/'package-manifest.json',plan)
        print('Release exported and inventoried:',a.output)
    except (OSError,ValueError,KeyError,subprocess.CalledProcessError) as e:
        if plan is not None and not a.dry_run and a.output.is_dir():
            plan.update(status='failed',failure=str(e))
            try: plan['source_at_failure']=source_identity(b.ROOT)
            except (OSError,ValueError) as snapshot_error: plan['source_snapshot_error']=str(snapshot_error)
            b.write_json(a.output/'package-manifest.json',plan)
        p.exit(1,'Linux export failed: '+str(e)+'\n')

if __name__=='__main__': main()
