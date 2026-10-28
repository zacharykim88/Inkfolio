require('setupkoenv');G_defaults=require('luadefaults'):open()
G_reader_settings=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
local settings=G_reader_settings;settings:saveSetting('read_receipt_v2_online',false)
local Device=require('device');require('document/canvascontext'):init(Device)
local UI=require('ui/uimanager');local Network=require('ui/network/manager')
local root=assert(arg[0]:match('^(.*)/tests/[^/]+$'))..'/'
local f=assert(io.open(root..'2-inkfolio.lua'));local source=f:read('*a');f:close()
local api=assert(loadstring(source..[[
return {ink=Inkfolio,S=S,net=NET,run=RUN,weather=WEATHER,store=store,cache=CACHE,key=bookKey,
 start=startPoll,daily=dailyCheck,current=currentCheck,library=newBooksCheck,abort=abortRound,
 begin=beginRound,awake=awake,sleep=doSleep,online=onlineEvent,send=sendHTTP,poll=pollWifi,
 setSend=function(fn)sendHTTP=fn end}
]]))()
local ink,S,R,N,W=api.ink,api.S,api.run,api.net,api.weather
local real_time,real_date=os.time,os.date;local now=real_time{year=2026,month=10,day=24,hour=10,min=0,sec=0}
os.time=function(t)if t then return real_time(t)end;return now end
os.date=function(fmt,t)return real_date(fmt,t or now)end
local jobs={}
UI.scheduleIn=function(_,delay,fn)jobs[fn]=now+delay end
UI.unschedule=function(_,fn)jobs[fn]=nil end
UI.nextTick=function(_,fn)jobs[fn]=now+.001 end
local connected=true;local wifi_calls=0
Network.queryNetworkState=function()end;Network.isConnected=function()return connected end
Network.enableWifi=function()wifi_calls=wifi_calls+1;return false end
local function advance(seconds)
 local target=now+seconds;local count=0
 while true do
  local fn,at
  for f,t in pairs(jobs)do if t<=target and(not at or t<at)then fn,at=f,t end end
  if not fn then break end
  now=at;jobs[fn]=nil;fn();count=count+1;assert(count<1000,'scheduler spun without a real deadline')
 end
 now=target
end
local passed,failed=0,0
local function check(name,fn)local ok,e=pcall(fn);if ok then passed=passed+1 else failed=failed+1;print('FAIL',name,e)end end
local function reset()
 jobs={};N.books={};N.pending={};R.auto_holds={};R.active=false;R.worker=nil;R.scanning=false;R.scan_pending=false
 R.sleeping=false;R.manual=false;R.cancelled_wake=false;R.transport_broken=false;R.network_failures=0;R.token=R.token+1
 settings:saveSetting(S.online,true);settings:saveSetting(S.weather,false);settings:saveSetting(S.weather_tomorrow,false);settings:saveSetting(S.intro,false)
 W.pending=false;W.error=nil;W.next_at=nil;W.attempt_day=nil;W.attempt_city=nil;W.records={};connected=true
 require('apps/reader/readerui').instance=nil
end
local function book(name)
 local path=os.getenv('KO_HOME')..'/'..name..'.epub';local f=assert(io.open(path,'w'));f:write('fixture');f:close()
 return {path=path,title=name,authors='测试作者',publisher='',isbn='',description=''}
end
local function failFetch(target,token,done)done(nil,'测试获取失败')end
local function successFetch(target,token,done)done({rating=8.2,url='https://book.douban.com/subject/1/',intro_state='absent'})end
check('idle network has no timer',function()reset();api.start();assert(next(jobs)==nil)end)
check('weather schedules its real six-hour deadline',function()
 reset();settings:saveSetting(S.weather,true)
 local day=os.date('%Y-%m-%d');W.records.lqYjK={day=day,text='晴 12～23°C',updated_at=now}
 api.start();assert(jobs[api.poll]==now+6*3600)
end)
check('crossing midnight schedules an earlier calendar refresh',function()
 reset();now=real_time{year=2026,month=10,day=24,hour=23,min=30,sec=0};settings:saveSetting(S.weather,true)
 W.records.lqYjK={day=os.date('%Y-%m-%d'),text='晴 12～23°C',updated_at=now};api.start();assert(jobs[api.poll]==ink.nextDay(now))
 now=real_time{year=2026,month=10,day=24,hour=10,min=0,sec=0}
end)
check('weather is eligible again after six hours',function()
 reset();settings:saveSetting(S.weather,true);W.records.lqYjK={day=os.date('%Y-%m-%d'),text='晴 12～23°C',updated_at=now-6*3600}
 assert(ink.weatherDeadline()==now)
end)
check('month cache schedules next month, not short polling',function()
 reset();settings:saveSetting(S.intro,true)
 local native=ink.visibleMonthly;ink.visibleMonthly=function()return {complete=true,update_date='2026-10-15'}end
 api.start();assert(jobs[api.poll]==real_time{year=2026,month=11,day=1,hour=0,min=0,sec=0});ink.visibleMonthly=native
end)
check('failed daily monthly request waits until next day',function()
 reset();settings:saveSetting(S.intro,true);local native=ink.visibleMonthly;ink.visibleMonthly=function()end
 ink.monthly.attempt_day=os.date('%Y-%m-%d');api.start();assert(jobs[api.poll]==ink.nextDay(now));ink.visibleMonthly=native
end)
check('opening a book does not scan the library',function()
 reset();local b=book('本书单独检查');local Reader=require('apps/reader/readerui');Reader.instance={document={file=b.path},doc_props={title=b.title,authors=b.authors}}
 local lfs=require('libs/libkoreader-lfs');local dir=lfs.dir;local scans=0;lfs.dir=function(...)scans=scans+1;return dir(...)end
 local fetch=ink.fetchVerifiedBook;local fetched=0;ink.fetchVerifiedBook=function(t,k,done)fetched=fetched+1;successFetch(t,k,done)end
 api.current();advance(2);lfs.dir=dir;ink.fetchVerifiedBook=fetch
 assert(scans==0 and fetched==1)
end)
check('automatic attempts are counted per book, not per library batch',function()
 reset();local a,b=book('失败甲'),book('失败乙');ink.queueBook(a);ink.queueBook(b)
 local fetch=ink.fetchVerifiedBook;ink.fetchVerifiedBook=failFetch
 api.daily();advance(3);ink.fetchVerifiedBook=fetch
 assert(N.books[api.key(a)].attempts==1 and N.books[api.key(b)].attempts==1)
 assert(N.books[api.key(a)].next_at>now+1790 and N.books[api.key(b)].next_at>now+1790)
end)
check('retry stops at three per book per local day and resumes next day',function()
 reset();local b=book('每日三次');ink.queueBook(b);local fetch=ink.fetchVerifiedBook;local calls=0
 ink.fetchVerifiedBook=function(t,k,done)calls=calls+1;failFetch(t,k,done)end
 api.daily();advance(2);assert(calls==1)
 advance(1790);assert(calls==1)
 advance(12);assert(calls==2)
 advance(1802);assert(calls==3)
 advance(3600);assert(calls==3)
 local next_day=ink.nextDay(now);advance(next_day-now+2);assert(calls==4 and N.books[api.key(b)].attempts==1)
 ink.fetchVerifiedBook=fetch
 now=real_time{year=2026,month=10,day=24,hour=10,min=0,sec=0}
end)
check('completed cache is never automatically refreshed',function()
 reset();local b=book('已完整');api.cache[api.key(b)]={rating=8,url='https://book.douban.com/subject/2/',intro_state='absent'}
 assert(not ink.queueBook(b));api.daily();api.start();assert(next(jobs)==nil)
end)
check('manual refresh bypasses retry budget without increasing it',function()
 reset();local b=book('手动重试');N.books[api.key(b)]={day=os.date('%Y-%m-%d'),attempts=3,next_at=ink.nextDay(now)}
 local fetch=ink.fetchVerifiedBook;local calls=0;ink.fetchVerifiedBook=function(t,k,done)calls=calls+1;successFetch(t,k,done)end
 assert(api.begin(true,b,nil,true));advance(2);ink.fetchVerifiedBook=fetch
 assert(calls==1 and N.books[api.key(b)].attempts==3)
end)
check('retry schedule persists across restart',function()
 reset();local b=book('保存重试时间');ink.queueBook(b);ink.bookAttempt(b,false)
 local saved=require('luasettings'):open(api.store.file):readSetting('network_schedule')
 assert(saved.pending[api.key(b)].title==b.title and saved.books[api.key(b)].attempts==1 and saved.books[api.key(b)].next_at==now+1800)
end)
check('cancelled books do not hold weather or monthly work',function()
 reset();R.active=true;api.abort(true)
 assert(ink.networkHeld('books')and not ink.networkHeld('weather')and not ink.networkHeld('monthly'))
 settings:saveSetting(S.weather,true);W.pending=true;assert(ink.weatherDeadline()==now)
end)
check('cancelled weather does not hold books or monthly work',function()
 reset();R.worker={kind='weather',city='lqYjK'};api.abort(true)
 assert(ink.networkHeld('weather')and not ink.networkHeld('books')and not ink.networkHeld('monthly'))
 local b=book('天气取消后继续');ink.queueBook(b);assert(#ink.dueBooks()==1)
end)
check('wake clears scoped cancellation without turning Wi-Fi on',function()
 reset();connected=false;R.auto_holds={books=true,weather=true,monthly=true};api.awake()
 assert(not ink.networkHeld('books')and not ink.networkHeld('weather')and not ink.networkHeld('monthly')and wifi_calls==0)
end)
check('sleep removes due timers and does not start work',function()
 reset();settings:saveSetting(S.weather,true);W.records.lqYjK={day=os.date('%Y-%m-%d'),text='晴 12～23°C',updated_at=now};api.start();assert(jobs[api.poll])
 api.sleep();assert(not jobs[api.poll]);advance(6*3600+1);assert(not R.worker);now=real_time{year=2026,month=10,day=24,hour=10,min=0,sec=0}
end)
check('offline due tasks wait for a network event without polling',function()
 reset();connected=false;local b=book('离线等待');ink.queueBook(b);api.start();assert(next(jobs)==nil)
 local fetch=ink.fetchVerifiedBook;local calls=0;ink.fetchVerifiedBook=function(t,k,done)calls=calls+1;successFetch(t,k,done)end
 connected=true;api.online();advance(2);assert(calls==1 and wifi_calls==0);ink.fetchVerifiedBook=fetch
end)
check('three real HTTP failures pause all automatic modules until reconnect',function()
 reset();local ffi=require('ffi/util');local spawn,done,terminate=ffi.runInSubProcess,ffi.isSubProcessDone,ffi.terminateSubProcess
 local https=require('ssl.https');local request=https.request
 ffi.runInSubProcess=function(fn)fn();return 12345 end;ffi.isSubProcessDone=function()return true end;ffi.terminateSubProcess=function()end
 https.request=function()return nil,'test unavailable' end
 for _,kind in ipairs({'weather','monthly','books'})do
  assert(api.send('https://example.invalid/test',R.token,function()end,kind));advance(.3)
 end
 https.request=request;ffi.runInSubProcess=spawn;ffi.isSubProcessDone=done;ffi.terminateSubProcess=terminate
 assert(R.network_failures==3 and R.transport_broken);api.start();assert(not jobs[api.poll])
 api.online();assert(not R.transport_broken and R.network_failures==0)
end)
check('library refresh events coalesce before scanning',function()
 reset();connected=false
 ink.libraryChanged();ink.libraryChanged();local count=0;for _ in pairs(jobs)do count=count+1 end;assert(count==1)
end)
check('a scan queued during another task runs after that task finishes even offline',function()
 reset();connected=false;settings:saveSetting(S.library_root,os.getenv('KO_HOME')..'/not-present')
 R.scan_pending=true;api.start();assert(jobs[api.poll]and jobs[api.poll]<now+1)
 advance(1);assert(not R.scan_pending and not R.scanning and not jobs[api.poll])
end)
check('a manual failure waits thirty minutes without spending automatic attempts',function()
 reset();local b=book('手动失败冷却');local fetch=ink.fetchVerifiedBook;ink.fetchVerifiedBook=failFetch
 assert(api.begin(true,b,nil,true));advance(2);ink.fetchVerifiedBook=fetch
 local entry=N.books[api.key(b)];assert(entry and entry.attempts==0 and entry.next_at>now+1790)
end)
check('fresh local metadata removes an outdated pending entry',function()
 reset();local b=book('简介已补齐');api.cache[api.key(b)]={rating=8,url='https://book.douban.com/subject/3/',intro_state='failed'}
 ink.queueBook(b);assert(N.pending[api.key(b)]);b.description='书籍文件中已有简介'
 assert(not ink.queueBook(b)and not N.pending[api.key(b)])
end)
for _,style in ipairs({'classic','pixel','swiss','cover'})do
 check(style..' uses identical network deadlines',function()
  reset();settings:saveSetting(S.ui_style,style);settings:saveSetting(S.weather,true)
  W.records.lqYjK={day=os.date('%Y-%m-%d'),text='晴 12～23°C',updated_at=now}
  assert(ink.weatherDeadline()==now+21600)
  local b=book('同规则'..style);ink.bookAttempt(b,false);assert(ink.bookDeadline(b)==now+1800)
 end)
end
print('NETWORK_PASS '..passed..' / FAIL '..failed);os.exit(failed==0 and 0 or 1)
