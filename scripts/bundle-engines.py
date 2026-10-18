#!/usr/bin/env python3
"""Bundle installed Homebrew runtimes, relocate Mach-O loads, retain notices."""
import json, os, pathlib, shutil, subprocess, re
P=pathlib.Path
root=P('dist/Dropform.app/Contents/Resources/Engines').resolve()
roots=['librsvg','ffmpeg','imagemagick','ghostscript','pandoc','python@3.14']
def run(*a): return subprocess.check_output(a,text=True).strip()
names=sorted(set(roots+run('brew','deps','--union',*roots).splitlines()))
root.mkdir(parents=True,exist_ok=True)
manifest=[]
for name in names:
    src=P('/opt/homebrew/opt')/name
    src=src.resolve(); dst=root/'Cellar'/name/src.name
    if not dst.exists():
        dst.parent.mkdir(parents=True,exist_ok=True)
        shutil.copytree(src,dst,symlinks=True)
    opt=root/'opt'/name; opt.parent.mkdir(exist_ok=True)
    if opt.is_symlink() and opt.resolve() != dst: opt.unlink()
    if not opt.is_symlink(): opt.symlink_to(os.path.relpath(dst,opt.parent))
    manifest.append({'name':name,'version':src.name})
lo=P('/Applications/LibreOffice.app')
if not (root/'LibreOffice.app').exists(): shutil.copytree(lo,root/'LibreOffice.app',symlinks=True)
# Rewrite external symlinks and all non-system Mach-O load commands.
for p in root.rglob('*.la'):
    if not p.is_symlink(): p.write_text(re.sub(r'^libdir=.*$', "libdir=''", p.read_text(), flags=re.M))
files=[]
for p in root.rglob('*'):
    if p.is_symlink():
        target=os.readlink(p)
        if target.startswith('/opt/homebrew/'):
            dest=root/target.removeprefix('/opt/homebrew/')
            p.unlink(); p.symlink_to(os.path.relpath(dest,p.parent))
        continue
    if not p.is_file() or p.suffix == '.class': continue
    with p.open('rb') as f: magic=f.read(4)
    if magic not in [b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xfe\xed\xfa\xcf']: continue
    files.append(p)
    try: deps=run('otool','-L',str(p)).splitlines()[1:]
    except subprocess.CalledProcessError: continue
    edits=[]
    for line in deps:
        dep=line.strip().split(' (')[0]
        if dep.startswith('/opt/homebrew/'):
            dest=root/dep.removeprefix('/opt/homebrew/')
            if not dest.exists():
                dest=root/P(dep).resolve().relative_to('/opt/homebrew')
            if not dest.exists(): raise RuntimeError(f'Missing {dep} for {p}')
            edits+=['-change',dep,'@loader_path/'+os.path.relpath(dest,p.parent)]
    if edits:
        p.chmod(p.stat().st_mode|0o200)
        subprocess.run(['install_name_tool',*edits,str(p)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    subprocess.run(['codesign','--force','--sign','-',str(p)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Sign nested bundles after their executable contents.
for p in sorted(root.rglob('*.app'),key=lambda p:len(p.parts),reverse=True):
    subprocess.run(['codesign','--force','--deep','--sign','-',str(p)],check=True)
print(f'Bundled {len(names)} packages and {len(files)} Mach-O files')
