from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import os,subprocess,tempfile,re,json
root=Path(__file__).resolve().parent
(root/'checks').mkdir(exist_ok=True)
runtime=Path(os.environ['KOREADER_RUNTIME'])
jobs=[]
for w,h in [(600,800),(758,1024),(1072,1448),(1440,1920),(1920,1440)]:
 for suite in ['weather','themes','cover','interactions']:
  jobs.append((suite,'all',w,h))
 for suite in ['layout','statistics','migration']:
  for style in ['classic','pixel','swiss']:jobs.append((suite,style,w,h))
jobs.append(('network','all',1440,1920))
def run(job):
 suite,style,w,h=job
 env={**os.environ,'KO_HOME':tempfile.mkdtemp(prefix='ink-weather-'),'SDL_VIDEODRIVER':'dummy','EMULATE_READER_W':str(w),'EMULATE_READER_H':str(h),'INK_OUTPUT':str(root/'checks'),'INK_SOURCE':str(root/'2-inkfolio.lua'),'KOREADER_RUNTIME':str(runtime),'INK_LEGACY_MODE':'selection' if w<1000 else 'toggles'}
 if style!='all':env['INK_STYLE']=style
 p=subprocess.run(['./luajit',str((root/'tests')/f'test_{suite}.lua')],cwd=runtime,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90)
 log=p.stdout;(root/'checks'/f'{suite}-{style}-{w}x{h}.log').write_text(log)
 m=re.search(r'(?:LAYOUT|THEMES|STATISTICS|MIGRATION|WEATHER|COVER|NETWORK|INTERACTIONS)_PASS (\d+) / FAIL (\d+)',log)
 result=dict(suite=suite,style=style,resolution=f'{w}x{h}',passed=int(m[1]) if m else 0,failed=int(m[2]) if m else 1,exit=p.returncode)
 print(json.dumps(result),flush=True)
 if result['failed']:print('\n'.join(v for v in log.splitlines() if v.startswith('FAIL') or v.startswith('./luajit:'))[:4000],flush=True)
 return result
with ThreadPoolExecutor(max_workers=4)as pool:results=list(pool.map(run,jobs))
report=dict(source_sha256=__import__('hashlib').sha256((root/'2-inkfolio.lua').read_bytes()).hexdigest(),passed=sum(x['passed'] for x in results),failed=sum(x['failed'] for x in results),results=results)
(root/'checks/results.json').write_text(json.dumps(report,indent=2))
print('TOTAL',report['passed'],report['failed'])
if report['failed'] or any(x['exit'] for x in results):raise SystemExit(1)
