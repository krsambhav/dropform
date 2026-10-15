#!/usr/bin/env python3
import pathlib,subprocess,re,concurrent.futures
root=pathlib.Path('dist/Dropform.app').resolve()
files=[]
for p in root.rglob('*'):
 if p.is_symlink():
  try: p.resolve().relative_to(root)
  except ValueError: raise SystemExit('Escaping symlink: '+str(p))
for p in root.rglob('*'):
 if p.is_symlink() or not p.is_file() or p.suffix=='.class': continue
 with p.open('rb') as f: magic=f.read(4)
 if magic in [b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xfe\xed\xfa\xcf']: files.append(p)
def check(p):
 out=subprocess.check_output(['otool','-l',str(p)],text=True)
 blocks=out.split('Load command ')
 deps=[]
 for block in blocks:
  if re.search(r'cmd LC_(?:LOAD|LOAD_WEAK|REEXPORT)_DYLIB\b',block):
   m=re.search(r'\n\s+name (.*?) \(offset',block)
   if m: deps.append(m[1])
 bad=[d for d in deps if d.startswith(('/opt/','/usr/local/','/Users/'))]
 bad += [d for d in deps if d.startswith('@loader_path/') and not (p.parent/d.removeprefix('@loader_path/')).exists()]
 minos=re.findall(r'minos (\d+\.\d+(?:\.\d+)?)',out)
 return str(p.relative_to(root)),bad,minos
results=list(concurrent.futures.ThreadPoolExecutor(max_workers=8).map(check,files))
bad=[r for r in results if r[1]]
print('Mach-O files:',len(files),'external loads:',len(bad))
for r in bad:print(r)
versions=[(tuple(map(int,v.split('.'))),p) for p,b,vs in results for v in vs]
print('Maximum deployment target:',max(versions))
if bad:raise SystemExit(1)
