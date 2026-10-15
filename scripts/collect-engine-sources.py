#!/usr/bin/env python3
"""Collect pinned source archives and Homebrew recipes alongside binary releases."""
import concurrent.futures, hashlib, pathlib, re, shutil, subprocess, urllib.request
P=pathlib.Path
root=P('dist/engine-sources');root.mkdir(parents=True,exist_ok=True)
recipes=list(P('dist/Dropform.app/Contents/Resources/Engines/Cellar').glob('*/*/.brew/*.rb'))
def collect(p):
    name=p.stem;dest=root/name;dest.mkdir(exist_ok=True);shutil.copy2(p,dest/p.name)
    s=p.read_text();url=re.search(r'^  url "([^"]+)"',s,re.M)[1]
    sha=re.search(r'^  sha256 "([^"]+)"',s,re.M)
    if url.endswith('.git'):
        rev=re.search(r'revision: "([^"]+)"',s)[1]
        checkout=dest/'git'
        if not checkout.exists():
            subprocess.run(['git','clone','--bare',url,str(checkout)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        subprocess.run(['git','-C',str(checkout),'archive','--format=tar.gz','-o',str((dest/'source.tar.gz').resolve()),rev],check=True)
    else:
        out=dest/url.split('/')[-1]
        if not out.exists():
            subprocess.run(['curl','-fL','--connect-timeout','15','--max-time','180','--retry','2',url,'-o',str(out)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        if sha and hashlib.sha256(out.read_bytes()).hexdigest()!=sha[1]: raise RuntimeError('Checksum '+name)
    # Include formula resources and upstream patches, pinned by the recipe's hashes.
    for i,(extra,digest) in enumerate(re.findall(r'url "([^"\n]+)"\s*\n\s*sha256 "([0-9a-f]{64})"',s.split('  test do')[0])):
        if extra == url: continue
        out=dest/(str(i)+'-'+extra.split('/')[-1])
        download=re.sub(r'https://github.com/([^/]+/[^/]+)/raw/', r'https://raw.githubusercontent.com/\1/', extra)
        if not out.exists(): subprocess.run(['curl','-fL','--connect-timeout','15','--max-time','180','--retry','2',download,'-o',str(out)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        if hashlib.sha256(out.read_bytes()).hexdigest()!=digest: raise RuntimeError('Resource checksum '+name)
    print(name,flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    for result in pool.map(collect,recipes): pass
