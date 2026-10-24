require('setupkoenv');G_defaults=require('luadefaults'):open()
G_reader_settings=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
local settings=G_reader_settings
settings:saveSetting('read_receipt_v2_online',false)
local Device=require('device');require('document/canvascontext'):init(Device)
local Screen=Device.screen;local BB=require('ffi/blitbuffer');local UI=require('ui/uimanager')
local test_dir=assert(arg[0]:match('^(.*)/[^/]+$'))
local project=test_dir..'/..'
local output=os.getenv('INK_OUTPUT') or os.getenv('KO_HOME')
local source=assert(io.open(project..'/2-inkfolio.lua')):read('*a')
local api=assert(loadstring(source..[[
return {ink=Inkfolio,S=S,weather=WEATHER,run=RUN,menu=receiptSettingsMenu,build=buildReceipt,render=renderReceipt,
 parse=parseWeather,weatherText=weatherText,city=selectedWeatherCity,pending=weatherPending,check=weatherCheck,
 stop=stopHTTP,abort=abortRound,next=nextItem,begin=beginRound,progress=PROGRESS,status=STATUS,
 rounds=function()return ROUNDS end,send=sendHTTP,
 mockSend=function(f)sendHTTP=f end,store=store}
]]))()
local ink,S,W,R=api.ink,api.S,api.weather,api.run
local passed,failed=0,0
local function check(name,f)local ok,e=pcall(f);if ok then passed=passed+1 else failed=failed+1;print('FAIL',name,e)end end
local json=require('rapidjson');local today=os.date('%Y-%m-%d')
local live=assert(io.open(test_dir..'/fixtures/nmc-suzhou.json')):read('*a')
local function responseFor(day)
 local obj=json.decode(live)
 for i,item in ipairs(obj.data.predict.detail)do item.date=ink.weatherDate(i-2,day)end
 return obj
end
check('live NMC response parses forecast',function()local t,e=api.parse(live,'lqYjK','2026-10-24');assert(t and t:find('°C',1,true),e)end)
for _,bad in ipairs({'not json','{}','{"code":1,"data":{}}'})do
 check('bad response rejected '..bad,function()assert(not api.parse(bad,'lqYjK',today))end)
end
check('wrong city and absent day rejected',function()assert(not api.parse(live,'wrong',today));assert(not api.parse(live,'lqYjK','2000-01-01'))end)
check('default city is Suzhou',function()assert(api.city().name=='苏州市')end)
check('tomorrow defaults off without changing today',function()assert(ink.weatherSelected(0) and not ink.weatherSelected(1) and settings:readSetting(S.weather_tomorrow)==nil)end)
check('weather hidden prevents fetch',function()settings:saveSetting(S.weather,false);W.pending=true;assert(not api.check() and not api.pending());settings:saveSetting(S.weather,true)end)
local Network=require('ui/network/manager');Network.queryNetworkState=function()end;Network.isConnected=function()return true end
local requests,callback=0
api.mockSend(function(url,token,cb,kind)requests=requests+1;assert(kind=='weather' and url:find('stationid=lqYjK',1,true));callback=cb;R.worker={kind=kind};return true end)
settings:saveSetting(S.online,true)
check('standalone fetch has no book quota impact',function()W.pending=true;local before=api.rounds();assert(api.check());assert(api.rounds()==before and api.progress.weather_only and not api.progress.scanning)end)
check('fetching status visible',function()assert(api.weatherText():find('获取中',1,true))end)
check('weather success caches source day',function()
 local obj=responseFor(today)
 R.worker=nil;callback(json.encode(obj));assert(W.records.lqYjK.day==today and not W.error and api.status.weather.lqYjK.result=='success')
 assert(W.records.lqYjK.text==ink.cachedWeather(W.records.lqYjK,today))
 assert(ink.cachedWeather(W.records.lqYjK,ink.weatherDate(1)))
end)
check('successful daily cache prevents duplicate requests',function()assert(not api.check() and not api.pending())end)
check('manual pending refreshes daily cache once',function()W.pending=true;assert(api.check());R.worker=nil;callback('bad json');assert(W.error and api.status.weather.lqYjK.result=='failed' and not api.pending())end)
check('failure remains visible despite older successful cache',function()assert(api.weatherText():find('天气获取失败',1,true))end)
check('sleep and cancellation suppress auto weather',function()W.pending=true;R.sleeping=true;assert(not api.check());R.sleeping=false;R.auto_holds.weather=true;assert(not api.check());R.auto_holds.weather=nil end)
check('no-city selection stops requests',function()settings:saveSetting(S.weather_city,false);assert(not api.city() and not api.pending());settings:saveSetting(S.weather_city,'lqYjK')end)
check('date toggle does not change weather eligibility',function()settings:saveSetting(S.date,false);assert(api.pending());settings:saveSetting(S.date,true)end)
check('weather failure does not block serialized book queue',function()
 local resumed=false;local before=R.token;W.pending=true;R.active=true;assert(api.check(true));R.worker=nil
 local nexttick=UI.nextTick;UI.nextTick=function(_,f)resumed=true end;callback('bad json');UI.nextTick=nexttick
 assert(resumed and R.token==before);R.active=false
end)
check('interrupted weather resumes on next wake',function()
 W.pending=true;assert(api.check());api.abort(true);assert(not R.worker and W.pending and R.auto_holds.weather and not api.check())
 R.auto_holds.weather=nil;assert(api.check());R.worker=nil;callback('bad json');assert(not api.pending())
end)
check('weather timeout does not cause unlimited retries',function()
 W.pending=true;assert(api.check());api.stop('HTTP subprocess timed out',false);callback('', 'HTTP subprocess timed out');assert(not api.pending())
end)
check('disabling weather stops active request',function()
 W.pending=true;assert(api.check());local row=api.menu().sub_item_table[2].sub_item_table[1].sub_item_table[1]
 row.callback();assert(not R.worker and not api.pending() and api.status.weather.lqYjK.result=='interrupted')
 settings:saveSetting(S.weather,true)
end)
settings:saveSetting(S.online,false);W.pending=false;W.error=nil
check('weather and date toggles operate independently',function()
 local top=api.menu().sub_item_table[2].sub_item_table[1];assert(top.text=='顶部信息')
 local a,b=top.sub_item_table[1],top.sub_item_table[3];assert(a.checked_func() and b.checked_func())
 a.callback();assert(not a.checked_func() and b.checked_func());b.callback();assert(not a.checked_func() and not b.checked_func());a.callback();b.callback()
end)

check('recorded response contains a separate tomorrow forecast',function()
 local t,e=api.parse(live,'lqYjK','2026-10-25');assert(t=='小雨 19～22°C',e)
end)
check('legacy cache remains readable and is not relabeled as tomorrow',function()
 local record={day=today,text='晴 12～23°C',updated_at=123}
 assert(ink.cachedWeather(record,today)==record.text and not ink.cachedWeather(record,ink.weatherDate(1)))
 assert(not record.forecasts and record.updated_at==123)
end)
check('calendar rollover uses correct forecast dates',function()
 assert(ink.weatherDate(1,'2026-12-31')=='2027-01-01')
 assert(ink.weatherDate(1,'2028-02-28')=='2028-02-29')
 assert(ink.weatherDate(1,'2028-02-29')=='2028-03-01')
end)
check('previous-day tomorrow cache is not silently displayed as freshly fetched today',function()
 local record={day='2026-10-24',forecasts={['2026-10-25']='晴 12～23°C'}}
 assert(not ink.cachedWeather(record,'2026-10-25','2026-10-25'))
end)
settings:saveSetting(S.online,true);W.pending=true
check('one HTTP response caches both days',function()
 settings:saveSetting(S.weather,true);settings:saveSetting(S.weather_tomorrow,true)
 local before=requests;assert(api.check());R.worker=nil;callback(json.encode(responseFor(today)))
 assert(requests==before+1 and ink.cachedWeather(W.records.lqYjK,today) and ink.cachedWeather(W.records.lqYjK,ink.weatherDate(1)))
 assert(not api.pending() and not api.check())
 local saved=require('luasettings'):open(api.store.file):readSetting('weather')
 assert(saved.records.lqYjK.forecasts[ink.weatherDate(1)])
end)
check('selecting cached tomorrow performs no extra HTTP request',function()
 settings:saveSetting(S.weather_tomorrow,false);local before=requests
 api.menu().sub_item_table[2].sub_item_table[1].sub_item_table[2].callback()
 assert(ink.weatherSelected(1) and requests==before and not api.pending())
end)
check('tomorrow-only selection fetches and labels tomorrow',function()
 settings:saveSetting(S.weather,false);W.pending=true;local before=requests
 assert(api.check());R.worker=nil;callback(json.encode(responseFor(today)))
 assert(requests==before+1 and api.weatherText(1):find('明日',1,true) and api.weatherText(1):find('19～22°C',1,true))
end)
check('disabling today leaves an active tomorrow request running',function()
 settings:saveSetting(S.weather,true);W.pending=true;assert(api.check())
 local worker=R.worker;local rows=api.menu().sub_item_table[2].sub_item_table[1].sub_item_table
 rows[1].callback();assert(not ink.weatherSelected(0) and ink.weatherSelected(1) and R.worker==worker)
 rows[2].callback();assert(not R.worker and not ink.weatherEnabled() and not api.pending())
end)
check('missing tomorrow remains an explicit partial failure without discarding today',function()
 settings:saveSetting(S.weather,true);settings:saveSetting(S.weather_tomorrow,true);W.pending=true;assert(api.check())
 local obj=responseFor(today)
 for i=#obj.data.predict.detail,1,-1 do if obj.data.predict.detail[i].date==ink.weatherDate(1)then table.remove(obj.data.predict.detail,i)end end
 R.worker=nil;callback(json.encode(obj))
 assert(ink.cachedWeather(W.records.lqYjK,today) and not ink.cachedWeather(W.records.lqYjK,ink.weatherDate(1)))
 assert(not W.error and not api.weatherText(0):find('失败',1,true) and api.weatherText(1):find('失败',1,true))
 assert(api.status.weather.lqYjK.result=='failed' and not api.pending() and not api.check())
end)
check('unselected missing today does not block a valid tomorrow forecast',function()
 settings:saveSetting(S.weather,false);settings:saveSetting(S.weather_tomorrow,true);W.pending=true;assert(api.check())
 local obj=responseFor(today)
 for i=#obj.data.predict.detail,1,-1 do if obj.data.predict.detail[i].date==today then table.remove(obj.data.predict.detail,i)end end
 R.worker=nil;callback(json.encode(obj))
 assert(api.status.weather.lqYjK.result=='success' and not api.weatherText(1):find('失败',1,true) and not api.pending())
end)
check('selected tomorrow error reports its own date failure',function()
 W.pending=true;assert(api.check());local obj=responseFor(today)
 for _,item in ipairs(obj.data.predict.detail)do
  if item.date==ink.weatherDate(1)then item.day.weather.temperature='-99';item.night.weather.temperature='-99' end
 end
 for i=#obj.data.tempchart,1,-1 do table.remove(obj.data.tempchart,i)end
 R.worker=nil;callback(json.encode(obj))
 assert(api.status.weather.lqYjK.result=='failed' and api.status.weather.lqYjK.reason:find('温度范围',1,true))
 settings:saveSetting(S.weather,true)
end)
check('enabling missing tomorrow explicitly retries once while preserving a valid today',function()
 settings:saveSetting(S.weather_tomorrow,false);local before=requests
 api.menu().sub_item_table[2].sub_item_table[1].sub_item_table[2].callback()
 assert(requests==before+1 and R.worker);R.worker=nil;callback(json.encode(responseFor(today)))
 assert(ink.cachedWeather(W.records.lqYjK,ink.weatherDate(1)) and not api.pending())
end)
settings:saveSetting(S.online,false);W.pending=false;W.error=nil
check('cover weather switches cached days without extra requests and preserves paper choices',function()
 settings:saveSetting(S.ui_style,'cover');settings:saveSetting(S.cover_weather,'today')
 settings:saveSetting(S.weather,true);settings:saveSetting(S.weather_tomorrow,true);settings:saveSetting(S.online,true)
 local before=requests;local rows=api.menu().sub_item_table[2].sub_item_table[1].sub_item_table
 rows[2].callback();assert(not ink.weatherSelected(0)and ink.weatherSelected(1)and requests==before)
 assert(settings:readSetting(S.weather)and settings:readSetting(S.weather_tomorrow))
end)
check('turning off cover weather stops an active request despite paper choices remaining enabled',function()
 W.pending=true;assert(api.check());local rows=api.menu().sub_item_table[2].sub_item_table[1].sub_item_table
 rows[2].callback();assert(not R.worker and not ink.weatherEnabled()and not api.pending())
 assert(settings:readSetting(S.weather)and settings:readSetting(S.weather_tomorrow))
end)
check('saving a skin change immediately updates weather eligibility',function()
 -- The public style switch and appearance save share the effective weather rules.
 settings:saveSetting(S.online,false);assert(ink.selectUIStyle('swiss'))
 assert(ink.weatherSelected(0)and ink.weatherSelected(1))
 assert(ink.selectUIStyle('cover'));assert(not ink.weatherEnabled())
 settings:saveSetting(S.ui_style,'classic');settings:delSetting(S.cover_weather);W.pending=false;W.error=nil
end)
local ui={document={file='weather.epub',getPageCount=function()return 100 end},doc_props={title='挽救计划',authors='安迪·威尔'},
 doc_settings={data={doc_pages=100}},view={state={page=23}},toc={getTocTitleByPage=function()return '第十二章'end}}
settings:saveSetting(S.cover,false);settings:saveSetting(S.intro,false);settings:saveSetting(S.stats,false)
local Text=require('ui/widget/textboxwidget')
local function inkCentre(t,p)
 local top,bottom
 for y=0,math.min(t._bb:getHeight(),t:getLineHeight())-1 do
  for x=0,t._bb:getWidth()-1 do if t._bb:getPixel(x,y):getColor8().a<128 then
   top=top or y;bottom=y;break
  end end
 end
 assert(top and bottom,'no first-line ink: '..t.text)
 return p.y+(top+bottom)/2
end
local function headerAligned(a,b,pos)return math.abs(inkCentre(a,pos[a])-inkCentre(b,pos[b]))<=1.5 end

local function positions(w,size)
 local out={};local native=Text.paintTo
 Text.paintTo=function(self,bb,x,y)out[self]={x=x,y=y,baseline=y+self:getBaseline()};return native(self,bb,x,y)end
 local bb=BB.new(size.width,size.height,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE)
 local ok,e=pcall(w.paintTo,w,bb,0,0);Text.paintTo=native;bb:free();assert(ok,e);return out
end

for _,style in ipairs({'classic','pixel','swiss'})do
 settings:saveSetting(S.ui_style,style)
 for _,font in ipairs({.8,1,1.2})do for _,width in ipairs({.55,.84,.90})do
 for _,show_date in ipairs({true,false})do
 for _,flags in ipairs({{true,false},{false,true},{true,true},{false,false}})do
 for _,status in ipairs({'晴 12～23°C','天气获取失败','待联网更新','雷阵雨转大到暴雨 -12～-3°C'})do
 check(style..' header '..font..' '..width..' date='..tostring(show_date)..' days='..tostring(flags[1])..tostring(flags[2])..status,function()
  settings:saveSetting(S.weather,flags[1]);settings:saveSetting(S.weather_tomorrow,flags[2]);settings:saveSetting(S.date,show_date)
  W.records.lqYjK={day=today,forecasts={[today]=status,[ink.weatherDate(1)]=status}}
  local fields={};local native=Text.new
  Text.new=function(self,args)local w=native(self,args);fields[#fields+1]=w;return w end
  local ok,paper,valid,size=pcall(api.render,ui,ui.view.state,{width=width,font=font,scale=.65,background='white',measure_only=true})
  Text.new=native;assert(ok,paper);assert(valid)
  local pos=positions(paper,size);local brand,date,a,b,city,chapter,progress,book
  local dual=flags[1] and flags[2]
  for _,t in ipairs(fields)do
   if t.text=='INKFOLIO'then brand=t elseif t.text==os.date('%Y.%m.%d')then date=t
   elseif t.text==api.weatherText(0,not dual)then a=t elseif t.text==api.weatherText(1,not dual)then b=t
   elseif t.text=='苏州'then city=t elseif t.text=='章节'then chapter=t
   elseif t.text=='23 / 100 页'then progress=t elseif t.text=='挽救计划'then book=t end
  end
  assert(brand and book and chapter and progress and (date~=nil)==show_date and (a~=nil)==flags[1] and (b~=nil)==flags[2])
  local left,right=paper.padding_left,size.width-paper.padding_right-paper.shadow_width
  if date then assert(date.alignment=='right' and math.abs(pos[date].x+date.width-right)<2 and headerAligned(date,brand,pos))end
  for _,t in pairs({date=date,today=a,tomorrow=b})do
   assert(t.face==chapter.face and t.face.size<=progress.face.size and not t.bold and t.fgcolor:getColor8().a==0)
  end
  if dual then
   assert(city and city.alignment=='left' and pos[city].x==left)
   assert(a.alignment=='center' and math.abs(pos[a].x+a.width/2-(left+right)/2)<2)
   assert(b.alignment=='right' and math.abs(pos[b].x+b.width-right)<2)
   assert(pos[city].x+city.width<=pos[a].x and pos[a].x+a.width<=pos[b].x)
   assert(pos[city].baseline==pos[a].baseline and pos[a].baseline==pos[b].baseline)
   assert(pos[city].y>=pos[brand].y+brand:getSize().h)
  elseif a or b then
   local weather=a or b
   assert(headerAligned(weather,brand,pos),'weather and brand visible centres differ')
   if date then assert(weather.alignment=='center' and math.abs(pos[weather].x+weather.width/2-(left+right)/2)<2)
   else assert(weather.alignment=='right' and math.abs(pos[weather].x+weather.width-right)<2)end
   assert(pos[weather].x>=pos[brand].x+brand.width and (not date or pos[weather].x+weather.width<=pos[date].x))
  else assert(not city) end
  for _,t in pairs({today=a,tomorrow=b,city=city})do
   assert(not t.height_overflow_show_ellipsis and t:getAllLineCount()>0)
   assert(pos[t].y+t:getSize().h<=pos[book].y)
  end
  for _,t in ipairs(fields)do if pos[t]then
   assert(pos[t].x>=0 and pos[t].x+t.width<=size.width)
   assert(pos[t].y>=0 and pos[t].y+t:getSize().h<=size.height)
  end end
  assert(size.width<=Screen:getWidth() and size.height<Screen:getHeight())
  if font==1 and width==.84 and status=='晴 12～23°C' then
   local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);paper:paintTo(bb,0,0)
   bb:writePNG(output..'/two-day-'..style..'-'..tostring(flags[1])..'-'..tostring(flags[2])..'-date-'..tostring(show_date)..'-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free()
  end
  paper:free()
 end)
 end end end end end
end
for _,style in ipairs({'classic','pixel','swiss'})do
 check(style..' longest city and long forecast wrap within equal-height header',function()
  settings:saveSetting(S.ui_style,style);settings:saveSetting(S.weather_city,'QCRTj')
  settings:saveSetting(S.weather,true);settings:saveSetting(S.weather_tomorrow,true);settings:saveSetting(S.date,true)
  W.records.QCRTj={day=today,forecasts={[today]='雷阵雨转大到暴雨 -12～-3°C',[ink.weatherDate(1)]='雷阵雨转大到暴雨 -12～-3°C'}}
  local paper,valid,size=api.render(ui,ui.view.state,{width=.55,font=1.2,scale=.65,background='white',measure_only=true});assert(paper and valid)
  assert(size.width<=Screen:getWidth() and size.height<Screen:getHeight())
  local pos=positions(paper,size);local found=0
  for t,p in pairs(pos)do if t.text:find('雷阵雨',1,true)or t.text=='克孜勒苏柯尔克孜自治州'then
   assert(not t.height_overflow_show_ellipsis and t:getAllLineCount()>1 and p.x>=0 and p.x+t.width<=size.width);found=found+1
  end end
  assert(found==3);paper:free();settings:saveSetting(S.weather_city,'lqYjK')
 end)
end
print('WEATHER_PASS '..passed..' / FAIL '..failed);os.exit(failed==0 and 0 or 1)
