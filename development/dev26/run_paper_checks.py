from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib,json,os,re,subprocess,tempfile

root=Path(__file__).resolve().parent
runtime=Path(os.environ['KOREADER_RUNTIME']).resolve()
compat=Path(os.environ['KOREADER_COMPAT_RUNTIME']).resolve()
out=root/'checks-paper'
out.mkdir(exist_ok=True)
jobs=[(runtime,suite,w,h,'all')for w,h in [(600,800),(758,1024),(1072,1448),(1440,1920),(1920,1440)]for suite in ['paper','development']]
jobs += [(runtime,'localization',1440,1920,p)for p in ['en_US','touch_en_US']]
jobs += [(compat,suite,1440,1920,'touch_en_US')for suite in ['paper','development','localization']]

def run(job):
    rt,suite,w,h,profile=job
    env={**os.environ,'KO_HOME':tempfile.mkdtemp(prefix='ink-paper-'),'SDL_VIDEODRIVER':'dummy','EMULATE_READER_W':str(w),'EMULATE_READER_H':str(h),'INK_OUTPUT':str(out),'KOREADER_RUNTIME':str(rt)}
    if profile=='touch_en_US':env['INK_TOUCH_ONLY']='1'
    if suite=='localization':env['INK_START_LANGUAGE']='en_US'
    p=subprocess.run(['./luajit',str(root/'tests'/f'test_{suite}.lua')],cwd=rt,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=180)
    (out/f'{rt.name}-{suite}-{profile}-{w}x{h}.log').write_text(p.stdout)
    m=re.search(r'(LOCALIZATION|PAPER|DEVELOPMENT)_PASS (\d+) / FAIL (\d+)',p.stdout)
    r=dict(runtime=rt.name,suite=suite,resolution=f'{w}x{h}',profile=profile,passed=int(m[2])if m else 0,failed=int(m[3])if m else 1,exit=p.returncode)
    print(json.dumps(r),flush=True)
    if r['failed']:print('\n'.join(x for x in p.stdout.splitlines()if x.startswith(('FAIL','./luajit:'))),flush=True)
    return r

with ThreadPoolExecutor(max_workers=3)as pool:results=list(pool.map(run,jobs))
r=dict(source_sha256=hashlib.sha256((root/'2-inkfolio.lua').read_bytes()).hexdigest(),passed=sum(x['passed']for x in results),failed=sum(x['failed']for x in results),results=results)
(root/'validation-results.json').write_text(json.dumps(r,indent=2)+'\n')
print('TOTAL',r['passed'],r['failed'])
if r['failed'] or any(x['exit']for x in results):raise SystemExit(1)
