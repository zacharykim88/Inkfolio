from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib,json,os,re,subprocess,tempfile

root=Path(__file__).resolve().parent
runtime=Path(os.environ['KOREADER_COMPAT_RUNTIME']).resolve()
out=root/'checks-compat'
out.mkdir(exist_ok=True)
jobs=[(suite,'all')for suite in ['weather','themes','cover','interactions','localization','development','network']]
jobs+=[('localization','touch_en_US'),('migration','selection'),('migration','toggles')]

def run(job):
    suite,profile=job
    env={**os.environ,'KO_HOME':tempfile.mkdtemp(prefix='ink-compat-'),'SDL_VIDEODRIVER':'dummy',
         'EMULATE_READER_W':'1440','EMULATE_READER_H':'1920','INK_OUTPUT':str(out),
         'INK_SOURCE':str(root/'2-inkfolio.lua'),'KOREADER_RUNTIME':str(runtime),
         'INK_LEGACY_MODE':profile if suite=='migration'else 'selection'}
    if profile=='touch_en_US':env['INK_TOUCH_ONLY']='1';env['INK_START_LANGUAGE']='en_US'
    p=subprocess.run(['./luajit',str(root/'tests'/f'test_{suite}.lua')],cwd=runtime,env=env,
                     stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=180)
    (out/f'{suite}-{profile}.log').write_text(p.stdout)
    m=re.search(r'[A-Z]+_PASS (\d+) / FAIL (\d+)',p.stdout)
    result=dict(suite=suite,profile=profile,resolution='1440x1920',passed=int(m[1])if m else 0,
                failed=int(m[2])if m else 1,exit=p.returncode)
    print(json.dumps(result),flush=True)
    if result['failed']:print('\n'.join(x for x in p.stdout.splitlines()if x.startswith(('FAIL','./luajit:'))),flush=True)
    return result

with ThreadPoolExecutor(max_workers=3)as pool:results=list(pool.map(run,jobs))
report=dict(source_sha256=hashlib.sha256((root/'2-inkfolio.lua').read_bytes()).hexdigest(),
            passed=sum(x['passed']for x in results),failed=sum(x['failed']for x in results),results=results)
(out/'results.json').write_text(json.dumps(report,indent=2)+'\n')
print('TOTAL',report['passed'],report['failed'])
if report['failed']or any(x['exit']for x in results):raise SystemExit(1)
