-- InkFolio v1.1.0 / KOReader user patch
-- SPDX-License-Identifier: GPL-3.0-only
-- Based on Estela-Zelin84/KOReader_Book-Receipt (GNU GPL v3).
-- Upstream credits u/hundredpercentcocoa and omer-faruq/koreader-user-patches.
-- Modifications and design: zacharykim88, 2026-10-10. Developed with OpenAI Codex.
-- Four UI styles; shared book-library metadata collection and permanent cache.
-- Network code must never turn Wi-Fi on automatically.
local Blitbuffer = require('ffi/blitbuffer')
local CenterContainer = require('ui/widget/container/centercontainer')
local Device = require('device')
local Dispatcher = require('dispatcher')
local Font = require('ui/font')
local FrameContainer = require('ui/widget/container/framecontainer')
local Geom = require('ui/geometry')
local GestureRange = require('ui/gesturerange')
local HorizontalGroup = require('ui/widget/horizontalgroup')
local HorizontalSpan = require('ui/widget/horizontalspan')
local ImageWidget = require('ui/widget/imagewidget')
local InputContainer = require('ui/widget/container/inputcontainer')
local ProgressWidget = require('ui/widget/progresswidget')
local ReaderUI = require('apps/reader/readerui')
local RenderImage = require('ui/renderimage')
local ScreenSaverWidget = require('ui/widget/screensaverwidget')
local TextWidget = require('ui/widget/textwidget')
local TextBoxWidget = require('ui/widget/textboxwidget')
local UIManager = require('ui/uimanager')
local VerticalGroup = require('ui/widget/verticalgroup')
local VerticalSpan = require('ui/widget/verticalspan')
local WidgetContainer = require('ui/widget/container/widgetcontainer')
local BookInfo = require('apps/filemanager/filemanagerbookinfo')
local DataStorage = require('datastorage')
local DocSettings = require('docsettings')
local DocRegistry = require('document/documentregistry')
local LuaSettings = require('luasettings')
local NetworkMgr = require('ui/network/manager')
local SQ3 = require('lua-ljsqlite3/init')
local socket_url = require('socket.url')
local lfs = require('libs/libkoreader-lfs')
local ffiUtil = require('ffi/util')
local logger = require('logger')
local util = require('util')
local _ = require('gettext')
local Screen = Device.screen
local Inkfolio = {}
local VERSION = '1.2.0'
local RELEASE_DATE = '2026-10-23'
local BUILD_ID='appearance-20261024-dev15'

-- Four skins share data, content choices and the common preview/export/suspend entry.
Inkfolio.UI_STYLES={{id='classic',label='小票'},{id='pixel',label='像素'},{id='swiss',label='现代'},{id='cover',label='封面'}}
-- Information roles and spacing are shared; skins only define their visual identity.
local UI_TEXT={
    section={size=24,bold=true},subheading={size=20,bold=true},
    label={size=20,muted=true},module={size=20},value={size=24,bold=true},
    header={size=20},text={size=24},percentage={size=30,bold=true},
    body={size=20},small={size=16,muted=true},
}
local UI_LAYOUT={rhythm=4,section=16,heading=8,card_sample_band=16,card_sample_step=4}
local UI_THEMES={
    classic={id='classic',label='小票',fonts={body='cfont',title='Xiangcui-Dazijiti-main/香萃打字机体 W40.ttf'},
        assets={'Xiangcui-Dazijiti-main/香萃打字机体 W40.ttf'},padding=25,shadow=8,summary_align='center',
        type={book={size=55,font='title',wear=true},brand={size=28,font='title',wear=true}}},
    pixel={id='pixel',label='像素',fonts={body='fusion-pixel-12px-proportional-zh_hans.otf'},
        assets={'fusion-pixel-12px-proportional-zh_hans.otf'},padding=25,summary_align='center',
        type={book={size=55,bold=true},brand={size=28,bold=true}}},
    swiss={id='swiss',label='现代',fonts={body='NotoSans-Regular.ttf'},assets={'NotoSans-Regular.ttf'},padding=28,summary_align='left',
        type={book={size=55,bold=true},brand={size=28,bold=true}}},
    cover={id='cover',label='封面',fonts={body='NotoSans-Regular.ttf'},assets={'NotoSans-Regular.ttf'},padding=32,summary_align='left',
        type={book={size=40,bold=true},brand={size=28,bold=true}}},
}
for _,theme in pairs(UI_THEMES)do
    for role,style in pairs(UI_TEXT)do theme.type[role]=style end
end

local P = 'read_receipt_v2_'
local S = {
    weather=P..'weather',weather_tomorrow=P..'weather_tomorrow',date=P..'date',weather_city=P..'weather_city',
    card_width=P..'card_width',card_font=P..'card_font',card_background=P..'card_background',cover_background=P..'cover_background',cover_weather=P..'cover_weather',
    online = P .. 'online', width = P .. 'width', font = P .. 'font',
    cover = P .. 'cover', chapter = P .. 'chapter', stats = P .. 'stats',
    intro = P .. 'intro', score = P .. 'score',
    remain = P .. 'remain', background = P .. 'background',
    footer = P .. 'footer', goal = P .. 'goal',
    global_today = P .. 'global_today', global_total = P .. 'global_total',
    summary = P .. 'summary', summary_metric=P..'summary_metric', progress = P .. 'progress', scale = P .. 'scale',
    library_root = P .. 'library_root', curve = P .. 'curve',
    word_book=P..'word_book',word_session=P..'word_session',debug_log=P..'debug_log',
    auto_fit=P..'auto_fit_pending',repro=P..'repro_record',charts=P..'charts',
    monthly_category=P..'monthly_category',monthly_rotate=P..'monthly_rotate',ui_style=P..'ui_style',
}
local previous_install=lfs.attributes(DataStorage:getSettingsDir()..'/read_receipt_v2_db.lua','mode')=='file'
for _,key in pairs(S) do if G_reader_settings:readSetting(key)~=nil then previous_install=true;break end end
local store = LuaSettings:open(DataStorage:getSettingsDir() .. '/read_receipt_v2_db.lua')
local CACHE = store:readSetting('books') or {}
local DAY = store:readSetting('day') or ''
local ROUNDS = tonumber(store:readSetting('auto_rounds')) or 0
local DAILY_DONE = store:readSetting('daily_done') == true
Inkfolio.monthly=store:readSetting('monthly_chart') or {}
assert(type(Inkfolio.monthly)=='table','InkFolio: 月榜缓存结构损坏')
local LIBRARY = store:readSetting('library_files') or {pending={}}
local NET=store:readSetting('network_schedule') or {books={},pending={}}
assert(type(NET)=='table' and type(NET.books)=='table' and type(NET.pending)=='table','InkFolio: 联网计划记录损坏')
local dailyCheck, weatherCheck, selectedWeatherCity
local WEATHER=store:readSetting('weather') or {records={}}
assert(type(WEATHER)=='table' and type(WEATHER.records)=='table','InkFolio: 天气缓存结构损坏')
-- CMA/NMC station identifiers verified from /rest/province on 2026-10-09.
-- Mainland prefecture names: Administrative-divisions-of-China (NBS-derived pc.json).
-- Municipalities and special administrative regions are listed directly.
local WEATHER_REGIONS={
    {name="北京市",cities={
        {name="北京市",code="Wqsps"},
    }},
    {name="天津市",cities={
        {name="天津市",code="yqSjH"},
    }},
    {name="河北省",cities={
        {name="石家庄市",code="uJQqI"},
        {name="唐山市",code="aCRJR"},
        {name="秦皇岛市",code="SBrmr"},
        {name="邯郸市",code="AwDQd"},
        {name="邢台市",code="WgyJx"},
        {name="保定市",code="FaykR"},
        {name="张家口市",code="AXmqR"},
        {name="承德市",code="oWYwK"},
        {name="沧州市",code="mHkdW"},
        {name="廊坊市",code="gXmTp"},
        {name="衡水市",code="Jiheq"},
    }},
    {name="山西省",cities={
        {name="太原市",code="jmHMK"},
        {name="大同市",code="VZgct"},
        {name="阳泉市",code="rwUnO"},
        {name="长治市",code="dwSMC"},
        {name="晋城市",code="VKljS"},
        {name="朔州市",code="OtlfP"},
        {name="晋中市",code="ovSsu"},
        {name="运城市",code="AupnI"},
        {name="忻州市",code="twMEQ"},
        {name="临汾市",code="nhsiM"},
        {name="吕梁市",code="EQQRH"},
    }},
    {name="内蒙古自治区",cities={
        {name="呼和浩特市",code="IlyWx"},
        {name="包头市",code="wzspS"},
        {name="乌海市",code="HfJln"},
        {name="赤峰市",code="yiSxk"},
        {name="通辽市",code="LUAqU"},
        {name="鄂尔多斯市",code="cSBaZ"},
        {name="呼伦贝尔市",code="YUznP"},
        {name="巴彦淖尔市",code="TBQLP"},
        {name="乌兰察布市",code="MwkIG"},
        {name="兴安盟",code="wfaiF"},
        {name="锡林郭勒盟",code="euSxF"},
        {name="阿拉善盟",code="foHBa"},
    }},
    {name="辽宁省",cities={
        {name="沈阳市",code="xasvS"},
        {name="大连市",code="nGPyb"},
        {name="鞍山市",code="TopGN"},
        {name="抚顺市",code="shhKE"},
        {name="本溪市",code="fZXDt"},
        {name="丹东市",code="DlvsN"},
        {name="锦州市",code="LgDdn"},
        {name="营口市",code="veIOe"},
        {name="阜新市",code="uxzEA"},
        {name="辽阳市",code="kgqfX"},
        {name="盘锦市",code="ooWvQ"},
        {name="铁岭市",code="WDQHL"},
        {name="朝阳市",code="SSCPq"},
        {name="葫芦岛市",code="NIFaR"},
    }},
    {name="吉林省",cities={
        {name="长春市",code="mxFBj"},
        {name="吉林市",code="oQKCU"},
        {name="四平市",code="UIlgs"},
        {name="辽源市",code="pSYcD"},
        {name="通化市",code="LaBrf"},
        {name="白山市",code="nFNOH"},
        {name="松原市",code="jJpzl"},
        {name="白城市",code="ktvDN"},
        {name="延边朝鲜族自治州",code="QHZhm"},
    }},
    {name="黑龙江省",cities={
        {name="哈尔滨市",code="pzXOG"},
        {name="齐齐哈尔市",code="pMfJu"},
        {name="鸡西市",code="tsmWc"},
        {name="鹤岗市",code="pQrYF"},
        {name="双鸭山市",code="xYzrU"},
        {name="大庆市",code="uLCaf"},
        {name="伊春市",code="BAQLD"},
        {name="佳木斯市",code="IwveF"},
        {name="七台河市",code="olTln"},
        {name="牡丹江市",code="WhkSY"},
        {name="黑河市",code="xggDD"},
        {name="绥化市",code="ccdEO"},
        {name="大兴安岭地区",code="HIKCZ"},
    }},
    {name="上海市",cities={
        {name="上海市",code="WwcJd"},
    }},
    {name="江苏省",cities={
        {name="南京市",code="CxOWZ"},
        {name="无锡市",code="fvlMy"},
        {name="徐州市",code="bWGZQ"},
        {name="常州市",code="bmyrb"},
        {name="苏州市",code="lqYjK"},
        {name="南通市",code="VHAmf"},
        {name="连云港市",code="HPnPL"},
        {name="淮安市",code="wVmjo"},
        {name="盐城市",code="bUGRK"},
        {name="扬州市",code="lDhJo"},
        {name="镇江市",code="xKfDh"},
        {name="泰州市",code="kQswL"},
        {name="宿迁市",code="jVxXh"},
    }},
    {name="浙江省",cities={
        {name="杭州市",code="HIieJ"},
        {name="宁波市",code="XjZpe"},
        {name="温州市",code="qgMmM"},
        {name="嘉兴市",code="pxfeS"},
        {name="湖州市",code="quMLV"},
        {name="绍兴市",code="gxbHp"},
        {name="金华市",code="QMNma"},
        {name="衢州市",code="ydEbu"},
        {name="舟山市",code="KElec"},
        {name="台州市",code="zWIte"},
        {name="丽水市",code="nEoHv"},
    }},
    {name="安徽省",cities={
        {name="合肥市",code="xqcji"},
        {name="芜湖市",code="YCdBx"},
        {name="蚌埠市",code="xEdTH"},
        {name="淮南市",code="DUBio"},
        {name="马鞍山市",code="cdzPY"},
        {name="淮北市",code="npJUD"},
        {name="铜陵市",code="VAMvd"},
        {name="安庆市",code="bIpli"},
        {name="黄山市",code="dFIpc"},
        {name="滁州市",code="aqZIQ"},
        {name="阜阳市",code="JcXXt"},
        {name="宿州市",code="KZzYj"},
        {name="六安市",code="RLVWB"},
        {name="亳州市",code="bjqNC"},
        {name="池州市",code="XbuHL"},
        {name="宣城市",code="hhgTF"},
    }},
    {name="福建省",cities={
        {name="福州市",code="djeOy"},
        {name="厦门市",code="gDCDS"},
        {name="莆田市",code="XbBQN"},
        {name="三明市",code="CZiRH"},
        {name="泉州市",code="MGECZ"},
        {name="漳州市",code="SCyJf"},
        {name="南平市",code="CGyTI"},
        {name="龙岩市",code="AVWuS"},
        {name="宁德市",code="uKfig"},
    }},
    {name="江西省",cities={
        {name="南昌市",code="JmxCz"},
        {name="景德镇市",code="DriXU"},
        {name="萍乡市",code="yBDJf"},
        {name="九江市",code="kVOgS"},
        {name="新余市",code="IzuqH"},
        {name="鹰潭市",code="UWvkt"},
        {name="赣州市",code="uBtqa"},
        {name="吉安市",code="riQqz"},
        {name="宜春市",code="OqvoJ"},
        {name="抚州市",code="toCHD"},
        {name="上饶市",code="KpYAB"},
    }},
    {name="山东省",cities={
        {name="济南市",code="VITKz"},
        {name="青岛市",code="Jrsbf"},
        {name="淄博市",code="BGfNv"},
        {name="枣庄市",code="rXLkZ"},
        {name="东营市",code="CHtLx"},
        {name="烟台市",code="qRqdU"},
        {name="潍坊市",code="hQrpa"},
        {name="济宁市",code="Jmcsg"},
        {name="泰安市",code="zUeIF"},
        {name="威海市",code="KeEOQ"},
        {name="日照市",code="GoJQw"},
        {name="临沂市",code="aGpFP"},
        {name="德州市",code="polCM"},
        {name="聊城市",code="XXeBL"},
        {name="滨州市",code="penbZ"},
        {name="菏泽市",code="MGAnB"},
    }},
    {name="河南省",cities={
        {name="郑州市",code="YVItN"},
        {name="开封市",code="swtij"},
        {name="洛阳市",code="rYaxY"},
        {name="平顶山市",code="nRecJ"},
        {name="安阳市",code="hNkdK"},
        {name="鹤壁市",code="NYclC"},
        {name="新乡市",code="VLpOH"},
        {name="焦作市",code="ubXHV"},
        {name="濮阳市",code="XbbBI"},
        {name="许昌市",code="ZzMTA"},
        {name="漯河市",code="lncFZ"},
        {name="三门峡市",code="TjcXC"},
        {name="南阳市",code="vRweN"},
        {name="商丘市",code="aMsMR"},
        {name="信阳市",code="hdKHW"},
        {name="周口市",code="URskB"},
        {name="驻马店市",code="ZmGSj"},
    }},
    {name="湖北省",cities={
        {name="武汉市",code="bSpCz"},
        {name="黄石市",code="MTZwr"},
        {name="十堰市",code="BREJr"},
        {name="宜昌市",code="ekVpr"},
        {name="襄阳市",code="fTXja"},
        {name="鄂州市",code="Agzls"},
        {name="荆门市",code="vGwSN"},
        {name="孝感市",code="CQLZw"},
        {name="荆州市",code="xBZlA"},
        {name="黄冈市",code="sWCpi"},
        {name="咸宁市",code="BokVQ"},
        {name="随州市",code="VHSxv"},
        {name="恩施土家族苗族自治州",code="zKHUp"},
    }},
    {name="湖南省",cities={
        {name="长沙市",code="zOenJ"},
        {name="株洲市",code="siHjW"},
        {name="湘潭市",code="tWpqg"},
        {name="衡阳市",code="ObykY"},
        {name="邵阳市",code="KZYji"},
        {name="岳阳市",code="bwVav"},
        {name="常德市",code="NMRKc"},
        {name="张家界市",code="FOUZo"},
        {name="益阳市",code="OZhHG"},
        {name="郴州市",code="cYyyF"},
        {name="永州市",code="vXgNI"},
        {name="怀化市",code="pJrqw"},
        {name="娄底市",code="ZrEsO"},
        {name="湘西土家族苗族自治州",code="TaxlO"},
    }},
    {name="广东省",cities={
        {name="广州市",code="DwzZf"},
        {name="韶关市",code="fXufo"},
        {name="深圳市",code="AhpEU"},
        {name="珠海市",code="sdnjf"},
        {name="汕头市",code="KYhpn"},
        {name="佛山市",code="YOyIv"},
        {name="江门市",code="YtTxj"},
        {name="湛江市",code="OKhmr"},
        {name="茂名市",code="aELXI"},
        {name="肇庆市",code="SwPNZ"},
        {name="惠州市",code="VDZzQ"},
        {name="梅州市",code="lWavY"},
        {name="汕尾市",code="hlwPp"},
        {name="河源市",code="Fkjlf"},
        {name="阳江市",code="dCezB"},
        {name="清远市",code="WYryQ"},
        {name="东莞市",code="cqsJg"},
        {name="中山市",code="YIWau"},
        {name="潮州市",code="CSTxF"},
        {name="揭阳市",code="rUWdQ"},
        {name="云浮市",code="JMZwt"},
    }},
    {name="广西壮族自治区",cities={
        {name="南宁市",code="dvHfb"},
        {name="柳州市",code="hDSje"},
        {name="桂林市",code="qiegc"},
        {name="梧州市",code="EUqSO"},
        {name="北海市",code="lBdeM"},
        {name="防城港市",code="kXkLV"},
        {name="钦州市",code="jPyoz"},
        {name="贵港市",code="UzLca"},
        {name="玉林市",code="cFeHF"},
        {name="百色市",code="Cejmy"},
        {name="贺州市",code="SdWDF"},
        {name="河池市",code="GGGqW"},
        {name="来宾市",code="qxttW"},
        {name="崇左市",code="Pnyfc"},
    }},
    {name="海南省",cities={
        {name="海口市",code="vmEKa"},
        {name="三亚市",code="PtnWb"},
        {name="三沙市",code="iIkAm"},
        {name="儋州市",code="pFFlS"},
    }},
    {name="重庆市",cities={
        {name="重庆市",code="UkfaS"},
    }},
    {name="四川省",cities={
        {name="成都市",code="yGYHR"},
        {name="自贡市",code="MIIAp"},
        {name="攀枝花市",code="jrDgO"},
        {name="泸州市",code="nLWnl"},
        {name="德阳市",code="QFQLG"},
        {name="绵阳市",code="GcFwG"},
        {name="广元市",code="OwVIj"},
        {name="遂宁市",code="pcHfo"},
        {name="内江市",code="wNtyv"},
        {name="乐山市",code="YuAXe"},
        {name="南充市",code="vihpz"},
        {name="眉山市",code="zkdYW"},
        {name="宜宾市",code="wfNOD"},
        {name="广安市",code="zJhEo"},
        {name="达州市",code="uEFLb"},
        {name="雅安市",code="MfnxC"},
        {name="巴中市",code="UxUlc"},
        {name="资阳市",code="AVVPj"},
        {name="阿坝藏族羌族自治州",code="ujnor"},
        {name="甘孜藏族自治州",code="EvJZp"},
        {name="凉山彝族自治州",code="kSbRT"},
    }},
    {name="贵州省",cities={
        {name="贵阳市",code="SKMHP"},
        {name="六盘水市",code="neXJx"},
        {name="遵义市",code="mKDbo"},
        {name="安顺市",code="zYxtY"},
        {name="毕节市",code="QJFow"},
        {name="铜仁市",code="EaOOy"},
        {name="黔西南布依族苗族自治州",code="pYfUO"},
        {name="黔东南苗族侗族自治州",code="NwqhO"},
        {name="黔南布依族苗族自治州",code="ikFVR"},
    }},
    {name="云南省",cities={
        {name="昆明市",code="IayMy"},
        {name="曲靖市",code="rYbQI"},
        {name="玉溪市",code="eHman"},
        {name="保山市",code="DQgGy"},
        {name="昭通市",code="CMqgr"},
        {name="丽江市",code="AwEIF"},
        {name="普洱市",code="weSDX"},
        {name="临沧市",code="oiQQr"},
        {name="楚雄彝族自治州",code="xbekN"},
        {name="红河哈尼族彝族自治州",code="kLDAL"},
        {name="文山壮族苗族自治州",code="ZQEia"},
        {name="西双版纳傣族自治州",code="IhAco"},
        {name="大理白族自治州",code="MXvqt"},
        {name="德宏傣族景颇族自治州",code="YpfMn"},
        {name="怒江傈僳族自治州",code="MlVrp"},
        {name="迪庆藏族自治州",code="dghSe"},
    }},
    {name="西藏自治区",cities={
        {name="拉萨市",code="utJQK"},
        {name="日喀则市",code="wcnpZ"},
        {name="昌都市",code="FKHOa"},
        {name="林芝市",code="ulvCs"},
        {name="山南市",code="uuiXc"},
        {name="那曲市",code="aDeyn"},
        {name="阿里地区",code="DDraR"},
    }},
    {name="陕西省",cities={
        {name="西安市",code="RfjCI"},
        {name="铜川市",code="lZvra"},
        {name="宝鸡市",code="jrjXm"},
        {name="咸阳市",code="FXoMd"},
        {name="渭南市",code="fXkRh"},
        {name="延安市",code="gtpZu"},
        {name="汉中市",code="cASRq"},
        {name="榆林市",code="eEPbq"},
        {name="安康市",code="RprEI"},
        {name="商洛市",code="qbDbK"},
    }},
    {name="甘肃省",cities={
        {name="兰州市",code="ARkZA"},
        {name="嘉峪关市",code="WVCbx"},
        {name="金昌市",code="chtaw"},
        {name="白银市",code="soZAZ"},
        {name="天水市",code="tiBhu"},
        {name="武威市",code="LAPGD"},
        {name="张掖市",code="nvQbo"},
        {name="平凉市",code="Yekjp"},
        {name="酒泉市",code="vDJSl"},
        {name="庆阳市",code="Nvedf"},
        {name="定西市",code="rsMQP"},
        {name="陇南市",code="mdYJa"},
        {name="临夏回族自治州",code="orIIe"},
        {name="甘南藏族自治州",code="QyZJe"},
    }},
    {name="青海省",cities={
        {name="西宁市",code="SHRvr"},
        {name="海东市",code="CrGat"},
        {name="海北藏族自治州",code="biGag"},
        {name="黄南藏族自治州",code="pVcUC"},
        {name="海南藏族自治州",code="bwKfK"},
        {name="果洛藏族自治州",code="ycCXH"},
        {name="玉树藏族自治州",code="MDlNL"},
        {name="海西蒙古族藏族自治州",code="UpIIn"},
    }},
    {name="宁夏回族自治区",cities={
        {name="银川市",code="LqTRN"},
        {name="石嘴山市",code="jNMZg"},
        {name="吴忠市",code="VXPXK"},
        {name="固原市",code="muLnq"},
        {name="中卫市",code="mZrCd"},
    }},
    {name="新疆维吾尔自治区",cities={
        {name="乌鲁木齐市",code="lIPam"},
        {name="克拉玛依市",code="RHxwy"},
        {name="吐鲁番市",code="DGEdf"},
        {name="哈密市",code="LFhJu"},
        {name="昌吉回族自治州",code="bIfiH"},
        {name="博尔塔拉蒙古自治州",code="UnvYB"},
        {name="巴音郭楞蒙古自治州",code="QAgHw"},
        {name="阿克苏地区",code="wPpQt"},
        {name="克孜勒苏柯尔克孜自治州",code="QCRTj"},
        {name="喀什地区",code="aHjQA"},
        {name="和田地区",code="HDzeq"},
        {name="伊犁哈萨克自治州",code="kAFDB"},
        {name="塔城地区",code="qHPXG"},
        {name="阿勒泰地区",code="SnOYy"},
    }},
    {name="香港特别行政区",cities={
        {name="香港特别行政区",code="KnxKc"},
    }},
    {name="澳门特别行政区",cities={
        {name="澳门特别行政区",code="ZZhCJ"},
    }},
    {name="台湾省",cities={
        {name="台北市",code="VrMVF"},
        {name="新北市",code=""},
        {name="桃园市",code=""},
        {name="台中市",code="FYDSf"},
        {name="台南市",code=""},
        {name="高雄市",code="Urwjw"},
        {name="基隆市",code=""},
        {name="新竹市",code=""},
        {name="嘉义市",code=""},
    }},
}


local STATS_PATH = DataStorage:getSettingsDir() .. '/statistics.sqlite3'
local MAX_BOOK_ATTEMPTS = 3
local RUN = { active = false, sleeping = false, token = 0, manual = false,
              queue = {}, index = 1, started = false, processed = 0,
              worker = nil, transport_broken = false, network_failures = 0, last_error = nil,
              failed = 0, last_book_error = nil }
-- Cancellation lasts only until the next resume; discard the old daily hold.
RUN.cancelled_wake = false
RUN.auto_holds={}
RUN.scan_pending=true
store:delSetting('cancelled_day')
local refreshQuicklook = nil
function Inkfolio.uiStyle(appearance)
    local id=appearance and appearance.ui_style or G_reader_settings:readSetting(S.ui_style) or 'classic'
    return assert(UI_THEMES[id],'InkFolio UI风格设置无效：'..tostring(id))
end
function Inkfolio.uiFontError(theme,size)
    for _,name in ipairs(theme.assets)do
        if not Font:getFace(name,size or 20) then return '“'..theme.label..'”字体无法加载：\n'..name..'\n请安装随包 fonts 中的字体，再完全重启 KOReader。' end
    end
end
function Inkfolio.persistSettings(changes)
    local previous={}
    for key in pairs(changes)do previous[key]=G_reader_settings:readSetting(key) end
    local ok,err=pcall(function()
        for key,value in pairs(changes)do G_reader_settings:saveSetting(key,value) end
        G_reader_settings:flush()
        -- Native flush can discard an I/O error; verify our scalar choices on disk.
        local saved=dofile(assert(G_reader_settings.file,'InkFolio 设置文件路径缺失'))
        assert(type(saved)=='table','InkFolio 设置保存结果无效')
        for key,value in pairs(changes)do
            assert(saved[key]==value,'InkFolio 设置未能保存：'..key)
        end
    end)
    if not ok then
        for key in pairs(changes)do
            if previous[key]==nil then G_reader_settings:delSetting(key)
            else G_reader_settings:saveSetting(key,previous[key]) end
        end
        error(err)
    end
end
function Inkfolio.selectUIStyle(id)
    local theme=assert(UI_THEMES[id],'InkFolio UI风格无效：'..tostring(id))
    local reason=Inkfolio.uiFontError(theme)
    if reason then return false,reason end
    if G_reader_settings:readSetting(S.ui_style)==id then return true end
    local today,tomorrow=Inkfolio.weatherSelected(0),Inkfolio.weatherSelected(1)
    Inkfolio.persistSettings({[S.ui_style]=id})
    Inkfolio.recordAction('UI风格')
    if today~=Inkfolio.weatherSelected(0)or tomorrow~=Inkfolio.weatherSelected(1)then
        Inkfolio.weatherChanged(Inkfolio.weatherEnabled())
    elseif refreshQuicklook then refreshQuicklook()end
    return true
end
local MANUAL_CONNECT_PENDING = false
local startPoll -- declared before the cancellation path that may need to re-arm Wi-Fi polling

local function saveData()
    store:saveSetting('books', CACHE)
    store:saveSetting('day', DAY)
    store:saveSetting('auto_rounds', ROUNDS)
    store:saveSetting('daily_done', DAILY_DONE)
    store:flush()
end
local function enabled(key)
    return G_reader_settings:readSetting(key) ~= false
end
local function networkingEnabled() return enabled(S.online) end
local function localDate() return os.date('%Y-%m-%d') end
local function resetDay()
    local d = localDate()
    if DAY ~= d then
        DAY, ROUNDS, DAILY_DONE = d, 0, false
        saveData()
    end
end
local function connected()
    NetworkMgr:queryNetworkState()
    return NetworkMgr:isConnected() == true
end
local function shortText(txt, count)
    txt = tostring(txt or '')
    local pos, chars = 1, 0
    while pos <= #txt and chars < count do
        local c = txt:byte(pos)
        if c >= 240 then pos = pos + 4
        elseif c >= 224 then pos = pos + 3
        elseif c >= 192 then pos = pos + 2
        else pos = pos + 1 end
        chars = chars + 1
    end
    return txt:sub(1, pos - 1) .. (pos <= #txt and '…' or '')
end
local function normalize(txt)
    local s = tostring(txt or ''):lower()
    for _, c in ipairs({'《','》','【','】','（','）','·','•','・','‧','．','：','，','。','-',' ', '[',']','(',')',':',',','.', '\n'}) do
        s = s:gsub(c:gsub('(%W)', '%%%1'), '')
    end
    -- gsub also returns its replacement count; never leak it into bookKey's table.
    return (s:gsub('%s+', ''))
end
local function htmlText(s)
    s = tostring(s or ''):gsub('<script.-</script>', ' '):gsub('<style.-</style>', ' ')
    s = s:gsub('<[^>]*>', ' ')
    local ok, v = pcall(util.htmlEntitiesToUtf8, s)
    if ok and v then s = v end
    return (s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end
local function extractBook(props, path)
    props = props or {}
    local file_title = path and path:match('([^/]+)%.[^%.]+$') or ''
    local title_source='内部标题'
    local title=util.trim(props.display_title or '')
    if title=='' then title=util.trim(props.title or '') end
    if title=='' then title=util.trim(file_title or '');title_source='文件名（内部标题为空）' end
    return {
        title = title,title_source=title_source,
        authors = util.trim(props.authors or ''),
        publisher = util.trim(props.publisher or ''),
        isbn = tostring(props.isbn or ''):gsub('[^%dXx]', ''),
        description = htmlText(props.description or ''),
        path = path,
    }
end
function Inkfolio.metadataKey(book) return table.concat({normalize(book.title),normalize(book.authors)},'|') end
local function bookKey(book)
    -- Same work is intentionally shared across editions. The publisher and ISBN
    -- are ranking criteria, not cache identity: metadata can differ between the
    -- file manager and reader, or be unavailable for never-opened books.
    local choice=Inkfolio.confirmedChoice and Inkfolio.confirmedChoice(book)
    if choice then return 'confirmed:'..Inkfolio.fileMatchKey(book) end
    local key=Inkfolio.metadataKey(book)
    local collection=Inkfolio.collectionInfo and Inkfolio.collectionInfo(book)
    if collection and collection.first and not collection.blocked then key=key..'|volumes:'..collection.first..'-'..collection.last end
    return key
end
local function validURL(url)
    return type(url) == 'string' and url:match('^https://book%.douban%.com/subject/%d+/$') ~= nil
end
local function cached(book)
    local item = CACHE[bookKey(book)]
    local rating = type(item) == 'table' and tonumber(item.rating)
    return rating and rating > 0 and rating <= 10 and validURL(item.url) and item or nil
end
local SEARCH_TITLES=store:readSetting('search_titles') or {}
assert(type(SEARCH_TITLES)=='table','InkFolio: 搜索书名设置损坏')
for key,value in pairs(SEARCH_TITLES) do
    assert(type(key)=='string' and type(value)=='string' and util.trim(value)~='' and not value:find('[\r\n]'),
        'InkFolio: 搜索书名设置条目损坏')
end
function Inkfolio.searchOverride(book) return SEARCH_TITLES[Inkfolio.metadataKey(book)] end
-- Persisted choices belong to the file, not every file sharing its title.
Inkfolio.matchState=store:readSetting('book_matching') or {choices={},pending={}}
Inkfolio.matchState.holds=Inkfolio.matchState.holds or {}
assert(type(Inkfolio.matchState.holds)=='table','InkFolio: 暂停记录损坏')
assert(type(Inkfolio.matchState)=='table' and type(Inkfolio.matchState.choices)=='table'
    and type(Inkfolio.matchState.pending)=='table','InkFolio: 图书匹配设置损坏')
for key,choice in pairs(Inkfolio.matchState.choices)do
    assert(type(key)=='string' and type(choice)=='table' and validURL(choice.url)
        and type(choice.title)=='string' and type(choice.authors)=='string','InkFolio: 图书确认记录损坏')
end
for key,pending in pairs(Inkfolio.matchState.pending)do
    assert(type(key)=='string' and type(pending)=='table' and type(pending.book)=='table'
        and type(pending.candidates)=='table','InkFolio: 待确认记录损坏')
    assert(type(pending.book.title)=='string' and type(pending.book.authors)=='string','InkFolio: 待确认图书身份损坏')
    for _,c in ipairs(pending.candidates)do
        assert(type(c)=='table' and validURL(c.url) and type(c.rating)=='number' and c.rating>0 and c.rating<=10
            and type(c.title)=='string' and type(c.authors)=='string','InkFolio: 待确认候选损坏')
    end
end
function Inkfolio.fileMatchKey(book) return book.path or Inkfolio.metadataKey(book) end
function Inkfolio.confirmedChoice(book)
    local c=Inkfolio.matchState.choices[Inkfolio.fileMatchKey(book)]
    return c and c.book_identity==Inkfolio.metadataKey(book) and c or nil
end
function Inkfolio.writeMatchState(next_state)
    local previous=Inkfolio.matchState
    local ok=pcall(function()store:saveSetting('book_matching',next_state);store:flush()end)
    if not ok then store:saveSetting('book_matching',previous);return false,'匹配记录保存失败，请检查设置目录。' end
    Inkfolio.matchState=next_state;return true
end
function Inkfolio.setPending(book,candidates,reason,query)
    local old=Inkfolio.matchState;local state={choices={},pending={},holds=Inkfolio.matchState.holds}
    for k,v in pairs(old.choices)do state.choices[k]=v end
    for k,v in pairs(old.pending)do state.pending[k]=v end
    state.pending[Inkfolio.fileMatchKey(book)]={book=book,candidates=candidates or {},reason=reason,query=query,at=os.time()}
    return Inkfolio.writeMatchState(state)
end

function Inkfolio.cacheMatches(book,record)
    if not record then return false end
    local choice=Inkfolio.confirmedChoice(book)
    if choice then return record.identity_version==2 and record.user_confirmed and record.url==choice.url end
    -- Historical records may remain usable without asserting a new verification.
    if record.score_kind=='volumes' then
        local collection=Inkfolio.collectionInfo(book)
        if not collection or collection.blocked or record.collection_scope~=collection.scope then return false end
    end
    if not record.search_query then return Inkfolio.searchOverride(book)==nil end
    return record.search_query==Inkfolio.searchTitle(book)
end
function Inkfolio.setSearchTitle(book,text)
    if RUN.active or RUN.worker or MANUAL_CONNECT_PENDING then return false,'获取进行中，请结束后再修改搜索书名。' end
    if text~=nil then
        text=util.trim(tostring(text))
        if text=='' or text:find('[\r\n]') then return false,'搜索书名不能为空，请输入一行书名。' end
    end
    local key=Inkfolio.metadataKey(book);local next_titles={}
    for k,v in pairs(SEARCH_TITLES) do next_titles[k]=v end
    next_titles[key]=text
    local previous=SEARCH_TITLES
    local ok,reason=pcall(function()store:saveSetting('search_titles',next_titles);store:flush()end)
    if not ok then
        store:saveSetting('search_titles',previous)
        logger.warn('InkFolio search title save failed',reason)
        return false,'搜索书名保存失败，请检查设置目录是否可写。'
    end
    SEARCH_TITLES=next_titles
    return true
end
for key,value in pairs(Inkfolio.matchState.holds)do
    assert(type(key)=='string' and type(value)=='string','InkFolio: 暂停记录损坏')
end
local function completed(book)
    local item = cached(book)
    if not item or not Inkfolio.cacheMatches(book,item) then return false end
    return item.user_confirmed == true or item.intro_state == 'absent'
        or (type(book.description)=='string' and book.description~='')
        or (type(item.intro)=='string' and item.intro~='')
end
function Inkfolio.needsFetch(book)
    if completed(book) then return false end
    local key=Inkfolio.fileMatchKey(book)
    local hold=Inkfolio.matchState.holds[key]
    if hold and hold==Inkfolio.metadataKey(book) then return false end
    local pending=Inkfolio.matchState.pending[key]
    if pending and Inkfolio.metadataKey(pending.book)==Inkfolio.metadataKey(book)
        and #pending.candidates>0 then return false end
    return true
end

-- Automatic work is scheduled only at its actual deadline, never by a heartbeat.
Inkfolio.NET_RULES={weather_age=6*3600,book_retry=30*60,book_attempts=MAX_BOOK_ATTEMPTS}
function Inkfolio.saveNetwork()
    store:saveSetting('network_schedule',NET);store:flush()
end
function Inkfolio.nextDay(now)
    local d=os.date('*t',now or os.time())
    return os.time{year=d.year,month=d.month,day=d.day+1,hour=0,min=0,sec=0}
end
function Inkfolio.networkHeld(kind)
    return RUN.auto_holds[kind]==true
end
function Inkfolio.resetNetworkPause()
    RUN.transport_broken=false;RUN.network_failures=0
end
function Inkfolio.bookDeadline(book,now)
    if not Inkfolio.needsFetch(book) then return nil end
    now=now or os.time()
    local entry=NET.books[bookKey(book)]
    if not entry or entry.day~=os.date('%Y-%m-%d',now) then return now end
    if entry.attempts>=Inkfolio.NET_RULES.book_attempts then return Inkfolio.nextDay(now) end
    return math.max(now,entry.next_at or now)
end
function Inkfolio.queueBook(book,defer)
    if not book or book.title=='' then return false end
    local key=bookKey(book)
    if not Inkfolio.needsFetch(book) then
        if NET.pending[key]then NET.pending[key]=nil;if not defer then Inkfolio.saveNetwork()end end
        return false
    end
    if book.path then
        for other,queued in pairs(NET.pending)do
            if other~=key and queued.path==book.path then NET.pending[other]=nil end
        end
    end
    local copy={}
    for _,field in ipairs({'title','authors','publisher','isbn','description','path'})do copy[field]=book[field] end
    NET.pending[key]=copy
    if not defer then Inkfolio.saveNetwork() end
    return true
end
function Inkfolio.bookAttempt(book,manual)
    if manual then return end
    local now=os.time();local day=os.date('%Y-%m-%d',now);local key=bookKey(book)
    local entry=NET.books[key]
    if not entry or entry.day~=day then entry={day=day,attempts=0};NET.books[key]=entry end
    entry.attempts=entry.attempts+1;entry.next_at=now+Inkfolio.NET_RULES.book_retry
    Inkfolio.saveNetwork()
end
function Inkfolio.bookFinished(book)
    local key=bookKey(book)
    if not Inkfolio.needsFetch(book) then NET.pending[key]=nil
    else
        Inkfolio.queueBook(book,true)
        local now=os.time();local day=os.date('%Y-%m-%d',now);local entry=NET.books[key]
        if not entry or entry.day~=day then entry={day=day,attempts=0};NET.books[key]=entry end
        entry.next_at=now+Inkfolio.NET_RULES.book_retry
    end
    Inkfolio.saveNetwork()
end
function Inkfolio.networkFailure(book_request,reason)
    if book_request then RUN.last_error=reason end
    RUN.network_failures=RUN.network_failures+1
    if RUN.network_failures>=3 then RUN.transport_broken=true end
end

local STATUS=store:readSetting('information_status') or {version=1,books={},history={}}
assert(type(STATUS)=='table' and STATUS.version==1 and type(STATUS.books)=='table'
    and type(STATUS.history)=='table','InkFolio: 信息状态记录损坏')
STATUS.weather=STATUS.weather or {}
assert(type(STATUS.weather)=='table','InkFolio: 天气状态记录损坏')
STATUS.write_error=nil;STATUS.log_error=nil
local RESULTS={pending='待用户确认',success='成功',partial='部分成功',failed='失败',cancelled='已取消',interrupted='已中断',cached='缓存复用'}
local function validEntry(entry,final)
    assert(type(entry)=='table' and (RESULTS[entry.result] or not final and entry.result=='running'),'InkFolio: 信息状态条目损坏')
    assert(entry.reason==nil or type(entry.reason)=='string','InkFolio: 信息状态原因损坏')
    for _,field in ipairs({'attempt_at','finished_at'}) do
        local value=entry[field]
        assert(value==nil or type(value)=='number' and value>=0 and value<math.huge,'InkFolio: 信息状态时间损坏')
    end
end
for _,records in ipairs({STATUS.books,STATUS.weather})do
    for key,entry in pairs(records)do assert(type(key)=='string','InkFolio: 信息状态标识损坏');validEntry(entry,false) end
end
assert(#STATUS.history<=20,'InkFolio: 信息状态历史超过限制')
for _,entry in ipairs(STATUS.history) do
    validEntry(entry,true)
    assert(entry.kind=='books' or entry.kind=='weather' or entry.kind=='batch','InkFolio: 信息状态历史类型损坏')
end
local function infoTime(value)
    if type(value)~='number' or value<=0 or value>=math.huge then return '未记录' end
    return os.date('%Y-%m-%d %H:%M:%S',value)
end
local function errorCategory(reason)
    if not reason or reason=='' then return '无' end
    reason=tostring(reason)
    local http=reason:match('HTTP:%s*(%d%d%d)')
    if http then return 'HTTP '..http end
    if reason:find('timed out',1,true) or reason:find('timeout',1,true) then return '请求超时' end
    if reason:find('解析',1,true) then return '解析失败' end
    if reason:find('保存',1,true) then return '保存失败' end
    if reason:find('匹配',1,true) then return '图书匹配失败' end
    if reason:find('网络未连接',1,true) then return '网络未连接' end
    if reason:find('联网已关闭',1,true) then return '联网已关闭' end
    if reason:find('subprocess',1,true) or reason:find('未启动',1,true) then return '任务启动或执行失败' end
    if reason:find('ERROR:',1,true) then return '连接或传输错误' end
    return '其他错误（原文仅本机可见）'
end
local function saveStatus()
    STATUS.write_error=nil
    local ok,reason=pcall(function()store:saveSetting('information_status',STATUS);store:flush()end)
    if not ok then STATUS.write_error='信息状态保存失败';logger.warn('InkFolio status save failed',reason)
    else STATUS.write_error=nil end
    return ok
end
function Inkfolio.debugEvent(stage,result,reason)
    if G_reader_settings:readSetting(S.debug_log)~=true then return end
    local dir=DataStorage:getSettingsDir()..'/inkfolio-diagnostics'
    local ok,err=pcall(function()
        assert(util.makePath(dir)~=false,'诊断目录无法创建')
        local path=dir..'/events.log'
        local size=lfs.attributes(path,'size') or 0
        if size>=262144 then
            os.remove(path..'.1');assert(os.rename(path,path..'.1'),'日志轮换失败')
        end
        local file=assert(io.open(path,'ab'))
        local wrote,why=file:write(infoTime(os.time()),' | ',stage,' | ',result or '', ' | ',errorCategory(reason),'\n')
        local closed=file:close();assert(wrote and closed,why or '日志写入失败')
    end)
    if not ok then STATUS.log_error='详细日志写入失败';logger.warn('InkFolio diagnostic log failed',err)
    else STATUS.log_error=nil end
end
function Inkfolio.infoAttempt(kind,key)
    local entry={attempt_at=os.time(),result='running'}
    STATUS[kind][key]=entry
    RUN.info_task={kind=kind,key=key}
    saveStatus();Inkfolio.debugEvent(kind=='weather' and '天气任务' or '图书任务','开始')
end
function Inkfolio.infoResult(kind,key,result,reason)
    local entry=STATUS[kind][key] or {}
    entry.finished_at=os.time();entry.result=result;entry.reason=reason
    STATUS[kind][key]=entry
    STATUS.history[#STATUS.history+1]={kind=kind,result=result,attempt_at=entry.attempt_at,
        finished_at=entry.finished_at,reason=reason,category=errorCategory(reason)}
    while #STATUS.history>20 do table.remove(STATUS.history,1) end
    if RUN.info_task and RUN.info_task.kind==kind and RUN.info_task.key==key then RUN.info_task=nil end
    saveStatus();Inkfolio.debugEvent(kind=='weather' and '天气任务' or '图书任务',RESULTS[result] or result,reason)
end
function Inkfolio.infoCancelled(reason)
    STATUS.history[#STATUS.history+1]={kind='batch',result='cancelled',finished_at=os.time()}
    while #STATUS.history>20 do table.remove(STATUS.history,1) end
    saveStatus();Inkfolio.debugEvent('批次任务','已取消')
end
function Inkfolio.infoStatus()return STATUS end
local function countRecords(records,predicate)
    local n=0
    for _,record in pairs(records) do if not predicate or predicate(record) then n=n+1 end end
    return n
end
-- Diagnostic records contain bounded, structured fields only. Raw error text
-- remains in this process and is never persisted or exported.
Inkfolio.diagnostics=store:readSetting('diagnostics_v2') or {events={},errors={}}
assert(type(Inkfolio.diagnostics)=='table' and type(Inkfolio.diagnostics.events)=='table'
    and type(Inkfolio.diagnostics.errors)=='table','InkFolio: 诊断记录损坏')
local REPRO_STAGES={}
for _,name in ipairs({'设置选项','UI风格','InkFolio 设置','显示内容','图书信息','阅读进度','阅读摘要','外观调整',
 '联网设置','天气城市','天气请求','天气任务','显示天气','显示日期','阅读目标','书库目录','底部文字','保存截图','开发者选项','关于','诊断信息',
 '统计说明','显示阅读摘要','摘要内容（最多2项）','周期摘要指标','阅读图表（最多2项）','全局本周','全局本月','时长＋字数','时长＋页数','周期第二项','趋势图','字数','页数','今日','本周','本月','估算已读','本次唤醒','详细日志','进度弹窗','复现记录','允许联网','更新信息','信息状态','重新匹配本书','解除本书匹配',
 '启用休眠显示','封面','评分','豆瓣月榜','预计剩余','本书已读','唤醒已读','显示摘要',
 '本书今日','本书累计','全局今日','全局累计','本周时长柱状图','本月时长柱状图',
 '小票渲染','外观保存','外观调整操作','菜单返回','菜单关闭','设置关闭','休眠','唤醒',
 '匹配认可','暂不采用','重新检索','导出预览','复制诊断','导出诊断'})do REPRO_STAGES[name]=true end
function Inkfolio.saveDiagnostics()
    local ok=pcall(function()store:saveSetting('diagnostics_v2',Inkfolio.diagnostics);store:flush()end)
    Inkfolio.diagnostics.save_error=not ok and '诊断保存失败' or nil
end
function Inkfolio.recordAction(stage)
    if G_reader_settings:readSetting(S.repro)~=true then return end
    stage=REPRO_STAGES[stage] and stage or '设置选项'
    local events=Inkfolio.diagnostics.events
    events[#events+1]={at=os.time(),stage=stage}
    while #events>60 do table.remove(events,1) end
    Inkfolio.saveDiagnostics()
end
function Inkfolio.safeFrame(source,line,name)
    local path=tostring(source or ''):gsub('\\','/')
    local file='外部调用'
    if path:find('2-inkfolio.lua',1,true) or path:find('-- InkFolio',1,true) then file='2-inkfolio.lua'
    else
        local relative=path:match('(frontend/[%w_./-]+%.lua)')
        if relative and not relative:find('..',1,true) then file=relative end
    end
    local fn=type(name)=='string' and name:match('^[%w_.:]+$') and name:sub(1,64) or '匿名函数'
    return {file=file,line=type(line)=='number' and math.max(0,math.floor(line)) or 0,fn=fn}
end
function Inkfolio.captureError(stage,err)
    local text=tostring(err)
    local code=text:find('attempt to index',1,true) and 'LUA_INDEX_ERROR'
        or text:find('attempt to call',1,true) and 'LUA_CALL_ERROR'
        or text:find('bad argument',1,true) and 'LUA_ARGUMENT_ERROR'
        or text:find('assertion',1,true) and 'LUA_ASSERTION_ERROR' or 'LUA_ERROR'
    local frames={}
    for i=2,14 do
        local info=debug.getinfo(i,'Sln')
        if not info then break end
        frames[#frames+1]=Inkfolio.safeFrame(info.source,info.currentline,info.name)
    end
    local errors=Inkfolio.diagnostics.errors
    errors[#errors+1]={at=os.time(),stage=REPRO_STAGES[stage] and stage or '设置选项',code=code,frames=frames}
    while #errors>10 do table.remove(errors,1) end
    Inkfolio.lastPrivateError=text
    Inkfolio.saveDiagnostics()
end
local guardDepth=0
function Inkfolio.guard(stage,fn,...)
    Inkfolio.recordAction(stage)
    if guardDepth>0 then return fn(...) end
    guardDepth=guardDepth+1
    local arguments={n=select('#',...),...};local results
    local ok,err=xpcall(function()results={n=0};local function collect(...)results={n=select('#',...),...}end
        collect(fn(unpack(arguments,1,arguments.n)))
    end,function(e)
        local captured=pcall(Inkfolio.captureError,stage,e)
        if not captured then Inkfolio.diagnostics.save_error='异常记录失败' end
        return e
    end)
    guardDepth=guardDepth-1
    if not ok then error(err,0) end -- preserve original failure, never pretend success
    return unpack(results,1,results.n)
end
function Inkfolio.diagnosticContextText()
    local function capability(obj,method)
        if type(obj[method])~='function' then return '接口不可用' end
        local ok,value=pcall(obj[method],obj)
        return ok and tostring(value) or '读取失败'
    end
    local lines={'屏幕方向：'..(Screen:getWidth()>Screen:getHeight() and '横屏' or '竖屏'),
        '屏幕DPI：'..capability(Screen,'getDPI'),'界面缩放（100单位）：'..capability({read=function()return Screen:scaleBySize(100)end},'read'),
        '休眠显示支持：'..capability(Device,'supportsScreensaver'),
        '休眠显示选择：'..(G_reader_settings:readSetting('screensaver_type')=='book_receipt' and 'InkFolio' or '其他'),
        '外观宽度：'..tostring(G_reader_settings:readSetting(S.width) or .72),
        '字号倍率：'..tostring(G_reader_settings:readSetting(S.font) or 1),
        '整体比例：'..tostring(G_reader_settings:readSetting(S.scale) or 1),
        '背景：'..tostring(G_reader_settings:readSetting(S.background) or 'white'),
        '首次比例适配：'..(G_reader_settings:readSetting(S.auto_fit)==true and '等待图书数据' or '未待处理'),
        '进度弹窗：'..(enabled(S.progress) and '开启' or '关闭'),
        '复现记录：'..(G_reader_settings:readSetting(S.repro)==true and '开启' or '关闭'),
        '诊断保存：'..(Inkfolio.diagnostics.save_error or '未发现错误')}
    for _,item in ipairs({{'封面',S.cover},{'评分',S.score},{'豆瓣月榜',S.intro},{'阅读摘要',S.stats}})do
        lines[#lines+1]=item[1]..'：'..(enabled(item[2]) and '开启' or '关闭')
    end
    for _,item in ipairs({{'估算已读',S.word_book},{'本次唤醒',S.word_session},{'预计剩余',S.remain}})do
        lines[#lines+1]=item[1]..'：'..(Inkfolio.progressEnabled(item[2]) and '开启' or '关闭')
    end
    if Inkfolio.lastLayout then
        local d=Inkfolio.lastLayout
        lines[#lines+1]=string.format('最近小票尺寸：%d×%d；屏幕：%d×%d；%s',d.width,d.height,d.screen_w,d.screen_h,d.valid and '完整适屏' or '超出屏幕')
    else lines[#lines+1]='最近小票尺寸：未渲染' end
    local selected=G_reader_settings:readSetting(S.summary) or {}
    local labels={book_today='本书今日',book_total='本书累计',global_today='今日阅读',global_week='本周阅读',global_month='本月阅读',global_total='全局累计'}
    local summaries={};for _,id in ipairs(selected)do if labels[id] then summaries[#summaries+1]=labels[id] end end
    lines[#lines+1]='摘要组合：'..table.concat(summaries,'、')
    lines[#lines+1]='周期摘要指标：时长＋'..(Inkfolio.summaryMetric()=='words' and '字数' or '页数')
    local charts={};for _,item in ipairs(Inkfolio.chartItems())do charts[#charts+1]=item.label end
    lines[#lines+1]='阅读图表：'..(#charts>0 and table.concat(charts,'、') or '关闭')
    lines[#lines+1]='每日记录保存：'..(Inkfolio.wordState.storage_error or '未发现错误')
    local theme=Inkfolio.uiStyle()
    lines[#lines+1]='UI风格：'..theme.label
    for _,file in ipairs(theme.assets)do
        local ok,face=pcall(Font.getFace,Font,file,20)
        lines[#lines+1]='界面字体 '..file..'：'..(ok and face and '可加载' or '无法加载')
    end
    local icon=require('ui/widget/iconwidget'):new{icon='appbar.tools'}
    lines[#lines+1]='工具图标：'..(icon.file and not icon.file:find('icon-not-found',1,true) and '可加载' or '缺失')
    icon:free()
    local ui=ReaderUI.instance
    lines[#lines+1]='当前界面：'..(ui and ui.document and '阅读' or '非阅读')
    local file=ui and ui.document and ui.document.file
    local format=file and file:match('%.([%w]+)$')
    local formats={epub=true,pdf=true,mobi=true,azw=true,azw3=true,fb2=true,txt=true,rtf=true,djvu=true,cbz=true,cbr=true,html=true,htm=true,md=true,doc=true,docx=true,pdb=true,prc=true,xps=true,zip=true}
    format=format and format:lower()
    lines[#lines+1]='当前图书格式：'..(formats[format] and format:upper() or file and '其他格式' or '无当前图书')
    lines[#lines+1]='复现操作（最多60条）：'
    for _,e in ipairs(Inkfolio.diagnostics.events)do
        lines[#lines+1]=infoTime(e.at)..' | '..(REPRO_STAGES[e.stage] and e.stage or '设置选项')
    end
    lines[#lines+1]='InkFolio异常（最多10条）：'
    for _,e in ipairs(Inkfolio.diagnostics.errors)do
        local codes={LUA_INDEX_ERROR=true,LUA_CALL_ERROR=true,LUA_ARGUMENT_ERROR=true,LUA_ASSERTION_ERROR=true,LUA_ERROR=true}
        lines[#lines+1]=infoTime(e.at)..' | '..(REPRO_STAGES[e.stage] and e.stage or '设置选项')..' | '..(codes[e.code] and e.code or 'LUA_ERROR')
        for _,f in ipairs(e.frames or {})do
            local safe=Inkfolio.safeFrame(f.file,f.line,f.fn)
            lines[#lines+1]=safe.file..':'..safe.line..' '..safe.fn
        end
    end
    if #Inkfolio.diagnostics.errors==0 then lines[#lines+1]='没有InkFolio异常记录；启动或原生崩溃可能需要脱敏crash.log。' end
    return table.concat(lines,'\n')
end
function Inkfolio.previewDiagnostics()
    Inkfolio.recordAction('导出预览')
    UIManager:show(require('ui/widget/textviewer'):new{title='诊断导出预览（脱敏）',text=Inkfolio.diagnosticText(false),
        justified=false,show_menu=false,add_default_buttons=true,
        buttons_table={{{text='复制',callback=Inkfolio.copyDiagnostics},{text='导出',callback=Inkfolio.exportDiagnostics}}}})
end

function Inkfolio.diagnosticText(private)
    local ok,revision=pcall(function()return require('version'):getCurrentRevision()end)
    local goal=Inkfolio.goalConfig()
    local lines={
        'InkFolio诊断报告（默认脱敏）','InkFolio版本：v'..VERSION,
        '构建标识：'..BUILD_ID,
        'KOReader版本：'..(ok and tostring(revision) or '读取失败'),
        '设备：'..tostring(Device.model or '未提供'),'分辨率：'..Screen:getWidth()..'×'..Screen:getHeight(),
        '允许联网：'..(networkingEnabled() and '是' or '否'),
        '网络连接：'..(connected() and '已连接' or '未连接'),
        '阅读目标：'..(goal.enabled and '启用' or '停用')..' · '..goal.period..' · '..goal.metric,
        '目标值：'..Inkfolio.goalTargetText(goal),
        '网络任务：'..(RUN.sleeping and '休眠中' or RUN.worker and '请求执行中' or RUN.active and '任务进行中' or '空闲'),
        '任务类型：'..(RUN.worker and RUN.worker.kind=='monthly' and '豆瓣月榜' or RUN.info_task and (RUN.info_task.kind=='weather' and '天气' or '图书') or '无'),
        '当前请求阶段：'..(RUN.worker and RUN.request_stage or '无'),
        '图书任务进度：'..(RUN.active and ((RUN.total or 0)>0 and tostring(RUN.done or 0)..' / '..RUN.total or '扫描中，尚未确定总数') or '无进行中的图书任务'),
        '图书缓存条目：'..countRecords(CACHE),
        '待确认图书：'..Inkfolio.pendingCount(),
        '用户确认匹配关系：'..countRecords(Inkfolio.matchState.choices),
        '含有效评分的缓存：'..countRecords(CACHE,function(r)return type(r)=='table' and tonumber(r.rating) and tonumber(r.rating)>0 and tonumber(r.rating)<=10 and validURL(r.url)end),
        '含缓存简介的条目：'..countRecords(CACHE,function(r)return type(r)=='table' and type(r.intro)=='string' and r.intro~=''end),
        '月榜分类：'..Inkfolio.monthlyCategory().label,
        '月榜锁屏轮换：'..(G_reader_settings:readSetting(S.monthly_rotate)==true and '开启' or '关闭'),
        '月榜显示位置：'..tostring(Inkfolio.monthly.cursor or 1),
        '月榜缓存：'..(Inkfolio.monthly.record and Inkfolio.validMonthly(Inkfolio.monthly.record) and
            string.format('%d年%d月',Inkfolio.monthly.record.year,Inkfolio.monthly.record.month) or '无有效缓存'),
        '月榜最近尝试：'..infoTime(Inkfolio.monthly.attempt_at),
        '月榜最近结果：'..tostring(Inkfolio.monthly.result or '未获取'),
        '月榜错误：'..(private and tostring(Inkfolio.monthly.error or '无') or errorCategory(Inkfolio.monthly.error)),
        '详细日志：'..(G_reader_settings:readSetting(S.debug_log)==true and '开启' or '关闭'),
        '记录保存状态（本次运行）：'..(STATUS.write_error or '未发现保存错误'),
        '日志写入状态（本次运行）：'..(STATUS.log_error or '未发现写入错误'),
        '当前运行错误：'..(private and tostring(RUN.last_error or RUN.last_book_error or '无') or errorCategory(RUN.last_error or RUN.last_book_error)),
        '最近任务结果（最多20条）：',
    }
    for i=#STATUS.history,1,-1 do
        local e=STATUS.history[i]
        lines[#lines+1]=infoTime(e.finished_at)..' | '..(e.kind=='books' and '图书' or e.kind=='weather' and '天气' or '批次')..' | '..(RESULTS[e.result] or e.result)
            ..' | '..(private and tostring(e.reason or '无') or errorCategory(e.reason))
    end
    if #STATUS.history==0 then lines[#lines+1]='尚无任务记录' end
    for i=#STATUS.history,1,-1 do
        local e=STATUS.history[i]
        if e.result=='failed' or e.result=='partial' then
            lines[#lines+1]='最近失败（历史记录）：'..infoTime(e.finished_at)..' | '..(private and tostring(e.reason or '未记录具体原因') or errorCategory(e.reason))
            break
        end
    end
    lines[#lines+1]=Inkfolio.diagnosticContextText()
    if private and Inkfolio.lastPrivateError then lines[#lines+1]='本次InkFolio异常原文（仅本机）：'..Inkfolio.lastPrivateError end
    lines[#lines+1]='复制内容可能仅进入设备内部剪贴板；向手机反馈请导出报告。'
    if private then lines[1]='InkFolio诊断信息（错误原文仅本机显示，复制／导出均脱敏）' end
    return table.concat(lines,'\n')
end
function Inkfolio.copyDiagnostics()
    Inkfolio.recordAction('复制诊断')
    if type(Device.hasClipboard)~='function' or not Device:hasClipboard() or not Device.input or type(Device.input.setClipboardText)~='function' then
        Inkfolio.message('此设备的剪贴板接口不可用，请导出诊断报告。');return false
    end
    local ok,reason=pcall(Device.input.setClipboardText,Inkfolio.diagnosticText(false))
    if ok and reason==false then ok=false;reason='剪贴板拒绝写入' end
    Inkfolio.message(ok and '已复制脱敏诊断信息到设备剪贴板，可能仅在本设备内可粘贴。' or '复制失败：'..tostring(reason))
    return ok
end
function Inkfolio.exportDiagnostics()
    Inkfolio.recordAction('导出诊断')
    local dir=DataStorage:getSettingsDir()..'/inkfolio-diagnostics'
    local path
    local ok,err=pcall(function()
        assert(util.makePath(dir)~=false,'诊断目录无法创建')
        local stem=dir..'/Inkfolio-diagnostic-'..os.date('%Y%m%d-%H%M%S')
        local n=0;path=stem..'.txt'
        while lfs.attributes(path) do n=n+1;path=stem..'-'..n..'.txt' end
        local file=assert(io.open(path,'wb'))
        local wrote,why=file:write(Inkfolio.diagnosticText(false));local closed=file:close()
        assert(wrote and closed,why or '报告写入失败')
    end)
    if not ok then if path then os.remove(path)end;Inkfolio.message('诊断报告导出失败：'..tostring(err));return false end
    Inkfolio.message('已导出脱敏报告：\n'..path);return path
end
function Inkfolio.showDiagnostics()
    local viewer
    local function open()
        if viewer then UIManager:close(viewer)end
        viewer=require('ui/widget/textviewer'):new{title='InkFolio诊断信息',text=Inkfolio.diagnosticText(true),
            text_selection_callback=function()Inkfolio.message('错误原文不复制，请使用“复制”按钮获取脱敏报告。')end,
            justified=false,show_menu=false,add_default_buttons=true,
            buttons_table={{ {text='刷新',callback=open},{text='复制',enabled=type(Device.hasClipboard)=='function' and Device:hasClipboard(),callback=Inkfolio.copyDiagnostics},
                {text='导出预览',callback=Inkfolio.previewDiagnostics} }} }
        UIManager:show(viewer)
    end
    open()
end
function Inkfolio.informationText(ui)
    local lines={'当前图书信息','允许联网：'..(networkingEnabled() and '是' or '否'),'网络连接：'..(connected() and '已连接' or '未连接')}
    if ui and ui.document then
        local book=extractBook(ui.doc_props,ui.document.file);local record=cached(book)
        lines[#lines+1]='书名：'..book.title
        local identity=Inkfolio.searchIdentity(book)
        lines[#lines+1]='搜索书名：'..identity.query..(Inkfolio.searchOverride(book) and '（自定义）' or '（默认）')
        lines[#lines+1]='书名依据：'..identity.source
        if identity.note then lines[#lines+1]='书名检查：'..identity.note end
        local pending=Inkfolio.matchState.pending[Inkfolio.fileMatchKey(book)]
        if pending then lines[#lines+1]='匹配状态：待用户确认（'..#pending.candidates..'个候选）；'..tostring(pending.reason or '') end
        if record then
            lines[#lines+1]='身份核验：'..(record.user_confirmed and '用户确认匹配' or record.identity_version==2 and '详情页核验' or '历史缓存，未经新规则核验')
            if record.matched_title then lines[#lines+1]='匹配图书：'..record.matched_title end
            if record.identity_sources then for _,url in ipairs(record.identity_sources)do lines[#lines+1]='核验来源：'..url end end
        end
        if record and not Inkfolio.cacheMatches(book,record) then lines[#lines+1]='缓存状态：搜索书名或卷册范围已变化，待重新获取' end
        if record then
            lines[#lines+1]='评分：'..record.rating..'/10；'..(record.score_kind=='volumes' and ('已匹配分册均分（'..#record.matched_volumes..'册）') or ('参与平均版本：'..tostring(record.rated_versions or '未记录')))
            if record.score_kind=='volumes' then
                for _,v in ipairs(record.matched_volumes) do lines[#lines+1]=string.format('%s均分：%.2f/10；已匹配版本：%d',type(v.volume)=='number' and ('第'..v.volume..'册') or v.volume,v.rating,v.versions) end
            end
            lines[#lines+1]='评分最近成功：'..infoTime(record.rating_updated_at)
            if type(record.rating_sources)=='table' then
                for _,source in ipairs(record.rating_sources)do lines[#lines+1]='评分来源：'..source.via..(source.volume and (' 第'..source.volume..'册') or '')..(source.title and (' · '..source.title) or '')..' | '..source.rating..' | '..source.url end
            else lines[#lines+1]='评分来源：存在豆瓣链接，具体评分来源明细未记录' end
        else lines[#lines+1]='评分：尚无有效缓存' end
        if book.description~='' then
            lines[#lines+1]='简介来源：书籍文件内元数据（没有联网获取时间）'
        elseif record and record.intro and record.intro~='' then
            lines[#lines+1]='简介来源：'..(record.intro_source and '豆瓣详情页 '..record.intro_source or '历史缓存，来源未记录')
            if record.intro_volume then lines[#lines+1]='简介取自：'..(type(record.intro_volume)=='number' and ('第'..record.intro_volume..'册') or record.intro_volume)..'（'..tostring(record.intro_title or '标题未记录')..'），不代表全集简介' end
            lines[#lines+1]='简介最近成功：'..infoTime(record.intro_updated_at)
        else lines[#lines+1]='简介：'..(record and record.intro_state=='absent' and '来源确认没有简介' or record and record.intro_state=='failed' and '字段获取失败，允许重试' or '尚无可显示内容') end
        if record then lines[#lines+1]='缓存记录时间：'..infoTime(record.updated_at)..'（旧记录不等于各字段的成功时间）' end
        local status=STATUS.books[bookKey(book)]
        if status then
            lines[#lines+1]='最近尝试：'..infoTime(status.attempt_at)
            local active=RUN.info_task and RUN.info_task.kind=='books' and RUN.info_task.key==bookKey(book)
            lines[#lines+1]='最近结果：'..(status.result=='running' and (active and '获取中' or '上次任务未完成') or RESULTS[status.result])
            lines[#lines+1]='原因：'..tostring(status.reason or '无')
        else lines[#lines+1]='最近尝试：未记录' end
    else lines[#lines+1]='尚无最近阅读书籍' end
    local chart=Inkfolio.monthly.record
    lines[#lines+1]='\n月榜来源：豆瓣读书 · '..Inkfolio.monthlyCategory().label..'月榜'
    lines[#lines+1]='锁屏轮换：'..(G_reader_settings:readSetting(S.monthly_rotate)==true and '开启' or '关闭')
    lines[#lines+1]='榜单月份：'..(chart and Inkfolio.validMonthly(chart) and string.format('%d年%d月',chart.year,chart.month) or '暂无有效缓存')
    lines[#lines+1]='来源链接：'..(chart and Inkfolio.validMonthly(chart) and chart.url or Inkfolio.monthlyURL())
    lines[#lines+1]='最近成功：'..infoTime(chart and chart.updated_at)
    lines[#lines+1]='最近尝试：'..infoTime(Inkfolio.monthly.attempt_at)
    lines[#lines+1]='最近结果：'..tostring(Inkfolio.monthly.result or '未获取')
    lines[#lines+1]='原因：'..tostring(Inkfolio.monthly.error or '无')
    local city=selectedWeatherCity()
    lines[#lines+1]='\n天气来源：中国气象局中央气象台（nmc.cn）'
    if city then
        local record=WEATHER.records[city.code];local status=STATUS.weather[city.code]
        lines[#lines+1]='城市：'..city.name
        lines[#lines+1]='最近成功：'..infoTime(record and record.updated_at)
        lines[#lines+1]='最近尝试：'..infoTime(status and status.attempt_at)
        local active=RUN.info_task and RUN.info_task.kind=='weather' and RUN.info_task.key==city.code
        lines[#lines+1]='最近结果：'..(status and (status.result=='running' and (active and '获取中' or '上次任务未完成') or RESULTS[status.result]) or '未记录')
        lines[#lines+1]='缓存获取日期：'..tostring(record and record.day or '未记录')
        for offset=0,1 do
            local date=Inkfolio.weatherDate(offset)
            lines[#lines+1]=(offset==0 and '今日预报：' or '明日预报：')..date..' · '..(Inkfolio.cachedWeather(record,date) or '暂无有效缓存')
        end
        lines[#lines+1]='原因：'..tostring(status and status.reason or '无')
    else lines[#lines+1]='未选择城市' end
    return table.concat(lines,'\n')
end
function Inkfolio.showInformation()
    local viewer
    local function open()
        if viewer then UIManager:close(viewer) end
        viewer=require('ui/widget/textviewer'):new{title='信息来源与状态',text=Inkfolio.informationText(Inkfolio.context()),
            justified=false,show_menu=false,add_default_buttons=true,
            buttons_table={{{text='刷新',callback=open}}}}
        UIManager:show(viewer)
    end
    open()
end

local SUMMARY_ITEMS = {
    {id='book_today',label='本书今日',period='day',legacy=true},
    {id='global_today',label='今日阅读',period='day',global=true},
    {id='global_week',label='本周阅读',period='week',global=true},
    {id='global_month',label='本月阅读',period='month',global=true},
    {id='book_total',label='本书累计'},
    {id='global_total',label='全局累计',global=true},
}
function Inkfolio.deviceDefaults()
    local sw,sh=Screen:getWidth(),Screen:getHeight()
    return {width=math.min(sw,sh)>=1000 and .78 or .84,scale=sw>sh and .90 or .95}
end
function Inkfolio.initializeDefaults(existing)
    if existing then return end
    local d=Inkfolio.deviceDefaults()
    for key,value in pairs({[S.width]=d.width,[S.scale]=d.scale,[S.summary]={'global_today'},[S.summary_metric]='words',
        [S.word_book]=false,[S.word_session]=false,[S.remain]=true,
        [S.progress]=false,[S.background]='black',[S.auto_fit]=true,[S.repro]=false}) do
        G_reader_settings:saveSetting(key,value)
    end
end
Inkfolio.initializeDefaults(previous_install)
if G_reader_settings:readSetting(P..'qr')~=nil then
    G_reader_settings:delSetting(P..'qr')
    G_reader_settings:flush()
end
-- Existing summaries displayed pages. Preserve that secondary metric on upgrade.
if G_reader_settings:readSetting(S.summary_metric)==nil then G_reader_settings:saveSetting(S.summary_metric,previous_install and 'pages' or 'words') end
function Inkfolio.summaryMetric()
    local metric=G_reader_settings:readSetting(S.summary_metric)
    assert(metric=='words' or metric=='pages','摘要指标设置无效')
    return metric
end
local PROGRESS_ITEMS={
    {key=S.word_book,label='估算已读'},
    {key=S.word_session,label='本次唤醒'},
    {key=S.remain,label='预计剩余'},
}
function Inkfolio.progressEnabled(key)
    local value=G_reader_settings:readSetting(key)
    return value==true or (key==S.remain and value==nil)
end
function Inkfolio.progressCount()
    local n=0
    for _,item in ipairs(PROGRESS_ITEMS) do if Inkfolio.progressEnabled(item.key) then n=n+1 end end
    return n
end
-- beta.3 treated unset word switches as enabled. Preserve that preference first.
if previous_install then
    for _,key in ipairs({S.word_book,S.word_session}) do
        if G_reader_settings:readSetting(key)==nil then G_reader_settings:saveSetting(key,true) end
    end
end
-- beta.3 allowed all three. Preserve remaining-time then book count on that upgrade.
if Inkfolio.progressCount()>2 then G_reader_settings:saveSetting(S.word_session,false) end

Inkfolio.CHART_ITEMS={
    {id='week',label='本周时长柱状图',title='本周全局阅读时长',period='week',metric='time'},
    {id='month',label='本月时长柱状图',title='本月全局阅读时长',period='month',metric='time'},
    {id='week_words',label='本周字数柱状图',title='本周全局阅读字数',period='week',metric='words'},
    {id='month_words',label='本月字数柱状图',title='本月全局阅读字数',period='month',metric='words'},
}
function Inkfolio.chartItems()
    local chosen=G_reader_settings:readSetting(S.charts)
    if chosen==nil then
        local old=G_reader_settings:readSetting(S.curve)
        chosen=(old=='week' or old=='month') and {old} or {}
        G_reader_settings:saveSetting(S.charts,chosen)
    end
    assert(type(chosen)=='table' and #chosen<=2,'阅读图表设置无效')
    -- Remove the retired development chart while preserving other selections.
    local retained={}
    for _,id in ipairs(chosen) do if id~='month_heatmap' then retained[#retained+1]=id end end
    if #retained~=#chosen then chosen=retained;G_reader_settings:saveSetting(S.charts,chosen) end
    local items,seen={},{}
    for _,id in ipairs(chosen) do
        assert(not seen[id],'阅读图表设置重复');seen[id]=true
        local found
        for _,item in ipairs(Inkfolio.CHART_ITEMS) do if item.id==id then found=item;break end end
        assert(found,'阅读图表选项无效');items[#items+1]=found
    end
    return items
end

local function summaryItems()
    local chosen = G_reader_settings:readSetting(S.summary)
    if chosen == nil then
        chosen = {
            G_reader_settings:readSetting(S.global_today)==true and 'global_today' or 'book_today',
            G_reader_settings:readSetting(S.global_total)==true and 'global_total' or 'book_total',
        }
        G_reader_settings:saveSetting(S.summary,chosen)
    end
    local result={}
    -- Stable order: legacy today, global day/week/month, then lifetime scopes.
    for _,item in ipairs(SUMMARY_ITEMS) do
        for _,id in ipairs(chosen) do
            if id==item.id then result[#result+1]=item;break end
        end
    end
    assert(#result==#chosen and #chosen<=2,'Invalid reading-summary selection')
    return result
end

-- Read native recorded durations, not page counts or estimated time.
function Inkfolio.periodDays(period,now)
    assert(period=='day' or period=='week' or period=='month','统计周期无效')
    now=now or os.time()
    local clock=os.date('*t',now)
    local first={year=clock.year,month=clock.month,
        day=period=='day' and clock.day or period=='week' and (clock.day-(clock.wday+5)%7) or 1,
        hour=0,min=0,sec=0,isdst=nil}
    local first_time=os.time(first)
    local last=period=='day' and {year=first.year,month=first.month,day=first.day+1,hour=0}
        or period=='week' and {year=first.year,month=first.month,day=first.day+7,hour=0}
        or {year=clock.year,month=clock.month+1,day=1,hour=0}
    local end_time=os.time(last)
    local days={}
    local date=os.date('*t',first_time)
    while true do
        local start=os.time{year=date.year,month=date.month,day=date.day,hour=0,min=0,sec=0,isdst=nil}
        if start>=end_time then break end
        local finish=os.time{year=date.year,month=date.month,day=date.day+1,hour=0,min=0,sec=0,isdst=nil}
        days[#days+1]={start=start,finish=finish,day=date.day,future=start>now}
        date=os.date('*t',finish)
    end
    return days,first_time,end_time,now
end
-- Load native records once per render; no second statistics database or counters.
function Inkfolio.timeRecords(ui,first,now)
    local stats=ui and ui.statistics
    if not stats or (stats.isEnabled and not stats:isEnabled()) then return nil,'请开启 KOReader 阅读统计' end
    if stats.insertDB and not pcall(stats.insertDB,stats) then return nil,'阅读统计保存失败' end
    if lfs.attributes(STATS_PATH,'mode')~='file' then return nil,'暂无阅读统计数据库' end
    local opened,db=pcall(SQ3.open,STATS_PATH)
    if not opened or not db then return nil,'阅读统计无法打开' end
    local ok,rows=pcall(db.exec,db,string.format(
        'SELECT start_time,duration,id_book FROM page_stat_data WHERE duration>=0 AND start_time<%d AND start_time+duration>=%d;',now+1,first))
    db:close()
    if not ok then logger.warn('InkFolio statistics query failed',rows);return nil,'阅读时长读取失败' end
    return rows or {}
end
function Inkfolio.readCurve(ui,period,now,records,id)
    if period~='day' and period~='week' and period~='month' then return nil,'时长统计周期无效' end
    local days,first,_,clock=Inkfolio.periodDays(period,now)
    local reason
    if not records then records,reason=Inkfolio.timeRecords(ui,first,clock) end
    if not records then return nil,reason end
    for i,start in ipairs(records[1] or {}) do
        if not id or tonumber(records[3][i])==id then
            local stamp=assert(tonumber(start),'无效统计时间')
            local seconds=assert(tonumber(records[2][i]),'无效统计时长')
            local finish=math.min(stamp+seconds,clock+1)
            if finish>first or (seconds==0 and stamp>=first) then for _,day in ipairs(days) do
                local overlap=math.max(0,math.min(finish,day.finish)-math.max(stamp,day.start))
                if not day.future and (overlap>0 or (seconds==0 and stamp>=day.start and stamp<day.finish)) then
                    day.seconds=(day.seconds or 0)+overlap
                end
            end end
        end
    end
    local total,elapsed,missing,known=0,0,0,0
    for _,day in ipairs(days) do
        if not day.future then
            elapsed=elapsed+1
            if day.seconds~=nil then total=total+day.seconds;known=known+1 else missing=missing+1 end
        end
    end
    return {period=period,days=days,total=total,average=known>0 and total/elapsed or nil,
        elapsed=elapsed,known=known,missing=missing}
end

local function duration(value)
    if value == nil then return '—' end
    local n = math.max(0, math.floor(tonumber(value) or 0))
    local hours, minutes = math.floor(n/3600), math.floor(n%3600/60)
    if hours > 0 then return string.format('%d时%d分',hours,minutes) end
    return string.format('%d分钟', minutes)
end
local function scoreStars(score)
    local half = math.max(0, math.min(10, math.floor(score + 0.5))) -- /10 -> 0..10 half-stars
    local full = math.floor(half/2)
    return string.rep('★', full) .. string.rep('☆', 5-full)
end

-- Only promote v1.1 records whose link AND rating were actually collected.
if store:readSetting('migrated_v11') ~= true then
    local old = G_reader_settings:readSetting('book_receipt_douban_cache_v11') or {}
    for key, row in pairs(old) do
        if type(key) == 'string' and type(row) == 'table'
           and validURL(row.url) and tonumber(row.rating) and tonumber(row.rating) > 0 then
            CACHE[key] = {rating = tonumber(row.rating), url = row.url,
                          intro = row.intro, rated_versions = row.rated_versions or 1}
        end
    end
    store:saveSetting('migrated_v11', true)
    saveData()
end

-- Earlier keys accidentally included gsub's replacement count: title|author|0.
-- Remove that extra numeric field; a current-key record takes precedence.
if store:readSetting('cache_schema') ~= 261 then
    local keys = {}
    for key in pairs(CACHE) do keys[#keys+1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local current = key:match('^([^|]*|[^|]*)|%d+$')
        if current then
            if CACHE[current] == nil then CACHE[current] = CACHE[key] end
            CACHE[key] = nil
        end
    end
    store:saveSetting('cache_schema', 261)
    DAILY_DONE, ROUNDS = false, 0
    saveData()
end

-- Fixed-size native dialog: dirty only its own rectangle, at most once per five seconds.
local PROGRESS={active=false,hidden=false,phase='',scanning=true,total=0,done=0,book=''}
local progressTick, cancelFetch
local function progressText()
    local lines={PROGRESS.title or '获取信息'}
    if PROGRESS.scanning then
        lines[#lines+1]='正在扫描书库'
        if PROGRESS.scan_total then lines[#lines+1]=string.format('%d / %d 个文件',PROGRESS.scan_done or 0,PROGRESS.scan_total) end
    elseif not PROGRESS.weather_only then
        lines[#lines+1]=string.format('已处理 %d / %d 本',PROGRESS.done,PROGRESS.total)
        lines[#lines+1]=string.format('已更新 %d 本，未完整获取 %d 本',RUN.processed or 0,RUN.failed or 0)
    end
    if PROGRESS.book~='' then lines[#lines+1]=shortText(PROGRESS.book,38) end
    if not PROGRESS.scanning or PROGRESS.phase~='正在扫描书库' then lines[#lines+1]=PROGRESS.phase end
    return table.concat(lines,'\n')
end
local function progressClose()
    local popup=PROGRESS.popup
    PROGRESS.popup=nil
    if popup then UIManager:close(popup) end
    if progressTick then UIManager:unschedule(progressTick) end
end
local function progressIgnore()
    PROGRESS.hidden=true
    progressClose()
end
local function progressPaint(force)
    if not PROGRESS.active or PROGRESS.hidden or not enabled(S.progress) then return end
    local now=os.time()
    if not force and PROGRESS.last_paint and now-PROGRESS.last_paint<5 then return end
    local text=progressText()
    if PROGRESS.popup then
        if text~=PROGRESS.last_text then
            PROGRESS.popup.text_widget:setText(text)
            UIManager:setDirty(PROGRESS.popup,'ui',PROGRESS.popup.frame.dimen)
        end
    else
        local ButtonTable=require('ui/widget/buttontable')
        local Popup=InputContainer:extend{modal=true,name='read_receipt_progress'}
        function Popup:init()
            local width=math.floor(math.min(Screen:getWidth(),Screen:getHeight())*.8)
            local point_size=math.max(10,math.floor(20*math.min(1,Screen:getHeight()/Screen:scaleBySize(620))))
            local face=Font:getFace('infofont',point_size)
            self.text_widget=TextBoxWidget:new{
                text=text,face=face,width=width,justified=false,line_height=.3,
                height=math.floor(face.size*1.3+0.5)*7,height_adjust=false,
                height_overflow_show_ellipsis=true,
            }
            self.frame=FrameContainer:new{background=Blitbuffer.COLOR_WHITE,
                bordersize=Screen:scaleBySize(1),padding=Screen:scaleBySize(12),margin=0,
                VerticalGroup:new{
                    self.text_widget,
                    ButtonTable:new{width=width,buttons={{
                        {text='忽略',callback=progressIgnore},
                        {text='取消',callback=function() cancelFetch() end},
                    }}},
                },
            }
            self[1]=CenterContainer:new{dimen=Screen:getSize(),self.frame}
            if Device:hasKeys() then self.key_events.Ignore={{Device.input.group.Back}} end
        end
        function Popup:onShow()
            UIManager:setDirty(self,function() return 'ui',self.frame.dimen end)
            return true
        end
        function Popup:onIgnore() progressIgnore();return true end
        function Popup:onCloseWidget()
            UIManager:setDirty(nil,function() return 'ui',self.frame.dimen end)
            if PROGRESS.popup==self then
                PROGRESS.popup=nil;PROGRESS.hidden=true;UIManager:unschedule(progressTick)
            end
        end
        PROGRESS.popup=Popup:new{}
        UIManager:show(PROGRESS.popup,'ui')
    end
    PROGRESS.last_paint,PROGRESS.last_text=now,text
end
progressTick=function()
    if not PROGRESS.active or PROGRESS.hidden then return end
    progressPaint(false)
    UIManager:scheduleIn(5,progressTick)
end
local function progressBegin(manual,weather_only)
    progressClose()
    PROGRESS.active,PROGRESS.hidden,PROGRESS.scanning=true,not enabled(S.progress),not weather_only
    PROGRESS.weather_only=weather_only
    PROGRESS.title=weather_only and '获取天气信息' or (manual and '手动获取图书信息' or '自动获取图书信息')
    PROGRESS.total,PROGRESS.done,PROGRESS.book=0,0,''
    PROGRESS.phase=weather_only and '正在请求天气' or '正在扫描书库'
    PROGRESS.scan_done,PROGRESS.scan_total,PROGRESS.last_paint,PROGRESS.last_text=nil,nil,nil,nil
    progressPaint(true)
    if not PROGRESS.hidden then UIManager:scheduleIn(5,progressTick) end
end
local function progressStage(phase)
    RUN.phase=phase
    if PROGRESS.active then PROGRESS.phase=phase end
end
local function progressEnd(message,silent)
    local visible=PROGRESS.active and not PROGRESS.hidden and enabled(S.progress)
    PROGRESS.active=false
    progressClose()
    if visible and not silent then
        UIManager:show(require('ui/widget/infomessage'):new{text=message,timeout=8})
    end
end

local function authorNames(value)
    local names = {}
    local s = tostring(value or ''):gsub('%b[]', ''):gsub('【.-】', '')
        :gsub('（.-）', ''):gsub('%b()', '')
        :gsub('，', ';'):gsub('；', ';'):gsub('｜',';'):gsub('[,;|/\n]', ';')
    for name in s:gmatch('[^;]+') do
        name = util.trim(name)
        -- Explicit translator roles are contributors, not author identity.
        if not name:match('译$') and not name:match('译者') then
            name = util.trim(name:gsub('著$', ''))
            if normalize(name) ~= '' then names[#names+1] = name end
        end
    end
    return names
end

local function displayTitle(value)
    local title=util.trim(tostring(value or ''))
    -- Only balanced brackets are removed. Volume markers remain part of identity.
    local volume={['上']=true,['中']=true,['下']=true,['上册']=true,['中册']=true,
        ['下册']=true,['上卷']=true,['中卷']=true,['下卷']=true}
    local work=title:gsub('（','('):gsub('）',')'):gsub('【','['):gsub('】',']')
    local function bracket(part)
        local inside=util.trim(part:sub(2,-2))
        if volume[inside] or inside:match('^%d+$') or inside:match('^第.-册$') or inside:match('^第.-卷$') then return part end
        return ''
    end
    local clean=util.trim(work:gsub('%b()',bracket):gsub('%b[]',bracket))
    if clean=='' or normalize(clean)==normalize(title) then return title end
    return clean
end

local function searchTitle(value)
    local title=util.trim(tostring(value or ''))
    local clean=displayTitle(title)
    -- Collection counts are edition qualifiers, not title identity.
    local prefix,count=clean:match('^(.*)全(.-)册$')
    if count and count~='' then
        local digits=count:gsub('%d','')
        for _,word in ipairs({'一','二','三','四','五','六','七','八','九','十','百'}) do digits=digits:gsub(word,'') end
        if digits=='' then clean=util.trim(prefix) end
    end
    -- Preserve original punctuation when no qualifier was removed.
    if clean=='' or normalize(clean)==normalize(title) then return title end
    return clean
end

-- Explicit collection declarations and printed volume ranges determine scope.
function Inkfolio.collectionInfo(book)
    local metadata=searchTitle(book.title)
    local filename=book.path and book.path:match('([^/]+)%.[^%.]+$') or ''
    local first,last
    local scope_parts={}
    filename=filename:gsub('（','('):gsub('）',')')
    for part in filename:gmatch('%b()') do
        if (part:find('卷',1,true) or part:find('册',1,true)) and not part:match('^%(全.-册%)$') and not part:match('^%(共.-册%)$') and not part:match('^%(全.-卷%)$') and not part:match('^%(共.-卷%)$') then
            local range=part:gsub('～','~'):gsub('至','~'):gsub('—','~'):gsub('%-','~'):gsub('卷',''):gsub('册','')
            local found=false
            local function accept(a,b)
                a,b=tonumber(a),tonumber(b)
                if a<1 or b<a or first and (a~=first or b~=last) then return false end
                first,last,found=a,b,true;scope_parts[part]=true
                return true
            end
            for a,b in range:gmatch('(%d+)%s*~%s*(%d+)') do
                if not accept(a,b) then return {blocked='卷册范围不合法或互相冲突'} end
            end
            if not found and range:find('~',1,true) then return {blocked='卷册范围格式无法解析'} end
            if not found then
                local number=part:match('卷%s*(%d+)') or part:match('册%s*(%d+)')
                    or part:match('(%d+)%s*卷') or part:match('(%d+)%s*册')
                if not number then
                    local explicit=part:match('^%(第(.-)卷%)$') or part:match('^%(第(.-)册%)$')
                    if explicit then
                        number=Inkfolio.numberValue(explicit)
                        if not number then return {blocked='卷册编号格式无法解析'} end
                    end
                end
                if number and not accept(number,number) then return {blocked='卷册编号不合法或互相冲突'} end
            end
        end
    end
    local cleanfile=searchTitle(filename:gsub('%b()',function(part)return scope_parts[part] and '' or part end))
    local base=metadata:match('^(.-)大全集$') or metadata:match('^(.-)全集$')
    if not base and first then base=cleanfile end
    if not base or util.trim(base)=='' then return nil end
    base=util.trim(base)
    if first and normalize(cleanfile)~=normalize(base) and normalize(cleanfile)~=normalize(metadata) then
        return {blocked='卷册范围所在文件名与全集标题不一致'}
    end
    return {base=base,first=first,last=last,metadata=metadata,
        query=base,
        scope=normalize(base)..'|'..tostring(first or 'any')..'|'..tostring(last or 'any')}
end
function Inkfolio.volumeNumber(title,base)
    local text=searchTitle(title):gsub('（','('):gsub('）',')'):gsub('·',' ')
    local prefix,number=text:match('^(.-)%s*%((%d+)%)$')
    if not number then prefix,number=text:match('^(.-)%s*%(第(%d+)卷%)$') end
    if not number then prefix,number=text:match('^(.-)%s*%(第(%d+)册%)$') end
    if not number then prefix,number=text:match('^(.-)%s*第(%d+)卷$') end
    if not number then prefix,number=text:match('^(.-)%s*第(%d+)册$') end
    if not number then prefix,number=text:match('^(.-)%s+[Vv][Oo][Ll]%.?%s*(%d+)$') end
    if not number then prefix,number=text:match('^(.-)%s+(%d+)$') end
    if not number then prefix,number=text:match('^(.-)(%d+)$') end
    number=tonumber(number)
    if number and number>=1 and normalize(prefix)==normalize(base) then return number end
end
-- Select from actual local sources; never discard a prefix based on a word list.
function Inkfolio.searchIdentity(book)
    local custom=Inkfolio.searchOverride(book)
    if custom then return {query=custom,source='用户自定义'} end
    local collection=Inkfolio.collectionInfo(book)
    if collection and not collection.blocked then return {query=collection.query,source='明确全集或卷册范围',note=collection.first and ('仅匹配第'..collection.first..'～'..collection.last..'册') or nil} end
    if collection and collection.blocked then return {query=searchTitle(book.title),source='内部标题',note=collection.blocked} end
    local metadata=searchTitle(book.title)
    local filename=book.path and book.path:match('([^/]+)%.[^%.]+$') or ''
    filename=searchTitle(filename)
    local source=book.title_source or '内部标题'
    local result={query=metadata,source=source}
    if filename=='' or normalize(filename)==normalize(metadata) then return result end
    -- A shorter filename must equal an entire colon-delimited title component,
    -- and the book must have author metadata. No arbitrary substring extraction.
    local components=metadata:gsub('：',':')
    local supported=false
    if components:find(':',1,true) then
        for part in components:gmatch('[^:]+') do
            if normalize(part)==normalize(filename) then supported=true;break end
        end
    end
    if supported and #authorNames(book.authors)>0 then
        return {query=filename,source='文件名与内部标题交叉确认'}
    end
    result.note=supported and '缺少作者信息，未自动采用文件名中的简短书名'
        or '文件名与内部标题不能相互确认，未自动采用文件名'
    return result
end
function Inkfolio.searchTitle(book) return Inkfolio.searchIdentity(book).query end
function Inkfolio.validISBN(value)
    local isbn=tostring(value or ''):upper()
    local sum=0
    if #isbn==13 and isbn:match('^97[89]%d+$') then
        for i=1,13 do sum=sum+tonumber(isbn:sub(i,i))*(i%2==1 and 1 or 3) end
        return sum%10==0
    elseif #isbn==10 and isbn:match('^%d%d%d%d%d%d%d%d%d[%dX]$') then
        for i=1,10 do local c=isbn:sub(i,i);sum=sum+(c=='X' and 10 or tonumber(c))*(11-i) end
        return sum%11==0
    end
    return false
end
local function parseDetail(html)
    local ok, parser = pcall(require, 'htmlparser')
    if not ok then return nil, nil, '缺少 HTML 解析组件' end
    local good, root = pcall(parser.parse, tostring(html or ''), 6000)
    if not good or not root then return nil, nil, '详情页内容无法解析' end
    local parsed, rating, intro = pcall(function()
        local ratings = root:select('strong[property="v:average"]')
        local n = ratings[1] and tonumber(htmlText(ratings[1]:gettext()))
        if not n or n <= 0 or n > 10 then return nil end
        local descriptions = root:select('#link-report .intro')
        -- When collapsed and expanded copies coexist, the last is the full text.
        local node = descriptions[#descriptions]
        local text = node and htmlText(node:gettext()) or ''
        return n, text ~= '' and shortText(text, 240) or nil
    end)
    if not parsed then return nil, nil, '详情页字段解析失败' end
    if not rating then return nil, nil, '详情页没有有效评分，可能未评分或访问被限制' end
    if not intro then return rating, nil, '详情页没有可提取的内容简介' end
    return rating, intro
end
function Inkfolio.finalizeVolumes(candidates,verified_only)
    local groups,sources,seen={},{},{}
    local preferred
    for _,c in ipairs(candidates) do
        if c.volume and c.rating and not seen[c.url] and (not verified_only or c.checked_detail) then
            seen[c.url]=true
            local group=groups[c.volume] or {volume=c.volume,sum=0,versions=0}
            groups[c.volume]=group
            if group.versions<8 then
                group.sum=group.sum+c.rating;group.versions=group.versions+1
                sources[#sources+1]={url=c.url,rating=c.rating,via=c.checked_detail and '豆瓣详情页' or '豆瓣搜索页',volume=c.volume}
                if not preferred or (type(c.volume)=='number' and type(preferred.volume)=='number' and c.volume<preferred.volume) or (type(c.volume)~='number' or type(preferred.volume)~='number') and tostring(c.volume)<tostring(preferred.volume) then preferred=c end
            end
        end
    end
    if not preferred then return nil end
    if not preferred.intro or preferred.intro=='' then
        for _,c in ipairs(candidates)do if c.volume and c.rating and c.intro and c.intro~='' and (not verified_only or c.checked_detail) then preferred=c;break end end
    end
    local volumes,sum,versions={},0,0
    for _,g in pairs(groups) do
        local average=g.sum/g.versions
        sum=sum+average;versions=versions+g.versions
        volumes[#volumes+1]={volume=g.volume,rating=average,versions=g.versions}
    end
    table.sort(volumes,function(a,b)if type(a.volume)=='number' and type(b.volume)=='number' then return a.volume<b.volume end;return tostring(a.volume)<tostring(b.volume)end)
    return {rating=math.floor(sum/#volumes*10+.5)/10,score_kind='volumes',matched_volumes=volumes,
        rated_versions=versions,collection_scope=preferred.collection_scope,url=preferred.url,
        primary_title=preferred.title,primary_volume=preferred.volume,intro=preferred.intro,intro_state=preferred.intro_state,
        intro_source=preferred.intro and preferred.url or nil,intro_updated_at=preferred.intro and os.time() or nil,
        intro_title=preferred.intro and preferred.title or nil,intro_volume=preferred.intro and preferred.volume or nil,
        updated_at=os.time(),rating_updated_at=os.time(),rating_sources=sources}
end
local function finalizeCandidates(candidates, verified_only)
    local direct={};local has_volumes=false;local seen={}
    local unique={};for _,c in ipairs(candidates)do if not seen[c.url] then seen[c.url]=true;unique[#unique+1]=c end end
    candidates=unique
    for _,c in ipairs(candidates) do
        if c.volume then has_volumes=true
        elseif c.rating and (not verified_only or c.checked_detail) then direct[#direct+1]=c end
    end
    if has_volumes and #direct==0 then
        table.sort(candidates,function(a,b)if a.relevance~=b.relevance then return a.relevance>b.relevance end;return a.id<b.id end)
        return Inkfolio.finalizeVolumes(candidates,verified_only)
    elseif has_volumes then candidates=direct end
    table.sort(candidates, function(a,b) if a.relevance~=b.relevance then return a.relevance>b.relevance end;return a.url<b.url end)
    local n, sum, accepted = 0, 0, 0
    local sources={}
    for i = 1, math.min(8, #candidates) do
        local c = candidates[i]
        if c.rating and (not verified_only or c.checked_detail) then
            sum, n = sum + c.rating, n + 1
            sources[#sources+1]={url=c.url,title=c.title,rating=c.rating,via=c.checked_detail and '豆瓣详情页' or '豆瓣搜索页'}
        end
    end
    if n == 0 then return nil end
    for i = 1, math.min(8,#candidates) do
        if candidates[i].rating then
            accepted = i
            break
        end
    end
    local preferred = candidates[accepted]
    for i=1,math.min(8,#candidates)do local c=candidates[i];if c.rating and c.intro and c.intro~='' and (not verified_only or c.checked_detail) then preferred=c;break end end
    if not preferred or not validURL(preferred.url) then return nil end
    return {rating = math.floor(sum / n * 10 + 0.5) / 10,
            matched_title=preferred.title, rated_versions = n, score_kind=n>1 and 'versions' or nil, url = preferred.url,
            intro_state=preferred.intro_state,
            intro = preferred.intro, updated_at = os.time(),rating_updated_at=os.time(),rating_sources=sources,
            intro_source=preferred.intro and preferred.url or nil,intro_updated_at=preferred.intro and os.time() or nil}
end

-- Kobo / KOReader may not initialize Turbo's UIManager.looper. Running httpclient
-- in that configuration throws "attempt to index field looper (a nil value)".
-- Use KOReader's supported POSIX subprocess runner. HTTPS runs outside the UI
-- process; the UI polls only process status and reads the completed result file.
-- Never fall back to synchronous HTTPS in the UI thread.
local HTTP_TIMEOUT = 25
local HTTP_MAX_BYTES = 512 * 1024
local HTTP_SEQ = 0

local function stopHTTP(reason,retry_weather)
    local worker = RUN.worker
    if not worker then return end
    RUN.worker = nil
    if worker.kind=='weather' then
        WEATHER.pending=retry_weather~=false
        WEATHER.error=reason or (RUN.sleeping and '休眠中，天气获取已中断' or not networkingEnabled() and '联网已关闭' or '天气获取已中断')
        store:saveSetting('weather',WEATHER);store:flush()
    end
    if worker.kind=='monthly' and Inkfolio.monthly.result=='running' then
        Inkfolio.monthly.result='interrupted'
        Inkfolio.monthly.error=reason or (RUN.sleeping and '休眠中，月榜获取已中断' or not networkingEnabled() and '联网已关闭' or '月榜任务已中断')
        Inkfolio.monthly.finished_at=os.time();Inkfolio.saveMonthly()
    end
    if worker.pid and worker.pid ~= false then
        ffiUtil.terminateSubProcess(worker.pid)
        local pid = worker.pid
        local function reap()
            if not ffiUtil.isSubProcessDone(pid) then
                UIManager:scheduleIn(0.25, reap)
            elseif worker.path then
                os.remove(worker.path)
            end
        end
        reap()
    end
    if worker.path then os.remove(worker.path) end
end

local function markAttempt()
    if RUN.started then return end
    RUN.started = true
    if not RUN.manual and not RUN.new_books then
        resetDay()
        ROUNDS = ROUNDS + 1 -- diagnostic count, not a shared per-book quota
        DAILY_DONE = true
        saveData()
    end
end

local function sendHTTP(url, token, cb, kind)
    if RUN.sleeping or not networkingEnabled() or not connected() or token ~= RUN.token then
        RUN.last_error=RUN.sleeping and '休眠中，任务未启动' or not networkingEnabled() and '联网已关闭'
            or token~=RUN.token and '任务已失效' or '网络未连接'
        return false
    end
    local book_request=kind~='monthly' and kind~='weather'
    RUN.request_stage=kind=='weather' and '天气请求' or kind=='monthly' and '豆瓣月榜' or url:find('www.bing.com/',1,true) and 'Bing检索'
        or url:find('www.douban.com/search',1,true) and '豆瓣检索' or '豆瓣详情'
    Inkfolio.debugEvent(RUN.request_stage,'开始')
    if RUN.transport_broken and book_request then return false end
    if RUN.worker then
        RUN.last_error = 'HTTP worker already active'
        logger.warn('READ RECEIPT:', RUN.last_error)
        return false
    end
    if type(ffiUtil.runInSubProcess) ~= 'function' or
       type(ffiUtil.isSubProcessDone) ~= 'function' or
       type(ffiUtil.terminateSubProcess) ~= 'function' then
        RUN.last_error = 'KOReader subprocess API unavailable'
        RUN.transport_broken = true
        logger.warn('READ RECEIPT:', RUN.last_error)
        return false
    end

    HTTP_SEQ = HTTP_SEQ + 1
    -- The child writes its result to a unique path; the UI never reads a
    -- half-written response or a pipe that could block on an oversized page.
    local resultpath = DataStorage:getSettingsDir() .. '/read_receipt_http_' ..
                       tostring(os.time()) .. '_' .. tostring(HTTP_SEQ) .. '.tmp'
    os.remove(resultpath)
    local ok, pid, error_text = pcall(ffiUtil.runInSubProcess, function()
        local status, data = 'ERROR', 'unknown error'
        local good, why = pcall(function()
            local https = require('ssl.https')
            local socketutil = require('socketutil')
            -- Limit connection and entire receive time to avoid hung tasks.
            socketutil:set_timeout(6, 12)
            local chunks, bytes = {}, 0
            local sink = function(chunk)
                if chunk then
                    bytes = bytes + #chunk
                    if bytes > HTTP_MAX_BYTES then return nil, 'response too large' end
                    chunks[#chunks+1] = chunk
                end
                return 1
            end
            local request_ok, res, code = pcall(https.request, {
                url=url, method='GET', sink=sink,
                headers={ ['User-Agent']='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Safari/537.36',
                          ['Accept-Encoding']='identity' },
            })
            socketutil:reset_timeout()
            if request_ok and tonumber(code) == 200 then
                status, data = 'OK', table.concat(chunks)
            elseif request_ok then
                status, data = 'HTTP', tostring(code or res)
            else
                status, data = 'ERROR', tostring(res)
            end
        end)
        if not good then status, data = 'ERROR', tostring(why) end
        local file = io.open(resultpath, 'wb')
        if file then
            file:write(status, '\n', data)
            file:close()
        end
    end)
    if not ok or type(pid) ~= 'number' or pid <= 0 then
        RUN.last_error = 'cannot start HTTP subprocess: ' .. tostring(ok and error_text or pid)
        RUN.transport_broken = true
        os.remove(resultpath)
        logger.warn('READ RECEIPT:', RUN.last_error)
        return false
    end

    if book_request then markAttempt() end
    RUN.worker = { pid=pid, path=resultpath, token=token, started=os.time(), kind=kind }
    local function checkResult()
        local worker = RUN.worker
        if not worker or worker.pid ~= pid then return end
        if token ~= RUN.token or RUN.sleeping or not networkingEnabled() then
            stopHTTP()
            return
        end
        if os.time() - worker.started > HTTP_TIMEOUT then
            local reason='HTTP subprocess timed out'
            Inkfolio.networkFailure(book_request,reason)
            logger.warn('READ RECEIPT:',reason)
            stopHTTP(reason,false)
            Inkfolio.debugEvent(RUN.request_stage,'失败',reason)
            cb('',reason)
            return
        end
        if not ffiUtil.isSubProcessDone(pid) then
            UIManager:scheduleIn(0.25, checkResult)
            return
        end
        RUN.worker = nil
        local f = io.open(resultpath,'rb')
        local result = f and f:read('*a') or nil
        if f then f:close() end
        os.remove(resultpath)
        local status, body
        if result then status, body = result:match('^([^\n]*)\n(.*)$') end
        if status ~= 'OK' then
            local reason = status and (status .. ': ' .. tostring(body):sub(1,160))
                or 'no HTTP subprocess response'
            logger.warn('READ RECEIPT network:', reason)
            Inkfolio.networkFailure(book_request,reason)
            Inkfolio.debugEvent(RUN.request_stage,'失败',reason)
            cb('',reason)
        else
            RUN.network_failures = 0
            Inkfolio.debugEvent(RUN.request_stage,'成功，响应字节 '..#body)
            cb(body)
        end
    end
    UIManager:scheduleIn(0.25, checkResult)
    return true
end
-- One shared monthly chart, fetched serially with book metadata.
-- Keep the source month and publication date; never infer a month from today.
Inkfolio.MONTHLY_URL='https://book.douban.com/chart?subcat=all'
Inkfolio.MONTHLY_CATEGORIES={
    {id='all',label='综合',source='全部'},{id='literary',label='文学',source='文学'},
    {id='novel',label='小说',source='小说'},{id='history',label='历史文化',source='历史文化'},
    {id='social',label='社会纪实',source='社会纪实'},{id='tech',label='科学新知',source='科学新知'},
    {id='art',label='艺术设计',source='艺术设计'},{id='comics',label='绘本漫画',source='绘本漫画'},
}
function Inkfolio.monthlyCategory(id)
    id=id or G_reader_settings:readSetting(S.monthly_category) or 'all'
    for _,item in ipairs(Inkfolio.MONTHLY_CATEGORIES)do if item.id==id then return item end end
    error('豆瓣月榜分类设置无效')
end
function Inkfolio.monthlyURL(category,date,page)
    local url='https://book.douban.com/chart?subcat='..Inkfolio.monthlyCategory(category).id
    if date then url=url..'&updated_at='..date end
    if page and page>1 then url=url..'&p='..page end
    return url
end
function Inkfolio.validMonthly(record)
    if type(record)~='table' or type(record.year)~='number' or record.year<2000 or record.year>9999 or record.year~=math.floor(record.year)
        or type(record.month)~='number' or record.month<1 or record.month>12 or record.month~=math.floor(record.month)
        or not Inkfolio.validRecordDate(record.update_date) or type(record.items)~='table' or #record.items<1 or #record.items>200 then return false end
    local category
    for _,item in ipairs(Inkfolio.MONTHLY_CATEGORIES)do if item.id==(record.category or 'all') then category=item.id;break end end
    if not category or record.url~=Inkfolio.monthlyURL(category,record.update_date) then return false end
    local seen={}
    local previous=0
    for i,item in ipairs(record.items)do
        if type(item)~='table' or type(item.rank)~='number' or item.rank<=previous or item.rank~=math.floor(item.rank)
            or type(item.title)~='string' or item.title==''
            or type(item.author)~='string' or item.author=='' or type(item.rating)~='number'
            or not (item.rating>0 and item.rating<=10) or not validURL(item.url) or seen[item.url] then return false end
        seen[item.url]=true
        previous=item.rank
    end
    return true
end
function Inkfolio.parseMonthly(body,category,page)
    local selected=Inkfolio.monthlyCategory(category)
    local ok,root=pcall(function()return require('htmlparser').parse(tostring(body or ''),6000)end)
    if not ok or not root then return nil,'月榜页面无法解析' end
    local good,record,reason=pcall(function()
        local heading=root:select('.page-header h1')[1]
        local title=heading and htmlText(heading:gettext()) or ''
        local month=tonumber(title:match('^(%d+)月热门图书榜$'))
        local year,selected_month
        for _,section in ipairs(root:select('.date-selector .year-section'))do
            local selected=section:select('.month.selected')[1]
            if selected then
                if year then return nil,'月榜月份重复' end
                local y=section:select('.year')[1]
                year=y and tonumber(htmlText(y:gettext()))
                selected_month=tonumber(htmlText(selected:gettext()):match('^(%d+)月$'))
            end
        end
        local all=root:select('.xbar .now')[1]
        if not month or month~=selected_month or not year or not all or htmlText(all:gettext())~=selected.source then
            return nil,'月榜月份或分类标识不匹配，可能受到访问限制'
        end
        local date
        for _,link in ipairs(root:select('.xbar a'))do
            local found=htmlText(link.attributes.href):match('[?&]updated_at=(%d%d%d%d%-%d%d%-%d%d)')
            if found then
                if date and date~=found then return nil,'月榜发布日期不一致' end
                date=found
            end
        end
        if not Inkfolio.validRecordDate(date) then return nil,'月榜发布日期缺失或无效' end
        local result={year=year,month=month,category=selected.id,update_date=date,url=Inkfolio.monthlyURL(selected.id,date),items={}}
        local rows=root:select('.chart-dashed-list > li')
        if #rows<1 then return nil,'月榜没有图书条目' end
        for i=1,#rows do
            local row=rows[i]
            local rank=row:select('.rank-info strong')[1]
            local link=row:select('h2 a')[1]
            local author=row:select('.subject-abstract')[1]
            local rating=row:select('.subject-rating .font-small')[1]
            result.items[i]={rank=rank and tonumber(htmlText(rank:gettext())),title=link and htmlText(link:gettext()),
                author=author and util.trim((htmlText(author:gettext()):match('^(.-)%s*/%s*%d%d%d%d[%d%-]*%s*/') or '')),
                rating=rating and tonumber(htmlText(rating:gettext())),url=link and link.attributes.href}
        end
        if not Inkfolio.validMonthly(result) then return nil,'月榜条目字段不完整或排名无效' end
        local next_link=root:select('.paginator link[rel="next"]')[1]
        if next_link then
            local href=htmlText(next_link.attributes.href)
            local subcat=href:match('[?&]subcat=([%a]+)')
            local next_page=tonumber(href:match('[?&]p=(%d+)'))
            if subcat~=selected.id or href:match('[?&]updated_at=([%d%-]+)')~=date or next_page~=(page or 1)+1 then
                return nil,'月榜分页链接无效'
            end
            result.next_page=next_page
        end
        return result
    end)
    if not good then return nil,'月榜字段解析失败' end
    return record,reason
end
function Inkfolio.saveMonthly()
    store:saveSetting('monthly_chart',Inkfolio.monthly);store:flush()
end
function Inkfolio.selectMonthlyCategory(id)
    id=Inkfolio.monthlyCategory(id).id
    if RUN.active or RUN.worker then return false end
    local state=Inkfolio.monthly
    if id==Inkfolio.monthlyCategory().id then return true end
    state.records=state.records or {}
    if state.record then state.records[state.record.category or 'all']=state.record end
    G_reader_settings:saveSetting(S.monthly_category,id)
    state.record=state.records[id];state.cursor=1;state.pending=nil
    state.attempt_day=nil;state.result=nil;state.error=nil;state.rotate_pending=nil
    Inkfolio.saveMonthly()
    if refreshQuicklook then refreshQuicklook() end
    Inkfolio.resetNetworkPause();RUN.auto_holds.monthly=nil
    Inkfolio.monthlyCheck()
    if startPoll then startPoll() end
    return true
end
function Inkfolio.visibleMonthly()
    local record=Inkfolio.monthly.record
    if Inkfolio.validMonthly(record) and (record.category or 'all')==Inkfolio.monthlyCategory().id then return record end
end
function Inkfolio.monthlyItems()
    local record=Inkfolio.visibleMonthly()
    if not record then return {} end
    local first=G_reader_settings:readSetting(S.monthly_rotate)==true and (Inkfolio.monthly.cursor or 1) or 1
    assert(type(first)=='number' and first>=1 and first<=#record.items and first%3==1,'月榜轮换位置无效')
    local rows={}
    for i=first,math.min(first+2,#record.items)do rows[#rows+1]=record.items[i] end
    return rows
end
function Inkfolio.rotateMonthly()
    local state=Inkfolio.monthly;local record=Inkfolio.visibleMonthly()
    if not enabled(S.intro) or not record or not record.complete
        or G_reader_settings:readSetting(S.monthly_rotate)~=true then return end
    local groups=math.ceil(#record.items/3)
    state.cursor=((math.floor(((state.cursor or 1)-1)/3)+1)%groups)*3+1
    Inkfolio.saveMonthly()
    if refreshQuicklook then refreshQuicklook() end
end
function Inkfolio.monthlyCheck(continue)
    local state=Inkfolio.monthly
    if not enabled(S.intro) or RUN.sleeping or not networkingEnabled() or RUN.worker
        or (RUN.active and not continue) or (Inkfolio.networkHeld('monthly') and not state.pending)
        or (RUN.transport_broken and not state.pending)
        or not connected() then return false end
    local today=localDate()
    local forced=state.pending==true
    local cached=Inkfolio.visibleMonthly()
    -- Monthly issues are published in the following month. Once this month's
    -- publication is cached in full, keep its ratings as a retrieval-time snapshot.
    if not forced and cached and cached.complete and cached.update_date:sub(1,7)==today:sub(1,7) then return false end
    if state.attempt_day==today and not forced then return false end
    local token=RUN.token
    if RUN.active then progressStage('正在获取豆瓣月榜') end
    state.pending=nil;state.attempt_day=today;state.attempt_at=os.time()
    state.result='running';state.error='上次月榜任务未完成';Inkfolio.saveMonthly()
    local category=Inkfolio.monthlyCategory().id
    local collected,seen={},{}
    local function finish(record,reason)
        if token~=RUN.token then return end
        state.finished_at=os.time()
        if record then
            local old=Inkfolio.visibleMonthly()
            if record~=old then
                if not old or old.url~=record.url or not old.complete then state.cursor=1 end
                if (state.cursor or 1)>#record.items then state.cursor=1 end
                record.complete=true;record.next_page=nil;record.updated_at=state.finished_at
                state.record=record;state.records=state.records or {};state.records[category]=record
            end
            state.result='success';state.error=nil
        else state.result='failed';state.error=reason or '月榜获取失败' end
        Inkfolio.saveMonthly();Inkfolio.debugEvent('豆瓣月榜',state.result,state.error)
        if refreshQuicklook then refreshQuicklook() end
        if continue then UIManager:nextTick(function()if token==RUN.token then continue()end end)
        elseif startPoll then startPoll() end
    end
    local requestPage
    requestPage=function(page,date)
        if page>10 then finish(nil,'月榜分页超过安全上限');return true end
        local started=sendHTTP(Inkfolio.monthlyURL(category,date,page),token,function(body,error_text)
            if token~=RUN.token then return end
            local record,reason
            if not error_text then record,reason=Inkfolio.parseMonthly(body,category,page) end
            if not record then finish(nil,error_text or reason);return end
            -- Until the next issue appears, only check page 1 once per day.
            if page==1 and not forced and cached and cached.complete and cached.url==record.url then finish(cached);return end
            if collected[1] and collected[1].url~=record.url then finish(nil,'月榜分页月份不一致');return end
            for _,item in ipairs(record.items)do
                local last=collected[#collected] and collected[#collected].items
                last=last and last[#last]
                if seen[item.url] or (last and item.rank<=last.rank) then finish(nil,'月榜分页条目重复或排名无效');return end
                seen[item.url]=true
            end
            collected[#collected+1]=record
            if record.next_page then requestPage(record.next_page,record.update_date)
            else
                local whole=collected[1];local items={}
                for _,part in ipairs(collected)do for _,item in ipairs(part.items)do items[#items+1]=item end end
                whole.items=items
                if not Inkfolio.validMonthly(whole) then finish(nil,'完整月榜校验失败');return end
                finish(whole)
            end
        end,'monthly')
        if not started then finish(nil,RUN.last_error or '月榜请求未启动');return continue~=nil end
        return started
    end
    local started=requestPage(1)
    return started
end
function Inkfolio.refreshMonthly()
    if RUN.sleeping or RUN.active or RUN.worker or not networkingEnabled() or not connected() then return false end
    Inkfolio.resetNetworkPause();RUN.auto_holds.monthly=nil
    Inkfolio.monthly.pending=true
    local started=Inkfolio.monthlyCheck()
    if startPoll then startPoll() end
    return started
end
function Inkfolio.monthlyNote()
    local state=Inkfolio.monthly
    if RUN.worker and RUN.worker.kind=='monthly' then return '正在更新月榜' end
    if state.result=='interrupted' then return '月榜更新中断：'..tostring(state.error or '任务未完成') end
    if state.result=='failed' or state.result=='running' then return '月榜更新失败：'..tostring(state.error or '任务未完成') end
    if state.record and not Inkfolio.validMonthly(state.record) then return '月榜缓存无效，请重新获取' end
    if not state.record then return networkingEnabled() and '月榜尚未获取' or '联网已关闭，暂无月榜缓存' end
end
local function captureResponse(book, stage, url, body)
    Inkfolio.debugEvent('响应解析',stage..'，字节 '..#tostring(body or ''))
end
local function fetchBook(book,token,done)
    return Inkfolio.fetchVerifiedBook(book,token,done)
end

-- Detailed identity and human confirmation are distinct from discovery.
function Inkfolio.discovery(body,kind)
    local out,seen={},{}
    local function add(id,title,summary)
        if id and id:match('^%d+$') and not seen[id] and title~='' then
            seen[id]=true;out[#out+1]={id=id,url='https://book.douban.com/subject/'..id..'/',title=title,summary=summary}
        end
    end
    if kind=='bing' then
        for item in tostring(body):gmatch('<item[^>]*>(.-)</item>')do
            local link=htmlText(item:match('<link[^>]*>(.-)</link>') or '')
            local title=htmlText(item:match('<title[^>]*>(.-)</title>') or ''):gsub('%s*%(豆瓣%).*$',''):gsub('%s*（豆瓣）.*$','')
            add(link:match('^https?://book%.douban%.com/subject/(%d+)/?'),title,htmlText(item:match('<description[^>]*>(.-)</description>') or ''))
        end
    else
        local ok,root=pcall(function()return require('htmlparser').parse(body,6000)end)
        if not ok or not root then return out,'搜索页内容无法解析' end
        if #root:select('div.result-list')==0 then return out,'搜索页没有结果结构，可能受到访问限制' end
        for _,node in ipairs(root:select('div.result-list div.result'))do
            local link=node:select('a.nbg')[1];local attr=link and link.attributes or {}
            local title=node:select('div.title h3 a')[1];local cast=node:select('span.subject-cast')[1]
            add((attr.href or ''):match('/subject/(%d+)') or (attr.onclick or ''):match('sid:%s*(%d+)'),
                title and htmlText(title:gettext()) or '',cast and htmlText(cast:gettext()) or '')
        end
    end
    return out
end
function Inkfolio.titleCloseness(a,b)
    local function chars(s)local out={};for c in normalize(s):gmatch('[%z\1-\127\194-\244][\128-\191]*')do out[#out+1]=c;if #out==160 then break end end;return out end
    local x,y=chars(a),chars(b);local row={}
    for j=0,#y do row[j]=j end
    for i=1,#x do local prev=row[0];row[0]=i
        for j=1,#y do local old=row[j];row[j]=math.min(row[j]+1,row[j-1]+1,prev+(x[i]==y[j] and 0 or 1));prev=old end
    end
    return #x+#y>0 and 1-row[#y]/math.max(#x,#y) or 0
end
function Inkfolio.identityDetail(body,url)
    local ok,root=pcall(function()return require('htmlparser').parse(body,6000)end)
    if not ok or not root then return nil,'详情页内容无法解析' end
    local title=root:select('h1 span[property="v:itemreviewed"]')[1]
    local header=root:select('#info')[1]
    if not title or not header then return nil,'详情页缺少图书身份字段，可能受到访问限制' end
    local d={url=url,title=htmlText(title:gettext()),authors={},contributors={},profiles={},aliases={},sources={url},author_display={},display_seen={}}
    local function addName(name,role,href)
        for _,n in ipairs(authorNames(name))do
            local key=normalize(n)
            d.contributors[key]=true
            if role=='作者' then d.authors[key]=true end
            if not d.display_seen[key] then d.display_seen[key]=true;d.author_display[#d.author_display+1]=n..'（'..role..'）' end
            if href and role=='作者' then
                if href:match('^/author/%d+/?$') then href='https://book.douban.com'..href end
                if href:match('^https://book%.douban%.com/author/%d+/?$') then d.profiles[href]=key end
            end
        end
    end
    local content=header:getcontent()
    for field in (content..'<br/>'):gmatch('(.-)<[bB][rR][^>]*>')do
        local text=htmlText(field)
        local label,value=text:match('^%s*(.-)%s*[:：]%s*(.*)$')
        if label then
            label=util.trim(label)
            if label=='作者' or label=='译者' or label=='编者' or label=='校注' or label=='评注' then
                addName(value,label)
                local parsed=require('htmlparser').parse(field,1000)
                for _,a in ipairs(parsed:select('a'))do addName(htmlText(a:gettext()),label,a.attributes.href) end
            elseif label=='ISBN' then d.isbn=value:gsub('[^%dXx]','')
            elseif label=='原作名' then d.original_title=value
            elseif label=='副标题' then d.subtitle=value
            elseif label=='丛书' then d.series=value
            elseif label=='出版社' then d.publisher=value end
        end
    end
    for _,row in ipairs(root:select('#authors li.author'))do
        local name=row:select('a.name')[1];local role=row:select('span.role')[1]
        if name and role then addName(htmlText(name:gettext()),htmlText(role:gettext()),name.attributes.href) end
    end
    local directory=root:select('div[id="dir_'..tostring(url:match('/subject/(%d+)/'))..'_full"]')[1]
    d.contents={}
    if directory then for name in htmlText(directory:gettext()):gmatch('《(.-)》')do d.contents[normalize(name)]=true end end
    local intro=root:select('#link-report .intro');local node=intro[#intro]
    d.full_intro=node and htmlText(node:gettext()) or ''
    d.rating,d.intro,d.rating_error=parseDetail(body)
    d.intro_state=d.intro and 'available' or (d.rating and d.rating_error=='详情页没有可提取的内容简介' and 'absent' or 'failed')
    return d
end
function Inkfolio.numberValue(s)
        if tonumber(s) then local n=tonumber(s);return n>0 and n%1==0 and n or nil end
        local units={['一']=1,['二']=2,['三']=3,['四']=4,['五']=5,['六']=6,['七']=7,['八']=8,['九']=9,['零']=0,['两']=2}
        local total,last=0,0
        for c in s:gmatch('[\194-\244][\128-\191]*')do
            if c=='十' then total=total+(last==0 and 1 or last)*10;last=0
            elseif c=='百' then total=total+(last==0 and 1 or last)*100;last=0
            elseif units[c] then if last~=0 and units[c]~=0 then return nil end;last=units[c] else return nil end
        end
        return total+last>0 and total+last or nil
    end
function Inkfolio.collectionCount(text)
    text=tostring(text or '')
    local count
    for _,marker in ipairs({'全','共'})do
        local pos=1
        while true do
            local at=text:find(marker,pos,true);if not at then break end
            local tail=text:sub(at+#marker)
            local a,b=tail:find('册',1,true),tail:find('卷',1,true)
            local stop=a and b and math.min(a,b) or a or b
            local n=stop and tail:sub(1,stop-1)
            local value=n and Inkfolio.numberValue(n)
            if value then
                if count and value~=count then return nil,'册数说明相互冲突' end
                count=value
            end
            pos=at+#marker
        end
    end
    return count
end
function Inkfolio.profileAliases(body,name)
    local root=require('htmlparser').parse(body,6000)
    local title=root:select('h1')[1];local info=root:select('#info')[1]
    if not title or not info or normalize(htmlText(title:gettext()))~=name then return nil,'作者页面身份无法确认' end
    local aliases={}
    for field in (info:getcontent()..'<br/>'):gmatch('(.-)<[bB][rR][^>]*>')do
        local label,value=htmlText(field):match('^(.-)[:：]%s*(.*)$')
        label=label and util.trim(label)
        if label=='外文名' or label=='英文名' or label=='中文名' or label=='更多外文名' or label=='更多中文名' then
            for _,n in ipairs(authorNames(value))do aliases[normalize(n)]=true end
        end
    end
    return aliases
end
function Inkfolio.verifyIdentity(book,d)
    local query=Inkfolio.searchTitle(book);local collection=Inkfolio.collectionInfo(book)
    if collection and collection.blocked then return nil,collection.blocked end
    local volume;local title_ok=normalize(searchTitle(query))==normalize(searchTitle(d.title))
    if not title_ok and d.original_title then title_ok=normalize(query)==normalize(d.original_title) end
    if not title_ok and d.subtitle then title_ok=normalize(query)==normalize(d.title..'：'..d.subtitle) end
    if collection and normalize(query)==normalize(collection.base) then
        volume=Inkfolio.volumeNumber(d.title,collection.base)
        local count,count_error=Inkfolio.collectionCount(book.title)
        local declared,declared_error=Inkfolio.collectionCount(d.title..' '..d.full_intro)
        if count_error or declared_error then return nil,'套装册数说明相互冲突，需要用户确认' end
        local author_collection=false
        for _,name in ipairs(authorNames(book.authors))do
            if normalize(collection.base):sub(1,#normalize(name))==normalize(name) then author_collection=true end
        end
        local full_title=normalize(searchTitle(d.title))==normalize(collection.metadata)
        if title_ok or full_title then
            if collection.first then return nil,'套装无法确认属于文件卷册范围' end
            if (count and declared~=count) or not full_title and (not declared or declared<2) then return nil,'套装册数或收录范围无法确认' end
            title_ok=true
        elseif author_collection then
            title_ok=false
            for _,name in ipairs(book.contents or {})do if normalize(name)==normalize(d.title) then title_ok=true;volume=d.title;break end end
            if not title_ok then return nil,'作者作品合集缺少可核验的收录目录或结果不在目录中' end
        elseif volume then
            title_ok=not collection.first or volume>=collection.first and volume<=collection.last
            if not title_ok then return nil,'分册不在文件卷册范围内' end
        elseif d.series and normalize(d.series)==normalize(collection.base) then
            -- Explicit source series membership; no substring-based membership.
            if collection.first then return nil,'系列已确认，但分册序号无法确认' end
            title_ok=true;volume=d.title
        else return nil,'结果缺少可核验的套装或系列关系' end
    end
    if not title_ok then return nil,'主书名或特定校注版本不一致' end
    local names=authorNames(book.authors);local isbn=Inkfolio.validISBN(book.isbn) and book.isbn==d.isbn
    if #names==0 and not isbn then return nil,'缺少可验证的作者或有效ISBN' end
    for _,name in ipairs(names)do
        local n=normalize(name)
        if not d.contributors[n] and not d.aliases[n] then return nil,'作者或贡献者身份无法确认：需核验详情或别名资料'..(d.alias_error and ('；'..d.alias_error) or '') end
    end
    if volume and #names==0 then return nil,'分册匹配需要明确作者' end
    local edition_exact
    if Inkfolio.validISBN(book.isbn) then edition_exact=book.isbn==d.isbn
    else edition_exact=(book.title:find('（',1,true) or book.title:find('(',1,true))~=nil
        and normalize(book.title)==normalize(d.title) end
    return {volume=volume,collection_scope=volume and collection.scope or nil,edition_exact=edition_exact}
end
function Inkfolio.detailRecord(d,proof)
    local now=os.time()
    return {rating=d.rating,intro=d.intro,intro_state=d.intro_state,url=d.url,updated_at=now,rating_updated_at=now,
        intro_source=d.intro and d.url or nil,intro_updated_at=d.intro and now or nil,
        identity_version=2,identity_sources=d.sources,matched_title=d.title,
        matched_authors=d.author_text or '',rated_versions=1,
        rating_sources={{url=d.url,rating=d.rating,via='豆瓣详情页'}},
        volume=proof and proof.volume,collection_scope=proof and proof.collection_scope}
end
function Inkfolio.pendingCount()
    local n=0;for _,p in pairs(Inkfolio.matchState.pending)do if #p.candidates>0 then n=n+1 end end;return n
end
function Inkfolio.fetchVerifiedBook(book,token,done)
    local target=book.review_target or book
    local chosen=not book.force_review and Inkfolio.confirmedChoice(target)
    local query=Inkfolio.searchTitle(book)
    local collection=Inkfolio.collectionInfo(book)
    local candidates,seen,verified,review,rejections={},{},{},{},{}
    local profiles,profile_count={},0
    local moreSearch,fallback_attempted
    local function reject(reason)
        rejections[reason]=(rejections[reason] or 0)+1
        Inkfolio.debugEvent('身份核验','候选排除',reason)
    end
    local function finish()
        if token~=RUN.token then return end
        if #verified==0 and not chosen and not fallback_attempted and moreSearch then moreSearch();return end
        local record
        if not book.force_review and #verified>0 then
            local direct={};for _,c in ipairs(verified)do if not c.volume then direct[#direct+1]=c end end
            if #direct>0 then
                local exact={};for _,c in ipairs(direct)do if c.edition_exact then exact[#exact+1]=c end end
                if #exact>0 then direct=exact end
                -- Each reviewed edition is verified independently, not by snippet.
                record=finalizeCandidates(direct,true)
            else
                record=Inkfolio.finalizeVerifiedVolumes(verified)
            end
            if record then
                record.identity_version=2;record.search_query=query
                record.matched_title=record.matched_title or verified[1].title;record.identity_sources={}
                for _,c in ipairs(verified)do for _,url in ipairs(c.sources or {c.url})do record.identity_sources[#record.identity_sources+1]=url end end
            end
        end
        local reason=record and record.intro_state=='failed' and target.description=='' and '简介字段获取失败' or nil
        if not record then
            table.sort(review,function(a,b)
                local x,y=Inkfolio.titleCloseness(query,a.title),Inkfolio.titleCloseness(query,b.title)
                if x~=y then return x>y end;return a.url<b.url
            end)
            while #review>3 do table.remove(review) end
            local list={};for r,n in pairs(rejections)do list[#list+1]=r..'（'..n..'）' end;table.sort(list)
            reason=#list>0 and table.concat(list,'；') or '搜索没有返回可读取的图书候选'
            if #review>0 then reason=reason..'；有'..#review..'个候选待用户确认' end
            local ok,err=Inkfolio.setPending(target,review,reason,query)
            if not ok then reason=reason..'；'..err end
        else
            -- Clear only this file's pending proposal, keeping choices and others.
            local old=Inkfolio.matchState;local state={choices=old.choices,pending={},holds=old.holds}
        for k,v in pairs(old.pending)do if k~=Inkfolio.fileMatchKey(target) then state.pending[k]=v end end
            local ok,err=Inkfolio.writeMatchState(state);if not ok then done(nil,err);return end
        end
        done(record,reason)
    end
    if collection and collection.blocked then reject(collection.blocked);finish();return end
    local function examine(d,cb)
        local proof,why=Inkfolio.verifyIdentity(book,d)
        if proof or chosen then cb(proof,why);return end
        local urls={};for url,name in pairs(d.profiles)do urls[#urls+1]={url=url,name=name} end;table.sort(urls,function(a,b)return a.url<b.url end)
        local i=1
        local function step()
            if token~=RUN.token then return end
            if i>#urls or profile_count>=8 then cb(Inkfolio.verifyIdentity(book,d));return end
            local p=urls[i];i=i+1
            local function merge(value)
                if value then for alias in pairs(value)do d.aliases[alias]=true end;d.sources[#d.sources+1]=p.url end
                step()
            end
            if profiles[p.url]~=nil then merge(profiles[p.url] or nil);return end
            profile_count=profile_count+1;progressStage('正在核验作者身份')
            if not sendHTTP(p.url,token,function(body,err)
                if token~=RUN.token then return end
                local ok,value=pcall(Inkfolio.profileAliases,body,p.name)
                profiles[p.url]=not err and ok and value or false
                if not profiles[p.url] then d.alias_error=err and ('作者资料请求失败：'..err) or '作者资料页面无法核验身份，可能受到访问限制' end
                merge(profiles[p.url] or nil)
            end) then profiles[p.url]=false;merge(nil) end
        end
        step()
    end
    local index=1
    local function details()
        if token~=RUN.token then return end
        if index>math.min(6,#candidates) then finish();return end
        local c=candidates[index];index=index+1
        progressStage('正在核验图书详情 '..(index-1)..' / '..math.min(6,#candidates))
        if not sendHTTP(c.url,token,function(body,err)
            if token~=RUN.token then return end
            local d,parse_error
            if not err then d,parse_error=Inkfolio.identityDetail(body,c.url) end
            if not d then reject(err or parse_error);UIManager:scheduleIn(.7,details);return end
            d.author_text=table.concat(d.author_display,'；')
            examine(d,function(proof,why)
                if token~=RUN.token then return end
                if not d.rating then reject(d.rating_error or '详情页没有有效评分')
                else
                    local proposal=Inkfolio.detailRecord(d,proof)
                    proposal.title=d.title;proposal.authors=d.author_text;proposal.version_note=d.subtitle or '';proposal.reason=why
                    review[#review+1]=proposal
                    if chosen then
                        if normalize(chosen.title)~=normalize(d.title) or chosen.authors~=d.author_text then reject('已确认条目的书名或作者发生变化，需要重新确认')
                        else
                            proposal.user_confirmed=true;proposal.confirmed_at=chosen.at;proposal.search_query=query
                            done(proposal,proposal.intro_state=='failed' and d.rating_error or nil);return
                        end
                    elseif proof and not book.force_review then
                        verified[#verified+1]={id=c.id,url=c.url,title=d.title,rating=d.rating,intro=d.intro,intro_state=d.intro_state,edition_exact=proof.edition_exact,
                            relevance=10,checked_detail=true,volume=proof.volume,collection_scope=proof.collection_scope,sources=d.sources}
                    else reject(why or '用户重新检索，等待确认') end
                end
                UIManager:scheduleIn(.7,details)
            end)
        end) then reject(RUN.last_error or '详情请求未启动');finish() end
    end
    if chosen then candidates={{id=chosen.url:match('/subject/(%d+)/'),url=chosen.url,title=chosen.title}};details();return end
    local function add(body,kind)
        local list,err=Inkfolio.discovery(body,kind);if err then reject(err) end
        for _,c in ipairs(list)do if not seen[c.id] then seen[c.id]=true;candidates[#candidates+1]=c end end
    end
    local function rankAndRead()
        table.sort(candidates,function(a,b)
            local x,y=Inkfolio.titleCloseness(query,a.title),Inkfolio.titleCloseness(query,b.title)
            if x~=y then return x>y end;return a.id<b.id
        end)
        if collection then
            local unique,others,groups={},{},{}
            for _,c in ipairs(candidates)do
                local group=Inkfolio.volumeNumber(c.title,collection.base) or normalize(searchTitle(c.title))
                if not groups[group] then groups[group]=true;unique[#unique+1]=c else others[#others+1]=c end
            end
            for _,c in ipairs(others)do unique[#unique+1]=c end;candidates=unique
        end
        details()
    end
    moreSearch=function()
        fallback_attempted=true;candidates={};index=1
        progressStage('正在补充搜索图书（Bing）')
        if not sendHTTP('https://www.bing.com/search?format=rss&q='..socket_url.escape(query..' site:book.douban.com/subject/'),token,function(xml,err)
            if token~=RUN.token then return end
            if err then reject(err) else add(xml,'bing') end
            rankAndRead()
        end) then reject(RUN.last_error or '补充搜索请求未启动');finish() end
    end
    progressStage('正在搜索图书（豆瓣）')
    if not sendHTTP('https://www.douban.com/search?cat=1001&q='..socket_url.escape(query),token,function(body,err)
        if token~=RUN.token then return end
        if err then reject(err) else add(body,'douban') end
        if #candidates>0 then rankAndRead();return end
        fallback_attempted=true
        progressStage('正在搜索图书（Bing）')
        if not sendHTTP('https://www.bing.com/search?format=rss&q='..socket_url.escape(query..' site:book.douban.com/subject/'),token,function(xml,error_text)
            if token~=RUN.token then return end
            if error_text then reject(error_text) else add(xml,'bing') end
            rankAndRead()
        end) then reject(RUN.last_error or '搜索请求未启动');finish() end
    end) then reject(RUN.last_error or '搜索请求未启动');finish() end
end
function Inkfolio.finalizeVerifiedVolumes(candidates)
    return Inkfolio.finalizeVolumes(candidates,true)
end

local function rootPath()
    local selected=G_reader_settings:readSetting(S.library_root)
    if selected then
        if selected~='/' and lfs.attributes(selected,'mode')=='directory' then return selected end
        return nil -- A missing chosen directory must not redirect scans elsewhere.
    end
    local home = G_reader_settings:readSetting('home_dir') or Device.home_dir
    if home and home ~= '/' and lfs.attributes(home, 'mode') == 'directory' then
        return home
    end
    return nil
end
local SKIP_DIR = { ['.adds']=true, ['.kobo']=true, ['.sdr']=true,
    ['.adobe-digital-editions']=true, ['digital editions']=true,
    ['lost+found']=true, ['system volume information']=true }
local BOOK_EXT = {epub=true, pdf=true, mobi=true, azw=true, azw3=true, fb2=true,
    txt=true, rtf=true, djvu=true, cbz=true, cbr=true, html=true, htm=true,
    md=true, doc=true, docx=true, pdb=true, prc=true, xps=true, zip=true}
local function collectPaths()
    local root = rootPath()
    if not root then return nil end
    local out, failed = {}, false
    local function walk(dir, depth)
        if depth > 24 then
            failed=true
            RUN.last_error='书库目录层级超过24层，扫描未完成：'..dir
            logger.warn('InkFolio:',RUN.last_error)
            return
        end
        local ok, iter, state = pcall(lfs.dir, dir)
        if not ok or not iter then
            logger.warn('READ RECEIPT: cannot scan directory', dir)
            failed = true
            RUN.last_error='无法读取书库目录：'..dir
            return
        end
        for filename in iter, state do
            if filename ~= '.' and filename ~= '..' and filename:sub(1,1) ~= '.' then
                local path = dir .. '/' .. filename
                local mode = lfs.symlinkattributes(path, 'mode')
                if not mode then
                    failed=true
                    RUN.last_error='无法读取书库文件属性：'..path
                    logger.warn('InkFolio:',RUN.last_error)
                elseif mode == 'directory' and not SKIP_DIR[filename:lower()] and
                   not filename:lower():match('%.sdr$') then
                    walk(path, depth+1)
                elseif mode == 'file' and BOOK_EXT[(filename:match('%.([^%.]+)$') or ''):lower()]
                    and DocRegistry:hasProvider(path) then
                    out[#out+1] = path
                end
            end
        end
    end
    local ok,reason=pcall(walk,root,0)
    if not ok then
        failed=true
        RUN.last_error='书库扫描失败：'..tostring(reason)
        logger.warn('InkFolio:',RUN.last_error)
    end
    if failed then return nil end
    table.sort(out)
    return out
end
local function observePaths(paths)
    local root=rootPath()
    if LIBRARY.root and LIBRARY.root~=root then LIBRARY.known=nil;LIBRARY.pending={} end
    local known, changed = {}, LIBRARY.known == nil or LIBRARY.root~=root
    LIBRARY.root=root
    for _,path in ipairs(paths) do
        known[path] = true
        if LIBRARY.known and not LIBRARY.known[path] then
            LIBRARY.pending[path] = ''
            changed = true
        end
    end
    for path in pairs(LIBRARY.known or {}) do
        if not known[path] then LIBRARY.pending[path] = nil; changed = true end
    end
    LIBRARY.known = known
    if changed then store:saveSetting('library_files', LIBRARY);store:flush() end
end
local function finishNewPaths(book, complete)
    local paths = (RUN.book_paths or {})[bookKey(book)]
    if not paths then return end
    for _,path in ipairs(paths) do
        if LIBRARY.pending[path] then
            -- Failed books get one new-book attempt per day, avoiding endless retries.
            if complete then LIBRARY.pending[path] = nil
            else LIBRARY.pending[path] = localDate() end
        end
    end
    store:saveSetting('library_files', LIBRARY);store:flush()
end
local function currentBook()
    local ui = ReaderUI.instance
    if ui and ui.document and ui.doc_props then
        local book=extractBook(ui.doc_props,ui.document.file)
        if Inkfolio.collectionInfo(book) and ui.document.getToc then
            local ok,toc=pcall(ui.document.getToc,ui.document)
            if ok and type(toc)=='table' then
                book.contents={}
                for _,entry in ipairs(toc)do if entry.depth==1 and type(entry.title)=='string' then book.contents[#book.contents+1]=entry.title end end
            end
        end
        return book
    end
end
local function getBookFromFile(path)
    local ui = ReaderUI.instance
    if ui and ui.document and ui.document.file == path then
        return currentBook()
    end
    -- KOReader's own metadata reader supports books that have never been opened.
    local ok, props = pcall(BookInfo.getDocProps, {ui = {}}, path)
    if not ok then
        logger.warn('READ RECEIPT: cannot read metadata', path, props)
        return nil
    end
    -- BookInfo.extendProps keeps only KOReader's standard fields. When a
    -- previously opened book has richer sidecar metadata, merge real fields.
    if DocSettings:hasSidecarFile(path) then
        local ok_side, side = pcall(function()
            return DocSettings:open(path):readSetting('doc_props')
        end)
        if ok_side and type(side)=='table' then
            props.publisher = props.publisher or side.publisher
            props.isbn = props.isbn or side.isbn
        end
    end
    return extractBook(props, path)
end
local function abortRound(user_cancel)
    if RUN.info_task then
        Inkfolio.infoResult(RUN.info_task.kind,RUN.info_task.key,user_cancel and 'cancelled' or 'interrupted',not user_cancel and (RUN.sleeping and '休眠中，任务已中断' or not networkingEnabled() and '联网已关闭' or not connected() and '网络未连接' or '任务已中断') or nil)
    elseif user_cancel and RUN.active then Inkfolio.infoCancelled() end
    local cancelled_kind=RUN.worker and RUN.worker.kind or (RUN.active and 'books' or nil)
    if cancelled_kind~='weather' and cancelled_kind~='monthly' then cancelled_kind='books' end
    stopHTTP(user_cancel and '用户取消本轮获取' or nil)
    if user_cancel then
        RUN.auto_holds[cancelled_kind]=true
        RUN.cancelled_wake=RUN.auto_holds.books==true
        DAILY_DONE=false
        saveData()
    elseif RUN.active and RUN.started and not RUN.manual and not RUN.new_books then
        DAILY_DONE = false -- interrupted automatic scan must be retried on reconnection
        saveData()
    end
    RUN.token = RUN.token + 1
    RUN.active, RUN.started, RUN.manual = false, false, false
    RUN.queue = {}
    progressEnd(user_cancel and '已取消获取，已保存的图书信息保留。' or '获取已中断。',RUN.sleeping)
    if startPoll then startPoll() end
end
cancelFetch=function() abortRound(true) end
local function finishRound()
    local processed = RUN.processed
    RUN.active, RUN.manual, RUN.started = false, false, false
    RUN.queue = {}
    local text=string.format('获取结束：已处理 %d / %d 本，更新 %d 本，未完整获取 %d 本。',
        RUN.done or 0,RUN.total or 0,processed,RUN.failed)
    local reason=RUN.last_error or RUN.last_book_error
    if RUN.weather_result then text=text..'\n'..RUN.weather_result end
    if reason then text=text..'\n最近失败原因：'..tostring(reason):sub(1,140) end
    local manual=RUN.review_after_round
    RUN.review_after_round=nil
    progressEnd(text)
    if manual and Inkfolio.pendingCount()>0 then UIManager:scheduleIn(0.1,Inkfolio.showPendingMatches) end
    if startPoll then startPoll() end
end
local function nextItem()
    if not RUN.active then return end
    if RUN.sleeping or not networkingEnabled() or not connected() then
        abortRound(); return
    end
    if weatherCheck(true) then return end
    if RUN.transport_broken then finishRound(); return end
    if Inkfolio.monthlyCheck(nextItem)then return end
    while not RUN.current_only and RUN.index <= #RUN.queue and
        (not Inkfolio.needsFetch(RUN.queue[RUN.index]) or (not RUN.manual and (Inkfolio.bookDeadline(RUN.queue[RUN.index]) or math.huge)>os.time())) do
        Inkfolio.infoResult('books',bookKey(RUN.queue[RUN.index]),'cached')
        finishNewPaths(RUN.queue[RUN.index], true)
        RUN.done=RUN.done+1;PROGRESS.done=RUN.done
        RUN.index = RUN.index + 1
    end
    if RUN.index > #RUN.queue then finishRound(); return end
    local book = RUN.queue[RUN.index]
    RUN.index = RUN.index + 1
    local token = RUN.token
    PROGRESS.book=book.title
    Inkfolio.infoAttempt('books',bookKey(book))
    Inkfolio.bookAttempt(book,RUN.manual)
    fetchBook(book, token, function(record, reason)
        if token ~= RUN.token or not RUN.active then return end
        if record and (not tonumber(record.rating) or tonumber(record.rating)<=0 or tonumber(record.rating)>10 or not validURL(record.url)) then record=nil;reason='获取结果缺少有效评分或链接' end
        if reason or not record then
            reason=reason or '未找到匹配且有评分的图书'
            RUN.failed = RUN.failed + 1
            RUN.last_book_error = reason or '未找到匹配且有评分的图书'
            logger.warn('READ RECEIPT book incomplete:', book.title, RUN.last_book_error)
        end
        if record and record.rating and validURL(record.url) then
            -- A failed introduction refresh must not erase the last valid introduction.
            local previous = cached(book)
            if RUN.current_only and previous and Inkfolio.cacheMatches(book,previous) and record.intro_state=='failed' then
                record.intro,record.intro_source,record.intro_updated_at=previous.intro,previous.intro_source,previous.intro_updated_at
                record.intro_title,record.intro_volume=previous.intro_title,previous.intro_volume
                record.intro_state='failed'
            end
            CACHE[bookKey(book)] = record
            RUN.processed = RUN.processed + 1
            saveData()
            if refreshQuicklook then refreshQuicklook(bookKey(book)) end
        end
        local pending=Inkfolio.matchState.pending[Inkfolio.fileMatchKey(book)]
        Inkfolio.infoResult('books',bookKey(book),record and (reason and 'partial' or 'success') or pending and #pending.candidates>0 and 'pending' or 'failed',reason)
        finishNewPaths(book, completed(book))
        Inkfolio.bookFinished(book)
        RUN.done=RUN.done+1;PROGRESS.done=RUN.done
        UIManager:scheduleIn(0.8, nextItem)
    end)
end
local function beginRound(manual, priority, new_paths, current_only, queued_books)
    resetDay()
    if RUN.active or RUN.worker or RUN.sleeping or not networkingEnabled() or not connected() then return false end
    if current_only and (not manual or not priority or priority.title == '') then return false end
    if not current_only and not new_paths and not queued_books and not rootPath() then
        if manual or not RUN.directory_error_shown then
            UIManager:show(require('ui/widget/infomessage'):new{
                text='书库目录不可用，请在“InkFolio → 联网设置 → 书库目录”选择可读取的文件夹。没有发起联网请求。'})
            RUN.directory_error_shown=true
        end
        return false
    end
    RUN.directory_error_shown=false
    if not manual and (Inkfolio.networkHeld('books') or RUN.transport_broken) then return false end
    if manual then RUN.transport_broken = false; RUN.network_failures = 0 end
    RUN.active = true
    -- A manual request does not release the automatic hold for this wake.
    store:flush()
    if manual then RUN.auto_holds.weather=nil;WEATHER.pending=Inkfolio.weatherEnabled() and selectedWeatherCity()~=nil end
    RUN.weather_result=nil
    RUN.done,RUN.total=0,0
    progressBegin(manual)
    RUN.manual = manual
    RUN.review_after_round=manual
    RUN.current_only = current_only == true
    RUN.new_books = new_paths ~= nil
    RUN.book_paths = {}
    RUN.started = false
    RUN.processed = 0
    RUN.failed = 0
    RUN.last_book_error = nil
    RUN.last_error = nil
    RUN.index = 1
    RUN.token = RUN.token + 1
    local token = RUN.token
    UIManager:scheduleIn(0.05,function()
        if token~=RUN.token or not RUN.active then return end
        local filepaths = (current_only or queued_books) and {} or new_paths or collectPaths()
        if not filepaths then
            finishRound()
            if manual then
                local InfoMessage = require('ui/widget/infomessage')
                UIManager:show(InfoMessage:new{ text = '书库目录不可用，请在“InkFolio → 联网设置 → 书库目录”选择可读取的文件夹。没有发起联网请求。' })
            end
            return false
        end
        if not current_only and not new_paths then observePaths(filepaths) end
        PROGRESS.scan_total,PROGRESS.scan_done=#filepaths,0
        local seen = {}
        RUN.queue = {}
        local function add(book, path)
            if path and LIBRARY.pending[path] then
                if book and not Inkfolio.needsFetch(book) then
                    LIBRARY.pending[path]=nil
                elseif book then
                    local key=bookKey(book)
                    RUN.book_paths[key]=RUN.book_paths[key] or {}
                    table.insert(RUN.book_paths[key],path)
                else
                    LIBRARY.pending[path]=localDate()
                end
            end
            if book and book.title ~= '' and (current_only or Inkfolio.needsFetch(book))
                and (manual or (Inkfolio.bookDeadline(book) or math.huge)<=os.time()) then
                local key = bookKey(book)
                if not seen[key] then
                    seen[key] = true
                    RUN.queue[#RUN.queue+1] = book
                end
            end
        end
        -- Prioritize currently opened book without opening the same document twice.
        if queued_books then for _,book in ipairs(queued_books)do add(book,book.path)end
        elseif not new_paths then add(priority or currentBook()) end
        local idx = 1
        local function scanStep()
            if token ~= RUN.token or not RUN.active then return end
            if RUN.sleeping or not networkingEnabled() then abortRound(); return end
            for _ = 1, 3 do
                if idx > #filepaths then
                    RUN.total=#RUN.queue
                    PROGRESS.total,PROGRESS.scanning=RUN.total,false
                    if not current_only then store:saveSetting('library_files',LIBRARY);store:flush() end
                    if #RUN.queue==0 and not RUN.manual and not RUN.new_books then DAILY_DONE=true;saveData() end
                    nextItem()
                    return
                end
                add(getBookFromFile(filepaths[idx]),filepaths[idx])
                idx = idx + 1
                PROGRESS.scan_done=idx-1
            end
            UIManager:scheduleIn(0.03, scanStep)
        end
        scanStep()
    end)
    return true
end

selectedWeatherCity=function()
    local code=G_reader_settings:readSetting(S.weather_city)
    if code==nil then code='lqYjK' end
    if not code then return nil end
    for _,region in ipairs(WEATHER_REGIONS) do
        for _,city in ipairs(region.cities) do
            if city.code~='' and city.code==code then return city end
        end
    end
end
-- Cover weather is exclusive; the other skins retain their two-day choices.
function Inkfolio.coverWeather()
    local choice=G_reader_settings:readSetting(S.cover_weather)
    if choice==nil then
        if enabled(S.weather)then return 'today' end
        return G_reader_settings:readSetting(S.weather_tomorrow)==true and 'tomorrow'or 'off'
    end
    assert(choice=='today'or choice=='tomorrow'or choice=='off','InkFolio: 封面天气选项无效')
    return choice
end
function Inkfolio.weatherSelected(offset,appearance)
    assert(offset==0 or offset==1,'InkFolio: 无效天气日期')
    if Inkfolio.uiStyle(appearance).id=='cover'then
        return Inkfolio.coverWeather()==(offset==0 and 'today'or 'tomorrow')
    end
    return offset==0 and enabled(S.weather) or offset==1 and G_reader_settings:readSetting(S.weather_tomorrow)==true
end
function Inkfolio.weatherEnabled(appearance)
    return Inkfolio.weatherSelected(0,appearance) or Inkfolio.weatherSelected(1,appearance)
end
function Inkfolio.weatherDate(offset,day)
    local year,month,date=(day or localDate()):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    assert(year,'InkFolio: 无效天气日期')
    -- Calendar arithmetic at noon handles month/year changes and local DST.
    return os.date('%Y-%m-%d',os.time{year=tonumber(year),month=tonumber(month),day=tonumber(date)+offset,hour=12})
end
function Inkfolio.cachedWeather(record,date,day)
    if not record or record.day~=(day or localDate()) then return nil end
    if record.forecasts then
        assert(type(record.forecasts)=='table','InkFolio: 天气预报缓存结构损坏')
        return record.forecasts[date]
    end
    -- Read a valid pre-two-day cache without rewriting or discarding it.
    if date==record.day then return record.text end
end
function Inkfolio.weatherDeadline(now)
    if not Inkfolio.weatherEnabled() or not selectedWeatherCity() or Inkfolio.networkHeld('weather') then return nil end
    now=now or os.time()
    if WEATHER.pending==true then return now end
    local city=selectedWeatherCity();local day=os.date('%Y-%m-%d',now)
    local record=WEATHER.records[city.code]
    if WEATHER.attempt_city==city.code and WEATHER.attempt_day==day and WEATHER.next_at then
        return math.max(now,math.min(WEATHER.next_at,Inkfolio.nextDay(now)))
    end
    if record and record.day==day and record.updated_at then
        local complete=true
        for offset=0,1 do
            if Inkfolio.weatherSelected(offset) and not Inkfolio.cachedWeather(record,Inkfolio.weatherDate(offset,day),day) then complete=false end
        end
        if complete then return math.max(now,math.min(record.updated_at+Inkfolio.NET_RULES.weather_age,Inkfolio.nextDay(now))) end
    end
    if WEATHER.attempt_city==city.code and WEATHER.attempt_day==day then return Inkfolio.nextDay(now) end
    return now
end
local function weatherPending()
    local due=Inkfolio.weatherDeadline()
    return due~=nil and due<=os.time()
end
local function validTemperature(value)
    local n=tonumber(value)
    if n and n>=-90 and n<=65 then return n end
end
local function parseWeather(body,code,day)
    local ok,response=pcall(function() return require('rapidjson').decode(body) end)
    if not ok or type(response)~='table' then return nil,'天气数据JSON无法解析' end
    if response.code~=0 or type(response.data)~='table' then return nil,'天气数据接口返回异常' end
    local data=response.data
    local forecast=data.predict
    if type(forecast)~='table' or type(forecast.station)~='table' or forecast.station.code~=code then return nil,'天气数据城市不匹配或缺失' end
    local entry
    for _,item in ipairs(type(forecast.detail)=='table' and forecast.detail or {}) do
        if type(item)=='table' and item.date==day then entry=item;break end
    end
    if not entry then return nil,'天气数据缺少请求日期的预报' end
    local dw=type(entry.day)=='table' and entry.day.weather or nil
    local nw=type(entry.night)=='table' and entry.night.weather or nil
    dw=type(dw)=='table' and dw or {}; nw=type(nw)=='table' and nw or {}
    local high,low=validTemperature(dw.temperature),validTemperature(nw.temperature)
    -- The official daily chart supplies both extrema when the daytime forecast has expired.
    if not high or not low then
        for _,item in ipairs(type(data.tempchart)=='table' and data.tempchart or {}) do
            if type(item)=='table' and type(item.time)=='string' and item.time:gsub('/','-')==day then
                high,low=validTemperature(item.max_temp),validTemperature(item.min_temp)
                break
            end
        end
    end
    if not high or not low or high<low then return nil,'天气数据温度范围无效或缺失' end
    local info=dw.info
    if not info or info=='' or info=='9999' then info=nw.info end
    if type(info)~='string' or info=='' or info=='9999' then return nil,'天气数据状态无效或缺失' end
    if info=='阴' then info='阴天' end
    return info..' '..string.format('%.0f～%.0f°C',low,high)
end
local function cityLabel(city)
    return (city.name:gsub('市$',''))
end
local function weatherText(offset,include_city)
    offset=offset or 0
    local label=offset==0 and '今日' or '明日'
    local city=selectedWeatherCity()
    if not city then return include_city==false and (label..' 未选择城市') or '未选择城市' end
    local prefix=(include_city==false and '' or (cityLabel(city)..'　'))..label..' '
    if RUN.worker and RUN.worker.kind=='weather' and RUN.worker.city==city.code then return prefix..'获取中…' end
    if WEATHER.error and WEATHER.attempt_city==city.code and WEATHER.attempt_day==localDate() then return prefix..WEATHER.error end
    local record=WEATHER.records[city.code]
    local text=Inkfolio.cachedWeather(record,Inkfolio.weatherDate(offset))
    if text then return prefix..text end
    if record and record.day==localDate() and record.forecast_errors and record.forecast_errors[Inkfolio.weatherDate(offset)] then return prefix..'天气获取失败' end
    if WEATHER.attempt_city==city.code and WEATHER.attempt_day==localDate() then return prefix..'天气获取失败' end
    return prefix..'待联网更新'
end
weatherCheck=function(allow_active)
    if RUN.sleeping or not networkingEnabled() or RUN.transport_broken or (RUN.active and not allow_active) or RUN.worker or not weatherPending() then return false end
    if not connected() then return false end
    local city,day,token=selectedWeatherCity(),localDate(),RUN.token
    local standalone=not RUN.active
    if standalone then
        RUN.processed,RUN.failed=0,0
        progressBegin(false,true)
    end
    progressStage('正在获取'..cityLabel(city)..'天气')
    Inkfolio.infoAttempt('weather',city.code)
    local started=sendHTTP('https://www.nmc.cn/rest/weather?stationid='..socket_url.escape(city.code),token,function(body,error_text)
        if token~=RUN.token then return end
        local forecasts,errors={},{}
        for offset=0,1 do
            local date=Inkfolio.weatherDate(offset,day)
            if error_text then errors[date]=error_text
            else forecasts[date],errors[date]=parseWeather(body,city.code,date) end
        end
        local any=next(forecasts)~=nil
        local success=true
        local reason=error_text
        local result={}
        for offset=0,1 do
            local date=Inkfolio.weatherDate(offset,day)
            if Inkfolio.weatherSelected(offset) then
                if not forecasts[date] then success=false;reason=reason or errors[date] end
                result[#result+1]=(offset==0 and '今日 ' or '明日 ')..(forecasts[date] or '天气获取失败')
            end
        end
        if any then
            WEATHER.records[city.code]={day=day,text=forecasts[day],forecasts=forecasts,forecast_errors=errors,updated_at=os.time()}
            WEATHER.error=nil
        else
            WEATHER.error='天气获取失败'
        end
        if not success then logger.warn('READ RECEIPT weather:',reason) end
        Inkfolio.infoResult('weather',city.code,success and 'success' or 'failed',not success and reason or nil)
        RUN.weather_result=cityLabel(city)..'：'..table.concat(result,'；')
        store:saveSetting('weather',WEATHER);store:flush()
        if refreshQuicklook then refreshQuicklook() end
        UIManager:nextTick(function()
            if token~=RUN.token then return end
            if RUN.active then nextItem()
            elseif weatherPending() then weatherCheck()
            else progressEnd(RUN.weather_result);startPoll() end
        end)
    end,'weather')
    if started then
        WEATHER.pending=false
        WEATHER.attempt_day,WEATHER.attempt_city,WEATHER.error=day,city.code,'天气获取中断'
        WEATHER.next_at=os.time()+Inkfolio.NET_RULES.weather_age
        RUN.worker.city=city.code
        store:saveSetting('weather',WEATHER);store:flush()
    else
        WEATHER.pending=false
        WEATHER.attempt_day,WEATHER.attempt_city=day,city.code
        WEATHER.next_at=os.time()+Inkfolio.NET_RULES.weather_age
        WEATHER.error='天气请求未启动'
        Inkfolio.infoResult('weather',city.code,'failed',RUN.last_error or WEATHER.error)
        store:saveSetting('weather',WEATHER);store:flush()
        if standalone then progressEnd(WEATHER.error) end
    end
    return started
end

function Inkfolio.weatherChanged(selected)
    if selected then RUN.auto_holds.weather=nil end
    if Inkfolio.weatherEnabled() then
        local city=selectedWeatherCity()
        local record=city and WEATHER.records[city.code]
        for offset=0,1 do
            if selected and city and Inkfolio.weatherSelected(offset) and not Inkfolio.cachedWeather(record,Inkfolio.weatherDate(offset)) then
                WEATHER.pending=true;Inkfolio.resetNetworkPause()
            end
        end
        weatherCheck()
    elseif RUN.worker and RUN.worker.kind=='weather' then
        Inkfolio.infoResult('weather',RUN.worker.city,'interrupted','天气显示已关闭')
        stopHTTP('天气显示已关闭')
        if RUN.active then UIManager:nextTick(nextItem) else progressEnd('天气显示已关闭') end
    end
    if startPoll then startPoll()end
    if refreshQuicklook then refreshQuicklook() end
end

local function newBooksCheck(force)
    if not force or RUN.sleeping or RUN.active or RUN.worker or RUN.scanning then return false end
    RUN.scan_pending=false
    local paths=collectPaths()
    if not paths then return false end
    observePaths(paths);RUN.scanning=true
    local index=1
    local function step()
        if RUN.sleeping then RUN.scanning=false;RUN.scan_pending=true;Inkfolio.saveNetwork();return end
        for _=1,3 do
            local path=paths[index]
            if not path then
                RUN.scanning=false;Inkfolio.saveNetwork()
                dailyCheck();startPoll();return
            end
            Inkfolio.queueBook(getBookFromFile(path),true);index=index+1
        end
        UIManager:scheduleIn(.03,step)
    end
    step();return true
end
function Inkfolio.monthlyDeadline(now)
    if not enabled(S.intro) or Inkfolio.networkHeld('monthly') then return nil end
    now=now or os.time()
    local state=Inkfolio.monthly
    if state.pending then return now end
    local cached=Inkfolio.visibleMonthly()
    if cached and cached.complete and cached.update_date:sub(1,7)==os.date('%Y-%m',now) then
        local d=os.date('*t',now)
        return os.time{year=d.year,month=d.month+1,day=1,hour=0,min=0,sec=0}
    end
    if state.attempt_day==os.date('%Y-%m-%d',now) then return Inkfolio.nextDay(now) end
    return now
end
function Inkfolio.dueBooks(now)
    now=now or os.time();local due,changed={},false
    for key,book in pairs(NET.pending)do
        if not Inkfolio.needsFetch(book) or (book.path and lfs.attributes(book.path,'mode')~='file') then
            NET.pending[key]=nil;changed=true
        elseif (Inkfolio.bookDeadline(book,now) or math.huge)<=now then due[#due+1]=book end
    end
    if changed then Inkfolio.saveNetwork() end
    local current=currentBook();local priority=current and bookKey(current)
    table.sort(due,function(a,b)
        local x,y=bookKey(a),bookKey(b)
        if (x==priority)~=(y==priority)then return x==priority end
        return x<y
    end)
    return due
end
dailyCheck=function(scan)
    resetDay()
    if scan then RUN.scan_pending=true end
    if RUN.sleeping or not networkingEnabled() or RUN.scanning or RUN.active or RUN.worker then return end
    if RUN.scan_pending and newBooksCheck(true) then return end
    if RUN.transport_broken or not connected() then return end
    if weatherCheck() then return end
    if Inkfolio.monthlyCheck() then return end
    if not Inkfolio.networkHeld('books') then
        local books=Inkfolio.dueBooks()
        if #books>0 then beginRound(false,nil,nil,false,books) end
    end
end
local function currentCheck()
    resetDay();Inkfolio.queueBook(currentBook());dailyCheck()
end
local POLL_ENABLED=false
local function pollWifi()
    POLL_ENABLED=false
    dailyCheck();startPoll()
end
startPoll=function()
    UIManager:unschedule(pollWifi);POLL_ENABLED=false
    if RUN.sleeping or not networkingEnabled() or RUN.transport_broken or RUN.scanning or RUN.active or RUN.worker then return end
    local now=os.time();local deadline
    local function consider(value)if value then deadline=deadline and math.min(deadline,value)or value end end
    if RUN.scan_pending then consider(now)end
    consider(Inkfolio.weatherDeadline(now));consider(Inkfolio.monthlyDeadline(now))
    if not Inkfolio.networkHeld('books')then
        for _,book in pairs(NET.pending)do consider(Inkfolio.bookDeadline(book,now))end
    end
    if not deadline or (deadline<=now and not RUN.scan_pending and not connected())then return end
    POLL_ENABLED=true;UIManager:scheduleIn(math.max(.05,deadline-now),pollWifi)
end
function Inkfolio.libraryChanged()
    RUN.scan_pending=true
    if RUN.scan_scheduled then return end
    RUN.scan_scheduled=true
    UIManager:nextTick(function()
        RUN.scan_scheduled=false;dailyCheck();startPoll()
    end)
end
local function updateManually()
    if not networkingEnabled() then
        local InfoMessage = require('ui/widget/infomessage')
        UIManager:show(InfoMessage:new{ text = '插件联网已关闭，请先开启联网开关。' })
        return
    end
    if RUN.active or RUN.worker then
        local InfoMessage = require('ui/widget/infomessage')
        UIManager:show(InfoMessage:new{ text = '已有查询正在进行，请稍后重试。' })
        return
    end
    -- Capture the reading context at invocation, including delayed Wi-Fi connection.
    local target = currentBook()
    if ReaderUI.instance and ReaderUI.instance.document and (not target or target.title == '') then
        UIManager:show(require('ui/widget/infomessage'):new{text='当前图书信息不可读取，没有发起获取。'})
        return
    end
    local function beginManual() return beginRound(true, target, nil, target ~= nil) end
    if connected() then beginManual(); return end
    if not Device:hasWifiToggle() then
        UIManager:show(require('ui/widget/infomessage'):new{
            text='当前网络不可用，请在设备系统设置中连接网络后重试。'})
        return
    end
    if NetworkMgr:isWifiOn() then
        local InfoMessage = require('ui/widget/infomessage')
        UIManager:show(InfoMessage:new{text='Wi-Fi 已开启，但尚未连接网络。请先连接后重试。'})
        return
    end
    local ConfirmBox = require('ui/widget/confirmbox')
    UIManager:show(ConfirmBox:new{
        text = '当前 Wi-Fi 未连接，需要开启 Wi-Fi 才能手动更新图书信息。',
        ok_text = '开启 Wi-Fi', cancel_text = '取消',
        ok_callback = function()
            if not networkingEnabled() then return end
            MANUAL_CONNECT_PENDING = true
            local ok = NetworkMgr:enableWifi(function()
                if not MANUAL_CONNECT_PENDING then return end
                MANUAL_CONNECT_PENDING = false
                if networkingEnabled() and connected() then beginManual() end
            end, true)
            if ok == false then MANUAL_CONNECT_PENDING = false end
            UIManager:scheduleIn(48, function()
                if MANUAL_CONNECT_PENDING then
                    MANUAL_CONNECT_PENDING = false
                    local InfoMessage = require('ui/widget/infomessage')
                    UIManager:show(InfoMessage:new{text='Wi-Fi 连接失败，未执行手动更新。'})
                end
            end)
        end,
    })
end
-- ---------- 纸质票根与机打排版 ----------
-- 融合了手撕票根的半圆齿孔、细纸边和真实收银小票的两端对齐明细。
-- 纸张和纹理只用内建画笔；票头使用上方指定的字体。
-- v2.5: 票纸边缘的磨蹭脏印。所有坐标都限制在纸张内侧留白区；
-- 固定整数散列产生可重复的深浅斑点，不使用随机数，也不加载图片。
-- 优先采用 paintRect（BlitBuffer 原生矩形填充），减少逐像素读写。
local function printEdgePatina(bb, x, y, w, h, top_pad, bottom_pad, left_pad, right_pad)
    -- 留出至少 6 像素的空白隔离带，避免碰到正文或封面。
    local max_depth = math.min(22, top_pad - 6, bottom_pad - 6,
                                    left_pad - 6, right_pad - 6)
    if max_depth < 4 then return end
    local function noise(a, b, side)
        return (a * 92821 + b * 68917 + side * 17041
             + (a * b) % 173 * 379) % 1009
    end
    -- edge: 1 上、2 下、3 左、4 右；沿边移动，深度逐步衰减。
    for edge = 1, 4 do
        local horizontal = edge <= 2
        local extent = horizontal and w or h
        for along = 3, extent - 12, 3 do
            local zone = noise(math.floor(along / 41), 17, edge)
            local dense_zone = zone % 7 < 2  -- 墨辊接触不均，形成稀疏的污渍区域。
            for depth = 2, max_depth, 2 do
                local r = noise(along, depth, edge)
                local chance = math.max(8, 135 - depth * 6)
                if dense_zone then chance = chance + 54 end
                if along < 85 or extent - along < 85 then chance = chance + 16 end
                if r < chance then
                    local shade = (r % 13 == 0) and Blitbuffer.COLOR_GRAY_5
                              or ((r % 3 == 0) and Blitbuffer.COLOR_GRAY_7
                              or Blitbuffer.COLOR_GRAY_9)
                    -- 斑点大小不一；极偶尔出现短而窄的擦痕。
                    local length = (r % 47 == 0 and depth < 8) and 7
                                 or ((r % 9 == 0) and 3 or 1)
                    local thickness = (r % 11 == 0) and 2 or 1
                    local rw = horizontal and length or thickness
                    local rh = horizontal and thickness or length
                    local px, py
                    if edge == 1 then
                        px, py = x + along, y + 2 + depth
                    elseif edge == 2 then
                        px, py = x + along, y + h - 3 - depth - rh + 1
                    elseif edge == 3 then
                        px, py = x + 2 + depth, y + along
                    else
                        px, py = x + w - 3 - depth - rw + 1, y + along
                    end
                    bb:paintRect(px, py, rw, rh, shade)
                end
            end
        end
    end
end

local ClassicPaper = WidgetContainer:extend{
    padding_top = 28, padding_bottom = 30,
    padding_left = 28, padding_right = 28, shadow_width = 8,
}
function ClassicPaper:getSize()
    local size = self[1]:getSize()
    return Geom:new{
        w = size.w + self.padding_left + self.padding_right + self.shadow_width,
        h = size.h + self.padding_top + self.padding_bottom,
    }
end
function ClassicPaper:paintTo(bb, x, y)
    local sz = self:getSize()
    self.dimen = Geom:new{x=x,y=y,w=sz.w,h=sz.h}
    local ink, white = self.outline_color or Blitbuffer.COLOR_GRAY_3, Blitbuffer.COLOR_WHITE
    local outline=self.outline_width or 1
    local w, h = sz.w-self.shadow_width, sz.h
    local under=bb:copy()
    local function restoreRect(rx,ry,rw,rh)
        bb:blitFrom(under,rx,ry,rx,ry,rw,rh)
    end
    local function restoreCircle(cx,cy,r)
        for dy=-r,r do
            local half=math.floor(math.sqrt(r*r-dy*dy))
            restoreRect(cx-half,cy+dy,half*2+1,1)
        end
    end
    for i=0,self.shadow_width-1 do
        local shade=math.floor(95+145*i/math.max(1,self.shadow_width-1))
        bb:paintRect(x+w+i,y+3,1,h-3,Blitbuffer.Color8(shade))
    end
    local radius = math.max(8, math.floor(math.min(w / 22, 17)))
    local side_r = math.max(9, math.floor(radius * 1.2))
    bb:paintRect(x, y, w, h, white)
    if not self.outline_color then bb:paintBorder(x, y, w, h, outline, ink, 0) end
    -- 先渲染边缘脏印，再挖齿孔和侧面缺口：缺口内仍是干净的纸外背景。
    -- 最后才绘制正文，因此任何脏印都不会覆盖文字。
    printEdgePatina(bb, x, y, w, h,
        self.padding_top, self.padding_bottom, self.padding_left, self.padding_right)
    if self.outline_color then bb:paintBorder(x,y,w,h,outline,ink,0) end
    -- 一排连贯的半圆缺口。先挖洞再画弧线，只保留纸内侧半圆。
    local count = math.max(3, math.floor((w-radius*3) / (radius*2.9)))
    local pitch = (w-radius*3)/(count-1)
    for i=0,count-1 do
        local cx=math.floor(x+radius*1.5+i*pitch)
        for _,edge in ipairs({'top','bottom'}) do
            local cy=(edge=='top') and y or (y+h-1)
            restoreCircle(cx,cy,radius)
            bb:paintCircle(cx,cy,radius,ink,outline)
            if edge=='top' then
                restoreRect(cx-radius-2,cy-radius-2,2*radius+4,radius+3)
            else
                restoreRect(cx-radius-2,cy+1,2*radius+4,radius+3)
            end
        end
    end
    -- 单对侧边内凹缺口，作为上下区块之间的视觉停顿。
    local side_y=math.floor(y+self.padding_top+self.stub_y)
    for _,edge in ipairs({'left','right'}) do
        local cx=(edge=='left') and x or (x+w-1)
        restoreCircle(cx,side_y,side_r)
        bb:paintCircle(cx,side_y,side_r,ink,outline)
        if edge=='left' then
            restoreRect(cx-side_r-2,side_y-side_r-2,side_r+3,2*side_r+4)
        else
            restoreRect(cx+1,side_y-side_r-2,side_r+3,2*side_r+4)
        end
    end
    under:free()
    self[1]:paintTo(bb,x+self.padding_left,y+self.padding_top)
end

local ReceiptPaper=ClassicPaper:extend{}
function ReceiptPaper:paintTo(bb,x,y)
    if self.theme.id=='classic' then return ClassicPaper.paintTo(self,bb,x,y) end
    local size=self:getSize()
    self.dimen=Geom:new{x=x,y=y,w=size.w,h=size.h}
    bb:paintRect(x,y,size.w,size.h,Blitbuffer.COLOR_WHITE)
    if self.theme.id=='pixel' then
        for gy=self.grid_pitch,size.h-self.grid_pitch,self.grid_pitch do
            for gx=self.grid_pitch,size.w-self.grid_pitch,self.grid_pitch do
                if gx<self.padding_left/2 or gx>size.w-self.padding_right/2
                    or gy<self.padding_top/2 or gy>size.h-self.padding_bottom/2 then
                    bb:paintRect(x+gx,y+gy,self.grid_dot,self.grid_dot,Blitbuffer.COLOR_GRAY_9)
                end
            end
        end
    end
    if self.outline_color then bb:paintBorder(x,y,size.w,size.h,self.outline_width,self.outline_color,0) end
    self[1]:paintTo(bb,x+self.padding_left,y+self.padding_top)
end
local PrintRule=WidgetContainer:extend{width=400,height=1,kind='dash',scale=1}
function PrintRule:getSize()
    return Geom:new{w=self.kind=='vertical' and math.max(1,math.floor(self.scale+.5)) or self.width,h=self.height}
end
function PrintRule:paintTo(bb,x,y)
    local size=self:getSize()
    self.dimen=Geom:new{x=x,y=y,w=size.w,h=size.h}
    if self.kind=='vertical' or self.kind=='solid' or self.theme.id=='swiss' then
        bb:paintRect(x,y,size.w,size.h,self.kind=='solid' and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_5)
    else
        local mark,gap
        if self.theme.id=='pixel' then mark,gap=self.height,math.max(2,self.height*3)
        else mark,gap=math.max(1,math.floor(8*self.scale+.5)),math.max(1,math.floor(7*self.scale+.5)) end
        for i=0,self.width-1,mark+gap do bb:paintRect(x+i,y,math.min(mark,self.width-i),self.height,Blitbuffer.COLOR_GRAY_3) end
    end
end

-- ---------- 仿热敏纸印迹 ----------
-- 只处理文字组件本身的已印墨点，不覆盖白底、不处理封面。
-- 逐点按固定散列产生掉墨/浅印，跨次重绘一致，不会出现随机闪烁。
-- wrapper 的 getSize 与原组件相同：不改变 v2.3 的任何布局尺寸和位置。
local InkWear = WidgetContainer:extend{wear_level=1, wear_seed=1}
function InkWear:getSize()
    return self[1]:getSize()
end
function InkWear:getBaseline()
    return self[1]:getBaseline()
end
local function wearInk(bb, x, y, width, height, level, seed)
    -- KOReader 的 BlitBuffer 支持像素读取及设置，RGB/灰阶均可转为 Color8。
    -- 所有点都限制在原组件的可视区域，避免修改周围文字与票根轮廓。
    local x0, y0 = math.max(0,math.floor(x)), math.max(0,math.floor(y))
    local x1 = math.min(bb:getWidth(),math.floor(x+width))
    local y1 = math.min(bb:getHeight(),math.floor(y+height))
    if x1<=x0 or y1<=y0 then return end
    local step = level==3 and 2 or (level==2 and 3 or 4)
    local density = level==3 and 215 or (level==2 and 145 or 78)
    local white, faded = Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_9
    for py=y0,y1-1,step do
        local ly=py-y0
        for px=x0,x1-1,step do
            local lx=px-x0
            -- 加入低频的印刷压力变化，模拟滚轮下压不均；采用整数散列且不取随机数。
            local pressure = ((math.floor(lx/29)+math.floor(ly/11)+seed)%7<2) and 65 or 0
            local h=(lx*92821+ly*68917+((lx*ly)%251)*499+seed*131)%1009
            if h<density+pressure then
                local tone=bb:getPixel(px,py):getColor8().a
                -- 仅处理明显的深色墨点，亮底与抗锯齿边缘不受影响。
                if tone<160 then
                    local erase=h%5==0
                    bb:setPixel(px,py,erase and white or faded)
                    -- 大标题加入极少量横向缺墨，模仿热敏头的细小擦痕。
                    if erase and level==3 and h%3==0 and px+1<x1 then
                        local adjacent=bb:getPixel(px+1,py):getColor8().a
                        if adjacent<150 then bb:setPixel(px+1,py,white) end
                    end
                end
            end
        end
    end
end
function InkWear:paintTo(bb,x,y)
    self[1]:paintTo(bb,x,y)
    local size=self:getSize()
    wearInk(bb,x,y,size.w,size.h,self.wear_level,self.wear_seed)
end
local function inkSeed(value)
    local seed=37
    local str=tostring(value or '')
    for i=1,math.min(#str,128) do seed=(seed*33+str:byte(i))%65521 end
    return seed
end
local function inkText(widget, text, level)
    return InkWear:new{wear_level=level,wear_seed=inkSeed(text),widget}
end

local PixelProgress=WidgetContainer:extend{}
function PixelProgress:getSize() return Geom:new{w=self.width,h=self.height} end
function PixelProgress:paintTo(bb,x,y)
    self.dimen=Geom:new{x=x,y=y,w=self.width,h=self.height}
    local count=20
    local filled=math.floor(math.max(0,math.min(1,self.percentage))*count)
    local gap=self.gap
    local usable=self.width-(count-1)*gap
    for i=0,count-1 do
        local left=math.floor(i*usable/count)+i*gap
        local right=math.floor((i+1)*usable/count)+i*gap
        local width=right-left
        if i<filled then bb:paintRect(x+left,y,width,self.height,Blitbuffer.COLOR_BLACK)
        else bb:paintBorder(x+left,y,width,self.height,self.stroke,Blitbuffer.COLOR_GRAY_3,0) end
    end
end

local ReadingBars=WidgetContainer:extend{}
function ReadingBars:getSize() return Geom:new{w=self.width,h=self.height} end
function ReadingBars:paintTo(bb,x,y)
    self.dimen=Geom:new{x=x,y=y,w=self.width,h=self.height}
    local fs=self.font_size
    local theme=self.theme or Inkfolio.uiStyle()
    local axis_font=theme.fonts.body
    local function label(text,lx,ly,width,align,color)
        local t=TextBoxWidget:new{text=text,face=Font:getFace(axis_font,fs),
            width=width,alignment=align or 'left',justified=false,fgcolor=color or Blitbuffer.COLOR_BLACK}
        t:paintTo(bb,lx,ly);t:free()
    end
    local font_px=Font:getFace(axis_font,fs).size
    local top=math.floor(font_px*.3)
    local bottom=self.height-math.floor(font_px*1.8)
    local right=self.width-math.max(2,self.stroke)
    local is_words=self.data.metric=='words'
    local peak=0
    local function value(day)return is_words and day.words or (day.seconds and day.seconds/60) end
    for _,day in ipairs(self.data.days) do peak=math.max(peak,value(day) or 0) end
    local step=is_words and 10^math.max(0,math.floor(math.log(math.max(1,peak))/math.log(10))) or 30
    local ceiling=math.max(step,math.ceil(peak/step)*step)
    local top_label=is_words and (ceiling>=10000 and string.format('%.1f万字',ceiling/10000) or string.format('%.0f字',ceiling)) or (tostring(ceiling)..'分')
    local axis=TextWidget:new{text=top_label,face=Font:getFace(axis_font,fs),padding=0}
    local left=math.ceil(axis:getSize().w)+math.max(2,self.stroke*2)
    axis:free()
    label(top_label,x,y+top,left,'left')
    label('0',x,y+bottom-math.floor(font_px*.9),left,'left')
    for _,gy in ipairs({bottom}) do
        for gx=left,right,7 do bb:paintRect(x+gx,y+gy,2,1,Blitbuffer.COLOR_GRAY_9) end
    end
    local n=#self.data.days
    local cell=(right-left)/n
    local bw=math.max(1,math.floor(cell*.58))
    for i,day in ipairs(self.data.days) do
        local gx=left+math.floor((i-.5)*cell)
        local amount=value(day)
        if amount and amount>0 then
            local bh=math.max(1,math.floor((bottom-top)*amount/ceiling+.5))
            if theme.id=='pixel' then
                local dot=math.max(1,math.min(self.stroke*2,math.floor(bw/2)))
                local pitch=dot+math.max(1,self.stroke)
                local columns=math.max(1,math.floor((bw+pitch-dot)/pitch))
                local gridw=(columns-1)*pitch+dot
                for column=0,columns-1 do for rise=0,bh-1,pitch do
                    local dh=math.min(dot,bh-rise)
                    bb:paintRect(x+gx-math.floor(gridw/2)+column*pitch,y+bottom-rise-dh,dot,dh,Blitbuffer.COLOR_BLACK)
                end end
            else bb:paintRect(x+gx-math.floor(bw/2),y+bottom-bh,bw,bh,Blitbuffer.COLOR_BLACK) end
        end
        if not day.future and amount==nil then
            -- A slash is unknown data; a flat short dash is a recorded zero.
            for k=0,math.max(3,self.stroke*2) do bb:paintRect(x+gx-1+k,y+bottom-k,1,1,Blitbuffer.COLOR_BLACK) end
        elseif not day.future and amount==0 then
            bb:paintRect(x+gx-math.floor(bw/2),y+bottom-math.max(2,self.stroke),bw,math.max(1,self.stroke),Blitbuffer.COLOR_BLACK)
        end
        if not day.future and day.incomplete then
            bb:paintCircle(x+gx,y+top,math.max(1,self.stroke),Blitbuffer.COLOR_BLACK)
        end
        if n==7 or i==1 or i==n or (day.day%5==0 and i<n-1) then
            local lw=math.floor(font_px*2)
            local lx=math.max(0,math.min(self.width-lw,gx-math.floor(lw/2)))
            label(n==7 and ({'一','二','三','四','五','六','日'})[i] or tostring(day.day),
                x+lx,y+bottom+math.floor(font_px*.25),lw,'center',day.future and Blitbuffer.COLOR_GRAY_6 or nil)
        end
    end
end

-- Book words are progress estimates; daily words use wake-session deduplicated increments.
Inkfolio.wordPath=DataStorage:getSettingsDir()..'/read_receipt_v2_words.lua'
Inkfolio.wordState={books={},session={},session_total=0,sleeping=false,errors={},
    days={},tracking_since=os.time(),dirty=true}
function Inkfolio.validRecordDate(value)
    if type(value)~='string' or not value:match('^%d%d%d%d%-%d%d%-%d%d$') then return false end
    local y,m,d=value:match('^(%d+)%-(%d+)%-(%d+)$')
    local t=os.time{year=tonumber(y),month=tonumber(m),day=tonumber(d),hour=12}
    return t and os.date('%Y-%m-%d',t)==value
end
function Inkfolio.validWordInteger(value)
    return type(value)=='number' and value>=0 and value<math.huge and value==math.floor(value)
end
if lfs.attributes(Inkfolio.wordPath,'mode')=='file' then
    local ok,data=pcall(dofile,Inkfolio.wordPath)
    if ok then
        ok=pcall(function()
            assert(type(data)=='table' and (data.version==1 or data.version==2 or data.version==3) and type(data.books)=='table')
            for path,book in pairs(data.books) do
                assert(type(path)=='string' and type(book)=='table' and type(book.signature)=='string')
                assert(book.document_total==nil or Inkfolio.validWordInteger(book.document_total))
                Inkfolio.wordState.books[path]={signature=book.signature,document_total=book.document_total}
            end
            if data.version==3 then
                assert(Inkfolio.validWordInteger(data.tracking_since) and type(data.days)=='table')
                for date,day in pairs(data.days) do
                    assert(Inkfolio.validRecordDate(date) and type(day)=='table' and Inkfolio.validWordInteger(day.words))
                    assert(day.incomplete==nil or type(day.incomplete)=='boolean')
                end
                Inkfolio.wordState.days=data.days;Inkfolio.wordState.tracking_since=data.tracking_since
                Inkfolio.wordState.dirty=false
            end
        end)
    end
    if not ok then Inkfolio.wordState.storage_error='字数及每日记录损坏' end
end
function Inkfolio.scheduleWordSave()
    local state=Inkfolio.wordState
    state.dirty=true
    if not state.flush_scheduled then state.flush_scheduled=true;UIManager:scheduleIn(5,Inkfolio.flushWords) end
end
function Inkfolio.recordDailyWords(amount,incomplete,now)
    local state=Inkfolio.wordState
    if state.storage_error then return end
    assert(Inkfolio.validWordInteger(amount),'每日新增字数无效')
    local date=os.date('%Y-%m-%d',now or os.time())
    local day=state.days[date] or {words=0}
    if state.days[date] and amount==0 and (not incomplete or day.incomplete) then return end
    day.words=day.words+amount
    if incomplete then day.incomplete=true end
    state.days[date]=day;Inkfolio.scheduleWordSave()
end
function Inkfolio.readWordChart(period,now)
    local state=Inkfolio.wordState
    if state.storage_error then return nil,state.storage_error end
    local days=Inkfolio.periodDays(period,now)
    local total,missing,incomplete=0,0,false
    for _,day in ipairs(days) do
        if not day.future then
            local recorded=state.days[os.date('%Y-%m-%d',day.start)]
            if day.finish<=state.tracking_since or not recorded then missing=missing+1
            else
                day.words=recorded.words
                day.incomplete=day.start<state.tracking_since or recorded.incomplete or false
                total=total+day.words;incomplete=incomplete or day.incomplete
            end
        end
    end
    return {period=period,metric='words',days=days,total=total,missing=missing,incomplete=incomplete}
end
local function wordSignature(path)
    local attrs=assert(lfs.attributes(path),'书籍文件无法读取')
    assert(attrs.mode=='file','书籍文件无法读取')
    return tostring(attrs.size)..':'..tostring(attrs.modification)
end
function Inkfolio.countWords(text)
    assert(type(text)=='string','正文不是文本')
    assert(util.fixUtf8(text,'')==text,'正文含无效字符')
    local count,english=0,false
    for char in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        local cp=ffiUtil.utf8charcode(char)
        if (cp>=0x3400 and cp<=0x4DBF) or (cp>=0x4E00 and cp<=0x9FFF)
            or (cp>=0xF900 and cp<=0xFAFF) or (cp>=0x20000 and cp<=0x323AF) then
            count=count+1;english=false
        elseif char:match('^[A-Za-z]$') or (cp>=0x00C0 and cp<=0x024F and cp~=0x00D7 and cp~=0x00F7)
            or (cp>=0x1E00 and cp<=0x1EFF) or (cp>=0xFF21 and cp<=0xFF3A) or (cp>=0xFF41 and cp<=0xFF5A) then
            if not english then count=count+1 end
            english=true
        elseif ((cp>=0x0300 and cp<=0x036F) or char=="'" or cp==0x2019) and english then
            -- Internal apostrophes do not split English contractions.
        else english=false end
    end
    return count
end
function Inkfolio.addWordRange(doc,record,start,finish)
    local function before(a,b)
        local value=doc:compareXPointers(a,b)
        assert(value~=nil,'正文位置失效')
        return value==1
    end
    assert(not before(finish,start),'正文位置顺序错误')
    if start==finish then return record,0 end
    local function words(a,b)
        if a==b then return 0 end
        return Inkfolio.countWords(doc:getTextFromXPointers(a,b,false))
    end
    local amount=words(start,finish)
    for _,range in ipairs(record.ranges) do
        local a=before(start,range[1]) and range[1] or start
        local b=before(finish,range[2]) and finish or range[2]
        if before(a,b) then amount=amount-words(a,b) end
    end
    assert(amount>=0,'正文重叠字数异常')
    local merged={}
    local a,b=start,finish
    local inserted=false
    for _,range in ipairs(record.ranges) do
        if before(range[2],a) then merged[#merged+1]=range
        elseif before(b,range[1]) then
            if not inserted then merged[#merged+1]={a,b};inserted=true end
            merged[#merged+1]=range
        else
            if before(range[1],a) then a=range[1] end
            if before(b,range[2]) then b=range[2] end
        end
    end
    if not inserted then merged[#merged+1]={a,b} end
    return {ranges=merged,total=record.total+amount,signature=record.signature},amount
end
function Inkfolio.observeWords(ui)
    local state=Inkfolio.wordState
    if not ui or not ui.document or ui.file_cover or state.sleeping then return end
    local doc,path=ui.document,ui.document.file
    if not path then return end
    if not ui.rolling or not doc.compareXPointers or not doc.getTextFromXPointers or not doc.getTextFromPositions then
        state.errors[path]='格式不支持';state.session_error='部分内容不支持字数统计'
        Inkfolio.recordDailyWords(0,true);return
    end
    local ok,reason=pcall(function()
        local signature=wordSignature(path)
        local record=state.session[path]
        if not record or record.signature~=signature then record={signature=signature,ranges={},total=0} end
        local visible=doc:getTextFromPositions({x=0,y=0},{x=Screen:getWidth(),y=Screen:getHeight()},true)
        if not visible then return end -- CRe has no selectable text on an illustration page.
        assert(visible.pos0 and visible.pos1,'当前正文位置无法读取')
        local updated,added=Inkfolio.addWordRange(doc,record,visible.pos0,visible.pos1)
        state.session[path]=updated;state.session_total=state.session_total+added
        Inkfolio.recordDailyWords(added,false)
    end)
    if not ok then
        state.errors[path]='本次字数记录不完整';state.session_error='本次字数记录不完整'
        Inkfolio.recordDailyWords(0,true)
        logger.warn('InkFolio wake words failed',reason)
    end
end
function Inkfolio.documentWords(doc)
    assert(doc.getPageXPointer and doc.isXPointerInDocument and doc.getTextFromXPointers,'格式不支持')
    local xp=assert(doc:getPageXPointer(1),'正文位置无法读取')
    local body=xp:match('^(.-/body)')
    if not body then
        -- A short HTML first page may point into head/title rather than body.
        local root=xp:match('^(/[^/%.%[]+)')
        body=root and root..'/body'
    end
    assert(body,'正文根节点不支持')
    assert(doc:isXPointerInDocument(body..'.0'),'正文根节点无法读取')
    -- Element offsets range from zero to the exact number of children.
    -- Search validated offsets to find its end, without navigating or changing selection.
    local low,high=0,1
    while doc:isXPointerInDocument(body..'.'..high) do
        assert(high<1073741824,'正文边界无效')
        low=high;high=high*2
    end
    while high-low>1 do
        local middle=math.floor((low+high)/2)
        if doc:isXPointerInDocument(body..'.'..middle) then low=middle else high=middle end
    end
    if low==0 then return 0 end
    local text=assert(doc:getTextFromXPointers(body..'.0',body..'.'..low,false),'全书正文无法读取')
    return Inkfolio.countWords(text)
end
function Inkfolio.estimatedWords(ui,progress)
    local state=Inkfolio.wordState
    if state.storage_error then return nil,state.storage_error end
    local doc=ui and ui.document
    if not doc or not doc.file then return nil,'书籍文件无法读取' end
    local ok,amount=pcall(function()
        local signature=wordSignature(doc.file)
        local record=state.books[doc.file]
        if not record or record.signature~=signature or record.document_total==nil then
            assert(not ui.file_cover,'请先打开本书统计字数')
            record={signature=signature,document_total=Inkfolio.documentWords(doc)}
            state.books[doc.file]=record;state.dirty=true
            if not state.flush_scheduled then state.flush_scheduled=true;UIManager:scheduleIn(5,Inkfolio.flushWords) end
        end
        assert(type(progress)=='number' and progress>=0 and progress<=1,'阅读进度无效')
        return math.floor(record.document_total*progress+.5)
    end)
    if not ok then logger.warn('InkFolio book words failed',amount);return nil,tostring(amount):match(': (.*)$') or tostring(amount) end
    return amount
end
function Inkfolio.flushWords()
    local state=Inkfolio.wordState
    UIManager:unschedule(Inkfolio.flushWords);state.flush_scheduled=false
    if not state.dirty or state.storage_error then return end
    local temporary=Inkfolio.wordPath..'.tmp'
    local file
    local ok,err=pcall(function()
        file=assert(io.open(temporary,'wb'))
        assert(file:write('return '..require('dump')({version=3,books=state.books,days=state.days,
            tracking_since=state.tracking_since},nil,true)..'\n'))
        assert(file:flush());assert(ffiUtil.fsyncOpenedFile(file));assert(file:close());file=nil
        assert(os.rename(temporary,Inkfolio.wordPath));assert(ffiUtil.fsyncDirectory(Inkfolio.wordPath))
    end)
    if file then file:close() end
    if not ok then os.remove(temporary);state.storage_error='字数记录保存失败';logger.warn('InkFolio word save failed',err)
    else state.dirty=false end
end
function Inkfolio.resumeWords()
    local state=Inkfolio.wordState
    if state.sleeping then
        state.session={};state.session_total=0;state.session_error=nil;state.errors={};state.sleeping=false
    end
    UIManager:nextTick(Inkfolio.captureWords)
end
function Inkfolio.captureWords() Inkfolio.observeWords(ReaderUI.instance) end
function Inkfolio.wakeWords(ui)
    if ui==ReaderUI.instance then Inkfolio.observeWords(ui) end
    local state=Inkfolio.wordState
    if state.session_error then return nil,state.session_error end
    return state.session_total
end

-- Establish only today as observed; never fill unobserved dates with zero.
Inkfolio.recordDailyWords(0,false)
if Inkfolio.wordState.dirty and not Inkfolio.wordState.storage_error then Inkfolio.scheduleWordSave() end

local function formatWordCount(amount)
    assert(type(amount)=='number' and amount>=0 and amount<math.huge and amount==math.floor(amount),'字数无效')
    if amount<10000 then return string.format('%.0f字',amount) end
    return string.format('%.1f万字',amount/10000)
end

-- One local snapshot shares period totals between summaries, charts and goal.
function Inkfolio.statisticsSnapshot(ui,now)
    local snap={now=now or os.time(),ui=ui,time_cache={},word_cache={},page_cache={},statuses={}}
    local first=snap.now
    local function include(period)
        if not period then first=0 else local _,stamp=Inkfolio.periodDays(period,snap.now);first=math.min(first,stamp) end
    end
    if enabled(S.stats) then
        for _,item in ipairs(summaryItems())do include(item.period) end
        for _,item in ipairs(Inkfolio.chartItems())do if item.metric=='time' then include(item.period) end end
    end
    local goal=Inkfolio.goalConfig()
    if goal.enabled and goal.metric=='time' then include(goal.period) end
    function snap:note(label,reason)
        if reason then self.statuses[label]=reason end
    end
    function snap:records()
        if not self.loaded then
            self.loaded=true;self.native,self.native_error=Inkfolio.timeRecords(self.ui,first,self.now)
        end
        return self.native,self.native_error
    end
    function snap:time(period,id)
        local key=(period or 'total')..':'..tostring(id or 'global')
        if self.time_cache[key] then return unpack(self.time_cache[key]) end
        local records,reason=self:records()
        if not records then self.time_cache[key]={false,reason};return nil,reason end
        local data
        if period then data=Inkfolio.readCurve(self.ui,period,self.now,records,id)
        else
            data={total=0,known=0,missing=0}
            for i,start in ipairs(records[1] or {}) do
                if not id or tonumber(records[3][i])==id then
                    local stamp,seconds=assert(tonumber(start)),assert(tonumber(records[2][i]))
                    data.total=data.total+math.max(0,math.min(stamp+seconds,self.now+1)-stamp);data.known=data.known+1
                end
            end
        end
        self.time_cache[key]={data};return data
    end
    function snap:words(period)
        if not self.word_cache[period] then
            local data,reason=Inkfolio.readWordChart(period,self.now)
            self.word_cache[period]={data or false,reason}
        end
        return unpack(self.word_cache[period])
    end
    function snap:pages(period,id)
        local key=(period or 'total')..':'..tostring(id or 'global')
        if self.page_cache[key] then return unpack(self.page_cache[key]) end
        local records,reason=self:records()
        if not records then return nil,reason end
        local start=0
        if period then local _,stamp=Inkfolio.periodDays(period,self.now);start=stamp end
        local opened,db=pcall(SQ3.open,STATS_PATH)
        if not opened or not db then return nil,'阅读统计无法打开' end
        local filter=id and string.format(' AND id_book=%d',id) or ''
        local ok,count=pcall(db.rowexec,db,string.format(
            'SELECT count(*) FROM (SELECT id_book,page FROM page_stat WHERE start_time<%d AND (start_time+duration>%d OR (duration=0 AND start_time>=%d))%s GROUP BY id_book,page);',self.now+1,start,start,filter))
        db:close()
        if not ok then logger.warn('InkFolio page query failed',count);return nil,'阅读页数读取失败' end
        count=assert(tonumber(count),'无效阅读页数')
        self.page_cache[key]={count};return count
    end
    return snap
end
function Inkfolio.summaryData(snapshot,item)
    local id
    if not item.global then
        local stats=snapshot.ui and snapshot.ui.statistics
        id=stats and tonumber(stats.id_curr_book)
        if not id and stats and stats.getIdBookDB then
            local ok,value=pcall(stats.getIdBookDB,stats);if ok then id=tonumber(value) end
        end
        if not id then snapshot:note(item.label,'当前图书没有统计记录');return {metric='pages'} end
    end
    local out={metric=item.global and item.period and Inkfolio.summaryMetric() or 'pages'}
    local time,reason=snapshot:time(item.period,id)
    if time and time.known>0 then out.time=time.total;out.incomplete=(time.missing or 0)>0 end
    snapshot:note(item.label..'时长',reason or (not out.time and '暂无时长记录' or out.incomplete and '部分日期没有记录' or nil))
    if out.metric=='words' then
        local words,error=snapshot:words(item.period)
        if words then
            local known=false
            for _,day in ipairs(words.days)do if day.words~=nil then known=true;break end end
            if known then out.amount=words.total end
            out.incomplete=out.incomplete or words.incomplete or words.missing>0
            snapshot:note(item.label..'字数',error or (not known and '暂无字数记录' or (words.incomplete or words.missing>0) and '字数记录不完整' or nil))
        else snapshot:note(item.label..'字数',error) end
    else
        local pages,error=snapshot:pages(item.period,id)
        -- A missing native record is unknown, not a confirmed zero.
        if time and time.known>0 then out.amount=pages end
        snapshot:note(item.label..'页数',error)
    end
    out.incomplete=(out.time~=nil or out.amount~=nil) and out.incomplete or false
    return out
end
function Inkfolio.statisticsText()
    local lines={
        '阅读进度',
        '当前页码与百分比表示阅读位置，跳页也会改变；不代表实际读过全部内容。估算已读为全书字数乘当前位置比例。预计剩余依据 KOReader 平均阅读速度计算。',
        '', '字数记录',
        '中文每字计一字，英文每单词计一字，不计标点和空白。实际记录来自可提取的正文；同次唤醒内同一内容去重，跨书累计，下次唤醒重新去重，重启 KOReader 也会开始新的会话。它表示翻阅量，不保证文字已被完整阅读。',
        '今日、本周、本月字数从InkFolio开始记录时累计，不补录安装前的数据。全书估算字数不参与周期统计或目标；累计摘要沿用时长和页数。',
        '', '时长与页数',
        '来自 KOReader 阅读统计，包含其保留的安装前历史；停留时间沿用原生记录规则。页数按周期内记录的图书与页面去重，并沿用原生分页换算；各日页数相加不一定等于累计页数。',
        '', '周期与图表',
        '按设备本地日期：每天零点、周一和自然月划分；跨午夜时长拆分到对应日期。日均为本周期已记录时长除以截至今天的自然日数，包含今天。未来日期不参与汇总。',
        '', '数据状态',
        '0表示已有零值记录；—表示暂无记录或数据不可用。已记录表示统计不完整，数字仅覆盖现有记录。无记录不等于确认未读，也不等于确认数据丢失。',
        '图表短横表示零，斜线表示无记录，圆点表示当日字数记录不完整；未来日期留空。',
        '', '显示与选择',
        '摘要与趋势图各最多两项，独立选择；关闭显示阅读摘要会隐藏两者，不影响阅读目标。在摘要内容中选择数字摘要，在阅读图表中选择柱状图。周期摘要指标可选择时长＋字数或时长＋页数；累计与旧本书今日保持时长与页数；升级保留原有页数选择。',
    }
    local status=Inkfolio.statisticsStatus or {}
    local keys={};for label in pairs(status)do keys[#keys+1]=label end;table.sort(keys)
    lines[#lines+1]='';lines[#lines+1]='最近一次显示的统计状态'
    if #keys==0 then lines[#lines+1]='暂无异常状态记录；打开InkFolio 预览可更新。'
    else for _,label in ipairs(keys)do lines[#lines+1]=label..'：'..status[label] end end
    return table.concat(lines,'\n')
end
function Inkfolio.showStatisticsHelp(parent)
    local viewer=require('ui/widget/textviewer'):new{title='统计说明',text=Inkfolio.statisticsText(),
        justified=false,show_menu=false,add_default_buttons=true}
    UIManager:show(Inkfolio.refreshParentOnClose(viewer,parent))
end

Inkfolio.GOAL_PERIODS={{id='day',label='每日',title='今日'},{id='week',label='每周',title='本周'},{id='month',label='每月',title='本月'}}
Inkfolio.GOAL_METRICS={{id='time',label='阅读时长'},{id='words',label='阅读字数'}}
function Inkfolio.goalConfig(value)
    if value==nil then value=G_reader_settings:readSetting(S.goal) end
    if value==nil then return {version=1,enabled=false,period='day',metric='time',values={}} end
    assert(type(value)=='table' and value.version==1 and type(value.enabled)=='boolean' and type(value.values)=='table','阅读目标设置损坏')
    local function validPeriod(p)return p=='day' or p=='week' or p=='month' end
    local function validMetric(m)return m=='time' or m=='words' end
    assert(validPeriod(value.period) and validMetric(value.metric),'阅读目标周期或类型无效')
    local copy={version=1,enabled=value.enabled,period=value.period,metric=value.metric,values={}}
    for key,target in pairs(value.values)do
        assert(type(key)=='string','阅读目标设置键无效')
        local period,metric=key:match('^(%a+)_(%a+)$')
        local unit=metric=='words' and 1000 or 60
        assert(validPeriod(period) and validMetric(metric) and type(target)=='number' and target>=unit
            and target<=9007199254740991 and target==math.floor(target) and target%unit==0,'阅读目标值无效')
        copy.values[key]=target
    end
    assert(not copy.enabled or copy.values[copy.period..'_'..copy.metric],'请先设置目标值')
    return copy
end
function Inkfolio.saveGoal(config)
    config=Inkfolio.goalConfig(config)
    local previous=G_reader_settings:readSetting(S.goal)
    G_reader_settings:saveSetting(S.goal,config)
    local ok,reason=pcall(G_reader_settings.flush,G_reader_settings)
    if not ok then
        if previous==nil then G_reader_settings:delSetting(S.goal) else G_reader_settings:saveSetting(S.goal,previous) end
        error(reason)
    end
    if refreshQuicklook then refreshQuicklook() end
    return true
end
function Inkfolio.setGoal(field,value)
    local config=Inkfolio.goalConfig()
    if field=='target' then config.values[config.period..'_'..config.metric]=value
    else assert(field=='period' or field=='metric' or field=='enabled','阅读目标选项无效');config[field]=value end
    if field~='enabled' and not config.values[config.period..'_'..config.metric] then config.enabled=false end
    return Inkfolio.saveGoal(config)
end
function Inkfolio.parseGoalTarget(text,metric)
    text=util.trim(tostring(text or ''))
    if metric=='time' then
        if not text:match('^%d+$') then return nil,'请输入大于0的整数分钟。' end
    elseif metric=='words' then
        if not text:match('^%d+$') and not text:match('^%d+%.%d$') then return nil,'请以万字输入，最多保留一位小数，例如2.5。' end
    else return nil,'阅读目标类型无效' end
    local number=tonumber(text)
    local target=number and number*(metric=='words' and 10000 or 60)
    if not target or target<1 or target>9007199254740991 then return nil,'目标值必须大于0且在有效范围内。' end
    target=math.floor(target+.5)
    if target%(metric=='words' and 1000 or 60)~=0 then return nil,'阅读目标精度无效。' end
    return target
end
function Inkfolio.goalTargetText(config)
    config=config or Inkfolio.goalConfig()
    local target=config.values[config.period..'_'..config.metric]
    if not target then return '未设置' end
    return config.metric=='words' and string.format('%.1f万字',target/10000) or duration(target)
end
function Inkfolio.goalSnapshot(ui,now,snapshot)
    local config=Inkfolio.goalConfig()
    if not config.enabled then return nil end
    local period
    for _,item in ipairs(Inkfolio.GOAL_PERIODS)do if item.id==config.period then period=item.title end end
    local goal={title=period..'阅读目标',
        target=config.values[config.period..'_'..config.metric],target_text=Inkfolio.goalTargetText(config),config=config}
    local chart,reason
    if config.metric=='words' then
        if snapshot then chart,reason=snapshot:words(config.period)
        else
            if ui and ui==ReaderUI.instance then Inkfolio.observeWords(ui) end
            chart,reason=Inkfolio.readWordChart(config.period,now)
        end
    elseif snapshot then chart,reason=snapshot:time(config.period)
    else chart,reason=Inkfolio.readCurve(ui,config.period,now) end
    if not chart then goal.reason=reason;return goal end
    local known=0
    for _,day in ipairs(chart.days)do
        if not day.future and (config.metric=='words' and day.words~=nil or config.metric=='time' and day.seconds~=nil) then known=known+1 end
    end
    if known==0 then goal.reason='暂无'..(config.metric=='words' and '字数' or '时长')..'记录';return goal end
    goal.amount=chart.total;goal.percent=math.floor(goal.amount/goal.target*100)
    goal.incomplete=(chart.missing or 0)>0 or chart.incomplete==true
    goal.amount_text=config.metric=='words' and formatWordCount(goal.amount) or duration(goal.amount)
    return goal
end
function Inkfolio.editGoalTarget(parent)
    local config=Inkfolio.goalConfig();local key=config.period..'_'..config.metric
    local target=config.values[key];local words=config.metric=='words'
    local dialog
    dialog=require('ui/widget/inputdialog'):new{
        title=words and '阅读字数目标（万字）' or '阅读时长目标（分钟）',
        input=target and (words and string.format('%.1f',target/10000) or string.format('%.0f',target/60)) or '',
        description=words and '例如2.5代表2.5万字；以0.1万字为单位。' or '请输入大于0的整数分钟。',
        input_type='number',buttons={{{text='取消',callback=function()UIManager:close(dialog)end},
            {text='保存',is_enter_default=true,callback=function()
                local value,reason=Inkfolio.parseGoalTarget(dialog:getInputText(),config.metric)
                if not value then Inkfolio.message(reason);return end
                config.values[key]=value;Inkfolio.saveGoal(config);UIManager:close(dialog)
            end}}}}
    UIManager:show(Inkfolio.refreshParentOnClose(dialog,parent));dialog:onShowKeyboard()
end
function Inkfolio.goalMenu()
    local periods,metrics={},{}
    for _,item in ipairs(Inkfolio.GOAL_PERIODS)do
        local id=item.id
        periods[#periods+1]={text=item.label,radio=true,keep_menu_open=true,
            checked_func=function()return Inkfolio.goalConfig().period==id end,
            callback=function()Inkfolio.setGoal('period',id)end}
    end
    for _,item in ipairs(Inkfolio.GOAL_METRICS)do
        local id=item.id
        metrics[#metrics+1]={text=item.label,radio=true,keep_menu_open=true,
            checked_func=function()return Inkfolio.goalConfig().metric==id end,
            callback=function()Inkfolio.setGoal('metric',id)end}
    end
    return {
        {text='启用阅读目标',keep_menu_open=true,
            help_text='先选择周期、类型并填写目标值，再启用。切换到尚未设置的组合时自动停用；各组合的目标值分别保存。',
            checked_func=function()return Inkfolio.goalConfig().enabled end,
            enabled_func=function()local c=Inkfolio.goalConfig();return c.values[c.period..'_'..c.metric]~=nil end,
            callback=function()Inkfolio.setGoal('enabled',not Inkfolio.goalConfig().enabled)end},
        {text='目标周期',help_text='按设备本地时间计算：每天零点、每周一零点及自然月月初开始新周期。',sub_item_table=periods},
        {text='目标类型',help_text='统计全局阅读量。时长沿用KOReader阅读统计；字数按实际翻阅记录，同次唤醒去重，不补录历史字数。',sub_item_table=metrics},
        {text='目标值',text_func=function()return '目标值：'..Inkfolio.goalTargetText()end,callback=Inkfolio.editGoalTarget},
    }
end

local CoverScene=WidgetContainer:extend{}
-- Sample only the visible background just outside the card, before drawing it.
-- The midpoint chooses the black/white fill with the larger mean contrast.
function Inkfolio.cardBackground(image,cover_rect,card_rect,background,sw,sh,band,step)
    local sum,count=0,0
    for y=math.max(0,card_rect.y-band),math.min(sh-1,card_rect.y+card_rect.h+band-1),step do
        for x=math.max(0,card_rect.x-band),math.min(sw-1,card_rect.x+card_rect.w+band-1),step do
            if x<card_rect.x or x>=card_rect.x+card_rect.w or y<card_rect.y or y>=card_rect.y+card_rect.h then
                local color=background
                if cover_rect and x>=cover_rect.x and x<cover_rect.x+cover_rect.w
                    and y>=cover_rect.y and y<cover_rect.y+cover_rect.h then
                    color=image:getPixel(x-cover_rect.x,y-cover_rect.y)
                end
                sum=sum+color:getColor8().a;count=count+1
            end
        end
    end
    assert(count>0,'InkFolio: 卡片周边没有可检测区域')
    return sum/count>=255/2 and 'black' or 'white'
end
function CoverScene:getSize()return Geom:new{w=self.screen_w,h=self.screen_h}end
function CoverScene:paintTo(bb,x,y)
    self.dimen=Geom:new{x=x,y=y,w=self.screen_w,h=self.screen_h}
    bb:paintRect(x,y,self.screen_w,self.screen_h,self.background)
    if self[2]then
        local size=self[2]:getSize()
        local cy=self.cover_missing and self.top_gap or math.floor((self.screen_h-size.h)/2)
        self[2]:paintTo(bb,x+math.floor((self.screen_w-size.w)/2),y+cy)
    end
    local size=self[1]:getSize()
    self[1]:paintTo(bb,x+math.floor((self.screen_w-size.w)/2),y+math.floor((self.screen_h-size.h)/2))
end
function Inkfolio.renderCover(ui,state,appearance)
    appearance=appearance or {}
    local theme=Inkfolio.uiStyle({ui_style='cover'})
    local sw,sh=Screen:getWidth(),Screen:getHeight()
    local fraction=appearance.card_width or G_reader_settings:readSetting(S.card_width) or .50
    local font_scale=appearance.card_font or G_reader_settings:readSetting(S.card_font) or 1
    assert(type(fraction)=='number' and fraction>=.4 and fraction<=.85,'InkFolio: 卡片宽度无效')
    assert(type(font_scale)=='number' and font_scale>=.8 and font_scale<=1.2,'InkFolio: 卡片字号无效')
    local background=appearance.cover_background or G_reader_settings:readSetting(S.cover_background) or 'white'
    assert(background=='white' or background=='black','InkFolio: 封面底色无效')
    local card_background=appearance.card_background or G_reader_settings:readSetting(S.card_background)or 'auto'
    assert(card_background=='auto'or card_background=='white'or card_background=='black','InkFolio: 卡片底色无效')
    local card_width=math.floor(sw*fraction)
    local unit=card_width/720
    local function px(n)return math.max(1,math.floor(n*unit+.5))end
    local function f(n)return math.max(1,math.floor(n*font_scale*card_width/Screen:scaleBySize(720)+.5))end
    local font_error=Inkfolio.uiFontError(theme,f(24));assert(not font_error,font_error)
    local pad,border=px(theme.padding),math.max(1,px(1))
    local width=card_width-2*(pad+border)
    local text_widgets={}
    local function txt(value,role,w,align)
        local style=assert(theme.type[role],'InkFolio: 未知文字层级')
        local widget=TextBoxWidget:new{text=tostring(value),face=Font:getFace(theme.fonts.body,f(style.size)),
            bold=style.bold==true,width=w or width,alignment=align or 'left',justified=false,line_height=.3,
            fgcolor=style.muted and Blitbuffer.COLOR_GRAY_3 or Blitbuffer.COLOR_BLACK}
        text_widgets[#text_widgets+1]=widget
        return widget
    end
    local function measured(value,role)
        local style=theme.type[role];local t=TextWidget:new{text=value,face=Font:getFace(theme.fonts.body,f(style.size)),bold=style.bold,padding=0}
        local w=t:getSize().w;t:free();return w
    end
    local function baseline(...)
        local children={...};local top=0
        for _,child in ipairs(children)do if child.getBaseline then top=math.max(top,child:getBaseline())end end
        for i,child in ipairs(children)do if child.getBaseline and child:getBaseline()<top then
            children[i]=VerticalGroup:new{VerticalSpan:new{width=top-child:getBaseline()},child}
        end end
        return HorizontalGroup:new{align='top',unpack(children)}
    end
    local function gap(n)return HorizontalSpan:new{width=px(n)}end
    local elements={}
    local function add(widget,space)
        elements[#elements+1]=widget
        if space then elements[#elements+1]=VerticalSpan:new{width=px(space)}end
    end
    local function row(label,value)
        local lw=math.floor(width*.36)
        return baseline(txt(label,'label',lw),gap(12),txt(value,'text',width-lw-px(12),'right'))
    end
    local book=extractBook(ui.doc_props,ui.document.file)
    if ui==ReaderUI.instance then Inkfolio.observeWords(ui)end
    local snapshot=Inkfolio.statisticsSnapshot(ui);Inkfolio.statisticsStatus=snapshot.statuses
    local page,total,pct=Inkfolio.readingPosition(ui,state)
    add(txt(displayTitle(book.title),'book'),8)
    add(txt(book.authors~='' and book.authors or '未提供作者','body'),24)
    local chapter
    if ui.toc and ui.toc.getTocTitleByPage then
        local ok,value=pcall(ui.toc.getTocTitleByPage,ui.toc,tonumber(state and state.page)or 1)
        assert(ok,'InkFolio: 章节读取失败：'..tostring(value));chapter=value
    end
    add(txt(chapter and chapter~='' and chapter or '暂无章节信息','body'),14)
    local pw=math.floor(width*.36)
    add(baseline(txt(pct..'%','percentage',pw),gap(12),txt(string.format('%d / %d 页',page,total),'body',width-pw-px(12),'right')),10)
    local progress=ProgressWidget:new{width=width,height=px(7),percentage=page/total,radius=0,bordersize=0,margin_v=0,margin_h=0,
        bgcolor=Blitbuffer.COLOR_GRAY_9,fillcolor=Blitbuffer.COLOR_BLACK}
    add(progress,18)
    if Inkfolio.progressEnabled(S.word_book)then
        local value,reason=Inkfolio.estimatedWords(ui,page/total);snapshot:note('估算已读',reason)
        add(row('估算已读',value and formatWordCount(value)or '—'),6)
    end
    if Inkfolio.progressEnabled(S.word_session)then
        local value,reason=Inkfolio.wakeWords(ui);snapshot:note('本次唤醒',reason)
        add(row('本次唤醒',value and formatWordCount(value)or '—'),6)
    end
    if Inkfolio.progressEnabled(S.remain)then
        local avg=ui.statistics and tonumber(ui.statistics.avg_time)
        add(row('预计剩余',avg and avg>0 and duration((total-page)*avg)or '—'),6)
    end
    local summaries=enabled(S.stats)and summaryItems()or {}
    if #summaries>0 then
        add(VerticalSpan:new{width=px(16)})
        local spacing=px(22);local half=math.floor((width-spacing)/2)
        local function block(item,w)
            local values=Inkfolio.summaryData(snapshot,item)
            local amount=values.amount~=nil and (values.metric=='words'and formatWordCount(values.amount)or values.amount..'页')or '—'
            return VerticalGroup:new{align='left',txt(item.label..(values.incomplete and ' · 已记录'or ''),'subheading',w),
                VerticalSpan:new{width=px(8)},txt(duration(values.time),'value',w),VerticalSpan:new{width=px(4)},
                txt((values.metric=='words'and '字数 'or '页数 ')..amount,'body',w)}
        end
        if #summaries==1 then add(block(summaries[1],width),14)
        else
            local first,second=block(summaries[1],half),block(summaries[2],half)
            for _,index in ipairs({1,3,5})do
                local height=math.max(first[index]:getSize().h,second[index]:getSize().h)
                for _,column in ipairs({first,second})do
                    local extra=height-column[index]:getSize().h
                    if extra>0 then column[index]=VerticalGroup:new{column[index],VerticalSpan:new{width=extra}}end
                end
            end
            add(HorizontalGroup:new{align='top',first,HorizontalSpan:new{width=width-2*half},second},14)
        end
    end
    local date=enabled(S.date)and os.date('%Y.%m.%d',snapshot.now)or nil
    local choice=Inkfolio.coverWeather()
    local weather=choice~='off'and weatherText(choice=='today'and 0 or 1)or nil
    if date or weather then
        add(VerticalSpan:new{width=px(10)})
        if date and weather then
            local dw=math.ceil(measured(date,'header'))+1
            add(baseline(txt(weather,'header',width-dw-px(16)),gap(16),txt(date,'header',dw,'right')))
        elseif date then add(txt(date,'header',width,'right'))
        else add(txt(weather,'header'))end
    end
    local card=FrameContainer:new{padding=pad,bordersize=border,color=Blitbuffer.COLOR_GRAY_3,
        radius=px(24),background=Blitbuffer.COLOR_WHITE,VerticalGroup:new{align='left',unpack(elements)}}
    local cs=card:getSize();local valid=cs.w<=sw and cs.h<=sh-px(24)
    if not appearance.measure_only and not valid then
        card:free()
        return CenterContainer:new{dimen=Screen:getSize(),TextBoxWidget:new{text='信息卡内容超出屏幕，请调整卡片宽度、字号或显示项目。',
            face=Font:getFace('cfont',f(22)),width=math.floor(sw*.8),alignment='center',justified=false}}
    end
    local cover,missing,cover_rect,cover_image
    if ui.bookinfo then
        local doc=not ui.file_cover and ui.document or nil
        local ok,bb=pcall(ui.bookinfo.getCoverImage,ui.bookinfo,doc,ui.file_cover and ui.document.file or nil)
        if not ok then card:free();error('InkFolio: 封面读取失败：'..tostring(bb))end
        if bb then
            local scale=math.min(sw/bb:getWidth(),sh/bb:getHeight())
            local cw,ch=math.max(1,math.floor(bb:getWidth()*scale)),math.max(1,math.floor(bb:getHeight()*scale))
            if cw~=bb:getWidth()or ch~=bb:getHeight()then bb=RenderImage:scaleBlitBuffer(bb,cw,ch,true)end
            cover=ImageWidget:new{image=bb,width=cw,height=ch,image_disposable=true}
            cover_image=bb
            cover_rect={x=math.floor((sw-cw)/2),y=math.floor((sh-ch)/2),w=cw,h=ch}
        end
    end
    if not cover then
        missing=true;cover=TextWidget:new{text='封面不可用',face=Font:getFace('cfont',f(20)),
            fgcolor=background=='black'and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK}
    end
    local background_color=background=='black'and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    local card_rect={x=math.floor((sw-cs.w)/2),y=math.floor((sh-cs.h)/2),w=cs.w,h=cs.h}
    if card_background=='auto'then
        card_background=Inkfolio.cardBackground(cover_image,cover_rect,card_rect,background_color,sw,sh,
            px(UI_LAYOUT.card_sample_band),px(UI_LAYOUT.card_sample_step))
    end
    if card_background=='black'then
        card.background=Blitbuffer.COLOR_BLACK;card.color=card.color:invert()
        progress.bgcolor=progress.bgcolor:invert();progress.fillcolor=Blitbuffer.COLOR_WHITE
        for _,widget in ipairs(text_widgets)do
            widget.bgcolor=Blitbuffer.COLOR_BLACK;widget.fgcolor=widget.fgcolor:invert();widget:update()
        end
    end
    local scene=CoverScene:new{screen_w=sw,screen_h=sh,background=background_color,card_background=card_background,
        cover_missing=missing,cover_rect=cover_rect,top_gap=px(20),card_rect=card_rect,card,cover}
    if appearance.measure_only then return scene,true,{width=cs.w,height=cs.h,screen_w=sw,screen_h=sh}end
    return scene,true
end
function Inkfolio.readingPosition(ui,state)
    local doc=(ui.doc_settings and ui.doc_settings.data) or {}
    local page=tonumber(state and state.page) or 1
    local total=math.max(1,tonumber(ui.file_cover and doc.doc_pages or ui.document:getPageCount()) or 1)
    page=math.max(1,math.min(page,total))
    if ui.pagemap and ui.pagemap.wantsPageLabels and ui.pagemap:wantsPageLabels() then
        local _,idx,count=ui.pagemap:getCurrentPageLabel(true)
        if idx and count and count>0 then page,total=idx,count end
    end
    local pct=math.floor(page*100/total+0.5)
    return page,total,pct
end
local function renderReceipt(ui, state, appearance)
    if not ui or not ui.document then return nil end
    appearance=appearance or {}
    local theme=Inkfolio.uiStyle(appearance)
    if theme.id=='cover' then return Inkfolio.renderCover(ui,state,appearance) end
    local factor=tonumber(appearance.width or G_reader_settings:readSetting(S.width)) or 0.72
    local scaler=tonumber(appearance.font or G_reader_settings:readSetting(S.font)) or 1
    local scale=tonumber(appearance.scale or G_reader_settings:readSetting(S.scale)) or 1
    local base_width=math.min(Screen:getWidth(),Screen:getHeight()*.75)
    local paper_w=math.floor(base_width*math.max(0.55,math.min(factor,0.90))*scale)
    local unit=paper_w/720
    local line_width=math.max(1,math.floor(scale+0.5))
    local function px(size) return math.max(1,math.floor(size*unit+0.5)) end
    local pad=px(theme.padding)
    local w=paper_w-2*pad
    -- Font:getFace scales its argument by DPI; widget dimensions are physical pixels.
    -- Express both in the same 720-pixel ticket design, independent of UI scaling.
    local font_unit=paper_w/Screen:scaleBySize(720)
    local function f(size) return math.max(1,math.floor(size*scaler*font_unit+0.5)) end
    local font_error=Inkfolio.uiFontError(theme,f(24))
    if font_error then return CenterContainer:new{dimen=Screen:getSize(),TextBoxWidget:new{
        text=font_error,face=Font:getFace('cfont',f(24)),width=math.floor(Screen:getWidth()*.78),alignment='center',justified=false}} end
    local styles=theme.type
    local function faceFor(style) return Font:getFace(theme.fonts[style.font or 'body'],f(style.size)) end
    local function txt(value,role,width,align,lines)
        local style=assert(styles[role],'未知文字层级')
        local face=faceFor(style)
        local widget=TextBoxWidget:new{
            text=tostring(value or ''),face=face,bold=style.bold==true,
            width=math.max(1,math.floor(width or w)),
            alignment=align or 'left',fgcolor=style.muted and Blitbuffer.COLOR_GRAY_3 or Blitbuffer.COLOR_BLACK,
            justified=false,line_height=0.3,
            height=lines and math.floor(face.size*1.3+0.5)*lines or nil,
            height_overflow_show_ellipsis=lines~=nil,height_adjust=lines~=nil,
        }
        return style.wear and inkText(widget,value,3) or widget
    end
    local heading=txt
    local function textWidth(value,role)
        local style=assert(styles[role],'未知文字层级')
        local t=TextWidget:new{text=tostring(value),face=faceFor(style),bold=style.bold,padding=0}
        local width=t:getSize().w;t:free();return width
    end
    -- A four-unit vertical rhythm, scaled with the whole layout.
    local function vg(n)
        if n>0 then n=math.max(UI_LAYOUT.rhythm,math.floor(n/UI_LAYOUT.rhythm+.5)*UI_LAYOUT.rhythm) end
        return VerticalSpan:new{width=n>0 and px(n) or 0}
    end
    local function hg(n) return HorizontalSpan:new{width=n>0 and px(n) or 0} end
    local function baselineRow(...)
        local children={...}
        local baseline=0
        for _,widget in ipairs(children)do
            if widget.getBaseline then baseline=math.max(baseline,widget:getBaseline()) end
        end
        for i,widget in ipairs(children)do
            if widget.getBaseline then
                local offset=baseline-widget:getBaseline()
                if offset>0 then children[i]=VerticalGroup:new{VerticalSpan:new{width=offset},widget} end
            end
        end
        return HorizontalGroup:new{align='top',unpack(children)}
    end
    -- Different fonts have different ink heights even on the same baseline.
    -- Align the visible first-line glyph centres; wrapped text grows downwards.
    local function headerRow(...)
        local children={...};local centres={};local centre=0
        for i,widget in ipairs(children)do
            if widget.getBaseline then
                local text=widget.text and widget or widget[1]
                local line=assert(text.vertical_string_list[1],'InkFolio: 顶栏文字缺少首行')
                local chars=util.splitToChars(text.text)
                local first=table.concat(chars,'',line.offset,line.end_offset)
                local bounds=require('ui/rendertext'):sizeUtf8Text(0,false,text.face,first,true,text.bold)
                centres[i]=widget:getBaseline()+(bounds.y_bottom-bounds.y_top)/2
                centre=math.max(centre,centres[i])
            end
        end
        for i,widget in ipairs(children)do
            if centres[i]then
                local offset=math.floor(centre-centres[i]+.5)
                if offset>0 then children[i]=VerticalGroup:new{VerticalSpan:new{width=offset},widget}end
            end
        end
        return HorizontalGroup:new{align='top',unpack(children)}
    end
    local function rule(kind) return PrintRule:new{theme=theme,width=w,height=kind=='solid' and px(theme.id=='swiss' and 2 or 1) or line_width,kind=kind or 'dash',scale=scale} end
    local elements={}
    local function add(widget,space)
        elements[#elements+1]=widget
        if space and space>0 then elements[#elements+1]=vg(space) end
    end
    local book=extractBook(ui.doc_props,ui.document.file)
    local cache=cached(book)
    if ui==ReaderUI.instance then Inkfolio.observeWords(ui) end
    local snapshot=Inkfolio.statisticsSnapshot(ui)
    Inkfolio.statisticsStatus=snapshot.statuses
    local page,total,pct=Inkfolio.readingPosition(ui,state)

    -- Single-day weather retains the original top row. Two days share a new
    -- measured row; symmetric side columns keep today's forecast truly centered.
    local date_text=enabled(S.date) and os.date('%Y.%m.%d',snapshot.now) or nil
    local brand_width=math.ceil(textWidth('INKFOLIO','brand'))+1
    local date_width=date_text and math.ceil(textWidth(date_text,'header'))+1 or 0
    local today_weather,tomorrow_weather=Inkfolio.weatherSelected(0,appearance),Inkfolio.weatherSelected(1,appearance)
    if today_weather and tomorrow_weather then
        if date_text then
            add(headerRow(heading('INKFOLIO','brand',brand_width,'left'),hg(12),
                txt(date_text,'header',w-brand_width-px(12),'right')),UI_LAYOUT.heading)
        else add(heading('INKFOLIO','brand',w,'left'),UI_LAYOUT.heading) end
        local city=selectedWeatherCity()
        local name=city and cityLabel(city) or '未选择城市'
        local tomorrow=weatherText(1,false)
        local gap=px(12)
        local side=math.min(math.max(textWidth(name,'header'),textWidth(tomorrow,'header')),
            math.floor((w-2*gap)/3))
        add(baselineRow(txt(name,'header',side,'left'),hg(12),
            txt(weatherText(0,false),'header',w-2*(side+gap),'center'),hg(12),
            txt(tomorrow,'header',side,'right')),12)
    elseif Inkfolio.weatherEnabled(appearance) and date_text then
        local side=math.max(brand_width,date_width)
        local gap=px(12)
        add(headerRow(heading('INKFOLIO','brand',side,'left'),hg(12),
            txt(weatherText(today_weather and 0 or 1),'header',w-2*(side+gap),'center'),hg(12),
            txt(date_text,'header',side,'right')),12)
    elseif Inkfolio.weatherEnabled(appearance) or date_text then
        add(headerRow(heading('INKFOLIO','brand',brand_width,'left'),hg(12),
            txt(date_text or weatherText(today_weather and 0 or 1),'header',w-brand_width-px(12),'right')),12)
    else
        add(heading('INKFOLIO','brand',w,'left'),12)
    end
    add(rule(theme.id=='classic' and 'dash' or 'solid'),12)

    -- Book details and a two-row goal share the left column; cover stays proportional.
    local cover,coverw
    if enabled(S.cover) and ui.bookinfo and ui.document then
        local cover_document=ui.document
        if ui.file_cover then cover_document=nil end
        local ok,bb=pcall(ui.bookinfo.getCoverImage,ui.bookinfo,
            cover_document,ui.file_cover and ui.document.file or nil)
        if ok and bb then
            local maxw=math.floor(w*.35)
            local maxh=px(320)
            local sc=math.min(maxw/bb:getWidth(),maxh/bb:getHeight())
            coverw=math.max(1,math.floor(bb:getWidth()*sc))
            local coverh=math.max(1,math.floor(bb:getHeight()*sc))
            if sc~=1 then bb=RenderImage:scaleBlitBuffer(bb,coverw,coverh,true) end
            cover=ImageWidget:new{image=bb,width=coverw,height=coverh}
        end
    end
    local detailw=w-(cover and (coverw+px(14)) or 0)
    local desc={heading(displayTitle(book.title),'book',detailw,'left',2),vg(7)}
    local function metadata(label,value)
        local labelw=px(78)
        return baselineRow(heading(label,'label',labelw,'left',1),hg(7),
            txt(value,'body',detailw-labelw-px(7),'left',2))
    end
    if book.authors~='' then
        desc[#desc+1]=metadata('作者',book.authors)
        desc[#desc+1]=vg(4)
    end
    if book.publisher~='' then
        desc[#desc+1]=metadata('出版社',book.publisher)
        desc[#desc+1]=vg(4)
    end
    if enabled(S.score) then
        local mark=cache and (scoreStars(cache.rating)..'  '..string.format('%.1f/10',cache.rating)) or '暂无评分'
        desc[#desc+1]=txt(mark,'body',detailw,'left',1)
        if cache and (cache.score_kind=='volumes' or cache.score_kind=='versions') then desc[#desc+1]=vg(3);desc[#desc+1]=txt(cache.score_kind=='volumes' and '已匹配分册均分' or '已匹配版本均分','body',detailw,'left',1) end
    end
    local info=VerticalGroup:new{align='left',unpack(desc)}
    local goal=Inkfolio.goalSnapshot(ui,snapshot.now,snapshot)
    local target
    if goal then
        snapshot:note(goal.title,goal.reason or (goal.incomplete and '记录不完整' or nil))
        local percent=goal.amount~=nil and string.format('%.0f%%',goal.percent) or '—'
        local amount=goal.amount~=nil and (goal.amount_text..' / '..goal.target_text)
            or ('目标 '..goal.target_text)
        local percent_width=math.ceil(textWidth(percent,'value'))+1
        local title
        if goal.incomplete then
            local marker_width=math.ceil(textWidth('已记录','small'))+1
            title=baselineRow(heading(goal.title,'module',detailw-marker_width-px(8),'left'),hg(8),
                txt('已记录','small',marker_width,'right'))
        else title=heading(goal.title,'module',detailw,'left') end
        target=VerticalGroup:new{align='left',title,vg(3),
            baselineRow(txt(percent,'value',percent_width,'left'),hg(8),
                txt(amount,'text',detailw-percent_width-px(8),'left'))}
    end
    local details=info
    if target then
        local gap=vg(12):getSize().h
        local height=math.max(info:getSize().h+gap+target:getSize().h,cover and cover:getSize().h or 0)
        details=VerticalGroup:new{align='left',info,
            VerticalSpan:new{width=height-info:getSize().h-target:getSize().h},target}
    end
    if cover then add(HorizontalGroup:new{align=target and 'bottom' or 'top',details,hg(14),cover},12)
    else add(details,11) end
    add(rule('solid'),10)

    -- 3. Shared label/value columns; optional rows determine the real height.
    local keyw=math.floor(w*.30)
    local valw=w-keyw-px(12)
    local function row(key,value,key_role,value_role)
        return baselineRow(heading(key,key_role or 'label',keyw,'left'),hg(12),
            txt(value,value_role or 'text',valw,'right'))
    end
    add(row('阅读进度',tostring(pct)..'%','section','percentage'),8)
    if theme.id=='pixel' then
        add(PixelProgress:new{width=w,height=px(12),percentage=page/total,gap=px(4),stroke=px(2)},9)
    else
        add(ProgressWidget:new{width=w,height=px(9),percentage=page/total,radius=0,bordersize=0,margin_v=0,margin_h=0,
            bgcolor=Blitbuffer.COLOR_GRAY_9,fillcolor=Blitbuffer.COLOR_BLACK},9)
    end
    local chapter
    if ui.toc then
        local ok,value=pcall(ui.toc.getTocTitleByPage,ui.toc,tonumber(state and state.page) or 1)
        if ok then chapter=value end
    end
    add(row('章节',chapter and chapter~='' and chapter or '—','label','body'),4)
    add(row('当前页码',string.format('%d / %d 页',page,total)),4)
    if Inkfolio.progressEnabled(S.word_book) then
        local amount,reason=Inkfolio.estimatedWords(ui,page/total)
        snapshot:note('估算已读',reason)
        add(row('估算已读',amount and formatWordCount(amount) or '—'),4)
    end
    if Inkfolio.progressEnabled(S.word_session) then
        local amount,reason=Inkfolio.wakeWords(ui)
        snapshot:note('本次唤醒',reason)
        add(row('本次唤醒',amount and formatWordCount(amount) or '—'),4)
    end
    if Inkfolio.progressEnabled(S.remain) then
        local avg=ui.statistics and tonumber(ui.statistics.avg_time)
        add(row('预计剩余',avg and avg>0 and duration((total-page)*avg) or '—'),4)
    end

    local notch_clearance
    if theme.id=='classic' then
        local edge_radius=math.max(8,math.floor(math.min(paper_w/22,17)))
        notch_clearance=math.max(9,math.floor(edge_radius*1.2))+px(4)
        add(VerticalSpan:new{width=notch_clearance})
    end
    local stub_y=0
    for _,widget in ipairs(elements)do stub_y=stub_y+widget:getSize().h end
    if notch_clearance then add(VerticalSpan:new{width=notch_clearance}) end
    -- 4. Equal summary columns. Duration is primary; words/pages share a secondary role.
    local summaries=summaryItems()
    local charts=Inkfolio.chartItems()
    local show_curve=#charts>0
    if enabled(S.stats) and (#summaries>0 or show_curve) then
        add(rule('dash'),UI_LAYOUT.heading)
        add(heading('阅读摘要','section',w,theme.summary_align,1),UI_LAYOUT.heading)
        local summary_gap=px(10)*2+line_width
        local half=math.floor((w-summary_gap)/2)
        local summary_tail=w-summary_gap-half*2
        local function block(item,width)
            local values=Inkfolio.summaryData(snapshot,item)
            local kw=math.floor(width*.30)
            local rw=width-kw-px(8)
            local amount=values.amount~=nil and (values.metric=='words' and formatWordCount(values.amount) or (values.amount..'页')) or '—'
            local marker_width=math.max(35,textWidth('已记录','small'))
            local header=baselineRow(heading(item.label,'subheading',width-marker_width-px(4),'left'),hg(4),
                txt(values.incomplete and '已记录' or '', 'small',marker_width,'right'))
            return VerticalGroup:new{header,vg(5),
                baselineRow(heading('时长','label',kw,'left'),hg(8),
                    txt(duration(values.time),'value',rw,'right')),vg(4),
                baselineRow(heading(values.metric=='words' and '字数' or '页数','label',kw,'left'),hg(8),
                    txt(amount,'body',rw,'right')),
            }
        end
        if #summaries==1 then
            add(block(summaries[1],w),5)
        elseif #summaries==2 then
            local first,second=block(summaries[1],half),block(summaries[2],half)
            -- Match corresponding rows even when one value wraps.
            for _,index in ipairs({1,3,5})do
                local height=math.max(first[index]:getSize().h,second[index]:getSize().h)
                for _,column in ipairs({first,second})do
                    local extra=height-column[index]:getSize().h
                    if extra>0 then column[index]=VerticalGroup:new{column[index],VerticalSpan:new{width=extra}} end
                end
            end
            local height=math.max(first:getSize().h,second:getSize().h)
            add(HorizontalGroup:new{align='top',
                first,hg(10),PrintRule:new{theme=theme,kind='vertical',height=height,scale=scale},hg(10),second,
                HorizontalSpan:new{width=summary_tail},
            },5)
        end
        for chart_index,item in ipairs(charts) do
            if #summaries>0 or chart_index>1 then add(vg(UI_LAYOUT.section)) end
            local chart,reason
            if item.metric=='words' then chart,reason=snapshot:words(item.period)
            else chart,reason=snapshot:time(item.period) end
            snapshot:note(item.title,reason or (chart and ((chart.missing or 0)>0 or chart.incomplete) and '记录不完整' or nil))
            if chart then
                local detail
                if item.metric=='words' then
                    local known=false
                    for _,day in ipairs(chart.days)do if day.words~=nil then known=true;break end end
                    detail=known and (((chart.missing or 0)>0 or chart.incomplete) and '已记录 ' or '合计 ')..formatWordCount(chart.total) or '—'
                elseif chart.known==0 then detail='—'
                else detail=((chart.missing or 0)>0 and '已记录 ' or '')..'日均 '..duration(chart.average)..' · 合计 '..duration(chart.total) end
                local lw=textWidth(item.title,'subheading')
                if lw+px(12)+textWidth(detail,'small')<=w then
                    add(baselineRow(heading(item.title,'subheading',lw,'left'),hg(12),
                        txt(detail,'small',w-lw-px(12),'right')),3)
                else
                    add(heading(item.title,'subheading',w,'left'),2)
                    add(txt(detail,'small',w,'left'),3)
                end
                local font_px=Font:getFace(theme.fonts.body,f(styles.small.size)).size
                add(ReadingBars:new{theme=theme,width=w,height=math.max(px(90),math.ceil(font_px*4)),font_size=f(styles.small.size),stroke=px(2),data=chart},3)
            else
                add(heading(item.title,'subheading',w,'left'),3);add(txt('—','small',w,'left'),3)
            end
        end

    end

    -- 5. One full-width group of up to three books, from the offline monthly cache.
    if enabled(S.intro) then
        local chart=Inkfolio.visibleMonthly()
        add(rule('dash'),6)
        local title=Inkfolio.monthlyCategory().id=='all' and '豆瓣月榜' or '豆瓣月榜 · '..Inkfolio.monthlyCategory().label
        add(heading(title,'section',w,'left',1),4)
        local rows={}
        if chart then
            local gap=px(12)
            local ratingw=math.ceil(textWidth('10.0分','body'))+1
            local titlew=math.floor((w-ratingw-gap*2)*.66)
            local authorw=w-ratingw-gap*2-titlew
            local visible=Inkfolio.monthlyItems()
            for i,item in ipairs(visible)do
                rows[#rows+1]=baselineRow(txt(item.title,'body',titlew,'left',1),hg(12),
                    txt(item.author,'body',authorw,'left',1),hg(12),
                    txt(string.format('%.1f分',item.rating),'body',ratingw,'right',1))
                if i<#visible then rows[#rows+1]=vg(3) end
            end
        end
        local note=Inkfolio.monthlyNote()
        if #rows>0 then add(VerticalGroup:new(rows),6) end
        if note then add(txt((chart and '缓存 · ' or '')..note,'small',w,'left',2),4) end
    end
    add(rule('solid'))
    local footer=util.trim(G_reader_settings:readSetting(S.footer) or '')
    if footer~='' then
        add(vg(9))
        add(txt(footer,'small',w,'left'),9)
    end
    local background=appearance.background or G_reader_settings:readSetting(S.background) or 'white'
    local paper=ReceiptPaper:new{
        theme=theme,padding_top=pad,padding_bottom=pad,padding_left=pad,padding_right=pad,
        stub_y=theme.id=='classic' and stub_y or nil,shadow_width=theme.shadow and px(theme.shadow) or 0,
        outline_color=(theme.id=='pixel' or background=='white') and Blitbuffer.COLOR_BLACK or nil,
        outline_width=px((theme.id=='pixel' or background=='white') and 2 or 1),
        grid_pitch=px(12),grid_dot=px(2),VerticalGroup:new(elements),
    }
    local size=paper:getSize()
    if appearance.measure_only then return paper,true,{width=size.w,height=size.h} end
    Inkfolio.lastLayout={width=size.w,height=size.h,screen_w=Screen:getWidth(),screen_h=Screen:getHeight(),
        valid=size.w<=Screen:getWidth() and size.h<=Screen:getHeight()-px(24)}
    if size.w>Screen:getWidth() or size.h>Screen:getHeight()-px(24) then
        logger.warn('Read Receipt: layout exceeds screen',size.w,size.h)
        paper:free()
        return CenterContainer:new{dimen=Screen:getSize(),TextBoxWidget:new{
            text='小票内容超出屏幕，请减小整体比例、字号或宽度。',
            face=Font:getFace('cfont',f(22)),width=w,
            alignment='center',justified=false,
        }}
    end
    return CenterContainer:new{dimen=Screen:getSize(),paper},true
end

-- New installs fit once, after a real book context exists. Manual appearance
-- choices and existing installs are never fitted again.
function Inkfolio.ensureAutoFit(ui,state)
    if Inkfolio.uiStyle().id=='cover' or G_reader_settings:readSetting(S.auto_fit)~=true or not ui or not ui.document then return false end
    local sw,sh=Screen:getWidth(),Screen:getHeight()
    local margin=math.max(8,math.floor(math.min(sw,sh)*.03))
    local width=G_reader_settings:readSetting(S.width) or Inkfolio.deviceDefaults().width
    local font=G_reader_settings:readSetting(S.font) or 1
    local function fits(scale)
        local widget,valid,size=Inkfolio.guard('小票渲染',renderReceipt,ui,state,{width=width,font=font,scale=scale,measure_only=true})
        if widget then widget:free() end
        if not valid or not size then return nil end
        return size.width<=sw-2*margin and size.height<=sh-2*margin
    end
    local low,high=.5,1.5
    local initial=fits(low)
    if initial~=true then return false end -- missing fonts or too small a screen stays explicit
    for _=1,7 do
        local middle=(low+high)/2
        local good=fits(middle)
        if good==nil then return false end
        if good then low=middle else high=middle end
    end
    local scale=math.floor(low*100)/100
    if not fits(scale) then return false end
    G_reader_settings:saveSetting(S.scale,scale)
    G_reader_settings:saveSetting(S.auto_fit,false)
    G_reader_settings:flush()
    return true
end
local function buildReceipt(ui,state,appearance)
    if not appearance then Inkfolio.ensureAutoFit(ui,state) end
    return Inkfolio.guard('小票渲染',renderReceipt,ui,state,appearance)
end

-- Full-screen quicklook; same renderer and cached data as the suspend screen.
local function receiptBackground(appearance)
    local cover=Inkfolio.uiStyle(appearance).id=='cover'
    local choice=cover and (appearance and appearance.cover_background or G_reader_settings:readSetting(S.cover_background)or 'white')
        or (appearance and appearance.background or G_reader_settings:readSetting(S.background)or 'white')
    if choice=='transparent' then return nil end
    return choice=='black' and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
end

local Quicklook = InputContainer:extend{modal=true,name='quick_look_box',covers_fullscreen=true}
function Quicklook:init()
    self[1]=buildReceipt(self.ui,self.state)
        or CenterContainer:new{dimen=Screen:getSize(),TextWidget:new{text='无法获取阅读小票',face=Font:getFace('cfont',22)}}
    self[1]=FrameContainer:new{width=Screen:getWidth(),height=Screen:getHeight(),
        bordersize=0,padding=0,margin=0,background=receiptBackground(),self[1]}
    if Device:hasKeys() then self.key_events.AnyKeyPressed={{Device.input.group.Any}} end
    if Device:isTouchDevice() then
        for _,v in ipairs({'Tap','Swipe','MultiSwipe'}) do
            local ges=v=='Tap' and 'tap' or (v=='Swipe' and 'swipe' or 'multiswipe')
            self.ges_events[v]={GestureRange:new{ges=ges,range=function() return self.dimen end}}
        end
    end
end
function Quicklook:onTap() UIManager:close(self);refreshQuicklook=nil;return true end
Quicklook.onSwipe=Quicklook.onTap
Quicklook.onMultiSwipe=Quicklook.onTap
Quicklook.onAnyKeyPressed=Quicklook.onTap
function Quicklook:onCloseWidget() refreshQuicklook=nil end
-- Persist only values, never the ReaderUI or a document that will be closed.
local function rememberReceipt(ui)
    if not ui.document or not ui.doc_props then return end
    local state=ui.view and ui.view.state
    local page=tonumber(state and state.page)
    local total=tonumber(ui.document:getPageCount())
    if not page or not total or total<1 then return end
    local display_page,display_total=page,total
    if ui.pagemap and ui.pagemap.wantsPageLabels and ui.pagemap:wantsPageLabels() then
        local _,idx,count=ui.pagemap:getCurrentPageLabel(true)
        if idx and count and count>0 then display_page,display_total=idx,count end
    end
    local chapter=ui.toc and ui.toc:getTocTitleByPage(page) or nil
    local stats=ui.statistics
    local snapshot={file=ui.document.file,props=ui.doc_props,page=page,total=total,
        display_page=display_page,display_total=display_total,chapter=chapter,
        stats_enabled=stats~=nil and (not stats.isEnabled or stats:isEnabled()),
        stats_id=stats and stats.id_curr_book,avg_time=stats and stats.avg_time}
    store:saveSetting('last_receipt',snapshot)
    store:flush()
end

local function homeReceiptContext()
    local path=G_reader_settings:readSetting('lastfile')
    if not path then return nil,'尚未阅读书籍，打开一本书后即可显示InkFolio。' end
    if lfs.attributes(path,'mode')~='file' then
        return nil,'最近阅读的书籍已移动或删除，请重新打开书籍。'
    end
    local saved=store:readSetting('last_receipt')
    if not saved or saved.file~=path then
        return nil,'最近阅读的书籍尚无InkFolio记录，请打开该书并返回主页一次。'
    end
    local context={document={file=path},doc_props=saved.props,
        doc_settings={data={doc_pages=saved.total}},
        view={state={page=saved.page}},file_cover=true,
        bookinfo=BookInfo,
        pagemap={wantsPageLabels=function()return true end,
            getCurrentPageLabel=function()return nil,saved.display_page,saved.display_total end},
        toc={getTocTitleByPage=function()return saved.chapter end},
        statistics={id_curr_book=saved.stats_id,avg_time=saved.avg_time,
            isEnabled=function()return saved.stats_enabled end}}
    return context
end

-- Capture while the document and its modules are still alive.
local nativeReaderClose=ReaderUI.onClose
ReaderUI.onClose=function(self,...)
    Inkfolio.observeWords(self)
    if Inkfolio.progressEnabled(S.word_book) then Inkfolio.estimatedWords(self,0) end
    Inkfolio.flushWords()
    rememberReceipt(self)
    return nativeReaderClose(self,...)
end

function Inkfolio.context()
    local ui=ReaderUI.instance
    if ui and ui.document then return ui end
    return homeReceiptContext()
end
function Inkfolio.message(text)
    UIManager:show(require('ui/widget/infomessage'):new{text=text})
end
function Inkfolio.backdrop()
    local bb=Screen.bb:copy()
    local ok,err=pcall(function()
        local ui=ReaderUI.instance
        if ui and ui.document and ui.view then ui.view:paintTo(bb,0,0)
        else
            local fm=require('apps/filemanager/filemanager').instance
            assert(fm,'主页界面不可用')
            fm:paintTo(bb,0,0)
        end
    end)
    if not ok then bb:free();error(err) end
    return bb
end
function Inkfolio.preview()
    UIManager:nextTick(function()
        local ui,reason=Inkfolio.context()
        if not ui then Inkfolio.message(reason);return end
        local box=Quicklook:new{ui=ui,state=ui.view and ui.view.state}
        local function refresh(key)
            if not key or key==bookKey(extractBook(ui.doc_props,ui.document.file)) then
                UIManager:close(box)
                box=Quicklook:new{ui=ui,state=ui.view and ui.view.state}
                refreshQuicklook=refresh
                UIManager:show(box)
            end
        end
        refreshQuicklook=refresh
        UIManager:show(box)
    end)
    return true
end
function Inkfolio.saveScreenshot()
    local ui,reason=Inkfolio.context()
    if not ui then Inkfolio.message(reason);return true end
    local receipt,canvas,path
    local ok,err=pcall(function()
        local valid
        receipt,valid=buildReceipt(ui,ui.view and ui.view.state)
        assert(valid,'InkFolio无法完整显示，请减小比例或检查字体。')
        local Screenshoter=require('ui/widget/screenshoter')
        local dir=G_reader_settings:readSetting('screenshot_dir') or Screenshoter.default_dir
        assert(type(dir)=='string' and dir~='' and util.makePath(dir),'截屏目录无法创建或访问')
        local stem=dir:gsub('/$','')..'/Inkfolio_'..os.date('%Y-%m-%d_%H%M%S')
        path=stem..'.png'
        local number=1
        while lfs.attributes(path) do path=stem..'_'..number..'.png';number=number+1 end
        local bg=receiptBackground()
        canvas=bg and Blitbuffer.new(Screen:getWidth(),Screen:getHeight(),Screen.bb:getType()) or Inkfolio.backdrop()
        if bg then canvas:fill(bg) end
        receipt:paintTo(canvas,0,0)
        canvas:writePNG(path)
        assert((lfs.attributes(path,'size') or 0)>0,'截图文件写入失败')
    end)
    if receipt then receipt:free() end
    if canvas then canvas:free() end
    if not ok then
        if path then os.remove(path) end
        Inkfolio.message('InkFolio 截图失败：'..tostring(err))
    else Inkfolio.message('InkFolio 截图已保存：\n'..path) end
    return true
end

local Screensaver=require('ui/screensaver')
local nativeShow=Screensaver.show
Screensaver.show=function(self)
    if self.screensaver_type~='book_receipt' then return nativeShow(self) end
    if not Device:supportsScreensaver() then
        UIManager:show(require('ui/widget/infomessage'):new{text='此平台不支持 KOReader 休眠壁纸，可在阅读中打开小票预览。'})
        return
    end
    -- Native sleep display precedes Suspend on Kobo and Kindle. Advance here,
    -- once per actual lock; previews, screenshots and duplicate shows do not.
    if not Device.screen_saver_mode and (not self.prefix or self.prefix=='') then Inkfolio.rotateMonthly() end
    local ui=self.ui or ReaderUI.instance
    local unavailable
    if not ui or not ui.document then ui,unavailable=homeReceiptContext() end
    if self.screensaver_widget then
        UIManager:close(self.screensaver_widget)
        self.screensaver_widget=nil
    end
    Device.screen_saver_mode=true
    -- Preserve the reader's orientation, including the underlying transparent image.
    local state=ui and ui.view and ui.view.state
    local receipt=ui and buildReceipt(ui,state) or CenterContainer:new{
        dimen=Screen:getSize(),TextBoxWidget:new{
            text=unavailable,face=Font:getFace('cfont',22),
            width=math.floor(Screen:getWidth()*.8),alignment='center',justified=false}}
    self.screensaver_widget=ScreenSaverWidget:new{
        widget=receipt,background=receiptBackground(),covers_fullscreen=true,
    }
    self.screensaver_widget.modal=true
    self.screensaver_widget.dithered=true
    UIManager:show(self.screensaver_widget,'full')
end

-- Keep event wrappers deliberately shallow: preserve existing KOReader handlers.
local function hook(target, event, callback)
    if not target then return end
    local previous=target[event]
    target[event]=function(self,...)
        local result
        if previous then result=previous(self,...) end
        callback()
        return result
    end
end
local function awake()
    Inkfolio.recordAction('唤醒')
    Inkfolio.recordDailyWords(0,false)
    Inkfolio.resumeWords()
    RUN.sleeping=false
    RUN.cancelled_wake=false;RUN.auto_holds={}
    currentCheck()
    startPoll()
end
local function doSleep()
    Inkfolio.recordAction('休眠')
    Inkfolio.observeWords(ReaderUI.instance)
    Inkfolio.flushWords()
    Inkfolio.wordState.sleeping=true
    RUN.sleeping=true
    if RUN.active or RUN.worker then abortRound() end
    POLL_ENABLED=false
    UIManager:unschedule(pollWifi)
end
local function onlineEvent()
    if RUN.sleeping or not networkingEnabled() or MANUAL_CONNECT_PENDING then return end
    resetDay();Inkfolio.resetNetworkPause()
    currentCheck();startPoll()
end
local function bookOpened()
    UIManager:nextTick(function()
        if RUN.sleeping or not networkingEnabled() then return end
        currentCheck();startPoll()
    end)
end
hook(ReaderUI,'onResume',awake)
hook(ReaderUI,'onSuspend',doSleep)
hook(ReaderUI,'onNetworkConnected',onlineEvent)
hook(ReaderUI,'onReaderReady',bookOpened)
local function recordVisibleWords()
    UIManager:unschedule(Inkfolio.captureWords)
    UIManager:nextTick(Inkfolio.captureWords)
end
hook(ReaderUI,'onReaderReady',recordVisibleWords)
hook(ReaderUI,'onPageUpdate',recordVisibleWords)
hook(ReaderUI,'onPosUpdate',recordVisibleWords)

-- KOReader's file manager can remain active while reader events are not delivered.
local FMok,FM=pcall(require,'apps/filemanager/filemanager')
if FMok and FM then
    hook(FM,'onResume',awake)
    hook(FM,'onSuspend',doSleep)
    hook(FM,'onNetworkConnected',onlineEvent)
    hook(FM,'showFiles',Inkfolio.libraryChanged)
    hook(FM,'onRefresh',Inkfolio.libraryChanged)
    hook(FM,'onRefreshContent',Inkfolio.libraryChanged)
end
UIManager:scheduleIn(3,function() awake() end)

-- Render at the device resolution, then shrink the actual pixels for editing.
Inkfolio.APPEARANCE_NUMBERS={
    {key='width',label='宽度',step=1,min=55,max=90},
    {key='font',label='字号',step=5,min=80,max=120},
    {key='scale',label='比例',step=5,min=50,max=150},
}
function Inkfolio.appearancePercent(value)
    return (string.format('%.1f',value*100):gsub('%.0$',''))..'%'
end
function Inkfolio.parseAppearanceNumber(text,spec)
    text=util.trim(tostring(text or ''))
    if not (text:match('^%d+$') or text:match('^%d+%.%d$')) then
        return nil,'请输入数值，最多保留一位小数。'
    end
    local value=tonumber(text)
    if value<spec.min or value>spec.max then
        return nil,'请输入 '..spec.min..'～'..spec.max..' 之间的数值（%）。'
    end
    return value/100
end
local AppearanceEditor=InputContainer:extend{modal=true,covers_fullscreen=true,name='inkfolio_appearance'}
function AppearanceEditor:init()
    self.draft={width=G_reader_settings:readSetting(S.width) or .72,
        font=G_reader_settings:readSetting(S.font) or 1,
        scale=G_reader_settings:readSetting(S.scale) or 1,
        background=G_reader_settings:readSetting(S.background) or 'white',ui_style=Inkfolio.uiStyle().id,
        card_width=G_reader_settings:readSetting(S.card_width)or .50,card_font=G_reader_settings:readSetting(S.card_font)or 1,
        card_background=G_reader_settings:readSetting(S.card_background)or 'auto',
        cover_background=G_reader_settings:readSetting(S.cover_background)or 'white'}
    self.backdrop=Screen.bb:copy()
    -- Repaint the reading view without the settings menu for transparent previews.
    local live=ReaderUI.instance
    if live and live.document and live.view then live.view:paintTo(self.backdrop,0,0) end
    if (not live or not live.document) and FM and FM.instance then FM.instance:paintTo(self.backdrop,0,0) end
    self.refresh_callback=function()if not self.closed then self:refreshPreview() end end
    if Device:hasKeys() then self.key_events.Cancel={{Device.input.group.Back}} end
    if Device:isTouchDevice()then
        self.ges_events.PreviewTap={GestureRange:new{ges='tap',range=function()
            return self.preview_image and self.preview_image.dimen or Geom:new()
        end}}
    end
    self:refreshPreview()
end
function AppearanceEditor:onPreviewTap()
    if self.fullscreen then return true end
    if self.pending then self:refreshPreview()end
    local editor=self
    local dialog=InputContainer:new{modal=true,covers_fullscreen=true,stop_events_propagation=true,
        name='inkfolio_appearance_fullscreen',dimen=Screen:getSize(),
        ImageWidget:new{image=self.preview_canvas,width=Screen:getWidth(),height=Screen:getHeight(),image_disposable=false}}
    local function close()UIManager:close(dialog);return true end
    dialog.ges_events.Tap={GestureRange:new{ges='tap',range=Screen:getSize()}}
    dialog.key_events.AnyKeyPressed={{Device.input.group.Any}}
    dialog.onTap=close;dialog.onCancel=close
    dialog.onAnyKeyPressed=close
    dialog.onSuspend=function()editor:onSuspend();return false end
    dialog.onSetRotationMode=dialog.onSuspend
    dialog.onCloseWidget=function(self)
        editor.fullscreen=nil;self:free();UIManager:setDirty(nil,'full')
    end
    self.fullscreen=dialog;UIManager:show(dialog);UIManager:setDirty(dialog,'full')
    return true
end
function AppearanceEditor:change(key,value)
    Inkfolio.recordAction('外观调整操作')
    self.draft[key]=value
    UIManager:unschedule(self.refresh_callback)
    self.pending=true
    UIManager:scheduleIn(.5,self.refresh_callback)
end
function AppearanceEditor:selectStyle(id)
    local theme=Inkfolio.uiStyle({ui_style=id})
    local reason=Inkfolio.uiFontError(theme)
    if reason then Inkfolio.message(reason);return false,reason end
    self:change('ui_style',id)
    self:refreshPreview()
    return true
end
function AppearanceEditor:editNumber(spec)
    local dialog
    dialog=require('ui/widget/inputdialog'):new{
        title=spec.label..'（%）',modal=true,
        input=(Inkfolio.appearancePercent(self.draft[spec.key]):gsub('%%$','')),
        description='输入 '..spec.min..'～'..spec.max..'，最多保留一位小数。',input_type='number',
        buttons={{{text='取消',callback=function()UIManager:close(dialog)end},
            {text='预览',is_enter_default=true,callback=function()
                local value,reason=Inkfolio.parseAppearanceNumber(dialog:getInputText(),spec)
                if not value then Inkfolio.message(reason);return end
                UIManager:close(dialog)
                self:change(spec.key,value);self:refreshPreview()
            end}}},
    }
    self.number_dialog=dialog
    local close=dialog.onCloseWidget
    dialog.onCloseWidget=function(child,...)
        self.number_dialog=nil
        if close then return close(child,...) end
    end
    UIManager:show(dialog);dialog:onShowKeyboard()
end
function AppearanceEditor:refreshPreview()
    UIManager:unschedule(self.refresh_callback)
    self.pending=false
    self.valid=false
    local sw,sh=Screen:getWidth(),Screen:getHeight()
    local pad=math.max(4,math.floor(math.min(sw,sh)*.02))
    local gap=math.max(3,math.floor(sh*.006))
    local rowh=math.max(20,math.floor(sh*.055))
    local fs=math.max(8,math.min(18,math.floor(rowh/Screen:scaleBySize(2.7))))
    local width=sw-2*pad
    local title=TextWidget:new{text='InkFolio 外观 · '..sw..'×'..sh,max_width=width,face=Font:getFace('infofont',fs+2)}
    local receipt,valid=buildReceipt(self.ui,self.ui.view and self.ui.view.state,self.draft)
    assert(receipt,'InkFolio appearance: missing book context')
    local preview_valid=valid==true
    local status=TextWidget:new{text=preview_valid and '点击画面全屏；点击数值输入；保存后生效' or '无法显示，请减小设置或检查字体',
        max_width=width,face=Font:getFace('infofont',fs)}
    local rows={}
    local button_padding=require('ui/size').padding.buttontable
    local function button(text,callback,enabled,bw,checked)
        return {text=text,callback=callback,enabled=enabled~=false,width=bw,checked_func=checked,height=math.max(1,rowh-2*button_padding),
            font_size=fs,font_face='infofont'}
    end
    local style_row={button('风格',nil,false)}
    for _,item in ipairs(Inkfolio.UI_STYLES)do
        local id=item.id
        style_row[#style_row+1]=button(item.label,function()self:selectStyle(id)end,true,nil,
            function()return self.draft.ui_style==id end)
    end
    rows[#rows+1]=style_row
    local specs=self.draft.ui_style=='cover'and {
        {key='card_width',label='卡片宽度',step=5,min=40,max=85},
        {key='card_font',label='卡片字号',step=5,min=80,max=120}}or Inkfolio.APPEARANCE_NUMBERS
    for _,spec in ipairs(specs)do
        local key=spec.key
        local current=math.floor(self.draft[key]*1000+.5)/10
        local function adjust(direction)
            local value=math.floor(self.draft[key]*1000+direction*spec.step*10+.5)/10
            self:change(key,math.max(spec.min,math.min(spec.max,value))/100)
        end
        rows[#rows+1]={
            button('−',function()adjust(-1)end,current>spec.min),
            button(spec.label..' '..Inkfolio.appearancePercent(self.draft[key]),function()self:editNumber(spec)end,true,math.floor(width*.5)),
            button('+',function()adjust(1)end,current<spec.max)}
    end
    local is_cover=self.draft.ui_style=='cover'
    local background_key=is_cover and 'cover_background'or 'background'
    local background={button(is_cover and '封面底色'or '背景',nil,false)}
    local choices=is_cover and {{'白色','white'},{'黑色','black'}}or {{'白色','white'},{'黑色','black'},{'透明','transparent'}}
    for _,item in ipairs(choices) do
        local label,key=item[1],item[2]
        background[#background+1]=button(label,function()self:change(background_key,key)end,true,nil,
            function()return self.draft[background_key]==key end)
    end
    rows[#rows+1]=background
    if is_cover then
        local card_colors={button('卡片底色',nil,false)}
        for _,item in ipairs({{'自动','auto'},{'白色','white'},{'黑色','black'}})do
            local label,key=item[1],item[2]
            card_colors[#card_colors+1]=button(label,function()self:change('card_background',key)end,true,nil,
                function()return self.draft.card_background==key end)
        end
        rows[#rows+1]=card_colors
    end
    rows[#rows+1]={button('取消',function()self:onCancel()end),
        button('保存',function()self:save()end,preview_valid)}
    local controls=require('ui/widget/buttontable'):new{width=width,buttons=rows,show_parent=self,
        addVerticalSpan=function(table_widget)
            table.insert(table_widget.container,VerticalSpan:new{width=gap})
        end}
    local available=sh-2*pad-title:getSize().h-status:getSize().h-controls:getSize().h-3*gap
    assert(available>0,'InkFolio appearance controls exceed screen')
    local zoom=math.min(width/sw,available/sh)
    local pw,ph=math.max(1,math.floor(sw*zoom)),math.max(1,math.floor(sh*zoom))
    local canvas=Blitbuffer.new(sw,sh,self.backdrop:getType())
    local background_color=receiptBackground(self.draft)
    if background_color then canvas:fill(background_color)
    else canvas:blitFrom(self.backdrop,0,0,0,0,sw,sh) end
    receipt:paintTo(canvas,0,0)
    receipt:free()
    local bitmap=RenderImage:scaleBlitBuffer(canvas,pw,ph,false)
    local preview_image=ImageWidget:new{image=bitmap,width=pw,height=ph,image_disposable=true}
    local preview=CenterContainer:new{dimen=Geom:new{w=width,h=available},
        preview_image}
    local old=self[1]
    self[1]=FrameContainer:new{width=sw,height=sh,bordersize=0,margin=0,padding=pad,
        background=Blitbuffer.COLOR_WHITE,VerticalGroup:new{align='center',title,
            VerticalSpan:new{width=gap},preview,VerticalSpan:new{width=gap},status,
            VerticalSpan:new{width=gap},controls}}
    if old then old:free() end
    if self.preview_canvas then self.preview_canvas:free()end
    self.preview_canvas=canvas;self.preview_image=preview_image
    self.valid=preview_valid
    UIManager:setDirty(self,'ui')
end
function AppearanceEditor:save()
    Inkfolio.recordAction('外观保存')
    if self.pending then self:refreshPreview() end
    if not self.valid then return end
    local before_today,before_tomorrow=Inkfolio.weatherSelected(0),Inkfolio.weatherSelected(1)
    local is_cover=self.draft.ui_style=='cover'
    local changes=is_cover and {}or {[S.auto_fit]=false}
    local keys=is_cover and {'ui_style','card_width','card_font','card_background','cover_background'}or {'width','font','scale','background','ui_style'}
    for _,key in ipairs(keys)do changes[S[key]]=self.draft[key]end
    Inkfolio.persistSettings(changes)
    UIManager:close(self)
    if before_today~=Inkfolio.weatherSelected(0)or before_tomorrow~=Inkfolio.weatherSelected(1)then
        Inkfolio.weatherChanged(Inkfolio.weatherEnabled())
    elseif refreshQuicklook then refreshQuicklook()end
end
function AppearanceEditor:onCancel()
    if self.number_dialog then UIManager:close(self.number_dialog) end
    if self.fullscreen then UIManager:close(self.fullscreen)end
    UIManager:close(self);return true
end
function AppearanceEditor:onSuspend() self:onCancel();return false end
AppearanceEditor.onSetRotationMode=AppearanceEditor.onSuspend
function AppearanceEditor:onCloseWidget()
    self.closed=true
    UIManager:unschedule(self.refresh_callback)
    if self.backdrop then self.backdrop:free();self.backdrop=nil end
    if self.fullscreen then UIManager:close(self.fullscreen)end
    if self.preview_canvas then self.preview_canvas:free();self.preview_canvas=nil end
    self:free()
    UIManager:setDirty(nil,'full')
end
local function editAppearance()
    local ui=ReaderUI.instance
    local reason
    if not ui or not ui.document then ui,reason=homeReceiptContext() end
    if not ui then
        UIManager:show(require('ui/widget/infomessage'):new{text=reason})
        return
    end
    Inkfolio.ensureAutoFit(ui,ui.view and ui.view.state)
    UIManager:show(AppearanceEditor:new{ui=ui})
end

function Inkfolio.copyMatchState()
    local state={choices={},pending={},holds=Inkfolio.matchState.holds}
    for k,v in pairs(Inkfolio.matchState.choices)do state.choices[k]=v end
    for k,v in pairs(Inkfolio.matchState.pending)do state.pending[k]=v end
    return state
end
function Inkfolio.acceptMatch(book,url)
    Inkfolio.recordAction('匹配认可')
    if RUN.active or RUN.worker or MANUAL_CONNECT_PENDING then return false,'获取进行中，请结束后再确认。' end
    local key=Inkfolio.fileMatchKey(book);local pending=Inkfolio.matchState.pending[key]
    if not pending then return false,'待确认结果已变化，请重新获取。' end
    local record
    for _,c in ipairs(pending.candidates)do if c.url==url then record=c;break end end
    if not record or not validURL(record.url) or not record.rating or record.rating<=0 or record.rating>10 then return false,'候选没有有效评分，不能确认。' end
    local copy={};for k,v in pairs(record)do copy[k]=v end
    copy.user_confirmed=true;copy.confirmed_at=os.time();copy.identity_version=2
    -- User accepts one concrete source, not a guessed collection average.
    copy.volume=nil;copy.collection_scope=nil;copy.score_kind=nil
    local state=Inkfolio.copyMatchState()
    state.choices[key]={url=record.url,title=record.title,authors=record.authors,at=copy.confirmed_at,book_identity=Inkfolio.metadataKey(book)}
    state.pending[key]=nil
    local holds={};for k,v in pairs(state.holds)do if k~=key then holds[k]=v end end;state.holds=holds
    local cachekey='confirmed:'..key;local old=CACHE[cachekey];local oldstate=Inkfolio.matchState
    CACHE[cachekey]=copy
    local ok=pcall(function()store:saveSetting('books',CACHE);store:saveSetting('book_matching',state);store:flush()end)
    if not ok then CACHE[cachekey]=old;store:saveSetting('books',CACHE);store:saveSetting('book_matching',oldstate);return false,'确认保存失败，请检查设置目录。' end
    Inkfolio.matchState=state
    Inkfolio.infoResult('books',bookKey(book),'success')
    if refreshQuicklook then refreshQuicklook(bookKey(book)) end
    return true
end
function Inkfolio.dismissMatch(book)
    Inkfolio.recordAction('暂不采用')
    if RUN.active or RUN.worker then return false,'获取进行中，请稍后操作。' end
    local state=Inkfolio.copyMatchState();local key=Inkfolio.fileMatchKey(book);state.pending[key]=nil
    local holds={};for k,v in pairs(state.holds)do holds[k]=v end
    holds[key]=Inkfolio.metadataKey(book);state.holds=holds
    return Inkfolio.writeMatchState(state)
end
function Inkfolio.showCandidate(book,candidate,parent)
    local text='当前文件：'..book.title..'\n\n候选图书：'..candidate.title..'\n作者／贡献者：'..candidate.authors
        ..'\n评分：'..candidate.rating..'/10\n版本信息：'..tostring(candidate.version_note or '')
        ..'\n核验差异：'..tostring(candidate.reason or '用户检索结果，仍需确认')
        ..'\n来源：'..candidate.url..'\n获取时间：'..infoTime(candidate.updated_at)
        ..'\n\n简介：'..tostring(candidate.intro or '来源没有可提取的简介')
        ..'\n\n认可后按此具体条目显示，不代表全集或其他版本的评分。'
    local viewer
    viewer=require('ui/widget/textviewer'):new{title='确认图书匹配',text=text,
        buttons_table={{{text='返回',callback=function()UIManager:close(viewer);Inkfolio.showBookMatches(book,parent)end},
            {text='认可此信息',callback=function()
                local ok,err=Inkfolio.acceptMatch(book,candidate.url)
                UIManager:show(require('ui/widget/infomessage'):new{text=ok and '已保存用户确认的匹配信息。' or err})
                if ok then UIManager:close(viewer);if parent then parent:refreshPending() end end
            end}}}}
    UIManager:show(viewer)
end
function Inkfolio.showBookMatches(book,parent)
    if RUN.active or RUN.worker then UIManager:show(require('ui/widget/infomessage'):new{text='获取进行中，请结束后再确认。'});return end
    local p=Inkfolio.matchState.pending[Inkfolio.fileMatchKey(book)]
    if not p then Inkfolio.editMatchQuery(book,parent);return end
    local buttons={};local dialog
    for _,c in ipairs(p.candidates)do
        local candidate=c
        buttons[#buttons+1]={{text=c.title..' · '..c.rating..'/10',callback=function()UIManager:close(dialog);Inkfolio.showCandidate(book,candidate,parent)end}}
    end
    buttons[#buttons+1]={{text='自行输入书名、作者',callback=function()UIManager:close(dialog);Inkfolio.editMatchQuery(book,parent)end}}
    buttons[#buttons+1]={{text='暂不采用',callback=function()
        local ok,err=Inkfolio.dismissMatch(book)
        if ok then UIManager:close(dialog);if parent then parent:refreshPending() end end
        UIManager:show(require('ui/widget/infomessage'):new{text=ok and (cached(book) and '保留已有信息；以后仍可重新获取。' or '本书暂不显示联网评分和简介；以后仍可重新获取。') or err})
    end},{text='稍后处理',callback=function()UIManager:close(dialog);if parent then parent:refreshPending() end end}}
    dialog=require('ui/widget/buttondialog'):new{title=shortText(book.title,45)..'\n待确认：'..shortText(tostring(p.reason or ''),80),buttons=buttons}
    UIManager:show(dialog)
end
function Inkfolio.showPendingMatches(parentMenu)
    if RUN.active or RUN.worker then UIManager:show(require('ui/widget/infomessage'):new{text='获取进行中，请结束后再确认。'});return end
    local dialog
    local function items()
        local entries={};for key,p in pairs(Inkfolio.matchState.pending)do
            if #p.candidates>0 then entries[#entries+1]={key=key,p=p} end
        end
        table.sort(entries,function(a,b)return a.key<b.key end)
        local rows={}
        for _,entry in ipairs(entries)do
            local book=entry.p.book
            rows[#rows+1]={text=book.title,callback=function()Inkfolio.showBookMatches(book,dialog)end}
        end
        if #rows==0 then rows={{text='暂无待确认图书',select_enabled=false}} end
        return rows
    end
    dialog=require('ui/widget/menu'):new{title='待确认图书',item_table=items(),width=math.floor(Screen:getWidth()*.9),
        onMenuSelect=function(_,item)if item.callback then item.callback() end end}
    function dialog:refreshPending()
        if self.inkfolio_closed then return end
        local page=self.page or 1
        self:switchItemTable('待确认图书',items(),-1)
        self.page=math.max(1,math.min(page,self.page_num or 1));self:updateItems()
    end
    local close=dialog.onCloseWidget
    dialog.onCloseWidget=function(self,...)
        self.inkfolio_closed=true
        if close then return close(self,...) end
    end
    UIManager:show(Inkfolio.refreshParentOnClose(dialog,parentMenu))
end
function Inkfolio.editMatchQuery(book,parent)
    Inkfolio.recordAction('重新检索')
    if not book then UIManager:show(require('ui/widget/infomessage'):new{text='请在阅读界面选择一本书。'});return end
    if RUN.active or RUN.worker or MANUAL_CONNECT_PENDING then UIManager:show(require('ui/widget/infomessage'):new{text='已有获取任务，请结束后再检索。'});return end
    local dialog
    dialog=require('ui/widget/multiinputdialog'):new{title='重新检索当前图书',
        fields={{description='书名',text=Inkfolio.searchTitle(book)},{description='作者',text=book.authors}},
        buttons={{{text='取消',callback=function()UIManager:close(dialog)end},
            {text='提交检索',callback=function()
                local fields=dialog:getFields();local title,author=util.trim(fields[1]),util.trim(fields[2])
                if title=='' or author=='' or #title>600 or #author>600 or title:find('[\r\n]') or author:find('[\r\n]') then
                    UIManager:show(require('ui/widget/infomessage'):new{text='请输入一行书名和作者，每项不超过200个汉字。'});return
                end
                if not networkingEnabled() or not connected() then UIManager:show(require('ui/widget/infomessage'):new{text='请开启插件联网并连接网络后提交。'});return end
                if RUN.active or RUN.worker then UIManager:show(require('ui/widget/infomessage'):new{text='已有获取任务，请稍后提交。'});return end
                UIManager:close(dialog)
                local request={};for k,v in pairs(book)do request[k]=v end
                request.title=title;request.path=nil;request.authors=author;request.isbn='';request.publisher='';request.description=''
                request.review_target=book;request.force_review=true
                RUN.active=true;RUN.manual=true;RUN.started=false;RUN.current_only=true;RUN.token=RUN.token+1
                RUN.transport_broken=false;RUN.network_failures=0;RUN.last_error=nil
                RUN.done,RUN.total,RUN.processed,RUN.failed=0,1,0,0;RUN.queue={};RUN.book_paths={}
                progressBegin(true);PROGRESS.total,PROGRESS.scanning,PROGRESS.book=1,false,book.title
                Inkfolio.infoAttempt('books',bookKey(book));local token=RUN.token
                Inkfolio.fetchVerifiedBook(request,token,function(_,reason)
                    if token~=RUN.token then return end
                    local pending=Inkfolio.matchState.pending[Inkfolio.fileMatchKey(book)]
                    Inkfolio.infoResult('books',bookKey(book),pending and #pending.candidates>0 and 'pending' or 'failed',reason)
                    RUN.done=1;PROGRESS.done=1;RUN.active=false;RUN.manual=false;progressEnd(reason or '检索完成，等待确认。')
                    if parent then parent:refreshPending() end
                    if pending and #pending.candidates>0 then Inkfolio.showBookMatches(book,parent)
                    else UIManager:show(require('ui/widget/infomessage'):new{text=(cached(book) and '未匹配成功，保留已有信息。' or '未匹配成功，本书暂不显示联网评分和简介。')..'\n'..tostring(reason or '')}) end
                    if startPoll then startPoll() end
                end)
            end}}}}
    UIManager:show(dialog);dialog:onShowKeyboard()
end
function Inkfolio.clearCurrentMatch()
    local book=currentBook();if not book or RUN.active or RUN.worker then return end
    local dialog
    dialog=require('ui/widget/confirmbox'):new{text='解除本书的用户确认匹配？后续重新按自动规则核验。',
        ok_text='解除',ok_callback=function()
            local state=Inkfolio.copyMatchState();state.choices[Inkfolio.fileMatchKey(book)]=nil
            local ok,err=Inkfolio.writeMatchState(state)
            UIManager:show(require('ui/widget/infomessage'):new{text=ok and '已解除匹配，请重新更新信息。' or err})
        end}
    UIManager:show(dialog)
end

local function footerTextValid(text)
    if text:find('[\r\n]') then return false end
    local _,count=text:gsub('[^\128-\191]','')
    return count<=20
end
function Inkfolio.editSearchTitle()
    local book=currentBook()
    if not book or book.title=='' then
        UIManager:show(require('ui/widget/infomessage'):new{text='请在需要设置的书籍阅读界面打开此选项。'})
        return
    end
    if RUN.active or RUN.worker or MANUAL_CONNECT_PENDING then
        UIManager:show(require('ui/widget/infomessage'):new{text='获取进行中，请结束后再修改搜索书名。'})
        return
    end
    local dialog
    local function save(text)
        local ok,reason=Inkfolio.setSearchTitle(book,text)
        if not ok then UIManager:show(require('ui/widget/infomessage'):new{text=reason});return end
        UIManager:close(dialog)
        UIManager:show(require('ui/widget/infomessage'):new{text='搜索书名已保存，请使用“更新信息”重新获取。'})
    end
    dialog=require('ui/widget/inputdialog'):new{
        title='当前书籍的搜索书名',input=Inkfolio.searchTitle(book),
        description='只影响此书的联网搜索与匹配，不修改文件或小票书名。恢复默认后自动根据内部标题和文件名确认。',
        buttons={{{text='取消',callback=function()UIManager:close(dialog)end},
            {text='恢复默认',callback=function()save(nil)end},
            {text='保存',is_enter_default=true,callback=function()save(dialog:getInputText())end}}},
    }
    UIManager:show(dialog);dialog:onShowKeyboard()
end
local function editFooter()
    local InputDialog=require('ui/widget/inputdialog')
    local dialog
    dialog=InputDialog:new{
        title='小票底部文字（最多20字）',
        input=G_reader_settings:readSetting(S.footer) or '',
        buttons={{
            {text='取消',callback=function() UIManager:close(dialog) end},
            {text='保存',is_enter_default=true,callback=function()
                local text=dialog:getInputText()
                if not footerTextValid(text) then
                    UIManager:show(require('ui/widget/infomessage'):new{text='请输入一行文字，最多20个字符。'})
                    return
                end
                G_reader_settings:saveSetting(S.footer,text)
                UIManager:close(dialog)
            end},
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end


local function weatherCityMenu()
    local regions={{text='不设置城市',radio=true,keep_menu_open=true,
        checked_func=function()return G_reader_settings:readSetting(S.weather_city)==false end,
        callback=function()
            G_reader_settings:saveSetting(S.weather_city,false)
            WEATHER.pending=false;store:saveSetting('weather',WEATHER);store:flush()
            startPoll();if refreshQuicklook then refreshQuicklook()end
        end}}
    for _,region in ipairs(WEATHER_REGIONS) do
        local rows={}
        for _,city in ipairs(region.cities) do
            rows[#rows+1]={
                radio=true,text=city.name..(city.code=='' and '（气象台暂无数据）' or ''),
                enabled=city.code~='',keep_menu_open=true,
                checked_func=function() local selected=selectedWeatherCity();return selected~=nil and selected.code==city.code end,
                callback=function()
                    if city.code=='' then return end
                    local selected=selectedWeatherCity()
                    if selected and selected.code==city.code then return end
                    G_reader_settings:saveSetting(S.weather_city,city.code)
                    RUN.auto_holds.weather=nil;Inkfolio.resetNetworkPause()
                    WEATHER.pending=selectedWeatherCity()~=nil
                    store:saveSetting('weather',WEATHER);store:flush()
                    -- Wait for the current HTTP request, then fetch the newly selected city.
                    weatherCheck();startPoll()
                end,
            }
        end
        regions[#regions+1]={text=region.name,sub_item_table=rows}
    end
    return regions
end

local function progressMenu()
    local rows={
        {text='章节（固定）',checked_func=function()return true end,enabled=false},
        {text='当前页码（固定）',checked_func=function()return true end,enabled=false},
    }
    for _,item in ipairs(PROGRESS_ITEMS) do
        local key=item.key
        local function available()return Inkfolio.progressEnabled(key) or Inkfolio.progressCount()<2 end
        rows[#rows+1]={text=item.label,keep_menu_open=true,
            help_text=key==S.word_book and '全书正文字数乘当前进度，属于折算值。' or key==S.word_session and '此次唤醒后跨书累计实际翻阅的正文，同一位置去重；休眠或重启后重新统计。' or nil,
            checked_func=function()return Inkfolio.progressEnabled(key)end,
            enabled_func=available,callback=function()
                if not available() then return end
                G_reader_settings:saveSetting(key,not Inkfolio.progressEnabled(key))
            end}
    end
    return rows
end

local function summaryMenu()
    local choices={}
    local rows={{text='显示阅读摘要',keep_menu_open=true,
        checked_func=function() return enabled(S.stats) end,
        callback=function() G_reader_settings:saveSetting(S.stats,not enabled(S.stats)) end}}
    for _,item in ipairs(SUMMARY_ITEMS) do
        local function checked()
            for _,selected in ipairs(summaryItems()) do if selected.id==item.id then return true end end
            return false
        end
        local function available()
            return enabled(S.stats) and (checked() or #summaryItems()<2)
        end
        local name=item.global and item.period and ('全局'..item.label) or item.label
        if not item.legacy or checked() then choices[#choices+1]={text=name..(item.legacy and '（旧设置）' or ''),keep_menu_open=true,checked_func=checked,
            enabled_func=available,callback=function()
                if not available() then return end
                local chosen={}
                local was_checked=checked()
                for _,selected in ipairs(summaryItems()) do
                    if selected.id~=item.id then chosen[#chosen+1]=selected.id end
                end
                if not was_checked then chosen[#chosen+1]=item.id end
                G_reader_settings:saveSetting(S.summary,chosen)
            end} end
    end
    rows[#rows+1]={text='摘要内容（最多2项）',sub_item_table=choices,
        text_func=function()return '摘要内容（已选'..#summaryItems()..'/2）' end,
        help_text='每项是一组数字摘要。选满两项后，请先取消一项，再选择其他内容；今日、本周、本月统计所有图书。'}
    local metrics={}
    for _,item in ipairs({{id='words',label='时长＋字数'},{id='pages',label='时长＋页数'}}) do
        local id=item.id
        metrics[#metrics+1]={text=item.label,radio=true,keep_menu_open=true,
            checked_func=function()return Inkfolio.summaryMetric()==id end,
            callback=function()G_reader_settings:saveSetting(S.summary_metric,id)end}
    end
    rows[#rows+1]={text='周期摘要指标',sub_item_table=metrics,
        text_func=function()return '周期摘要：时长＋'..(Inkfolio.summaryMetric()=='words' and '字数' or '页数') end,
        help_text='适用于全局今日、本周、本月。累计摘要与旧本书今日固定显示时长和页数。'}
    rows[#rows+1]={text='阅读图表（最多2项）',cover_disabled=true,sub_item_table={},
        text_func=function()return '阅读图表（已选'..#Inkfolio.chartItems()..'/2）' end,
        help_text='显示每天的阅读时长或字数，可独立于数字摘要选择；选满两项后，先取消一项再切换。'}
    local trend=rows[#rows].sub_item_table
    for _,item in ipairs(Inkfolio.CHART_ITEMS) do
        local function checked()
            for _,selected in ipairs(Inkfolio.chartItems()) do if selected.id==item.id then return true end end
            return false
        end
        local function available()return enabled(S.stats) and (checked() or #Inkfolio.chartItems()<2) end
        trend[#trend+1]={text=item.label,keep_menu_open=true,checked_func=checked,enabled_func=available,
            callback=function()
                if not available() then return end
                local chosen,was_checked={},checked()
                for _,selected in ipairs(Inkfolio.chartItems()) do if selected.id~=item.id then chosen[#chosen+1]=selected.id end end
                if not was_checked then chosen[#chosen+1]=item.id end
                G_reader_settings:saveSetting(S.charts,chosen)
            end}
    end
    rows[#rows+1]={text='统计说明',callback=Inkfolio.showStatisticsHelp}
    return rows
end

local function chooseLibraryRoot()
    local PathChooser=require('ui/widget/pathchooser')
    UIManager:show(PathChooser:new{
        title='选择书库目录',select_directory=true,select_file=false,show_files=false,
        path=rootPath() or Device.home_dir or '/',
        onConfirm=function(path)
            if path=='/' or lfs.attributes(path,'mode')~='directory' then
                UIManager:show(require('ui/widget/infomessage'):new{text='请选择可读取的图书文件夹，不能选择系统根目录。'})
                return
            end
            if RUN.active or RUN.worker then abortRound() end
            G_reader_settings:saveSetting(S.library_root,path)
            RUN.scan_pending=true
            dailyCheck(true);startPoll()
        end,
    })
end

local function openProjectLink(url)
    if not Device:openLink(url) then
        UIManager:show(require('ui/widget/textviewer'):new{
            title='此设备无法直接打开网页',text=url,justified=false,show_menu=false})
    end
end
function Inkfolio.showChangelog()
    UIManager:show(require('ui/widget/textviewer'):new{
        title='更新日志',text="尚未发布｜2026-10-24\n• 外观预览支持点击全屏，再次点击返回，保留未保存的调整。\n• 封面卡片底色支持自动、白色和黑色，自动按卡片周围画面明暗选择配色。\n• 修正单日天气与品牌文字的上下对齐；点击菜单外区域收起整套设置菜单。\n• 新增封面皮肤：完整封面与中央阅读卡片，默认卡片宽度为屏幕50%，支持黑白底色。\n• 封面皮肤不支持的显示选项灰显；天气单选今日或明日，左对齐，与右对齐的日期同排。\n• 按任务到期更新联网内容：天气6小时，图书失败间隔30分钟、每本每天最多3次；取消只暂停当前模块。\n• 取消固定45秒巡检与周期书库扫描，开书只检查本书，书库进入或刷新时扫描。\n• 统一信息层级与间距，现代皮肤书名字号提高到55，缩小顶栏天气与日期，简化图表分隔与辅助数字强调。\n• 统一外观选中标记，明确预览、保存及即时设置的生效方式。\n• 恢复城市天气，今日、明日天气与日期可分别勾选显示。\n• 单选天气沿用单行顶栏；同时选择两日天气时，第二排城市左对齐、今日居中、明日右对齐。\n\nv1.2.0｜2026-10-23\n\n新增\n• 阅读字数按日汇总，新增周／月字数柱状图，更直观地查看阅读量。\n• 日／周／月阅读目标，支持时长或字数，展示完成比例。\n• 小票、像素、现代三种风格，可切换并实时预览。\n• 豆瓣月榜，支持分类选择与离线轮换。\n\n调整\n• 阅读摘要扩展本周、本月统计，趋势图最多同时显示两项。\n• 优化排版、字体层级与设置操作，精简干扰视觉呈现的冗余功能。\n\n升级注意\n已安装用户请覆盖补丁并合并随包字体，保留原设置和阅读数据。\n仅 v1.0.0 用户需先删除旧补丁 2-book-receipt-shortcut-and-lockscreen.lua。\n\n---\n\nv1.1.0｜2026-10-13\n\n新增\n• InkFolio 截图及设置、截图手势入口。\n• 周／月阅读时长柱状图及已读字数统计。\n• 图书匹配确认、重新检索、来源查询、复现记录及脱敏诊断导出。\n\n调整\n• 完善豆瓣匹配、评分均分及获取规则，减少重复联网。\n• 整理设置层级与界面，修复菜单图标、返回、取消和缓存保留问题。\n• 新用户默认黑色背景、关闭进度弹窗，首次显示时自动适配比例；旧用户设置保留。\n\n升级注意\n已安装 v1.0.0 的用户：本次补丁文件更名为 2-inkfolio.lua。升级前请删除旧文件 2-book-receipt-shortcut-and-lockscreen.lua，再安装新补丁。已有设置和字体可继续使用。",
        justified=false,show_menu=false,add_default_buttons=true,
    })
end

local function showAbout()
    local text="InkFolio\n开发修订（基于 v1.2.0）｜2026-10-24\n\n为 KOReader 提供阅读信息卡，支持休眠显示与截图。\n\n• 顶部信息：今日、明日天气可分别勾选；日期独立开关，支持城市选择与天气缓存。\n• 图书信息：联网获取豆瓣评分，支持匹配确认、重新检索；展示豆瓣月榜，支持分类与离线轮换。\n• 阅读统计：展示阅读进度、时长、页数与字数，支持数据自定义组合及周／月趋势图。\n• 阅读目标：按日、周、月设置阅读时长或字数目标，查看完成进度。\n• UI皮肤：提供小票、像素、现代、封面四种风格，支持实时预览；封面皮肤完整显示书籍封面，中央为阅读信息卡，卡片宽度、封面底色与卡片底色独立设置，卡片支持自动黑白配色。\n\n兼容性\n• Kobo Sage：v1.2.0 已通过实机验证；当前开发修订待实机验证。\n• Kindle、PocketBook：需先安装并正常运行 KOReader；尚未经实机验证，休眠显示取决于设备支持。\n• Android 手机及安卓电纸书：使用 KOReader 官方 GitHub 安装包，可尝试信息卡预览与截图；不能替换系统锁屏，尚未经实机验证。\n• F-Droid 版 KOReader：不支持本项目所需的用户补丁，无法使用。\n\n开发与设计：zacharykim88\n开发辅助：OpenAI Codex\n推荐项目：墨享 · InkShare——分享 KOReader 截图。\n\n上游致谢\nEstela-Zelin84/KOReader_Book-Receipt\nu/hundredpercentcocoa\nomer-faruq/koreader-user-patches\n\n代码：GPL-3.0｜字体许可见随包说明"
    UIManager:show(require('ui/widget/textviewer'):new{
        title='关于 InkFolio',text=text,justified=false,show_menu=false,
        buttons_table={{
            {text='更新日志',callback=Inkfolio.showChangelog},
            {text='墨享 InkShare',callback=function()openProjectLink('https://github.com/zacharykim88/inkshare.koplugin')end},
            {text='上游项目',callback=function() openProjectLink('https://github.com/Estela-Zelin84/KOReader_Book-Receipt') end},
            {text='原始补丁',callback=function() openProjectLink('https://github.com/omer-faruq/koreader-user-patches') end},
            {text='许可证',callback=function() openProjectLink('https://github.com/Estela-Zelin84/KOReader_Book-Receipt/blob/main/LICENSE') end},
        }},add_default_buttons=true,
    })
end


function Inkfolio.refreshParentOnClose(child,parent)
    if not parent then return child end
    local close=child.onCloseWidget
    child.onCloseWidget=function(self,...)
        local result=close and close(self,...)
        if not parent.inkfolio_closed and parent.updateItems then parent:updateItems() end
        return result
    end
    return child
end
local function receiptSettingsMenu()
        local categories={}
        for _,category in ipairs(Inkfolio.MONTHLY_CATEGORIES)do
            local id=category.id
            categories[#categories+1]={text=category.label,radio=true,keep_menu_open=true,
                checked_func=function()return Inkfolio.monthlyCategory().id==id end,
                enabled_func=function()return not RUN.active and not RUN.worker end,
                callback=function()Inkfolio.selectMonthlyCategory(id)end}
        end
        local function toggle(label,key,action,default)
            local function checked()
                if default==false then return G_reader_settings:readSetting(key)==true end
                return enabled(key)
            end
            return {text=label,keep_menu_open=true,
                checked_func=checked,
                callback=function()
                    local nextval=not checked()
                    G_reader_settings:saveSetting(key,nextval)
                    if action then action(nextval) end
                end}
        end
        local function weatherOption(label,key,offset,default)
            local item=toggle(label,key,Inkfolio.weatherChanged,default)
            local callback=item.callback
            item.checked_func=function()return Inkfolio.weatherSelected(offset)end
            item.callback=function()
                if Inkfolio.uiStyle().id~='cover'then return callback()end
                local choice=Inkfolio.weatherSelected(offset)and 'off'or (offset==0 and 'today'or 'tomorrow')
                G_reader_settings:saveSetting(S.cover_weather,choice)
                Inkfolio.weatherChanged(choice~='off')
            end
            return item
        end
        local menu={
            text='InkFolio 设置',
            sub_item_table={
                {text='启用休眠显示',keep_menu_open=true,
                    help_text='使用 InkFolio作为休眠壁纸；关闭后保持屏幕原样。此功能仅在支持休眠壁纸的平台启用。',
                    enabled_func=function()return Device:supportsScreensaver()end,
                    checked_func=function()return G_reader_settings:readSetting('screensaver_type')=='book_receipt'end,
                    callback=function()
                        if not Device:supportsScreensaver() then return end
                        local selected=G_reader_settings:readSetting('screensaver_type')=='book_receipt'
                        G_reader_settings:saveSetting('screensaver_type',selected and 'disable' or 'book_receipt')
                    end},
                {text='显示内容',help_text='勾选与选择立即生效；返回菜单会保留修改。',sub_item_table={
                    {text='顶部信息',help_text='封面皮肤的今日、明日天气单选，与日期同行；其他皮肤可双选。封面首次沿用原选择，原来双选时默认今日；两种选择分别保留。天气缓存6小时到期，跨日或切城时重新检查，也可通过“更新信息”手动刷新。两项均关闭后不获取天气。',sub_item_table={
                        weatherOption('今日天气',S.weather,0),
                        weatherOption('明日天气',S.weather_tomorrow,1,false),
                        toggle('显示日期',S.date,function()if refreshQuicklook then refreshQuicklook() end end),
                        {text='天气城市',sub_item_table=weatherCityMenu()},
                    }},
                    {text='图书与榜单',cover_disabled=true,sub_item_table={toggle('封面',S.cover),toggle('评分',S.score),
                        toggle('豆瓣月榜',S.intro,function(on)
                            if on then
                                RUN.auto_holds.monthly=nil
                                local due=Inkfolio.monthlyDeadline()
                                if due and due<=os.time()then Inkfolio.resetNetworkPause();Inkfolio.monthlyCheck()end
                            end
                            startPoll()
                        end)}},
                    {text='阅读进度',sub_item_table=progressMenu()},
                    {text='阅读摘要',sub_item_table=summaryMenu()},
                    {text='底部文字',cover_disabled=true,callback=editFooter},
                    {text='月榜设置',cover_disabled=true,enabled_func=function()return enabled(S.intro)end,sub_item_table={
                        {text='榜单分类',sub_item_table=categories},
                        {text='锁屏时轮换',keep_menu_open=true,
                            help_text='关闭时显示所选分类的前3本；开启后，每次锁屏按缓存顺序换下一组，每组最多3本，末组后回到开头。离线可用，预览和截图不换组。评分为最近获取时的数值。',
                            checked_func=function()return G_reader_settings:readSetting(S.monthly_rotate)==true end,
                            callback=function()
                                local active=G_reader_settings:readSetting(S.monthly_rotate)~=true
                                G_reader_settings:saveSetting(S.monthly_rotate,active)
                                Inkfolio.monthly.cursor=1;Inkfolio.monthly.rotate_pending=nil
                                if active and (not Inkfolio.visibleMonthly() or not Inkfolio.visibleMonthly().complete) then Inkfolio.monthly.pending=true end
                                Inkfolio.saveMonthly()
                            end},
                        {text='刷新月榜',help_text='重新获取所选分类的完整月榜和评分。普通图书信息更新不会强制刷新月榜。',
                            enabled_func=function()return networkingEnabled() and connected() and not RUN.active and not RUN.worker end,
                            callback=Inkfolio.refreshMonthly},
                    }},
                }},
                {text='阅读目标',cover_disabled=true,sub_item_table=Inkfolio.goalMenu()},
                {text='外观调整',help_text='点击预览画面全屏显示，再次点击返回；调整在保存后生效，取消或返回放弃本次修改。封面卡片底色可选自动、白色或黑色；自动按卡片周边画面明暗选择配色。',callback=editAppearance},
                {text='联网设置',text_func=function()local n=Inkfolio.pendingCount();return n>0 and ('联网设置 · '..n..'本待确认') or '联网设置' end,sub_item_table={
                    toggle('允许联网',S.online,function(now)
                        if not now then MANUAL_CONNECT_PENDING=false;abortRound() else Inkfolio.resetNetworkPause();dailyCheck();startPoll() end
                    end),
                    {text='更新信息',enabled_func=function()
                        return networkingEnabled() and not RUN.active and not RUN.worker
                    end,callback=updateManually,help_text='阅读界面：重新获取当前书籍并更新一次天气。非阅读界面：扫描整个书库，补全未完整获取的书籍并更新一次天气。今日、明日天气均关闭后不请求天气。'},
                    {text='信息状态',callback=Inkfolio.showInformation},
                    {text_func=function()return '待确认图书（'..Inkfolio.pendingCount()..'）' end,callback=Inkfolio.showPendingMatches},
                    {text='重新匹配本书',callback=function()Inkfolio.editMatchQuery(currentBook())end,
                        enabled_func=function()return currentBook()~=nil and not RUN.active and not RUN.worker end},
                    {text='解除本书匹配',callback=Inkfolio.clearCurrentMatch,
                        enabled_func=function()local b=currentBook();return b and Inkfolio.matchState.choices[Inkfolio.fileMatchKey(b)]~=nil and not RUN.active and not RUN.worker end},

                    {text='书库目录',callback=chooseLibraryRoot,
                        help_text='选择存放图书的文件夹。更改后重新建立记录，已有图书可通过“更新信息”获取。'},
                }},
                {text='保存截图',callback=Inkfolio.saveScreenshot},
                {text='开发者选项',sub_item_table={
                    {text='诊断信息',callback=Inkfolio.showDiagnostics},
                    toggle('详细日志',S.debug_log,nil,false),
                    toggle('复现记录',S.repro,function(now)if now then Inkfolio.recordAction('复现记录') end end,false),
                    toggle('进度弹窗',S.progress,function(now)
                        if not now then progressIgnore()
                        elseif PROGRESS.active then
                            PROGRESS.hidden=false;progressPaint(true);UIManager:scheduleIn(5,progressTick)
                        end
                    end),
                }},
                {text='关于',callback=showAbout},
            },
        }
        local function restrict(rows,parent_disabled)
            for _,item in ipairs(rows)do
                local restricted=parent_disabled or item.cover_disabled
                if restricted then
                    local available=item.enabled_func
                    item.enabled_func=function()
                        return Inkfolio.uiStyle().id~='cover'and (not available or available())
                    end
                    item.help_text=(item.help_text and (item.help_text..'\n')or '')..'封面皮肤不显示此项；切换皮肤后可继续使用，原设置保留。'
                    if item.callback then
                        local callback=item.callback
                        item.callback=function(...)if item.enabled_func()then return callback(...)end end
                    end
                end
                if item.sub_item_table then restrict(item.sub_item_table,restricted)end
            end
        end
        restrict(menu.sub_item_table)
        return menu
end

-- Settings and the sleep toggle live exclusively in Tools / Inkfolio.
-- No sleep-menu injection: other native sleep modes are left untouched.
local receiptMenuWidget={name='read_receipt_settings'}
function receiptMenuWidget:addToMainMenu(items)
    items.read_receipt={text='InkFolio',callback=Inkfolio.settings}
    items.read_receipt.text_func=function()local n=Inkfolio.pendingCount();return n>0 and ('InkFolio · '..n..'本待确认') or 'InkFolio' end
end
for _,module_name in ipairs({'apps/reader/modules/readermenu','apps/filemanager/filemanagermenu'}) do
    local Menu=require(module_name)
    local init=Menu.init
    assert(type(init)=='function' and type(Menu.registerToMainMenu)=='function',
        'READ RECEIPT: unsupported KOReader main-menu API')
    Menu.init=function(self,...)
        init(self,...)
        self:registerToMainMenu(receiptMenuWidget)
    end
end

-- Move the single settings entry after native and user menu order have merged.
local MenuSorter=require('ui/menusorter')
local nativeSort=MenuSorter.sort
MenuSorter.sort=function(self,items,order)
    if items.read_receipt then
        assert(type(order.tools)=='table','InkFolio: KOReader 工具菜单不可用')
        for _,list in pairs(order) do
            if type(list)=='table' then
                for i=#list,1,-1 do if list[i]=='read_receipt' then table.remove(list,i) end end
            end
        end
        table.insert(order.tools,1,'read_receipt')
    end
    return nativeSort(self,items,order)
end
function Inkfolio.settings()
    Inkfolio.recordAction('InkFolio 设置')
    local menu=receiptSettingsMenu()
    local function retain(rows)
        for _,item in ipairs(rows)do
            if item.sub_item_table then retain(item.sub_item_table) end
            if item.callback then
                item.keep_menu_open=true
                local callback=item.callback;local stage=item.text or '设置选项'
                item.callback=function(...)return Inkfolio.guard(stage,callback,...)end
            end
            if item.checked_func then item.mandatory_func=function()return item.checked_func() and '☑' or '☐' end end
            if item.enabled_func then item.select_enabled_func=item.enabled_func end
        end
    end
    retain(menu.sub_item_table)
    local container=CenterContainer:new{dimen=Screen:getSize(),ignore='height',covers_header=true}
    if Device:isTouchDevice() or Device:hasDPad() then
        menu.sub_item_table.icon='appbar.tools';menu.sub_item_table.text='InkFolio'
        container[1]=require('ui/widget/touchmenu'):new{width=Screen:getWidth(),
            tab_item_table={menu.sub_item_table},show_parent=container}
    else
        local Menu=require('ui/widget/menu')
        container[1]=Menu:new{title='InkFolio',width=Screen:getWidth(),
            item_table=menu.sub_item_table,show_parent=container,
            onMenuSelect=function(self,item)
                if item.enabled==false or item.enabled_func and not item.enabled_func() then return true end
                if item.sub_item_table then
                    Inkfolio.recordAction(item.text)
                    self.item_table.title=self.title;table.insert(self.item_table_stack,self.item_table)
                    self:switchItemTable(item.text,item.sub_item_table)
                elseif item.callback then item.callback(self);self:updateItems() end
                return true
            end}
    end
    local widget=container[1]
    -- Outside taps dismiss this menu at any depth; the back button still goes up.
    widget.onTapCloseAllMenus=function(self,arg,gesture)
        if gesture.pos:notIntersectWith(self.dimen) then
            Inkfolio.recordAction('菜单外点击关闭')
            UIManager:close(container)
            return true
        end
    end
    if widget.backToUpperMenu then
        local select=widget.onMenuSelect
        widget.onMenuSelect=function(self,item,...)
            if item and item.sub_item_table then Inkfolio.recordAction(item.text) end
            return select(self,item,...)
        end
    end
    if widget.backToUpperMenu then
        local upper=widget.backToUpperMenu
        widget.backToUpperMenu=function(self,...)
            Inkfolio.recordAction(#self.item_table_stack>0 and '菜单返回' or '菜单关闭')
            return upper(self,...)
        end
        local close=widget.closeMenu
        widget.closeMenu=function(self)
            if #self.item_table_stack>0 then self:backToUpperMenu(true)
            else Inkfolio.recordAction('菜单关闭');close(self) end
        end
    end
    if not widget.backToUpperMenu then
        local parentClose=widget.onClose
        widget.onClose=function(self,...)
            Inkfolio.recordAction(#self.item_table_stack>0 and '菜单返回' or '菜单关闭')
            return parentClose(self,...)
        end
        local closeAll=widget.onCloseAllMenus
        widget.onCloseAllMenus=function(self)
            if #self.item_table_stack>0 then return self:onClose() end
            return closeAll(self)
        end
    end
    local onCloseWidget=widget.onCloseWidget
    widget.onCloseWidget=function(self,...)Inkfolio.recordAction('设置关闭');self.inkfolio_closed=true;if onCloseWidget then return onCloseWidget(self,...) end end
    UIManager:show(container)
    return true
end
for _,target in ipairs({ReaderUI,require('apps/filemanager/filemanager')}) do
    target.onQuickLook=function()return Inkfolio.preview()end
    target.onInkfolioSettings=function()return Inkfolio.settings()end
    target.onInkfolioScreenshot=function()return Inkfolio.saveScreenshot()end
end
Dispatcher:registerAction('quicklookbox_action',{
    category='none',event='QuickLook',title='InkFolio 预览',general=true})
Dispatcher:registerAction('inkfolio_settings',{
    category='none',event='InkfolioSettings',title='InkFolio 设置',general=true})
Dispatcher:registerAction('inkfolio_screenshot',{
    category='none',event='InkfolioScreenshot',title='保存InkFolio 截图',general=true})

-- Guard only Inkfolio entry points and editor methods. Do not hook UIManager,
-- KOReader's global exception handler, or another plugin's callbacks.
for _,entry in ipairs({{'preview','小票渲染'},{'settings','InkFolio 设置'},{'saveScreenshot','保存截图'}})do
    local name,stage=entry[1],entry[2];local original=Inkfolio[name]
    Inkfolio[name]=function(...)return Inkfolio.guard(stage,original,...)end
end
for _,entry in ipairs({{'init','外观调整'},{'refreshPreview','外观调整'},{'save','外观保存'},{'onCancel','菜单返回'}})do
    local name,stage=entry[1],entry[2];local original=AppearanceEditor[name]
    AppearanceEditor[name]=function(...)return Inkfolio.guard(stage,original,...)end
end
