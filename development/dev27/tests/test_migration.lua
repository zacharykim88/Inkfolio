require('setupkoenv');G_defaults=require('luadefaults'):open()
G_reader_settings=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
local settings=G_reader_settings
settings:saveSetting('read_receipt_v2_online',false)
local mode=assert(os.getenv('INK_LEGACY_MODE'))
if mode=='selection' then
 settings:saveSetting('read_receipt_v2_summary',{'book_today','global_total'})
 settings:saveSetting('read_receipt_v2_charts',{'week','month_words'})
else
 settings:saveSetting('read_receipt_v2_global_today',true)
 settings:saveSetting('read_receipt_v2_global_total',false)
 settings:saveSetting('read_receipt_v2_curve','month')
end
settings:saveSetting('read_receipt_v2_qr',mode=='selection')
settings:saveSetting('read_receipt_v2_width',.68)
settings:saveSetting('read_receipt_v2_font',1.15)
settings:saveSetting('read_receipt_v2_background','white')
settings:saveSetting('read_receipt_v2_word_book',true)
settings:saveSetting('read_receipt_v2_word_session',false)
settings:saveSetting('read_receipt_v2_remain',true)
local old_style=mode=='selection'and 'paper'or 'swiss'
settings:saveSetting('read_receipt_v2_ui_style',old_style)
settings:saveSetting('read_receipt_v2_paper_card_background','black')
settings:saveSetting('read_receipt_v2_card_background','white')
settings:saveSetting('read_receipt_v2_card_width',.6)
local Device=require('device');require('document/canvascontext'):init(Device)
local root=assert(arg[0]:match('^(.*)/tests/[^/]+$'))..'/'
local f=assert(io.open(root..'2-inkfolio.lua'));local source=f:read('*a');f:close()
local api=assert(loadstring(source..[[return {ink=Inkfolio,S=S,summary=summaryItems,menu=receiptSettingsMenu}]]))()
local ink,S=api.ink,api.S
local migrated_style=ink.uiStyle().id
if os.getenv('INK_STYLE') then settings:saveSetting(S.ui_style,os.getenv('INK_STYLE')) end
local passed,failed=0,0
local function check(name,fn)local ok,e=pcall(fn);if ok then passed=passed+1;print('PASS',name)else failed=failed+1;print('FAIL',name,e)end end
check('retired reading-page choice migrates once without changing other appearance settings',function()
 local expected=old_style=='paper'and 'cover'or old_style
 assert(migrated_style==expected and not settings:readSetting('read_receipt_v2_paper_card_background'))
 local saved=require('luasettings'):open(settings.file)
 assert(saved:readSetting(S.ui_style)==expected and not saved:readSetting('read_receipt_v2_paper_card_background'))
 assert(saved:readSetting(S.card_background)=='white'and saved:readSetting(S.card_width)==.6)
 assert(#ink.UI_STYLES==4 and not pcall(ink.uiStyle,{ui_style='paper'}))
end)
check('retired QR choice is deleted from memory and disk',function()
 assert(S.qr==nil and settings:readSetting('read_receipt_v2_qr')==nil)
 local saved=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
 assert(saved:readSetting('read_receipt_v2_qr')==nil and saved:readSetting('read_receipt_v2_width')==.68)
end)
check('upgrade preserves actual saved selection',function()
 local chosen=api.summary();assert(#chosen==2)
 if mode=='selection' then assert(chosen[1].id=='book_today' and chosen[2].id=='global_total')
 else assert(chosen[1].id=='global_today' and chosen[2].id=='book_total')end
end)
check('upgrade preserves appearance and progress selection',function()
 assert(settings:readSetting(S.width)==.68 and settings:readSetting(S.font)==1.15 and settings:readSetting(S.background)=='white')
 assert(ink.progressEnabled(S.word_book) and not ink.progressEnabled(S.word_session) and ink.progressEnabled(S.remain))
end)
check('upgrade defaults previous global secondary metric to pages',function()assert(ink.summaryMetric()=='pages')end)
check('upgrade preserves chart choices and retired curve migration',function()
 local charts=ink.chartItems();if mode=='selection' then assert(#charts==2 and charts[1].id=='week' and charts[2].id=='month_words')else assert(#charts==1 and charts[1].id=='month')end
end)
check('saved new secondary metric survives later initialization',function()
 settings:saveSetting(S.summary_metric,'words');ink.initializeDefaults(true);assert(ink.summaryMetric()=='words')
end)
check('new week month choices available without changing old choices',function()
 local rows=api.menu().sub_item_table[2].sub_item_table[4].sub_item_table[2].sub_item_table;local week,month=false,false
 for _,r in ipairs(rows)do week=week or r.text=='全局本周阅读';month=month or r.text=='全局本月阅读'end
 assert(week and month and #api.summary()==2)
end)
settings:flush()
check('updated settings persist to disk',function()
 local saved=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua');assert(saved:readSetting(S.summary_metric)=='words' and saved:readSetting(S.width)==.68)
end)
print('MIGRATION_PASS '..passed..' / FAIL '..failed);os.exit(failed==0 and 0 or 1)

