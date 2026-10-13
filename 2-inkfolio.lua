-- 墨笺 · Inkfolio v1.1.0 / KOReader user patch
-- SPDX-License-Identifier: GPL-3.0-only
-- Based on Estela-Zelin84/KOReader_Book-Receipt (GNU GPL v3).
-- Upstream credits u/hundredpercentcocoa and omer-faruq/koreader-user-patches.
-- Modifications and design: zacharykim88, 2026-10-10. Developed with OpenAI Codex.
-- One receipt theme; asynchronous book-library metadata collection, permanent cache.
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
local RenderText = require('ui/rendertext')
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
local QRWidget = require('ui/widget/qrwidget')
local SQ3 = require('lua-ljsqlite3/init')
local socket_url = require('socket.url')
local lfs = require('libs/libkoreader-lfs')
local ffiUtil = require('ffi/util')
local logger = require('logger')
local util = require('util')
local _ = require('gettext')
local Screen = Device.screen
local Inkfolio = {}
local VERSION = '1.1.0'
local RELEASE_DATE = '2026-10-13'
local BUILD_ID='defaults-diagnostics-20261013'

-- Cinzel Decorative has chisel-shaped Latin capitals inspired by Roman inscriptions.
-- Fonts are separate dependencies, installed in the KOReader data directory's fonts/.
-- Missing font is reported explicitly instead of silently substituting a different one.
local TITLE_FONT = 'CinzelDecorative-Bold.ttf'
local CHINESE_TITLE_FONT = 'Xiangcui-Dazijiti-main/香萃打字机体 W40.ttf'

local P = 'read_receipt_v2_'
local S = {
    online = P .. 'online', width = P .. 'width', font = P .. 'font',
    cover = P .. 'cover', chapter = P .. 'chapter', stats = P .. 'stats',
    intro = P .. 'intro', qr = P .. 'qr', score = P .. 'score',
    remain = P .. 'remain', background = P .. 'background',
    footer = P .. 'footer', weather_city = P .. 'weather_city',
    global_today = P .. 'global_today', global_total = P .. 'global_total',
    summary = P .. 'summary', progress = P .. 'progress', scale = P .. 'scale',
    library_root = P .. 'library_root', curve = P .. 'curve',
    word_book=P..'word_book',word_session=P..'word_session',debug_log=P..'debug_log',
    auto_fit=P..'auto_fit_pending',repro=P..'repro_record',
}
local previous_install=lfs.attributes(DataStorage:getSettingsDir()..'/read_receipt_v2_db.lua','mode')=='file'
for _,key in pairs(S) do if G_reader_settings:readSetting(key)~=nil then previous_install=true;break end end
local store = LuaSettings:open(DataStorage:getSettingsDir() .. '/read_receipt_v2_db.lua')
local CACHE = store:readSetting('books') or {}
local DAY = store:readSetting('day') or ''
local ROUNDS = tonumber(store:readSetting('auto_rounds')) or 0
local DAILY_DONE = store:readSetting('daily_done') == true
local WEATHER=store:readSetting('weather') or {records={}}
WEATHER.records=WEATHER.records or {}
local LIBRARY = store:readSetting('library_files') or {pending={}}
local nextLibraryScan = 0
local dailyCheck, weatherCheck, selectedWeatherCity
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
local MAX_AUTO = 3
local RUN = { active = false, sleeping = false, token = 0, manual = false,
              queue = {}, index = 1, started = false, processed = 0,
              worker = nil, transport_broken = false, network_failures = 0, last_error = nil,
              failed = 0, last_book_error = nil }
-- Cancellation lasts only until the next resume; discard the old daily hold.
RUN.cancelled_wake = false
store:delSetting('cancelled_day')
local refreshQuicklook = nil
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
        RUN.transport_broken = false
        RUN.network_failures = 0
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
assert(type(SEARCH_TITLES)=='table','Inkfolio: 搜索书名设置损坏')
for key,value in pairs(SEARCH_TITLES) do
    assert(type(key)=='string' and type(value)=='string' and util.trim(value)~='' and not value:find('[\r\n]'),
        'Inkfolio: 搜索书名设置条目损坏')
end
function Inkfolio.searchOverride(book) return SEARCH_TITLES[Inkfolio.metadataKey(book)] end
-- Persisted choices belong to the file, not every file sharing its title.
Inkfolio.matchState=store:readSetting('book_matching') or {choices={},pending={}}
Inkfolio.matchState.holds=Inkfolio.matchState.holds or {}
assert(type(Inkfolio.matchState.holds)=='table','Inkfolio: 暂停记录损坏')
assert(type(Inkfolio.matchState)=='table' and type(Inkfolio.matchState.choices)=='table'
    and type(Inkfolio.matchState.pending)=='table','Inkfolio: 图书匹配设置损坏')
for key,choice in pairs(Inkfolio.matchState.choices)do
    assert(type(key)=='string' and type(choice)=='table' and validURL(choice.url)
        and type(choice.title)=='string' and type(choice.authors)=='string','Inkfolio: 图书确认记录损坏')
end
for key,pending in pairs(Inkfolio.matchState.pending)do
    assert(type(key)=='string' and type(pending)=='table' and type(pending.book)=='table'
        and type(pending.candidates)=='table','Inkfolio: 待确认记录损坏')
    assert(type(pending.book.title)=='string' and type(pending.book.authors)=='string','Inkfolio: 待确认图书身份损坏')
    for _,c in ipairs(pending.candidates)do
        assert(type(c)=='table' and validURL(c.url) and type(c.rating)=='number' and c.rating>0 and c.rating<=10
            and type(c.title)=='string' and type(c.authors)=='string','Inkfolio: 待确认候选损坏')
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
        logger.warn('Inkfolio search title save failed',reason)
        return false,'搜索书名保存失败，请检查设置目录是否可写。'
    end
    SEARCH_TITLES=next_titles
    return true
end
for key,value in pairs(Inkfolio.matchState.holds)do
    assert(type(key)=='string' and type(value)=='string','Inkfolio: 暂停记录损坏')
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

local STATUS=store:readSetting('information_status') or {version=1,books={},weather={},history={}}
assert(type(STATUS)=='table' and STATUS.version==1 and type(STATUS.books)=='table'
    and type(STATUS.weather)=='table' and type(STATUS.history)=='table','Inkfolio: 信息状态记录损坏')
STATUS.write_error=nil;STATUS.log_error=nil
local RESULTS={pending='待用户确认',success='成功',partial='部分成功',failed='失败',cancelled='已取消',interrupted='已中断',cached='缓存复用'}
local function validEntry(entry,final)
    assert(type(entry)=='table' and (RESULTS[entry.result] or not final and entry.result=='running'),'Inkfolio: 信息状态条目损坏')
    assert(entry.reason==nil or type(entry.reason)=='string','Inkfolio: 信息状态原因损坏')
    for _,field in ipairs({'attempt_at','finished_at'}) do
        local value=entry[field]
        assert(value==nil or type(value)=='number' and value>=0 and value<math.huge,'Inkfolio: 信息状态时间损坏')
    end
end
for _,records in ipairs({STATUS.books,STATUS.weather}) do
    for key,entry in pairs(records) do assert(type(key)=='string','Inkfolio: 信息状态标识损坏');validEntry(entry,false) end
end
assert(#STATUS.history<=20,'Inkfolio: 信息状态历史超过限制')
for _,entry in ipairs(STATUS.history) do
    validEntry(entry,true)
    assert(entry.kind=='books' or entry.kind=='weather' or entry.kind=='batch','Inkfolio: 信息状态历史类型损坏')
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
    if reason:find('天气数据',1,true) then return '天气数据校验失败' end
    return '其他错误（原文仅本机可见）'
end
local function saveStatus()
    STATUS.write_error=nil
    local ok,reason=pcall(function()store:saveSetting('information_status',STATUS);store:flush()end)
    if not ok then STATUS.write_error='信息状态保存失败';logger.warn('Inkfolio status save failed',reason)
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
    if not ok then STATUS.log_error='详细日志写入失败';logger.warn('Inkfolio diagnostic log failed',err)
    else STATUS.log_error=nil end
end
function Inkfolio.infoAttempt(kind,key)
    local entry={attempt_at=os.time(),result='running'}
    STATUS[kind][key]=entry
    RUN.info_task={kind=kind,key=key}
    saveStatus();Inkfolio.debugEvent(kind=='books' and '图书任务' or '天气任务','开始')
end
function Inkfolio.infoResult(kind,key,result,reason)
    local entry=STATUS[kind][key] or {}
    entry.finished_at=os.time();entry.result=result;entry.reason=reason
    STATUS[kind][key]=entry
    STATUS.history[#STATUS.history+1]={kind=kind,result=result,attempt_at=entry.attempt_at,
        finished_at=entry.finished_at,reason=reason,category=errorCategory(reason)}
    while #STATUS.history>20 do table.remove(STATUS.history,1) end
    if RUN.info_task and RUN.info_task.kind==kind and RUN.info_task.key==key then RUN.info_task=nil end
    saveStatus();Inkfolio.debugEvent(kind=='books' and '图书任务' or '天气任务',RESULTS[result] or result,reason)
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
    and type(Inkfolio.diagnostics.errors)=='table','Inkfolio: 诊断记录损坏')
local REPRO_STAGES={}
for _,name in ipairs({'设置选项','墨笺设置','显示内容','图书信息','阅读进度','阅读摘要','外观调整',
 '联网设置','天气城市','书库目录','底部文字','保存截图','开发者选项','关于','诊断信息',
 '详细日志','进度弹窗','复现记录','允许联网','更新信息','信息状态','重新匹配本书','解除本书匹配',
 '启用休眠显示','封面','评分','简介','二维码','预计剩余','本书已读','唤醒已读','显示摘要',
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
    if path:find('2-inkfolio.lua',1,true) or path:find('-- 墨笺 · Inkfolio',1,true) then file='2-inkfolio.lua'
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
        '休眠显示选择：'..(G_reader_settings:readSetting('screensaver_type')=='book_receipt' and '墨笺' or '其他'),
        '外观宽度：'..tostring(G_reader_settings:readSetting(S.width) or .72),
        '字号倍率：'..tostring(G_reader_settings:readSetting(S.font) or 1),
        '整体比例：'..tostring(G_reader_settings:readSetting(S.scale) or 1),
        '背景：'..tostring(G_reader_settings:readSetting(S.background) or 'white'),
        '首次比例适配：'..(G_reader_settings:readSetting(S.auto_fit)==true and '等待图书数据' or '未待处理'),
        '进度弹窗：'..(enabled(S.progress) and '开启' or '关闭'),
        '复现记录：'..(G_reader_settings:readSetting(S.repro)==true and '开启' or '关闭'),
        '诊断保存：'..(Inkfolio.diagnostics.save_error or '未发现错误')}
    for _,item in ipairs({{'封面',S.cover},{'评分',S.score},{'简介',S.intro},{'二维码',S.qr},{'阅读摘要',S.stats}})do
        lines[#lines+1]=item[1]..'：'..(enabled(item[2]) and '开启' or '关闭')
    end
    for _,item in ipairs({{'本书已读',S.word_book},{'唤醒已读',S.word_session},{'预计剩余',S.remain}})do
        lines[#lines+1]=item[1]..'：'..(Inkfolio.progressEnabled(item[2]) and '开启' or '关闭')
    end
    if Inkfolio.lastLayout then
        local d=Inkfolio.lastLayout
        lines[#lines+1]=string.format('最近小票尺寸：%d×%d；屏幕：%d×%d；%s',d.width,d.height,d.screen_w,d.screen_h,d.valid and '完整适屏' or '超出屏幕')
    else lines[#lines+1]='最近小票尺寸：未渲染' end
    local selected=G_reader_settings:readSetting(S.summary) or {}
    local labels={book_today='本书今日',book_total='本书累计',global_today='全局今日',global_total='全局累计'}
    local summaries={};for _,id in ipairs(selected)do if labels[id] then summaries[#summaries+1]=labels[id] end end
    lines[#lines+1]='摘要组合：'..table.concat(summaries,'、')
    local chart=G_reader_settings:readSetting(S.curve)
    lines[#lines+1]='时长图：'..(chart=='week' and '本周' or chart=='month' and '本月' or '关闭')
    for _,file in ipairs({TITLE_FONT,CHINESE_TITLE_FONT})do
        local ok,face=pcall(Font.getFace,Font,file,20)
        lines[#lines+1]='标题字体 '..file..'：'..(ok and face and '可加载' or '无法加载')
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
    lines[#lines+1]='墨笺异常（最多10条）：'
    for _,e in ipairs(Inkfolio.diagnostics.errors)do
        local codes={LUA_INDEX_ERROR=true,LUA_CALL_ERROR=true,LUA_ARGUMENT_ERROR=true,LUA_ASSERTION_ERROR=true,LUA_ERROR=true}
        lines[#lines+1]=infoTime(e.at)..' | '..(REPRO_STAGES[e.stage] and e.stage or '设置选项')..' | '..(codes[e.code] and e.code or 'LUA_ERROR')
        for _,f in ipairs(e.frames or {})do
            local safe=Inkfolio.safeFrame(f.file,f.line,f.fn)
            lines[#lines+1]=safe.file..':'..safe.line..' '..safe.fn
        end
    end
    if #Inkfolio.diagnostics.errors==0 then lines[#lines+1]='没有墨笺异常记录；启动或原生崩溃可能需要脱敏crash.log。' end
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
    local lines={
        '墨笺诊断报告（默认脱敏）','墨笺版本：v'..VERSION,
        '构建标识：'..BUILD_ID,
        'KOReader版本：'..(ok and tostring(revision) or '读取失败'),
        '设备：'..tostring(Device.model or '未提供'),'分辨率：'..Screen:getWidth()..'×'..Screen:getHeight(),
        '允许联网：'..(networkingEnabled() and '是' or '否'),
        '网络连接：'..(connected() and '已连接' or '未连接'),
        '网络任务：'..(RUN.sleeping and '休眠中' or RUN.worker and '请求执行中' or RUN.active and '任务进行中' or '空闲'),
        '任务类型：'..(RUN.info_task and (RUN.info_task.kind=='books' and '图书' or '天气') or '无'),
        '当前请求阶段：'..(RUN.worker and RUN.request_stage or '无'),
        '图书任务进度：'..(RUN.active and ((RUN.total or 0)>0 and tostring(RUN.done or 0)..' / '..RUN.total or '扫描中，尚未确定总数') or '无进行中的图书任务'),
        '图书缓存条目：'..countRecords(CACHE),
        '待确认图书：'..Inkfolio.pendingCount(),
        '用户确认匹配关系：'..countRecords(Inkfolio.matchState.choices),
        '含有效评分的缓存：'..countRecords(CACHE,function(r)return type(r)=='table' and tonumber(r.rating) and tonumber(r.rating)>0 and tonumber(r.rating)<=10 and validURL(r.url)end),
        '含缓存简介的条目：'..countRecords(CACHE,function(r)return type(r)=='table' and type(r.intro)=='string' and r.intro~=''end),
        '天气缓存条目：'..countRecords(WEATHER.records),
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
    if private and Inkfolio.lastPrivateError then lines[#lines+1]='本次墨笺异常原文（仅本机）：'..Inkfolio.lastPrivateError end
    lines[#lines+1]='复制内容可能仅进入设备内部剪贴板；向手机反馈请导出报告。'
    if private then lines[1]='墨笺诊断信息（错误原文仅本机显示，复制／导出均脱敏）' end
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
        viewer=require('ui/widget/textviewer'):new{title='墨笺诊断信息',text=Inkfolio.diagnosticText(true),
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
    local city=selectedWeatherCity()
    lines[#lines+1]='\n天气来源：中国气象局中央气象台（nmc.cn）'
    if city then
        local record=WEATHER.records[city.code];local status=STATUS.weather[city.code]
        lines[#lines+1]='城市：'..city.name
        lines[#lines+1]='最近成功：'..infoTime(record and record.updated_at)
        lines[#lines+1]='最近尝试：'..infoTime(status and status.attempt_at)
        local active=RUN.info_task and RUN.info_task.kind=='weather' and RUN.info_task.key==city.code
        lines[#lines+1]='最近结果：'..(status and (status.result=='running' and (active and '获取中' or '上次任务未完成') or RESULTS[status.result]) or '未记录')
        lines[#lines+1]='缓存预报日期：'..tostring(record and record.day or '未记录')
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
    {id='book_today',label='本书今日',today=true},
    {id='global_today',label='全局今日',today=true,global=true},
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
    for key,value in pairs({[S.width]=d.width,[S.scale]=d.scale,[S.summary]={'book_today','global_total'},
        [S.word_book]=false,[S.word_session]=false,[S.remain]=true,[S.weather_city]='lqYjK',
        [S.progress]=false,[S.background]='black',[S.auto_fit]=true,[S.repro]=false}) do
        G_reader_settings:saveSetting(key,value)
    end
end
Inkfolio.initializeDefaults(previous_install)
local PROGRESS_ITEMS={
    {key=S.word_book,label='本书已读'},
    {key=S.word_session,label='唤醒已读'},
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
    -- Today precedes total; within the same period, book precedes global.
    for _,item in ipairs(SUMMARY_ITEMS) do
        for _,id in ipairs(chosen) do
            if id==item.id then result[#result+1]=item;break end
        end
    end
    assert(#result==#chosen and #chosen<=2,'Invalid reading-summary selection')
    return result
end

-- Count each book/page pair once; different books may share the same page number.
local function readStatistics(ui)
    local stats = ui.statistics
    if not stats or (stats.isEnabled and not stats:isEnabled()) then return nil end
    if stats.insertDB and not pcall(stats.insertDB, stats) then return nil end
    local id = tonumber(stats.id_curr_book)
    if not id and stats.getIdBookDB then
        local ok, v = pcall(stats.getIdBookDB, stats)
        if ok then id = tonumber(v) end
    end
    local items=summaryItems()
    if #items==0 then return {} end
    for _,item in ipairs(items) do if not item.global and not id then return nil end end
    if lfs.attributes(STATS_PATH, 'mode') ~= 'file' then return nil end
    local ok, db = pcall(SQ3.open, STATS_PATH)
    if not ok or not db then return nil end
    local clock = os.date('*t')
    clock.hour, clock.min, clock.sec, clock.isdst = 0, 0, 0, nil
    local start = os.time(clock)
    local function query(global, today)
        local filters = {}
        if not global then filters[#filters+1] = string.format('id_book=%d', id) end
        if today then filters[#filters+1] = string.format('start_time>=%d', start) end
        local where = #filters > 0 and (' WHERE '..table.concat(filters, ' AND ')) or ''
        return db:rowexec('SELECT count(*), sum(seconds) FROM ('..
            'SELECT sum(duration) AS seconds FROM page_stat'..where..
            ' GROUP BY id_book, page);')
    end
    local result={}
    local success,reason=pcall(function()
        for _,item in ipairs(items) do
            local pages,seconds=query(item.global,item.today)
            result[item.id]={pages=tonumber(pages) or 0,time=tonumber(seconds) or 0}
        end
    end)
    db:close()
    if not success then logger.warn('READ RECEIPT: cannot read statistics',reason);return nil end
    return result
end
-- Read native recorded durations, not page counts or estimated time.
function Inkfolio.readCurve(ui, period, now)
    if period~='week' and period~='month' then return nil,'时长图周期无效' end
    local stats=ui and ui.statistics
    if not stats or (stats.isEnabled and not stats:isEnabled()) then
        return nil,'请开启 KOReader 阅读统计'
    end
    if stats.insertDB then
        local ok=pcall(stats.insertDB,stats)
        if not ok then return nil,'阅读统计保存失败' end
    end
    if lfs.attributes(STATS_PATH,'mode')~='file' then return nil,'暂无阅读统计数据库' end
    now=now or os.time()
    local clock=os.date('*t',now)
    local first={year=clock.year,month=clock.month,
        day=period=='week' and (clock.day-(clock.wday+5)%7) or 1,
        hour=0,min=0,sec=0,isdst=nil}
    local first_time=os.time(first)
    local last=period=='week' and {year=first.year,month=first.month,day=first.day+7,hour=0}
        or {year=clock.year,month=clock.month+1,day=1,hour=0}
    local end_time=os.time(last)
    local days={}
    local date=os.date('*t',first_time)
    while true do
        local start=os.time{year=date.year,month=date.month,day=date.day,hour=0,min=0,sec=0,isdst=nil}
        if start>=end_time then break end
        local finish=os.time{year=date.year,month=date.month,day=date.day+1,hour=0,min=0,sec=0,isdst=nil}
        days[#days+1]={start=start,finish=finish,day=date.day,
            seconds=start<=now and 0 or nil}
        date=os.date('*t',finish)
    end
    local opened,db=pcall(SQ3.open,STATS_PATH)
    if not opened or not db then return nil,'阅读统计无法打开' end
    local ok,err=pcall(function()
        local rows=db:exec(string.format(
            'SELECT start_time,duration FROM page_stat_data WHERE duration>0 AND start_time<%d AND start_time+duration>%d;',
            math.min(end_time,now+1),first_time))
        if not rows then return end -- A successful empty query represents zero recorded time.
        for i,start in ipairs(rows[1]) do
            local stamp=assert(tonumber(start),'invalid statistics timestamp')
            local seconds=assert(tonumber(rows[2][i]),'invalid statistics duration')
            local finish=math.min(stamp+seconds,now+1)
            for _,day in ipairs(days) do
                if day.seconds~=nil then
                    day.seconds=day.seconds+math.max(0,math.min(finish,day.finish)-math.max(stamp,day.start))
                end
            end
        end
    end)
    db:close()
    if not ok then logger.warn('Inkfolio curve query failed',err);return nil,'阅读时长读取失败' end
    local total,elapsed=0,0
    for _,day in ipairs(days) do
        if day.seconds~=nil then total=total+day.seconds;elapsed=elapsed+1 end
    end
    return {period=period,days=days,total=total,average=total/elapsed,elapsed=elapsed}
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
    return string.rep('★', full) .. (half%2 == 1 and '½' or '') .. string.rep('☆', 5-full-(half%2))
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

local function stopHTTP()
    local worker = RUN.worker
    if not worker then return end
    RUN.worker = nil
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
        ROUNDS = math.min(MAX_AUTO, ROUNDS + 1)
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
    RUN.request_stage=kind=='weather' and '天气请求' or url:find('www.bing.com/',1,true) and 'Bing检索'
        or url:find('www.douban.com/search',1,true) and '豆瓣检索' or '豆瓣详情'
    Inkfolio.debugEvent(RUN.request_stage,'开始')
    if RUN.transport_broken and kind~='weather' then return false end
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

    if kind~='weather' then markAttempt() end
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
            if kind~='weather' then RUN.last_error=reason end
            logger.warn('READ RECEIPT:',reason)
            stopHTTP()
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
            if kind~='weather' then
                RUN.last_error=reason
                RUN.network_failures = RUN.network_failures + 1
                if RUN.network_failures >= 3 then
                    RUN.transport_broken = true
                    logger.warn('READ RECEIPT: stopped batch after three consecutive network errors')
                end
            end
            Inkfolio.debugEvent(RUN.request_stage,'失败',reason)
            cb('',reason)
        else
            if kind~='weather' then RUN.network_failures = 0 end
            Inkfolio.debugEvent(RUN.request_stage,'成功，响应字节 '..#body)
            cb(body)
        end
    end
    UIManager:scheduleIn(0.25, checkResult)
    return true
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
            logger.warn('Inkfolio:',RUN.last_error)
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
                    logger.warn('Inkfolio:',RUN.last_error)
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
        logger.warn('Inkfolio:',RUN.last_error)
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
    stopHTTP()
    if user_cancel then
        RUN.cancelled_wake=true
        DAILY_DONE=false
        WEATHER.pending=false
        WEATHER.error='天气获取已取消'
        store:saveSetting('weather',WEATHER)
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
    if RUN.weather_result then text=text..'\n'..RUN.weather_result end
    local reason=RUN.last_error or RUN.last_book_error
    if reason then text=text..'\n最近失败原因：'..tostring(reason):sub(1,140) end
    local manual=RUN.review_after_round
    RUN.review_after_round=nil
    progressEnd(text)
    if manual and Inkfolio.pendingCount()>0 then UIManager:scheduleIn(0.1,Inkfolio.showPendingMatches) end
    if startPoll then startPoll() end
end
local function nextItem()
    if not RUN.active then return end
    if RUN.transport_broken then finishRound(); return end
    if RUN.sleeping or not networkingEnabled() or not connected() then
        abortRound(); return
    end
    if weatherCheck and weatherCheck(true) then return end
    while not RUN.current_only and RUN.index <= #RUN.queue and not Inkfolio.needsFetch(RUN.queue[RUN.index]) do
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
        RUN.done=RUN.done+1;PROGRESS.done=RUN.done
        UIManager:scheduleIn(0.8, nextItem)
    end)
end
local function beginRound(manual, priority, new_paths, current_only)
    resetDay()
    if RUN.active or RUN.worker or RUN.sleeping or not networkingEnabled() or not connected() then return false end
    if current_only and (not manual or not priority or priority.title == '') then return false end
    if not current_only and not new_paths and not rootPath() then
        if manual or not RUN.directory_error_shown then
            UIManager:show(require('ui/widget/infomessage'):new{
                text='书库目录不可用，请在“墨笺 → 信息获取 → 书库目录”选择可读取的文件夹。没有发起联网请求。'})
            RUN.directory_error_shown=true
        end
        return false
    end
    RUN.directory_error_shown=false
    if not manual and (RUN.cancelled_wake or RUN.transport_broken or
       (not new_paths and ROUNDS >= MAX_AUTO)) then return false end
    if manual then RUN.transport_broken = false; RUN.network_failures = 0 end
    RUN.active = true
    -- A manual request does not release the automatic hold for this wake.
    store:flush()
    WEATHER.pending=selectedWeatherCity()~=nil
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
        local filepaths = current_only and {} or new_paths or collectPaths()
        if not filepaths then
            finishRound()
            if manual then
                local InfoMessage = require('ui/widget/infomessage')
                UIManager:show(InfoMessage:new{ text = '书库目录不可用，请在“墨笺 → 信息获取 → 书库目录”选择可读取的文件夹。没有发起联网请求。' })
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
            if book and book.title ~= '' and (current_only or Inkfolio.needsFetch(book)) then
                local key = bookKey(book)
                if not seen[key] then
                    seen[key] = true
                    RUN.queue[#RUN.queue+1] = book
                end
            end
        end
        -- Prioritize currently opened book without opening the same document twice.
        if not new_paths then add(priority or currentBook()) end
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
    if not code then return nil end
    for _,region in ipairs(WEATHER_REGIONS) do
        for _,city in ipairs(region.cities) do
            if city.code~='' and city.code==code then return city end
        end
    end
end
local function weatherPending()
    return selectedWeatherCity()~=nil and WEATHER.pending==true
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
local function weatherText()
    local city=selectedWeatherCity()
    if not city then return '未选择城市' end
    local name=cityLabel(city)
    if RUN.worker and RUN.worker.kind=='weather' and RUN.worker.city==city.code then return name..'　获取中…' end
    if WEATHER.error and WEATHER.attempt_city==city.code and WEATHER.attempt_day==localDate() then return name..'　'..WEATHER.error end
    local record=WEATHER.records[city.code]
    if record and record.day==localDate() and record.text then return name..'　'..record.text end
    if WEATHER.attempt_city==city.code and WEATHER.attempt_day==localDate() then return name..'　'..(WEATHER.error or '天气获取失败') end
    return name..'　待联网更新'
end
weatherCheck=function(allow_active)
    if RUN.sleeping or not networkingEnabled() or (RUN.active and not allow_active) or RUN.worker or not weatherPending() then return false end
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
        local text,parse_error
        if not error_text then text,parse_error=parseWeather(body,city.code,day) end
        if text then
            WEATHER.records[city.code]={day=day,text=text,updated_at=os.time()}
            WEATHER.error=nil
        else
            WEATHER.error='天气获取失败'
            logger.warn('READ RECEIPT weather:',error_text or parse_error)
        end
        Inkfolio.infoResult('weather',city.code,text and 'success' or 'failed',error_text or parse_error)
        RUN.weather_result=cityLabel(city)..'：'..(text or '天气获取失败')
        store:saveSetting('weather',WEATHER);store:flush()
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
        RUN.worker.city=city.code
        store:saveSetting('weather',WEATHER);store:flush()
    else
        WEATHER.pending=false
        WEATHER.error='天气请求未启动'
        Inkfolio.infoResult('weather',city.code,'failed',RUN.last_error or WEATHER.error)
        store:saveSetting('weather',WEATHER);store:flush()
        if standalone then progressEnd(WEATHER.error) end
    end
    return started
end

local function newBooksCheck(force)
    if RUN.sleeping or RUN.active or RUN.worker or not networkingEnabled() or
       RUN.cancelled_wake or RUN.transport_broken then return false end
    if not force and LIBRARY.known and not connected() then return false end
    if not force and os.time()<nextLibraryScan then return false end
    nextLibraryScan=os.time()+180
    local paths=collectPaths()
    if not paths then return false end
    observePaths(paths)
    local added={}
    for _,path in ipairs(paths) do
        if LIBRARY.pending[path] and LIBRARY.pending[path]~=localDate() then
            added[#added+1]=path
        end
    end
    if #added>0 and connected() then return beginRound(false,nil,added) end
    return false
end
dailyCheck=function(force_scan)
    resetDay()
    if RUN.cancelled_wake then return end
    if newBooksCheck(force_scan) then return end
    if weatherCheck() then return end
    if RUN.sleeping or not networkingEnabled() or DAILY_DONE or RUN.active or RUN.transport_broken or ROUNDS >= MAX_AUTO then return end
    if connected() then beginRound(false) end
end
local function currentCheck()
    resetDay()
    if newBooksCheck(true) then return end
    if RUN.cancelled_wake or RUN.active or RUN.worker or RUN.sleeping or not networkingEnabled() or RUN.transport_broken or ROUNDS >= MAX_AUTO then return end
    local b = currentBook()
    if b and Inkfolio.needsFetch(b) and connected() then beginRound(false,b) end
end
local POLL_ENABLED = false
local function pollWifi()
    POLL_ENABLED = false
    if RUN.sleeping or not networkingEnabled() then return end
    dailyCheck() -- silently detects Wi-Fi connected, never enables it.
    if not RUN.cancelled_wake then
        POLL_ENABLED = true
        UIManager:scheduleIn(45, pollWifi)
    end
end
startPoll = function()
    if POLL_ENABLED or RUN.sleeping or not networkingEnabled() then return end
    resetDay()
    if not RUN.cancelled_wake then
        POLL_ENABLED = true
        UIManager:scheduleIn(45, pollWifi)
    end
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
    -- 留出至少 6 像素的空白隔离带，避免碰到正文、封面或二维码。
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

-- Transparent ink masks extracted from the three supplied JPEG stamps.
-- Existing clockwise tilt and missing ink are retained. No paper texture is painted.
local STAMP_SIZE=240
local STAMPS={
    pending={"108:3,112:1,115:3","103:4,108:12,121:2,124:3","97:22,121:2,124:10","92:1,96:23,127:12","89:6,96:4,102:22,128:2,131:4,137:3,141:2,146:1,151:1","85:8,94:30,125:1,132:1,134:14","83:5,91:32,134:16","79:10,91:6,98:11,110:12,128:2,135:17,153:2","75:6,83:2,87:28,119:2,127:3,137:12,150:7","73:11,91:5,98:17,120:1,128:1,138:20","70:16,88:1,94:9,105:1,138:8,147:14","68:4,74:4,79:7,94:2,137:5,143:10,154:8","68:17,88:1,138:2,142:21,164:1","64:15,81:4,144:12,157:1,159:3,163:3","63:22,111:1,145:22","62:13,77:1,79:3,83:1,101:3,106:12,121:3,150:20","60:12,73:5,97:8,106:16,135:1,152:19","57:4,62:2,65:6,73:3,94:15,120:2,126:2,132:1,134:4,156:3,160:13","56:12,69:2,90:5,96:3,132:3,136:7,157:2,161:13","54:14,70:1,85:2,88:1,90:4,138:7,146:1,160:8,169:3,174:1","53:17,83:5,140:9,161:12,174:4","52:16,80:2,83:5,144:3,148:2,162:1,164:15","50:7,58:3,62:3,77:9,149:3,164:17","48:12,62:2,76:5,150:6,170:12","47:4,52:10,72:2,75:4,152:2,156:1,171:12","46:14,71:5,157:1,171:14","45:9,57:2,68:2,71:4,158:4,171:15","43:5,49:5,55:1,57:1,67:4,159:4,174:13","41:7,49:6,67:3,160:2,163:2,175:13","41:14,64:1,67:2,161:6,175:13","40:10,52:2,62:3,66:2,164:3,177:12","38:3,42:3,47:5,60:5,165:3,179:4,185:2,188:4","37:14,60:4,167:4,179:13","36:6,43:4,57:3,61:2,169:4,180:3,184:7","36:11,57:1,170:4,184:2,187:6","35:1,40:2,43:4,55:4,171:4,184:10","34:1,38:1,42:4,55:3,172:1,174:2,184:12","39:1,52:2,56:2,175:1,184:14","51:3,176:3,185:14","31:2,52:1,177:2,187:11","30:3,48:2,52:1,177:4,190:7,198:1","29:3,48:4,178:4,189:8,198:2","29:4,47:4,180:3,190:8,200:1","27:2,30:2,37:1,181:3,191:3,195:4,200:1","27:4,37:1,182:2,192:1,194:9","26:5,45:2,182:3,194:10","25:6,183:1,193:6,200:4","25:10,42:1,187:1,194:11","23:4,28:4,187:2,196:9","22:2,25:7,33:1,42:2,187:3,196:10","21:3,27:4,188:1,196:12","21:3,26:2,40:1,188:4,197:11","21:3,25:3,37:1,189:3,199:10","25:2,28:1,37:1,39:1,190:3,199:10","25:5,36:4,191:2,199:10","19:1,25:4,35:4,191:4,200:10","28:1,35:3,192:1,194:1,200:2,203:8","194:2,202:9","17:8,33:3,194:2,202:4,208:4","16:3,20:5,32:3,194:3,203:9","15:3,20:5,32:3,195:2,203:9","15:3,21:4,31:4,196:1,204:7,212:1","15:4,20:5,31:1,33:1,197:2,204:6,212:1","15:8,31:1,197:3,205:10","13:9,30:2,64:3,198:2,205:4,210:6","12:11,29:3,64:3,198:3,206:4,211:5","12:10,29:2,63:5,199:3,207:10","12:4,17:5,28:3,63:7,199:2,207:10","11:7,19:2,28:1,62:9,200:3,208:8","11:10,28:1,61:11,201:2,209:4,214:3","11:10,26:2,61:12,201:2,209:5,215:3","10:10,26:1,60:13,202:2,209:2,212:2,216:3","10:6,17:1,25:3,59:7,68:8,202:3,210:9","9:9,25:3,58:18,204:2,211:9","8:10,24:3,57:8,66:10,87:3,203:2,213:2,216:4","9:2,12:2,15:4,24:3,56:20,87:4,203:2,213:8","9:3,13:5,24:2,54:2,58:17,87:6,204:1,212:9","11:4,16:1,24:1,53:3,57:15,87:8,205:2,212:9","8:1,11:4,16:1,52:18,87:2,90:7,205:2,212:4,217:4","7:9,50:9,60:4,65:3,86:7,95:4,213:9","6:10,23:1,49:10,60:7,86:14,213:9","6:10,23:1,48:17,86:14,206:2,214:8","6:10,21:1,47:1,49:4,54:8,72:3,85:16,207:2,214:4,219:2","6:3,11:4,21:1,45:8,55:7,72:5,85:16,207:2,214:1,216:2,222:1","5:10,20:3,44:8,54:4,60:3,72:7,85:5,91:3,95:5,207:2,215:2","5:7,13:1,20:3,44:3,49:7,60:4,73:9,85:13,207:3,215:3,220:1,222:1","5:9,19:3,44:3,50:2,58:7,72:25,208:3,215:2,220:4","5:9,19:3,58:2,61:5,72:25,208:3,220:4","5:8,19:2,59:4,64:3,72:25,208:3,220:3","5:9,19:2,59:4,64:3,72:8,81:7,89:7,104:3,209:2,220:2","5:8,19:2,55:13,76:20,102:5,210:1,219:1","4:9,19:2,54:3,58:11,79:12,93:5,101:7,210:1,218:2","4:8,53:16,82:5,88:2,91:1,93:2,96:7,104:5,210:1,217:2,225:1","4:6,11:1,17:3,52:18,82:5,88:2,91:4,96:7,104:5,136:3,210:2,217:2","3:6,17:3,52:18,82:16,99:11,135:6,210:2,217:3,224:1","3:5,17:3,51:14,66:3,82:21,104:6,134:9,210:2,217:3,224:2","3:5,17:2,49:16,66:3,81:18,100:3,104:7,135:10,211:2,218:3,224:2","2:5,17:2,46:17,65:6,81:12,95:7,103:8,136:10,211:2,219:2,225:1","2:9,17:1,46:16,65:9,81:7,89:3,99:13,137:10,211:2,218:1,220:1,225:2","3:2,7:1,9:2,16:2,45:15,65:12,81:11,101:11,137:8,146:2,211:3,218:1,220:1","7:1,9:2,16:2,43:16,65:14,80:12,104:8,138:7,146:2,211:1,213:1,218:3","8:2,16:2,42:18,65:27,107:5,138:12,212:1,219:3,226:1","2:1,7:1,10:1,16:2,41:20,66:25,109:2,138:12,171:1,219:7","16:2,41:20,70:21,138:6,145:5,170:3,219:7","17:1,38:1,41:11,55:6,73:18,104:3,138:1,140:10,170:7,219:8","2:1,17:1,35:2,38:5,44:5,50:2,54:7,76:7,84:10,103:5,137:13,170:7,219:9","2:1,15:1,34:3,39:21,78:3,82:1,85:2,88:9,101:8,137:12,169:13,219:8","1:2,15:1,32:4,45:1,47:11,81:5,88:22,139:10,169:14,212:1,219:6,226:2","6:1,15:2,31:5,40:2,43:1,47:10,83:27,138:10,154:5,169:14,212:1,220:8","15:3,33:2,37:1,40:1,46:11,61:2,86:25,138:10,153:8,169:4,174:9,221:8","16:1,33:2,46:12,60:4,87:24,140:6,153:12,169:14,222:7","16:1,33:2,46:11,60:6,86:26,154:13,168:10,179:2,222:6","45:12,60:9,86:8,96:16,153:16,171:9,213:1,221:7","1:3,45:12,60:10,86:9,99:12,112:1,153:16,172:8,213:1,221:7","1:3,16:1,45:11,60:14,85:12,101:13,124:3,136:3,155:24,220:8","15:2,44:3,48:8,61:16,85:13,104:9,123:7,135:5,160:5,166:13,222:7","1:1,15:2,44:12,63:6,70:3,74:6,85:14,107:6,123:18,162:19,190:4,223:6","1:1,5:1,16:1,44:4,49:6,65:4,70:12,85:14,110:3,123:18,165:19,189:5,223:6","0:2,15:2,45:2,49:6,64:4,69:30,103:1,125:6,132:10,149:2,165:21,187:8,223:5","0:2,14:3,44:1,48:7,63:5,72:17,90:7,102:3,123:20,148:5,165:30,213:1,222:6","3:1,8:1,14:3,43:2,48:7,63:7,74:14,89:7,100:6,123:7,131:13,148:6,165:6,172:24,213:1,222:7","7:2,14:1,42:3,48:6,63:8,77:19,99:7,124:1,126:19,148:5,154:5,164:13,179:18,212:3,220:9","1:3,5:4,42:12,64:7,80:6,88:19,126:2,130:15,149:12,164:13,180:17,213:3,222:6","1:9,14:1,42:10,53:1,64:6,71:2,82:10,93:5,99:8,131:10,142:3,148:22,171:6,182:16,213:2,223:6","1:9,16:1,42:1,45:9,64:10,83:8,94:14,130:15,148:6,155:21,185:13,214:2,222:8","1:8,15:2,43:1,46:8,64:10,82:8,92:1,94:14,130:9,140:4,150:18,169:7,189:9,214:2,220:9","1:3,5:3,14:3,41:1,46:7,64:3,68:7,82:10,93:16,130:7,138:3,156:12,169:6,190:7,213:2,221:1,223:6","1:2,5:3,15:2,41:2,44:9,64:11,82:20,103:6,129:8,138:3,158:17,195:2,213:2,220:2,224:2,227:2","1:7,9:1,15:2,40:10,51:1,64:3,68:7,81:13,97:12,129:12,154:3,160:18,188:2,213:1,220:1,224:5","1:2,6:4,15:1,40:12,64:10,81:12,99:10,129:5,135:6,153:5,163:6,170:11,186:5,213:2,219:2,225:1,227:2","3:1,6:3,16:1,40:1,42:10,66:8,81:10,102:7,128:13,153:7,165:4,170:13,185:6,213:2,219:2,224:4","3:7,16:1,42:5,48:4,64:10,81:12,104:5,128:12,153:8,168:24,213:2,219:9","2:8,16:1,42:4,47:5,65:8,80:13,107:1,128:12,154:9,171:3,176:16,219:2,222:6","2:8,15:2,38:3,43:3,47:4,66:6,80:13,129:7,137:3,146:2,154:2,158:6,166:3,174:19,212:2,223:5","1:9,16:2,38:8,47:4,68:2,79:10,90:2,127:6,135:1,137:2,145:4,155:3,159:5,166:5,176:18,212:3,223:5","1:9,16:2,38:13,79:13,126:3,130:3,135:2,145:7,156:8,166:8,179:15,212:3,223:5","1:9,16:2,38:8,49:1,66:1,80:12,126:6,134:4,145:8,156:8,166:9,182:13,212:2,219:1,222:6","2:9,15:3,38:9,66:2,69:3,79:12,126:6,133:1,135:3,146:8,155:10,166:12,183:13,212:2,219:8","3:8,16:3,37:2,41:8,67:5,78:13,126:5,133:1,135:3,147:8,156:8,165:14,182:15,206:1,212:2,219:8","3:8,16:3,37:6,46:3,69:6,78:13,126:10,147:4,152:11,165:14,181:16,212:2,219:9","2:9,16:3,40:4,47:2,68:10,79:9,89:1,126:6,135:2,147:9,157:5,164:15,181:16,211:2,218:9","2:6,10:2,17:2,45:4,68:3,73:13,87:1,89:1,125:8,135:1,147:9,164:14,180:16,211:3,218:9","3:9,17:2,47:1,69:2,74:13,88:1,124:8,133:2,148:9,164:12,179:17,218:5,224:3","3:9,17:1,19:1,71:1,73:2,76:13,124:4,129:7,147:10,163:13,179:10,210:1,218:1,220:6","3:10,18:2,71:18,124:4,129:7,140:3,147:9,163:13,179:8,210:1,217:2,221:5","4:2,8:4,18:2,72:17,123:12,140:5,149:7,162:14,180:3,210:2,217:5","4:3,8:4,18:1,20:1,72:5,78:2,82:6,123:12,140:7,149:6,162:13,210:2,217:5,224:2","6:6,18:3,72:8,83:5,123:12,141:10,162:7,170:5,209:3,217:7","4:1,6:5,12:1,18:3,72:8,83:5,122:13,142:8,151:3,164:5,172:2,209:2,217:8","5:8,18:3,72:8,84:3,122:12,145:10,162:1,165:1,167:6,210:2,218:7","5:9,19:3,71:9,82:3,86:1,122:1,124:2,127:6,138:20,165:8,210:1,216:9","5:9,72:7,82:2,121:18,140:13,154:9,166:7,216:9","5:9,20:2,73:7,83:2,118:22,141:1,144:3,149:15,167:5,208:3,215:10","6:9,20:2,32:2,79:1,84:1,118:7,126:16,147:7,155:4,160:5,167:3,207:3,215:9","6:10,20:3,32:1,117:25,150:8,160:1,163:1,169:2,181:4,207:3,215:9","6:5,12:4,22:1,117:23,153:5,160:3,165:1,169:3,180:5,207:2,214:10","6:10,22:2,118:20,155:9,166:8,178:8,207:2,214:5,220:4","6:4,11:5,22:2,119:18,153:16,170:16,206:3,214:9","7:9,22:1,119:17,152:17,170:4,175:11,207:1,214:1,216:7","8:9,38:1,118:12,134:1,152:9,162:7,170:17,205:3,213:1,216:6","8:9,23:2,120:12,150:14,167:20,205:3,213:9","8:6,16:2,23:3,120:10,149:16,170:18,204:3,212:9","9:9,25:1,120:9,147:18,172:17,204:3,211:3,215:7","9:9,120:8,145:10,156:1,158:9,175:15,203:2,211:10","9:6,17:1,26:1,121:4,140:15,156:12,179:11,203:1,211:10","9:9,121:4,138:9,148:11,162:8,180:9,203:1,205:1,210:6,217:4","10:1,14:2,17:3,26:2,122:2,136:21,158:1,163:9,183:6,202:3,211:5,218:2","11:1,15:3,19:1,26:3,129:9,140:19,164:10,186:3,201:4,210:6,218:1","12:1,14:4,26:3,129:8,140:16,164:11,201:3,209:7,217:2","12:7,20:1,27:3,129:9,139:13,165:11,201:3,209:10","12:7,20:1,27:3,130:4,135:14,165:2,168:10,200:3,210:3,216:2","12:6,20:2,28:2,135:3,140:2,166:12,199:3,207:4,216:2","12:5,20:2,28:1,166:13,199:1,201:1,207:6,216:1","14:3,18:1,22:2,167:13,198:2,206:7,215:1","15:9,31:1,167:13,198:3,206:9","15:9,31:2,168:13,197:3,205:10","15:7,23:1,31:3,168:5,174:7,196:4,205:7,213:2","16:6,23:2,31:2,168:14,196:3,205:1,207:5,213:1","16:6,24:1,169:12,195:2,204:7,212:1","17:1,19:1,25:1,169:2,172:9,194:4,203:7,211:2","16:3,23:1,35:2,168:13,195:2,202:8,211:1","17:2,20:3,25:3,34:3,169:11,193:3,201:11","21:7,36:1,168:12,192:2,201:11","19:7,27:1,37:2,170:8,192:2,200:11","20:8,37:2,171:6,191:3,199:12","21:2,24:2,27:2,37:1,172:4,190:2,199:12","21:5,29:2,189:1,198:7,206:3","21:3,26:6,39:3,188:2,198:11","23:1,26:2,29:3,40:3,187:4,198:10","23:8,42:1,187:3,198:9","24:10,186:3,195:4,200:7","24:4,29:2,32:4,44:1,185:2,194:4,200:6","27:9,43:3,183:4,194:12","27:9,44:3,183:3,194:11","27:4,32:5,44:4,182:1,184:1,194:4,200:4","27:5,34:3,45:4,181:3,191:1,193:4,200:3","27:7,36:1,48:2,180:4,190:7,199:2","28:7,38:3,48:3,178:3,182:1,189:8,199:1","29:3,34:3,39:2,48:4,177:4,188:11","31:1,33:10,49:5,179:1,187:12","31:5,37:3,41:3,53:2,187:12","32:7,41:4,173:2,188:6,195:2","33:12,175:1,186:3,190:4,195:1","35:1,37:9,183:12","36:5,42:5,184:1,187:1,189:5","36:12,169:1,187:1,190:3","37:7,45:3,61:1,167:2,185:1,187:1,190:2","38:8,165:5,187:1,190:1","39:7,51:2,64:2,164:5,177:2,184:1,186:1","40:7,51:2,64:3,162:5,175:4,184:3","41:6,51:1,64:6,160:5,185:2","42:6,51:1,53:1,55:2,66:5,158:3,162:1,176:1,184:2","44:3,52:1,54:4,67:3,71:2,157:5","44:1,52:2,55:2,69:1,71:4,154:6,169:2","51:3,55:2,60:1,72:4,153:4,167:4","51:6,58:1,60:2,73:7,150:7,167:4","51:11,76:7,147:7,164:7","50:8,60:2,64:3,77:7,143:7,162:13","50:6,57:1,60:2,63:5,79:4,84:5,141:8,159:4,164:8,173:3","52:6,60:8,83:7,136:2,139:8,158:13,173:3","53:4,60:4,65:3,70:3,85:11,133:4,138:1,140:3,155:5,161:10","55:3,60:9,70:5,88:3,92:10,128:6,135:3,155:17","59:2,62:3,66:7,75:3,93:4,98:13,117:2,121:4,126:4,133:4,151:4,157:5,163:8","59:6,66:8,75:4,97:1,100:1,102:4,107:3,112:1,114:1,118:2,124:7,151:4,157:13","60:5,66:8,75:8,103:3,108:1,113:2,117:4,145:22","62:3,67:1,69:16,143:6,150:10,162:4","63:1,65:2,68:3,72:9,82:8,138:1,141:13,155:5,161:4","67:14,82:14,133:2,138:2,141:21","68:32,131:17,149:12","72:20,93:3,98:6,114:4,119:3,123:3,130:6,137:13,152:5","73:19,94:10,108:3,113:11,125:1,132:12,145:2,148:8","75:9,85:20,109:2,113:11,133:1,135:2,138:2,141:6,148:3","79:27,107:17,133:3,138:2,141:9","80:14,95:22,118:5,134:2,138:8","86:37,133:3,138:3,142:2","91:7,100:4,105:19,126:1,132:3,136:3","92:2,95:3,99:15,115:3,119:6,126:2","103:24","107:1,115:3",""},
    reading={"113:3,120:3","107:4,113:6,120:5,126:2,130:3","101:3,105:19,127:1,129:11","96:1,100:24,133:3,137:9","93:6,101:4,106:21,128:2,134:1,137:4,143:6","89:8,98:31,137:2,140:15","87:5,94:35,140:16","82:11,95:7,103:11,115:12,134:2,141:17,160:1","79:6,86:2,91:29,124:3,133:3,143:15,159:5","76:11,95:6,102:18,125:2,134:1,144:21","73:17,92:1,98:3,102:6,109:2,144:8,153:15","71:5,77:4,82:8,98:2,143:5,149:20","71:5,77:12,92:1,144:2,148:22,172:1","67:16,84:5,150:13,164:1,166:3,170:4","66:23,113:1,116:1,152:23","65:14,80:2,83:3,87:1,106:3,111:12,127:2,130:1,157:14,172:5","62:13,77:5,101:8,111:17,141:1,159:20","59:5,65:2,68:6,77:3,99:15,125:3,132:1,138:1,140:4,163:3,167:14","58:13,72:2,94:6,101:2,138:3,142:8,164:2,168:13","56:15,73:1,89:2,92:1,94:4,145:6,168:8,177:3","55:18,86:5,146:10,168:13,182:4","54:18,83:3,87:5,150:4,155:1,169:1,171:16","53:7,61:2,65:3,81:9,156:3,172:17","50:4,55:7,65:2,80:5,156:7,176:1,178:12","49:4,55:7,63:2,76:1,78:5,159:2,163:1,176:1,179:11","48:14,74:5,164:1,178:15","47:10,59:3,72:1,75:3,165:5,179:16","45:11,57:4,70:4,76:1,166:5,181:14","43:7,51:7,70:3,167:2,171:1,182:14","43:14,67:1,70:2,168:6,183:14","42:10,54:2,64:3,70:1,171:3,184:13","40:3,44:4,49:6,63:5,172:3,186:5,193:3,197:3","39:8,48:5,62:4,175:4,187:9,197:3","38:6,45:4,51:1,60:2,63:3,176:4,188:3,192:8","37:12,59:2,177:5,192:10","37:1,42:2,45:4,58:4,179:4,192:11","36:1,44:4,57:4,180:1,182:1,193:11","40:2,43:1,54:2,59:1,183:1,193:13","54:2,183:4,194:14","32:3,54:2,184:3,196:11","31:4,51:1,54:1,185:4,198:8","31:3,50:4,186:4,198:8,207:2","30:3,34:1,49:4,188:3,198:9","29:1,31:2,189:4,199:8,209:1","28:4,190:3,200:2,203:9","27:6,47:1,191:2,203:10","26:7,191:2,202:11","26:10,43:2,195:1,202:12","24:5,30:3,195:2,204:10","23:10,35:1,42:1,44:2,195:3,204:11","22:3,29:3,197:1,205:12","22:4,27:3,42:1,197:3,206:11","22:3,26:4,39:1,197:4,208:10","26:3,38:2,41:1,198:1,200:1,208:11","26:5,38:3,200:2,208:11","20:1,26:5,37:4,200:3,209:10","29:1,37:3,201:1,203:1,209:12","203:1,211:10","18:8,35:2,202:3,211:4,217:5","16:4,21:5,34:3,203:3,211:11","16:10,33:4,204:2,212:10","16:3,21:6,33:3,205:1,213:7,222:1","15:5,21:5,32:1,34:1,205:3,213:7,222:1","16:8,34:1,206:3,214:8,223:1","14:9,31:2,207:3,214:4,219:6","13:11,30:3,207:3,216:3,220:6","13:10,30:3,81:2,208:3,216:10","12:5,18:5,29:1,31:1,81:3,208:2,217:10","12:7,20:2,29:1,80:5,209:1,211:1,217:9","11:11,29:2,80:6,210:2,218:4,224:3","11:11,27:3,79:3,83:6,210:2,218:6,225:3","11:10,27:1,53:2,78:5,84:6,211:2,218:2,221:3,225:4","10:9,26:3,53:6,78:13,211:3,219:1,221:8","9:10,26:3,53:8,77:15,212:1,214:1,221:8","9:10,25:4,52:10,63:2,76:18,212:3,222:2,225:5","9:3,13:2,16:3,25:3,51:8,60:1,62:5,75:6,82:1,85:9,213:1,222:9","10:9,25:3,51:9,63:3,67:2,74:13,88:6,213:1,222:4,227:3","9:1,11:7,26:1,51:9,61:5,67:2,70:24,215:1,221:9","12:3,51:12,64:2,67:1,71:10,82:5,88:3,214:3,222:3,227:4","8:9,52:7,62:1,65:2,71:10,82:5,88:2,216:1,222:10","7:10,24:2,55:3,60:3,64:25,222:10","6:10,24:1,59:4,64:4,69:19,216:2,223:9","6:4,11:5,24:1,64:14,79:9,216:3,223:5,229:2","6:3,11:5,22:1,66:8,75:13,216:3,223:2,226:1","5:6,12:4,21:3,66:17,84:4,91:3,216:3,225:2","5:8,14:1,21:3,65:12,78:4,85:3,90:3,94:3,217:2,225:3,230:1,232:1","5:10,20:3,64:4,69:2,73:13,88:5,96:4,217:3,225:1,230:4","6:9,20:3,63:20,86:4,91:2,94:9,117:1,217:3,225:1,229:5","6:1,8:6,20:2,63:5,69:11,81:4,86:7,94:2,97:2,101:4,116:5,217:3,229:4","5:9,20:2,62:5,69:10,83:2,86:4,91:17,115:6,146:1,218:3,229:3","5:9,20:2,60:2,63:5,69:9,86:4,92:12,105:7,114:7,145:3,219:2,229:1","4:10,20:2,58:2,63:14,90:7,98:23,144:4,228:1","4:9,57:3,62:12,92:8,102:6,110:12,144:7,219:2,226:3,235:1","4:7,18:3,56:9,66:8,90:1,94:12,107:15,145:9,219:3,226:3","4:5,18:3,56:16,89:3,97:1,99:3,104:19,147:7,219:3,227:3,234:1","3:5,18:3,54:17,88:6,100:9,110:13,145:10,219:2,227:3,234:2","3:5,17:3,53:7,61:10,88:8,104:20,145:11,220:3,227:4,233:3","2:6,18:2,51:8,60:10,88:9,107:17,146:7,154:3,220:3,229:2,235:2","2:6,9:2,17:2,49:9,60:6,88:14,109:1,111:14,146:12,220:3,227:1,230:1,236:1","3:2,7:2,10:2,17:2,48:18,87:16,113:9,123:2,146:12,220:3,227:2,230:1","7:1,10:1,17:2,46:17,64:3,87:12,100:3,115:9,146:12,178:3,221:2,228:3","8:3,17:2,45:22,87:6,95:8,117:7,146:6,153:5,178:7,221:1,229:3,236:1","2:1,7:1,10:1,17:2,44:5,50:16,86:6,94:8,121:3,145:13,178:8,189:1,221:1,228:8","17:2,43:23,86:11,99:1,145:13,178:7,187:4,228:8","16:3,40:1,43:13,59:7,85:15,145:12,163:1,177:14,229:9","2:1,37:2,40:6,47:6,54:2,58:3,62:4,71:1,85:13,146:10,162:4,177:4,183:8,229:9","2:1,16:1,36:3,41:18,62:2,69:4,85:7,93:5,146:9,162:6,177:5,183:8,229:8","1:2,16:1,33:5,48:1,51:6,58:2,61:2,69:6,84:15,148:6,161:12,177:4,182:9,222:1,229:6,236:2","7:1,16:2,33:5,43:1,50:11,62:1,69:9,84:15,162:5,169:5,176:10,187:2,222:1,230:9","16:2,34:3,39:1,49:14,69:7,77:4,84:6,91:7,161:8,170:18,231:8","17:1,34:3,49:14,71:27,161:16,180:8,232:7","17:1,34:3,49:14,68:30,132:2,144:2,163:5,169:8,178:10,232:7","48:8,57:6,68:13,82:4,88:10,131:6,142:5,167:6,175:12,231:7","1:3,48:14,71:4,76:11,88:5,94:3,105:2,131:7,140:7,169:4,174:5,180:8,199:4,222:2,231:7","1:3,17:1,48:14,76:8,85:11,104:4,131:6,138:5,145:3,173:21,198:4,230:8","15:3,48:2,52:9,77:21,102:7,132:16,156:2,173:10,184:11,196:7,224:1,232:7","16:2,47:4,52:2,55:6,81:28,131:7,139:10,155:4,173:31,233:6","1:1,5:1,17:1,48:3,52:9,80:17,98:11,130:8,140:8,155:6,173:7,181:6,188:16,233:6","0:2,16:1,48:3,52:8,80:13,95:11,107:3,130:6,137:14,155:7,172:14,187:18,233:5","0:2,15:3,47:1,52:8,80:6,88:5,94:17,133:19,155:6,162:5,172:13,188:18,223:1,232:6","8:2,15:3,46:2,52:8,80:17,99:12,137:15,156:14,172:13,190:9,200:6,222:2,232:7","7:2,15:1,46:2,51:8,79:12,92:1,96:16,137:11,149:3,154:24,179:6,192:1,194:13,222:2,230:9","1:3,5:5,45:14,79:9,89:4,98:5,104:7,136:15,156:5,163:22,198:8,223:2,232:6","1:9,15:1,45:11,57:1,78:10,89:4,100:11,136:14,158:15,174:1,177:7,199:7,223:2,232:7","1:9,17:1,45:1,48:9,78:15,103:8,135:9,145:1,147:1,163:2,166:2,169:7,177:6,204:1,224:1,233:7","1:9,16:2,46:1,49:9,78:2,81:12,106:5,135:8,144:3,162:1,167:10,178:6,197:2,224:2,230:10","1:3,5:4,15:3,44:1,47:1,49:4,54:4,77:15,135:12,161:3,168:21,195:4,223:2,231:1,233:6","1:2,5:3,16:2,44:2,47:10,78:14,135:6,142:5,160:6,172:5,178:12,193:7,222:3,230:1,234:2,238:1","1:4,6:2,9:1,16:2,43:10,55:2,78:5,84:7,134:13,164:1,166:2,174:26,222:2,234:5","1:2,6:4,16:2,43:11,55:1,76:4,81:10,134:5,140:6,161:8,178:23,222:3,229:2,235:1,237:2","3:1,6:1,8:2,17:1,43:1,45:11,76:15,134:12,161:10,174:2,181:1,184:17,222:3,229:2,234:5","3:8,17:1,45:5,51:5,76:14,135:11,153:2,162:1,166:5,174:4,183:19,223:1,229:10","2:9,17:1,44:5,50:6,75:14,133:9,144:1,152:4,162:3,166:6,174:6,186:7,194:9,223:1,229:2,232:6","2:9,16:2,41:3,46:3,50:5,57:2,75:4,80:9,132:3,136:4,141:2,151:3,155:4,163:9,173:9,188:12,201:3,222:2,233:5","1:10,16:3,41:14,57:6,75:3,80:6,87:1,131:4,136:2,141:4,152:8,162:10,173:13,191:13,221:3,233:5","1:9,17:2,41:14,57:7,74:9,84:4,132:6,139:5,155:6,162:10,173:14,190:15,221:3,233:5","1:9,16:3,41:8,52:2,56:6,64:4,74:7,82:6,132:5,139:1,141:1,143:1,153:18,173:14,190:16,221:3,229:1,232:6","2:9,16:3,40:11,56:8,65:3,74:6,82:6,132:2,135:7,153:5,159:11,172:15,189:17,221:3,228:9","3:8,17:3,40:2,43:4,48:3,52:1,56:28,85:3,132:7,140:3,154:9,165:3,171:6,178:2,181:6,188:3,192:13,215:1,222:1,228:9","3:8,17:3,40:2,43:3,49:3,56:21,79:3,83:4,130:9,141:1,154:10,171:14,187:17,222:1,228:10","2:9,17:3,43:3,50:2,56:10,67:8,77:6,86:1,130:9,141:1,154:9,171:13,186:11,221:2,228:9","2:7,11:2,18:2,48:4,59:6,67:7,79:5,85:1,129:9,139:3,154:9,170:14,188:8,221:2,228:9","3:9,18:2,63:3,67:4,72:1,77:1,80:6,100:1,129:5,135:7,146:3,154:9,169:15,188:4,228:5,234:3","3:10,18:1,20:1,65:15,82:6,100:4,129:12,146:6,155:7,169:14,220:1,227:2,230:6","3:6,10:3,19:1,67:13,84:8,98:6,129:3,133:8,146:7,156:5,169:13,219:2,227:2,231:3,235:1","4:3,8:5,19:2,69:10,81:1,86:3,90:4,97:7,128:13,147:10,170:7,178:4,219:3,227:5","4:3,8:5,19:3,74:4,82:2,86:4,92:12,128:7,136:5,148:8,158:2,172:4,178:1,180:2,219:3,227:5,233:3","6:7,19:3,75:2,82:2,87:3,91:13,128:13,149:1,151:6,158:5,169:1,172:1,174:2,177:3,219:2,227:7","5:8,19:3,82:2,88:17,127:12,145:3,149:16,166:2,172:9,218:3,227:1,229:6","5:9,19:3,87:4,93:8,102:4,127:4,132:28,161:9,174:6,219:2,228:8","5:9,20:3,86:5,93:13,125:2,128:18,147:1,151:3,156:15,174:6,219:1,226:9","6:8,20:1,86:21,123:7,132:16,154:7,162:4,167:3,171:1,175:3,189:4,225:10","6:9,21:2,90:8,99:8,123:7,131:17,156:9,170:1,176:1,188:5,217:3,225:5,231:3","6:10,21:2,34:1,93:15,123:23,160:5,167:2,170:1,176:2,187:7,217:3,225:9","6:10,21:3,94:1,96:13,123:7,131:11,143:2,162:9,173:11,186:8,216:3,226:8","6:5,12:4,23:2,97:7,105:3,124:20,160:16,177:17,216:3,224:10","6:10,23:2,99:1,101:7,124:18,159:17,178:4,183:12,216:3,224:5,230:3","7:3,11:5,23:2,104:3,124:12,137:1,139:2,158:18,178:17,216:2,224:9","8:8,23:1,124:12,137:1,157:15,175:21,216:1,224:1,226:7","8:9,40:1,125:11,155:17,178:18,214:3,223:1,226:6","9:7,17:1,24:3,125:10,154:18,181:17,214:3,222:9","9:5,17:2,24:3,125:9,152:10,163:1,165:10,184:14,214:3,221:10","9:10,26:1,126:5,148:13,163:13,187:11,213:3,221:11","9:10,126:4,145:23,169:9,188:9,213:1,220:11","10:6,17:2,27:1,126:4,142:22,165:1,170:10,192:5,212:1,220:11","10:3,14:5,37:1,135:3,139:5,145:20,171:10,195:2,212:1,214:1,220:6,227:4","10:2,15:2,18:3,27:2,135:8,146:17,171:12,211:3,220:6,228:2","15:4,20:1,27:3,135:8,145:1,148:11,172:3,176:8,210:4,219:7,227:1","12:7,27:3,135:9,145:11,172:13,210:3,219:7,227:2","13:7,21:1,28:3,135:4,140:9,150:2,154:1,173:4,178:8,210:3,219:1,221:8","12:6,19:1,21:1,29:3,174:13,209:3,219:4,226:2","12:6,21:2,29:3,174:13,208:3,216:4,225:2","13:5,21:2,29:2,174:14,208:1,210:1,216:2,219:3,225:2","13:5,19:1,23:2,32:1,175:14,207:2,215:7,224:1","15:3,19:6,175:6,182:6,206:3,215:10","16:9,32:3,175:14,206:3,215:10","16:7,24:1,32:3,176:13,205:4,214:11","16:7,24:2,33:1,177:12,204:4,214:1,216:5,222:2","17:6,25:1,176:3,180:9,204:2,213:7,221:2","17:2,20:1,26:2,36:1,176:12,203:3,212:8,221:1","17:3,37:1,176:12,204:2,212:10","18:2,21:3,26:4,36:3,176:11,202:3,210:11","22:8,36:1,38:1,177:9,201:2,210:11","20:7,28:1,39:1,179:5,200:3,209:11","21:8,39:2,181:2,200:3,208:12","22:8,39:1,199:1,208:12","22:5,30:3,198:1,207:12","22:4,27:6,41:3,197:2,207:11","24:1,27:2,30:4,42:2,196:3,206:12","24:6,31:2,44:1,195:4,206:10","25:11,194:4,204:4,209:7","25:4,31:1,33:4,46:1,193:2,203:4,209:7","28:9,45:3,192:4,202:13","28:10,45:4,191:4,203:11","28:4,33:6,46:4,190:1,192:2,203:3,209:4","28:5,35:4,47:4,189:4,199:1,202:4,209:3","29:5,35:1,38:1,51:1,188:4,198:8,208:2","30:6,40:3,51:3,186:3,190:1,197:7,205:1,208:1","30:3,35:4,40:3,51:4,185:4,196:11","32:1,35:9,52:4,187:1,195:12","33:5,39:3,43:3,56:1,195:12","34:7,43:4,181:2,196:6,204:2","34:13,56:1,183:1,194:4,199:3","36:2,39:9,56:1,191:4,196:8","37:1,39:3,44:5,177:1,192:1,195:2,198:5","37:14,176:2,196:1,198:4","38:8,47:3,64:1,175:2,193:4,199:2","40:8,173:4,195:1,199:1","41:7,54:1,67:2,172:4,184:3,192:1,194:2","42:7,54:2,67:3,169:5,183:4,192:3","43:6,67:6,167:5,194:2","44:6,53:1,56:4,69:5,165:3,169:1,184:1,192:2","46:3,55:5,71:2,74:3,162:1,164:5","46:1,54:6,72:6,161:7,176:3","54:3,58:1,63:1,76:3,159:5,175:4","54:5,60:5,76:7,156:8,174:4","53:12,79:7,153:7,172:6","52:7,60:1,62:2,67:3,81:7,150:7,169:14","53:6,60:1,62:3,66:5,82:5,88:5,148:8,167:12,180:4","54:5,60:1,63:8,87:7,142:2,146:8,165:13,181:3","56:3,63:4,68:3,73:4,89:11,139:4,144:6,162:6,169:9","58:2,63:9,73:5,92:3,96:11,133:7,141:3,162:17","61:7,69:8,78:4,97:5,103:13,122:3,126:5,132:4,138:5,158:4,164:15","62:6,69:8,78:5,102:1,104:2,107:4,112:3,117:1,119:1,123:2,130:6,157:5,164:13","63:5,70:7,78:9,108:2,113:1,118:3,122:5,151:23","65:3,70:1,72:5,78:11,149:6,157:10,169:5","68:2,71:3,75:10,86:8,144:2,147:20,168:4","70:14,85:15,138:3,144:2,147:22","71:33,137:4,142:26","75:21,97:3,102:7,114:1,119:4,124:3,128:4,136:3,140:2,143:14,159:5","77:20,99:10,113:3,118:11,130:2,137:14,152:1,155:8","78:9,89:20,114:2,118:10,129:1,138:2,141:2,144:9,155:3","83:28,112:11,124:5,138:4,144:3,148:8","84:14,99:30,140:2,144:8","90:39,139:3,145:1,149:1","95:8,104:4,109:21,131:1,138:6","96:2,100:2,104:15,120:4,125:5,132:2","107:17,125:7","112:1,120:3",""},
    finished={"110:1,115:3","103:4,108:12,121:2,124:3","97:22,121:2,124:5,130:4","92:1,96:23,127:3,131:8","89:6,96:4,102:22,128:2,131:4,137:3,141:2,146:1,151:1","85:8,94:30,125:1,132:16","83:5,90:33,134:16","79:10,91:6,98:11,110:12,128:2,135:17,153:1","75:6,83:2,87:28,119:2,127:3,136:21","73:11,90:7,98:17,120:1,128:1,138:20","70:16,88:1,94:12,138:8,147:14","68:4,74:4,79:7,94:2,137:5,143:19","68:5,74:11,88:1,138:2,141:22,164:1","64:15,81:4,144:12,157:1,159:7","63:22,111:1,145:22","62:13,77:1,79:3,83:1,101:3,106:12,121:2,150:19","61:11,73:6,97:8,106:16,152:19","57:4,62:2,65:6,73:3,94:15,120:2,126:2,132:6,156:3,160:13","56:12,69:2,90:5,96:3,132:11,157:1,161:13","54:14,70:1,85:2,88:6,138:7,160:8,169:4","53:17,83:5,91:1,140:9,161:12,174:2","52:17,80:2,83:5,144:3,148:2,162:1,164:15","50:7,58:3,62:3,77:9,149:3,164:17","48:11,62:2,76:5,150:6,166:1,170:11","47:4,52:10,72:2,75:4,152:2,155:2,171:12","46:14,71:5,157:1,171:4,176:8","45:7,53:1,57:2,69:1,71:4,158:1,160:2,171:15","43:11,55:1,57:1,67:4,159:4,173:14","41:7,49:6,67:3,160:2,163:1,175:13","41:14,64:1,67:2,161:6,175:13","40:10,52:2,62:3,66:2,164:3,176:13","38:3,42:4,47:5,61:4,165:3,179:4,185:2,188:3","37:14,60:4,167:4,179:8,188:4","36:6,43:4,58:2,61:2,168:4,180:3,184:8","36:11,57:1,169:5,184:2,187:6","35:1,40:7,55:4,171:4,184:10","34:1,38:1,42:4,55:4,172:1,174:1,184:11","39:1,52:2,56:2,175:1,184:14","51:3,175:4,185:14","31:2,51:2,176:3,187:11","30:3,49:1,52:1,177:4,190:7","29:4,48:4,178:4,189:7,198:2","29:4,47:4,180:3,190:8","28:1,30:2,37:1,181:3,191:7,200:1","27:4,37:1,182:2,192:1,194:9","26:5,45:2,182:3,194:10","25:6,183:1,185:1,193:10","25:10,42:1,187:1,194:10","23:4,28:4,187:2,195:10","22:10,33:1,41:1,43:1,187:3,196:10","21:3,27:4,32:1,188:2,196:12","21:3,26:2,40:1,188:4,197:11","21:3,25:4,189:3,199:10","25:2,37:1,39:1,189:4,199:10","25:5,36:4,191:2,199:10","25:5,35:4,191:4,200:10","28:1,35:3,192:1,194:1,200:11","194:2,201:10","17:8,34:2,194:2,202:4,207:5","16:3,20:5,33:2,194:3,202:10","15:4,20:5,32:3,195:2,203:9","15:3,20:5,32:3,196:1,204:7,212:1","15:4,20:5,31:1,33:1,196:3,204:6,212:1","15:8,31:1,197:3,205:7,213:1","13:9,30:2,198:2,205:4,210:5","13:10,29:3,55:2,198:3,206:4,211:5","12:10,29:3,54:4,199:3,207:10","12:2,15:1,17:5,28:3,53:5,199:3,207:10","11:7,19:2,28:1,53:8,200:1,202:1,208:8","11:10,28:1,53:5,59:4,201:2,208:5,214:3","11:10,26:2,54:10,201:2,209:5,215:3","11:9,26:1,54:6,61:4,202:2,209:2,212:2,215:4","10:6,17:1,25:3,54:5,61:5,202:2,209:2,212:7","9:9,25:3,55:12,204:2,211:8","8:10,24:3,55:12,89:3,203:2,212:3,216:4","9:2,12:2,15:4,24:3,55:4,60:8,89:6,203:2,213:2,216:5","9:3,13:5,24:2,55:3,60:8,89:8,204:1,212:4,217:4","11:6,24:2,55:14,89:10,205:2,212:9","8:1,11:4,16:1,55:5,61:5,67:1,89:13,205:2,212:4,217:4","7:9,55:5,62:6,74:1,88:14,213:9","6:10,23:1,55:12,73:4,88:14,213:9","6:10,23:1,55:9,65:2,73:7,88:4,93:9,206:2,213:9","6:10,23:1,55:10,72:12,87:5,93:7,206:3,214:4,219:2","6:3,11:4,21:1,56:8,73:1,75:11,87:5,93:6,207:2,214:1,216:2,222:1","5:6,12:3,20:3,58:3,73:26,207:2,215:2","5:7,13:1,20:3,73:3,77:2,80:19,207:3,215:3,220:1,222:1","5:9,19:3,42:3,55:3,73:10,84:7,92:7,110:3,208:2,215:2,220:4","5:9,19:3,42:6,54:5,79:20,109:4,208:3,215:1,220:4","5:9,19:2,42:8,52:7,80:12,93:2,96:6,107:6,208:2,219:4","5:9,19:2,42:13,56:3,84:30,209:2,220:2","5:8,19:2,42:18,66:2,85:1,88:11,100:7,108:7,210:1,219:1","4:9,19:2,42:15,58:3,66:4,84:9,94:21,210:1,218:2","4:9,42:20,65:7,84:7,92:4,97:19,210:1,217:2,225:1","4:6,11:1,18:2,42:8,51:11,66:9,84:4,89:2,92:2,95:6,102:14,210:2,217:2","3:6,17:3,42:8,52:11,66:12,84:7,92:4,100:17,210:2,217:3,224:1","3:5,17:3,46:1,48:16,66:15,83:9,93:3,102:2,105:3,109:9,158:2,210:1,217:3,224:2","3:5,17:2,49:8,58:6,65:8,74:18,93:2,105:4,110:6,117:1,158:3,211:2,217:4,223:3","2:5,17:2,49:8,58:5,66:6,73:22,109:9,157:6,211:2,218:3,225:1","2:6,9:2,17:1,48:8,57:6,69:26,111:6,158:7,211:2,217:1,220:1,225:2","3:2,7:1,9:2,16:2,48:12,73:6,80:14,114:2,137:3,158:10,211:3,218:1,220:1,223:1","7:1,9:2,16:2,48:11,73:1,76:19,107:3,137:4,158:12,211:3,218:3","8:2,16:3,47:9,57:2,72:3,78:21,106:4,136:6,158:13,212:1,219:3,226:1","2:1,6:2,10:1,16:2,48:11,71:6,82:20,104:7,135:6,158:5,164:4,170:2,219:7","16:2,47:12,71:2,74:4,84:9,95:16,135:7,158:4,165:4,170:3,219:7","16:2,46:12,71:3,75:4,87:10,98:14,137:6,158:5,165:8,219:8","2:1,17:1,46:4,51:7,72:9,90:23,132:3,137:9,158:6,165:8,219:9","2:1,15:1,46:11,72:9,85:2,92:2,95:18,131:18,158:4,163:5,169:4,219:8","1:2,15:1,46:11,64:3,73:3,77:5,84:3,88:1,96:5,102:12,130:22,158:14,212:1,219:6,226:2","6:1,15:3,45:1,47:10,63:5,73:10,84:7,99:15,129:27,158:13,212:1,220:8","15:3,44:2,47:9,63:7,74:8,84:2,87:6,102:13,127:44,221:7","16:1,44:8,53:3,63:8,74:22,102:14,126:5,132:4,138:25,164:5,222:7","16:1,44:6,53:3,64:7,74:8,83:14,101:15,125:15,143:12,156:13,222:6","44:7,52:2,55:1,64:9,74:7,83:11,95:2,101:16,125:14,146:9,157:1,159:7,167:3,213:1,221:7","1:3,44:10,65:9,75:5,83:6,90:7,100:16,125:14,150:24,213:1,221:7","1:3,16:1,44:11,65:10,76:3,82:14,99:3,103:12,125:13,153:10,165:11,190:2,220:8","15:2,43:12,65:10,81:13,98:13,112:2,126:12,159:5,165:14,188:5,214:1,222:7","15:2,42:13,66:9,81:12,98:10,126:12,159:2,165:17,187:6,223:6","1:1,5:1,16:1,42:12,66:5,72:3,81:12,98:8,126:11,162:2,165:7,173:6,180:14,223:6","0:2,15:2,42:3,46:8,57:3,65:10,80:13,99:2,127:9,138:2,165:6,172:22,223:5","0:2,14:3,42:4,47:7,57:6,66:8,80:13,128:7,137:5,168:27,213:1,222:6","3:1,8:1,14:3,41:5,47:6,57:8,67:6,80:12,130:3,137:8,172:18,192:4,213:1,222:7","7:2,14:2,41:5,47:6,57:15,80:7,88:4,137:11,174:3,178:18,212:3,220:9","1:3,5:4,41:11,57:1,59:6,66:5,79:12,137:14,179:18,213:3,222:6","1:9,41:11,56:1,60:2,63:5,69:4,78:6,86:5,138:15,181:16,213:2,223:6","1:9,16:1,40:2,43:16,60:12,73:3,78:12,137:21,172:2,182:16,214:2,222:8","1:8,15:2,36:5,43:13,57:2,60:11,72:10,83:7,137:5,143:17,170:4,182:16,214:2,220:1,222:7","1:8,14:3,35:24,62:5,68:15,84:5,138:25,169:6,181:18,213:2,221:8","1:2,5:3,15:2,35:24,65:1,67:16,84:1,86:3,100:3,143:4,148:18,167:2,170:5,180:19,213:2,220:2,224:2,227:2","1:7,9:1,15:2,36:15,52:6,67:12,81:4,87:2,99:4,146:12,159:10,170:6,179:19,213:1,220:1,224:5","1:2,6:4,15:1,36:21,71:14,87:2,97:7,122:3,149:4,154:15,170:6,179:19,213:2,219:2,225:1,227:2","3:1,6:3,36:2,39:16,73:20,96:8,122:2,125:3,153:16,171:4,176:1,179:11,191:1,193:1,196:1,213:2,219:2,224:4","3:7,16:1,36:1,39:9,49:5,73:11,85:20,122:6,130:1,156:15,172:5,179:8,213:2,219:9","2:8,16:1,37:1,39:2,42:11,72:33,122:12,159:19,180:2,219:9","2:9,15:2,37:1,39:8,48:4,71:17,89:17,122:14,161:18,212:2,223:5","1:9,16:2,37:13,69:5,76:6,83:2,86:21,122:18,165:14,212:3,223:5","1:9,16:2,38:11,68:17,87:20,122:3,126:17,167:13,212:3,223:5","1:9,16:2,38:9,66:18,90:18,122:12,135:8,144:2,170:9,212:2,219:1,222:6","2:9,16:2,38:9,65:7,73:13,93:16,127:9,139:3,143:7,172:6,212:2,219:8","3:8,16:3,38:6,61:11,74:13,96:13,130:7,138:15,175:3,205:2,212:2,219:8","3:8,16:3,38:5,59:15,75:3,79:10,99:10,134:11,147:9,212:2,219:9","2:10,16:3,39:5,54:9,64:15,81:6,88:2,102:6,137:7,148:9,211:2,218:9","2:6,10:2,17:2,41:1,48:1,51:12,64:14,82:10,105:3,137:5,147:9,159:2,182:2,211:3,218:9","3:9,17:2,47:10,59:11,71:4,83:10,137:6,147:9,158:7,181:4,218:5,224:3","3:9,17:1,19:1,46:9,56:1,59:14,83:3,87:8,136:11,149:7,158:9,180:5,210:1,218:1,220:6","3:10,18:2,47:9,59:1,61:10,83:7,92:4,136:12,149:5,158:2,161:4,166:4,178:8,210:1,217:2,221:5","4:2,8:4,18:2,47:12,60:7,84:6,93:5,135:12,148:1,152:1,155:1,158:2,161:13,176:10,210:2,217:5","4:3,8:4,18:1,20:1,53:3,57:2,85:13,135:14,155:4,161:10,172:15,209:3,217:5,223:3","6:7,18:3,85:8,94:2,97:2,134:9,145:3,155:2,159:1,161:26,209:3,217:7","4:1,6:5,12:1,18:3,86:13,133:14,155:3,159:2,163:22,186:2,209:2,217:8","5:8,18:3,86:10,97:3,133:14,154:9,166:19,187:1,209:3,219:6","5:9,19:3,86:15,132:7,141:6,154:10,167:5,173:16,210:1,216:9","5:9,21:1,87:14,132:14,155:10,169:21,216:9","5:9,20:2,87:7,95:6,131:14,153:8,162:2,172:18,208:3,215:5,221:4","6:9,20:2,33:1,88:13,130:14,153:11,178:13,207:3,215:9","6:10,20:3,32:1,88:3,92:9,129:6,136:6,155:9,178:13,207:2,215:9","6:5,12:4,22:1,88:3,93:8,128:10,139:3,152:12,181:10,207:2,214:10","6:10,22:2,88:8,97:4,127:15,152:12,185:5,207:2,214:5,220:3","6:4,11:5,22:2,88:8,97:3,125:17,152:9,162:2,187:3,206:3,214:9","7:8,22:2,88:11,124:17,152:11,207:1,214:1,216:7","8:9,38:1,90:9,122:18,151:12,205:2,213:1,216:6","8:9,23:2,91:6,120:3,124:11,136:2,151:1,153:10,205:3,213:9","8:6,16:2,23:3,93:2,118:4,123:14,150:5,156:1,158:4,204:3,212:9","9:5,15:3,24:2,115:6,122:1,124:2,127:1,129:6,150:12,204:3,211:3,215:7","9:9,111:9,122:2,125:3,129:5,150:11,203:3,211:10","9:6,17:1,26:1,110:10,123:1,125:6,149:12,178:3,203:1,211:10","9:9,109:10,124:6,149:12,177:5,202:2,210:6,217:4","10:1,14:2,17:3,26:2,109:9,119:2,124:2,149:11,177:4,202:3,211:5,218:2","11:1,15:3,19:1,26:3,109:11,148:4,153:7,176:5,201:4,210:6,218:1","12:6,26:3,148:4,156:5,175:6,201:3,209:7,217:2","12:7,20:1,27:3,148:8,157:6,175:6,201:3,209:10","12:7,20:1,27:3,148:6,156:2,159:2,162:4,174:7,200:3,210:3,216:2","12:6,20:2,28:3,148:2,153:8,165:4,173:8,199:3,207:4,216:2","12:5,20:2,28:1,30:1,148:1,151:1,154:4,159:3,164:8,173:5,179:2,199:1,201:1,207:1,209:4,215:3","14:3,18:1,22:2,149:4,154:21,176:5,198:2,206:7,215:1","15:9,31:1,150:6,158:15,174:1,176:5,198:3,206:9","15:9,31:2,149:21,171:2,174:7,197:3,205:10","15:9,31:3,150:20,171:3,176:6,196:4,205:7,213:2","16:6,23:2,31:2,151:13,165:2,169:12,196:3,205:1,207:5,213:1","16:6,24:1,153:18,172:10,195:2,204:7,212:1","17:1,19:1,25:1,155:28,194:4,203:7,211:2","16:3,23:1,35:2,156:2,160:13,174:9,195:2,202:8,211:1","17:2,20:3,25:3,34:3,160:2,163:10,175:8,193:3,201:11","21:7,34:1,36:1,163:20,192:3,201:10","19:7,27:1,37:2,165:17,192:2,200:11","20:8,37:2,169:13,191:3,199:12","21:2,24:5,37:1,39:1,172:9,190:2,199:11","21:5,29:2,198:7,206:3","21:3,26:6,39:3,188:2,198:11","23:1,26:2,29:4,40:2,187:4,198:10","23:8,187:3,197:10","24:10,186:3,195:4,200:7","24:4,29:2,32:3,44:1,185:2,194:4,200:6","27:9,43:3,183:4,193:13","27:9,44:3,183:3,194:11","27:10,44:4,182:1,184:1,194:3,200:4","27:3,31:1,34:3,45:4,181:3,191:1,193:4,200:3","28:7,36:1,48:2,180:4,190:7,198:3","28:7,38:3,48:3,178:5,189:6,196:1,199:1","29:3,34:3,39:2,48:4,177:4,188:10","31:1,33:10,49:5,179:1,187:12","31:5,37:3,41:3,53:2,187:12","32:7,41:4,173:2,188:6,195:2","33:12,175:1,186:3,190:4,195:1","35:1,37:9,183:12","36:5,42:5,184:1,187:1,189:5","36:12,169:1,187:1,190:3","37:7,45:3,61:1,167:2,185:3,190:2","38:6,45:1,165:5,187:1,190:1","39:7,52:1,64:2,164:5,176:3,184:1,186:1","40:7,51:2,64:3,162:5,175:4,184:3","41:6,51:1,64:6,160:1,162:3,185:2","42:6,51:1,53:4,66:5,158:3,162:1,176:1,184:2","43:4,52:1,54:4,68:2,72:1,157:5","44:1,52:2,55:2,68:7,154:6,169:2","51:3,55:2,60:1,72:4,152:5,167:4","51:6,58:1,60:2,73:7,149:7,166:5","51:11,76:7,147:7,164:7","50:8,60:2,64:3,77:7,143:7,162:13","50:6,57:1,60:2,63:5,79:4,84:5,141:8,159:4,164:7,173:3","52:6,60:8,83:7,136:2,139:8,158:13,173:3","53:4,60:4,65:3,70:3,85:11,133:4,138:1,140:3,155:5,161:10","55:3,60:9,70:5,88:3,92:11,128:6,135:3,140:1,155:17","59:6,66:7,75:3,93:4,99:12,117:2,121:4,126:4,133:4,151:4,157:5,163:8","59:6,66:8,75:4,97:1,100:1,102:4,107:3,112:1,114:1,118:2,124:7,150:5,157:13","60:5,66:8,75:8,103:3,108:1,113:2,117:4,145:22","62:3,67:1,69:16,143:6,150:10,162:4","65:2,68:3,72:9,82:8,138:1,140:14,155:5,161:4","67:14,82:14,133:2,137:3,141:21","68:32,131:19,151:9","72:20,93:3,98:6,109:1,114:4,119:3,123:3,130:3,134:2,137:13,152:5","73:19,94:10,108:3,113:11,125:1,132:12,145:2,148:8","75:9,85:20,109:2,113:11,133:1,135:2,138:9,148:3","79:27,107:10,118:6,133:3,138:2,141:9","81:13,95:28,134:1,138:8","86:37,133:3,138:3,142:2","91:7,100:3,104:20,126:1,132:3,136:2","92:2,95:3,99:15,115:3,119:6,126:2","103:23","107:1,115:3",""},
}
local function stampState(percent)
    if percent<=1 then return 'pending' end
    if percent>=99 then return 'finished' end
    return 'reading'
end
local function paintStamp(bb,paper,x,y,w,h,radius,count,pitch,side_y,side_r)
    local rows=STAMPS[paper.stamp]
    if not rows then return end
    local size=paper.stamp_size
    local left,top=math.floor(x+w-size*.82),math.floor(y-size*.14)
    local function onPaper(px,py)
        if px<x or px>=x+w or py<y or py>=y+h then return false end
        -- Stamp ink is absent in the receipt's scalloped cutouts as well as beyond its edges.
        if py-y<radius or y+h-1-py<radius then
            for i=0,count-1 do
                local cx=math.floor(x+radius*1.5+i*pitch)
                local dy=py-y<radius and py-y or py-(y+h-1)
                if (px-cx)^2+dy^2<=radius^2 then return false end
            end
        end
        if (px-x)^2+(py-side_y)^2<=side_r^2 or (px-(x+w-1))^2+(py-side_y)^2<=side_r^2 then return false end
        return true
    end
    for row,runs in ipairs(rows) do
        local ya=top+math.floor((row-1)*size/STAMP_SIZE)
        local yb=top+math.floor(row*size/STAMP_SIZE)-1
        for start,length in runs:gmatch('(%d+):(%d+)') do
            local xa=left+math.floor(tonumber(start)*size/STAMP_SIZE)
            local xb=left+math.floor((tonumber(start)+tonumber(length))*size/STAMP_SIZE)-1
            for py=math.max(y,ya),math.min(y+h-1,yb) do
                local run_start
                for px=math.max(x,xa),math.min(x+w-1,xb) do
                    if onPaper(px,py) then run_start=run_start or px
                    elseif run_start then bb:paintRect(run_start,py,px-run_start,1,Blitbuffer.COLOR_BLACK);run_start=nil end
                end
                if run_start then bb:paintRect(run_start,py,math.min(x+w-1,xb)-run_start+1,1,Blitbuffer.COLOR_BLACK) end
            end
        end
    end
end

local ReceiptPaper = WidgetContainer:extend{
    padding_top = 28, padding_bottom = 30,
    padding_left = 28, padding_right = 28, shadow_width = 8,
}
function ReceiptPaper:getSize()
    local size = self[1]:getSize()
    return Geom:new{
        w = size.w + self.padding_left + self.padding_right + self.shadow_width,
        h = size.h + self.padding_top + self.padding_bottom,
    }
end
function ReceiptPaper:paintTo(bb, x, y)
    local sz = self:getSize()
    self.dimen = Geom:new{x=x,y=y,w=sz.w,h=sz.h}
    local ink, white = Blitbuffer.COLOR_GRAY_3, Blitbuffer.COLOR_WHITE
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
    bb:paintBorder(x, y, w, h, 1, ink, 0)
    -- 先渲染边缘脏印，再挖齿孔和侧面缺口：缺口内仍是干净的纸外背景。
    -- 最后才绘制正文，因此任何脏印都不会覆盖文字或二维码。
    printEdgePatina(bb, x, y, w, h,
        self.padding_top, self.padding_bottom, self.padding_left, self.padding_right)
    -- 一排连贯的半圆缺口。先挖洞再画弧线，只保留纸内侧半圆。
    local count = math.max(3, math.floor((w-radius*3) / (radius*2.9)))
    local pitch = (w-radius*3)/(count-1)
    for i=0,count-1 do
        local cx=math.floor(x+radius*1.5+i*pitch)
        for _,edge in ipairs({'top','bottom'}) do
            local cy=(edge=='top') and y or (y+h-1)
            restoreCircle(cx,cy,radius)
            bb:paintCircle(cx,cy,radius,ink,1)
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
        bb:paintCircle(cx,side_y,side_r,ink,1)
        if edge=='left' then
            restoreRect(cx-side_r-2,side_y-side_r-2,side_r+3,2*side_r+4)
        else
            restoreRect(cx+1,side_y-side_r-2,side_r+3,2*side_r+4)
        end
    end
    under:free()
    self[1]:paintTo(bb,x+self.padding_left,y+self.padding_top)
    paintStamp(bb,self,x,y,w,h,radius,count,pitch,side_y,side_r)
end

local PrintRule = WidgetContainer:extend{width=400, height=2, kind='dash', scale=1}
function PrintRule:getSize()
    if self.kind=='vertical' then return Geom:new{w=math.max(1,math.floor(self.scale+0.5)),h=self.height} end
    return Geom:new{w=self.width,h=self.height}
end
function PrintRule:paintTo(bb,x,y)
    local sz=self:getSize()
    self.dimen=Geom:new{x=x,y=y,w=sz.w,h=sz.h}
    if self.kind=='vertical' then
        bb:paintRect(x,y,sz.w,self.height,Blitbuffer.COLOR_GRAY_5)
    elseif self.kind=='solid' then
        bb:paintRect(x,y,self.width,self.height,Blitbuffer.COLOR_BLACK)
    else
        -- 印刷虚线：细短点划，阅读高对比墨水屏下不糊成整条。
        local mark,gap=math.max(1,math.floor(8*self.scale+0.5)),math.max(1,math.floor(7*self.scale+0.5))
        for i=0,self.width-1,mark+gap do
            bb:paintRect(x+i,y,math.min(mark,self.width-i),self.height,Blitbuffer.COLOR_GRAY_3)
        end
    end
end

-- ---------- 仿热敏纸印迹 ----------
-- 只处理文字组件本身的已印墨点，不覆盖白底、不处理封面与二维码。
-- 逐点按固定散列产生掉墨/浅印，跨次重绘一致，不会出现随机闪烁。
-- wrapper 的 getSize 与原组件相同：不改变 v2.3 的任何布局尺寸和位置。
local InkWear = WidgetContainer:extend{wear_level=1, wear_seed=1}
function InkWear:getSize()
    return self[1]:getSize()
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

local ReadingBars=WidgetContainer:extend{}
function ReadingBars:getSize() return Geom:new{w=self.width,h=self.height} end
function ReadingBars:paintTo(bb,x,y)
    self.dimen=Geom:new{x=x,y=y,w=self.width,h=self.height}
    local fs=self.font_size
    local function label(text,lx,ly,width,align)
        local t=TextBoxWidget:new{text=text,face=Font:getFace('cfont',fs),
            width=width,alignment=align or 'left',justified=false}
        t:paintTo(bb,lx,ly);t:free()
    end
    local font_px=Font:getFace('cfont',fs).size
    local left=math.floor(font_px*3.4)
    local top=math.floor(font_px*.3)
    local bottom=self.height-math.floor(font_px*1.8)
    local right=self.width-math.max(2,self.stroke)
    local peak=0
    for _,day in ipairs(self.data.days) do peak=math.max(peak,(day.seconds or 0)/60) end
    local ceiling=math.max(30,math.ceil(peak/30)*30)
    label(tostring(ceiling)..'分',x,y+top,left,'left')
    label('0',x,y+bottom-math.floor(font_px*.9),left,'left')
    for _,gy in ipairs({bottom}) do
        for gx=left,right,7 do bb:paintRect(x+gx,y+gy,2,1,Blitbuffer.COLOR_GRAY_9) end
    end
    local n=#self.data.days
    local cell=(right-left)/n
    local bw=math.max(1,math.floor(cell*.58))
    for i,day in ipairs(self.data.days) do
        local gx=left+math.floor((i-.5)*cell)
        if day.seconds and day.seconds>0 then
            local bh=math.max(1,math.floor((bottom-top)*day.seconds/60/ceiling+.5))
            bb:paintRect(x+gx-math.floor(bw/2),y+bottom-bh,bw,bh,Blitbuffer.COLOR_BLACK)
        end
        if n==7 or i==1 or i==n or (day.day%5==0 and i<n-1) then
            local lw=math.floor(font_px*2)
            local lx=math.max(0,math.min(self.width-lw,gx-math.floor(lw/2)))
            label(n==7 and ({'一','二','三','四','五','六','日'})[i] or tostring(day.day),
                x+lx,y+bottom+math.floor(font_px*.25),lw,'center')
        end
    end
end

local ReceiptHeading=WidgetContainer:extend{}
function ReceiptHeading:init()
    self.glyphs={};self.width=0;self.ascent=0;local descent=0
    local gap=math.max(1,math.floor(self.face.size*.04+.5))
    for char in self.text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        local glyph=assert(RenderText:getGlyph(self.face,ffiUtil.utf8charcode(char),self.bold),'标题字形无法加载')
        local width=glyph.bb:getWidth()
        self.glyphs[#self.glyphs+1]={glyph=glyph,x=self.width}
        self.width=self.width+width+gap
        self.ascent=math.max(self.ascent,glyph.t)
        descent=math.max(descent,glyph.bb:getHeight()-glyph.t)
    end
    self.width=math.max(0,self.width-gap);self.height=self.ascent+descent
end
function ReceiptHeading:getSize()
    if not self.glyphs then self:init() end
    return Geom:new{w=self.width,h=self.height}
end
function ReceiptHeading:paintTo(bb,x,y)
    for _,item in ipairs(self.glyphs) do
        local glyph=item.glyph
        bb:colorblitFrom(glyph.bb,x+item.x,y+self.ascent-glyph.t,0,0,
            glyph.bb:getWidth(),glyph.bb:getHeight(),Blitbuffer.COLOR_BLACK)
    end
end

-- Book words are progress estimates; only wake-session words use visited ranges.
Inkfolio.wordPath=DataStorage:getSettingsDir()..'/read_receipt_v2_words.lua'
Inkfolio.wordState={books={},session={},session_total=0,sleeping=false,errors={}}
if lfs.attributes(Inkfolio.wordPath,'mode')=='file' then
    local ok,data=pcall(dofile,Inkfolio.wordPath)
    if ok and type(data)=='table' and (data.version==1 or data.version==2) and type(data.books)=='table' then
        for path,book in pairs(data.books) do
            if type(path)~='string' or type(book)~='table' or type(book.signature)~='string'
                or (book.document_total~=nil and (type(book.document_total)~='number' or book.document_total<0
                    or book.document_total>=math.huge or book.document_total~=math.floor(book.document_total))) then
                Inkfolio.wordState.storage_error='字数记录损坏';break
            end
            Inkfolio.wordState.books[path]={signature=book.signature,document_total=book.document_total}
        end
    else Inkfolio.wordState.storage_error='字数记录损坏' end
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
        state.errors[path]='格式不支持';state.session_error='部分内容不支持字数统计';return
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
    end)
    if not ok then
        state.errors[path]='本次字数记录不完整';state.session_error='本次字数记录不完整'
        logger.warn('Inkfolio wake words failed',reason)
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
    if not ok then logger.warn('Inkfolio book words failed',amount);return nil,tostring(amount):match(': (.*)$') or tostring(amount) end
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
        assert(file:write('return '..require('dump')({version=2,books=state.books},nil,true)..'\n'))
        assert(file:flush());assert(ffiUtil.fsyncOpenedFile(file));assert(file:close());file=nil
        assert(os.rename(temporary,Inkfolio.wordPath));assert(ffiUtil.fsyncDirectory(Inkfolio.wordPath))
    end)
    if file then file:close() end
    if not ok then os.remove(temporary);state.storage_error='字数记录保存失败';logger.warn('Inkfolio word save failed',err)
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

local function formatWordCount(amount)
    assert(type(amount)=='number' and amount>=0 and amount<math.huge and amount==math.floor(amount),'字数无效')
    if amount<10000 then return string.format('%.0f字',amount) end
    return string.format('%.1f万字',amount/10000)
end

local function renderReceipt(ui, state, appearance)
    if not ui or not ui.document then return nil end
    appearance=appearance or {}
    local factor=tonumber(appearance.width or G_reader_settings:readSetting(S.width)) or 0.72
    local scaler=tonumber(appearance.font or G_reader_settings:readSetting(S.font)) or 1
    local scale=tonumber(appearance.scale or G_reader_settings:readSetting(S.scale)) or 1
    local base_width=math.min(Screen:getWidth(),Screen:getHeight()*.75)
    local paper_w=math.floor(base_width*math.max(0.55,math.min(factor,0.90))*scale)
    local unit=paper_w/720
    local line_width=math.max(1,math.floor(scale+0.5))
    local function px(size) return math.max(1,math.floor(size*unit+0.5)) end
    local pad=px(25)
    local w=paper_w-2*pad
    -- Font:getFace scales its argument by DPI; widget dimensions are physical pixels.
    -- Express both in the same 720-pixel ticket design, independent of UI scaling.
    local font_unit=paper_w/Screen:scaleBySize(720)
    local function f(size) return math.max(1,math.floor(size*scaler*font_unit+0.5)) end
    local function missingTitleFont(name)
        return CenterContainer:new{
            dimen=Screen:getSize(),
            TextBoxWidget:new{
                text='小票标题字体无法加载：\n'..name..'\n请检查 KOReader 数据目录的 fonts 文件夹，再完全重启 KOReader。',
                face=Font:getFace('cfont',f(24)),
                width=math.floor(Screen:getWidth()*.78),
                alignment='center', justified=false,
            },
        }
    end
    -- Check at receipt build time: fonts added while KOReader is running need a restart.
    if not Font:getFace(TITLE_FONT,f(52)) then return missingTitleFont(TITLE_FONT) end
    if not Font:getFace(CHINESE_TITLE_FONT,f(36)) then return missingTitleFont(CHINESE_TITLE_FONT) end
    -- One hierarchy, in design units. Appearance changes scale every role together.
    local styles={
        book={size=50,title=true,bold=false},
        brand={size=36,title=true,bold=false},
        section={size=24,title=true,bold=true},
        subheading={size=20,title=true,bold=true},
        label={size=20,title=true,bold=false},
        value={size=24,bold=true},
        text={size=24,bold=false},
        percentage={size=30,bold=true},
        body={size=20,bold=false},
        small={size=16,bold=false},
        small_label={size=16,title=true,bold=false},
    }
    local function txt(value,role,width,align,lines)
        local style=assert(styles[role],'未知文字层级')
        local face=Font:getFace(style.title and CHINESE_TITLE_FONT or 'cfont',f(style.size))
        local widget=TextBoxWidget:new{
            text=tostring(value or ''),face=face,bold=style.bold,
            width=math.max(35,math.floor(width or w)),
            alignment=align or 'left',fgcolor=Blitbuffer.COLOR_BLACK,
            justified=false,line_height=0.3,
            height=lines and math.floor(face.size*1.3+0.5)*lines or nil,
            height_overflow_show_ellipsis=lines~=nil,height_adjust=lines~=nil,
        }
        return inkText(widget,value,(style.title or style.bold) and 3 or 2)
    end
    local function heading(value,role,width,align,lines)
        assert(styles[role].title,'标题层级必须使用标题字体')
        return txt(value,role,width,align,lines)
    end
    local function singleHeading(value,role,width)
        local style=assert(styles[role])
        local label=inkText(ReceiptHeading:new{text=value,face=Font:getFace(CHINESE_TITLE_FONT,f(style.size)),bold=style.bold},value,3)
        return HorizontalGroup:new{label,HorizontalSpan:new{width=math.max(0,width-label:getSize().w)}}
    end
    local function vg(n) return VerticalSpan:new{width=n>0 and px(n) or 0} end
    local function hg(n) return HorizontalSpan:new{width=n>0 and px(n) or 0} end
    local function rule(kind) return PrintRule:new{width=w,height=kind=='solid' and px(1) or line_width,kind=kind or 'dash',scale=scale} end
    local function pair(l,r,lw,rw)
        return HorizontalGroup:new{l,HorizontalSpan:new{width=math.max(0,w-lw-rw)},r}
    end
    local elements={}
    local function add(widget,space)
        elements[#elements+1]=widget
        if space and space>0 then elements[#elements+1]=vg(space) end
    end
    local book=extractBook(ui.doc_props,ui.document.file)
    local cache=cached(book)
    local stats=enabled(S.stats) and readStatistics(ui) or nil
    local doc=(ui.doc_settings and ui.doc_settings.data) or {}
    local page=tonumber(state and state.page) or 1
    local total=math.max(1,tonumber(ui.file_cover and doc.doc_pages or ui.document:getPageCount()) or 1)
    page=math.max(1,math.min(page,total))
    if ui.pagemap and ui.pagemap.wantsPageLabels and ui.pagemap:wantsPageLabels() then
        local _,idx,count=ui.pagemap:getCurrentPageLabel(true)
        if idx and count and count>0 then page,total=idx,count end
    end
    local pct=math.floor(page*100/total+0.5)

    -- 1. 票头：碑铭风格的雕刻衬线标题。仅改标题字体，不影响其他正文。
    local titlew=math.floor(w*.76)
    local sidew=w-titlew-px(10)-1
    local chinese_width=px(82)
    local english_width=titlew-chinese_width-px(12)
    -- Horizontal brand line, leaving the same region for the reading-state stamp.
    local function fittedHeading()
        local min_size=f(styles.text.size)
        for size=f(styles.brand.size),min_size,-1 do
            local face=Font:getFace(TITLE_FONT,size)
            if face then
                local widget=TextWidget:new{
                    text='INKFOLIO',face=face,fgcolor=Blitbuffer.COLOR_BLACK,
                    padding=0,bold=false,
                }
                if widget:getSize().w <= english_width then return widget,size end
            end
        end
        return nil
    end
    local engraved_heading,brand_size=fittedHeading()
    if engraved_heading then
        engraved_heading=inkText(engraved_heading,'INKFOLIO',3)
    end
    if not engraved_heading then
        return CenterContainer:new{
            dimen=Screen:getSize(),
            TextBoxWidget:new{
                text='墨笺标题宽度不足，请调大小票宽度或文字大小',
                face=Font:getFace('cfont',f(22)),width=math.floor(Screen:getWidth()*.8),
                alignment='center',justified=false,
            },
        }
    end
    local chinese_heading=TextWidget:new{text='墨笺',face=Font:getFace(CHINESE_TITLE_FONT,brand_size),padding=0}
    local english_widget=engraved_heading[1]
    chinese_heading:getSize();english_widget:getSize()
    -- Shared font size and baseline, using actual font metrics for the two typefaces.
    local brand_baseline=math.max(chinese_heading._baseline_h,english_widget._baseline_h)
    local brand_height=brand_baseline+math.max(chinese_heading._height-chinese_heading._baseline_h,english_widget._height-english_widget._baseline_h)
    for _,widget in ipairs({chinese_heading,english_widget}) do
        widget.forced_height=brand_height;widget.forced_baseline=brand_baseline
    end
    local chinese_label=inkText(chinese_heading,'墨笺',3)
    add(HorizontalGroup:new{align='top',
        HorizontalGroup:new{chinese_label,HorizontalSpan:new{width=math.max(0,chinese_width-chinese_label:getSize().w)}},hg(12),
        HorizontalGroup:new{engraved_heading,HorizontalSpan:new{width=math.max(0,english_width-engraved_heading:getSize().w)}},
        hg(10),HorizontalSpan:new{width=sidew+1},
    },15)
    add(rule('dash'),10)

    local date_gap=px(9)+px(10)+1
    local dl=math.floor((w-date_gap)*.43)
    local dr=w-date_gap-dl
    add(HorizontalGroup:new{align='top',
        VerticalGroup:new{heading('日期','label',dl,'left',1),vg(3),txt(os.date('%Y.%m.%d'),'text',dl,'left',2)},
        hg(9),PrintRule:new{kind='vertical',height=px(58),scale=scale},hg(10),
        VerticalGroup:new{heading('天气','label',dr,'left',1),vg(3),txt(weatherText(),'text',dr,'left',2)},
    },12)
    add(rule('dash'),13)

    -- 2. 书目：书名像机打商品主项；元数据是附注，封面固定为窄幅辅助图。
    local cover,coverw
    if enabled(S.cover) and ui.bookinfo and ui.document then
        local cover_document=ui.document
        if ui.file_cover then cover_document=nil end
        local ok,bb=pcall(ui.bookinfo.getCoverImage,ui.bookinfo,
            cover_document,ui.file_cover and ui.document.file or nil)
        if ok and bb then
            local maxw=math.floor(w*.275)
            local maxh=math.floor(base_width*(4/3)*.175*scale)
            local sc=math.min(scale*1.25,maxw/bb:getWidth(),maxh/bb:getHeight())
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
        return HorizontalGroup:new{
            heading(label,'label',labelw,'left',1),hg(7),
            txt(value,'body',detailw-labelw-px(7),'left',2),
        }
    end
    if book.authors~='' then
        desc[#desc+1]=metadata('作者',shortText(book.authors,50))
        desc[#desc+1]=vg(4)
    end
    if book.publisher~='' then
        desc[#desc+1]=metadata('出版社',shortText(book.publisher,44))
        desc[#desc+1]=vg(4)
    end
    if enabled(S.score) then
        local mark=cache and (scoreStars(cache.rating)..'  '..string.format('%.1f/10',cache.rating)) or '暂无评分'
        desc[#desc+1]=txt(mark,cache and 'value' or 'body',detailw,'left',1)
        if cache and (cache.score_kind=='volumes' or cache.score_kind=='versions') then desc[#desc+1]=vg(3);desc[#desc+1]=txt(cache.score_kind=='volumes' and '已匹配分册均分' or '已匹配版本均分','body',detailw,'left',1) end
    end
    if cover then add(HorizontalGroup:new{VerticalGroup:new(desc),hg(14),cover},11)
    else add(VerticalGroup:new(desc),11) end
    add(rule('solid'),10)

    -- 3. 条目明细：固定列宽并右对齐数字，不用居中卡片或过多标题。
    local keyw=math.floor(w*.45)
    local valw=w-keyw
    local function row(key,value,key_role,value_role)
        return pair(heading(key,key_role or 'label',keyw,'left',1),
            txt(value,value_role or 'value',valw,'right',1),keyw,valw)
    end
    add(row('阅读进度',tostring(pct)..'%','section','percentage'),8)
    add(ProgressWidget:new{width=w,height=px(8),
        percentage=page/total,radius=0,bordersize=0,margin_v=0,margin_h=0,
        bgcolor=Blitbuffer.COLOR_GRAY_9,fillcolor=Blitbuffer.COLOR_BLACK},9)
    local chapter
    if ui.toc then
        local ok,value=pcall(ui.toc.getTocTitleByPage,ui.toc,tonumber(state and state.page) or 1)
        if ok then chapter=value end
    end
    local chapter_width=math.floor(w*.24)
    add(pair(heading('章节','label',chapter_width,'left',1),
        txt(chapter and chapter~='' and shortText(chapter,60) or '—','text',w-chapter_width,'right',2),chapter_width,w-chapter_width),4)
    add(row('已读页数',string.format('%d / %d 页',page,total)),4)
    if Inkfolio.progressEnabled(S.word_book) then
        local amount,reason=Inkfolio.estimatedWords(ui,page/total)
        add(row('本书已读',amount and formatWordCount(amount) or reason),4)
    end
    if Inkfolio.progressEnabled(S.word_session) then
        local amount,reason=Inkfolio.wakeWords(ui)
        add(row('唤醒已读',amount and formatWordCount(amount) or reason),4)
    end
    if Inkfolio.progressEnabled(S.remain) then
        local avg=ui.statistics and tonumber(ui.statistics.avg_time)
        add(row('预计剩余',avg and avg>0 and duration((total-page)*avg) or '—'),4)
    end

    -- Attach the side notches to the actual summary separator, including optional rows.
    local stub_y=0
    for _,widget in ipairs(elements) do stub_y=stub_y+widget:getSize().h end
    -- 4. 阅读摘要：最多两项；只有一项时居中显示。
    local summaries=summaryItems()
    local curve_period=G_reader_settings:readSetting(S.curve)
    local show_curve=curve_period=='week' or curve_period=='month'
    if enabled(S.stats) and (#summaries>0 or show_curve) then
        add(rule('dash'),5)
        add(heading('阅读摘要','section',w,'center',1),5)
        local summary_gap=px(10)+px(11)+line_width
        local half=math.floor((w-summary_gap)/2)
        local other=w-summary_gap-half
        local function statblock(label, pages, seconds, ww)
            local kw=math.floor(ww*.43)
            local rw=ww-kw
            return VerticalGroup:new{
                heading(label,'subheading',ww,'center',1),vg(9),
                HorizontalGroup:new{
                    heading('页数','label',kw,'left',1),
                    txt(pages,'value',rw,'right',1),
                },vg(8),
                HorizontalGroup:new{
                    heading('时长','label',kw,'left',1),
                    txt(seconds,'value',rw,'right',1),
                },
            }
        end
        local function block(item,width)
            local values=stats and stats[item.id]
            return statblock(item.label,values and (values.pages..'页') or '—',
                values and duration(values.time) or '—',width)
        end
        if #summaries==1 then
            local single=block(summaries[1],half)
            add(CenterContainer:new{dimen=Geom:new{w=w,h=single:getSize().h},single},5)
        elseif #summaries==2 then
            add(HorizontalGroup:new{
                block(summaries[1],half),
                hg(10),PrintRule:new{kind='vertical',height=px(104),scale=scale},hg(11),
                block(summaries[2],other),
            },5)
        end
        if show_curve then
            if #summaries>0 then add(rule('dash'),8) end
            local chart,reason=Inkfolio.readCurve(ui,curve_period)
            local label=curve_period=='week' and '本周全局阅读时长' or '本月全局阅读时长'
            if chart then
                local lw=math.floor(w*.43)
                add(HorizontalGroup:new{align='top',heading(label,'subheading',lw,'left',1),
                    txt('日均 '..duration(chart.average)..' · 总时长 '..duration(chart.total),'small',w-lw,'right',2)},5)
                add(ReadingBars:new{width=w,height=px(118),font_size=f(styles.small.size),stroke=px(4),data=chart},12)
            else add(heading(label,'subheading',w,'left',1),5);add(txt(reason,'small',w,'center',1),12) end
        end
    end

    -- 5. 票根备注：左三行真实书籍简介，右可扫描的豆瓣详情二维码。
    local intro=enabled(S.intro) and (book.description~='' and book.description or (cache and cache.intro or '')) or ''
    local intro_heading=cache and cache.intro_volume and book.description=='' and ('书籍简介 · '..(type(cache.intro_volume)=='number' and ('第'..cache.intro_volume..'册') or cache.intro_volume)) or '书籍简介'
    local qr
    if enabled(S.qr) and cache and validURL(cache.url) and
        (book.description~='' or (type(cache.intro)=='string' and cache.intro~='')) then
        local size=math.floor(base_width*.105*scale)
        local ok,obj=pcall(function() return QRWidget:new{text=cache.url,width=size,height=size} end)
        if ok and obj and obj.image then
            qr=FrameContainer:new{bordersize=0,padding=math.max(1,math.floor(4*scale+0.5)),background=Blitbuffer.COLOR_WHITE,obj}
        end
    end
    if intro~='' or qr then
        add(rule('dash'),12)
        if intro~='' and qr then
            local qw=qr:getSize().w
            local tw=w-qw-px(13)
            add(HorizontalGroup:new{
                VerticalGroup:new{
                    singleHeading(intro_heading,'section',tw),vg(6),
                    txt(intro,'body',tw,'left',3),
                },hg(13),qr,
            },12)
        elseif intro~='' then
            add(singleHeading(intro_heading,'section',w),6)
            add(txt(intro,'body',w,'left',3),12)
        else
            add(CenterContainer:new{dimen=Geom:new{w=w,h=qr:getSize().h},qr},12)
        end
    end
    add(rule('solid'),9)
    -- 票尾小字，辅助信息保持低存在感。
    local battery=Device:hasBattery() and Device:getPowerDevice():getCapacity() or nil
    local cw=math.floor(w*.25)
    local battery_labelw=px(40)
    local battery_widget=HorizontalGroup:new{
        heading('电量','small_label',battery_labelw,'left',1),hg(6),
        txt(battery and (tostring(battery)..'%') or '—','small',cw-battery_labelw-px(6),'left',1),
    }
    add(HorizontalGroup:new{battery_widget,
        txt(G_reader_settings:readSetting(S.footer) or '','small',w-cw,'right',1)},9)
    local paper=ReceiptPaper:new{
        padding_top=pad,padding_bottom=pad,padding_left=pad,padding_right=pad,
        stub_y=stub_y,shadow_width=px(8),
        stamp=stampState(pct),stamp_size=px(132),
        VerticalGroup:new(elements),
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
    if G_reader_settings:readSetting(S.auto_fit)~=true or not ui or not ui.document then return false end
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
    local choice=appearance and appearance.background or G_reader_settings:readSetting(S.background) or 'white'
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
    if not path then return nil,'尚未阅读书籍，打开一本书后即可显示墨笺。' end
    if lfs.attributes(path,'mode')~='file' then
        return nil,'最近阅读的书籍已移动或删除，请重新打开书籍。'
    end
    local saved=store:readSetting('last_receipt')
    if not saved or saved.file~=path then
        return nil,'最近阅读的书籍尚无墨笺记录，请打开该书并返回主页一次。'
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
            if key==bookKey(extractBook(ui.doc_props,ui.document.file)) then
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
        assert(valid,'墨笺无法完整显示，请减小比例或检查字体。')
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
        Inkfolio.message('墨笺截图失败：'..tostring(err))
    else Inkfolio.message('墨笺截图已保存：\n'..path) end
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
    Inkfolio.resumeWords()
    RUN.sleeping=false
    RUN.cancelled_wake=false
    dailyCheck(true)
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
    resetDay()
    dailyCheck()
    if DAILY_DONE then currentCheck() end
    startPoll()
end
local function bookOpened()
    UIManager:nextTick(function()
        if RUN.sleeping or not networkingEnabled() then return end
        dailyCheck(true)
        -- When an initial library job is running, the current book is already first.
        if DAILY_DONE then currentCheck() end
        startPoll()
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
end
UIManager:scheduleIn(3,function() awake() end)

-- Render at the device resolution, then shrink the actual pixels for editing.
local AppearanceEditor=InputContainer:extend{modal=true,covers_fullscreen=true,name='inkfolio_appearance'}
function AppearanceEditor:init()
    self.draft={width=G_reader_settings:readSetting(S.width) or .72,
        font=G_reader_settings:readSetting(S.font) or 1,
        scale=G_reader_settings:readSetting(S.scale) or 1,
        background=G_reader_settings:readSetting(S.background) or 'white'}
    self.backdrop=Screen.bb:copy()
    -- Repaint the reading view without the settings menu for transparent previews.
    local live=ReaderUI.instance
    if live and live.document and live.view then live.view:paintTo(self.backdrop,0,0) end
    if (not live or not live.document) and FM and FM.instance then FM.instance:paintTo(self.backdrop,0,0) end
    self.refresh_callback=function()if not self.closed then self:refreshPreview() end end
    if Device:hasKeys() then self.key_events.Cancel={{Device.input.group.Back}} end
    self:refreshPreview()
end
function AppearanceEditor:change(key,value)
    Inkfolio.recordAction('外观调整操作')
    self.draft[key]=value
    UIManager:unschedule(self.refresh_callback)
    self.pending=true
    UIManager:scheduleIn(.5,self.refresh_callback)
end
function AppearanceEditor:refreshPreview()
    UIManager:unschedule(self.refresh_callback)
    self.pending=false
    local sw,sh=Screen:getWidth(),Screen:getHeight()
    local pad=math.max(4,math.floor(math.min(sw,sh)*.02))
    local gap=math.max(3,math.floor(sh*.006))
    local rowh=math.max(20,math.floor(sh*.055))
    local fs=math.max(8,math.min(18,math.floor(rowh/Screen:scaleBySize(2.7))))
    local width=sw-2*pad
    local title=TextWidget:new{text='墨笺外观 · '..sw..'×'..sh,max_width=width,face=Font:getFace('infofont',fs+2)}
    local receipt,valid=buildReceipt(self.ui,self.ui.view and self.ui.view.state,self.draft)
    assert(receipt,'Inkfolio appearance: missing book context')
    self.valid=valid==true
    local status=TextWidget:new{text=self.valid and '停下操作后更新预览；保存后应用' or '无法显示，请减小设置或检查字体',
        max_width=width,face=Font:getFace('infofont',fs)}
    local rows={}
    local button_padding=require('ui/size').padding.buttontable
    local function button(text,callback,enabled,bw)
        return {text=text,callback=callback,enabled=enabled~=false,width=bw,height=math.max(1,rowh-2*button_padding),
            font_size=fs,font_face='infofont'}
    end
    local function numeric(label,key,step,minval,maxval)
        local current=self.draft[key]
        rows[#rows+1]={
            button('−',function()self:change(key,math.max(minval,math.floor(self.draft[key]*100-step+.5)/100))end,current>minval),
            button(label..' '..math.floor(current*100+.5)..'%',nil,false,math.floor(width*.5)),
            button('+',function()self:change(key,math.min(maxval,math.floor(self.draft[key]*100+step+.5)/100))end,current<maxval)}
    end
    numeric('宽度', 'width',1,.55,.9)
    numeric('字号', 'font',5,.8,1.2)
    numeric('比例', 'scale',5,.5,1.5)
    local background={button('背景',nil,false)}
    for _,item in ipairs({{'白色','white'},{'黑色','black'},{'透明','transparent'}}) do
        local label,key=item[1],item[2]
        background[#background+1]=button(self.draft.background==key and ('['..label..']') or label,
            function()self:change('background',key)end)
    end
    rows[#rows+1]=background
    rows[#rows+1]={button('取消',function()self:onCancel()end),
        button('保存',function()self:save()end,self.valid)}
    local controls=require('ui/widget/buttontable'):new{width=width,buttons=rows,show_parent=self,
        addVerticalSpan=function(table_widget)
            table.insert(table_widget.container,VerticalSpan:new{width=gap})
        end}
    local available=sh-2*pad-title:getSize().h-status:getSize().h-controls:getSize().h-3*gap
    assert(available>0,'Inkfolio appearance controls exceed screen')
    local zoom=math.min(width/sw,available/sh)
    local pw,ph=math.max(1,math.floor(sw*zoom)),math.max(1,math.floor(sh*zoom))
    local canvas=Blitbuffer.new(sw,sh,self.backdrop:getType())
    local background_color=receiptBackground(self.draft)
    if background_color then canvas:fill(background_color)
    else canvas:blitFrom(self.backdrop,0,0,0,0,sw,sh) end
    receipt:paintTo(canvas,0,0)
    receipt:free()
    local bitmap=RenderImage:scaleBlitBuffer(canvas,pw,ph,true)
    local preview=CenterContainer:new{dimen=Geom:new{w=width,h=available},
        ImageWidget:new{image=bitmap,width=pw,height=ph,image_disposable=true}}
    local old=self[1]
    self[1]=FrameContainer:new{width=sw,height=sh,bordersize=0,margin=0,padding=pad,
        background=Blitbuffer.COLOR_WHITE,VerticalGroup:new{align='center',title,
            VerticalSpan:new{width=gap},preview,VerticalSpan:new{width=gap},status,
            VerticalSpan:new{width=gap},controls}}
    if old then old:free() end
    UIManager:setDirty(self,'ui')
end
function AppearanceEditor:save()
    Inkfolio.recordAction('外观保存')
    if self.pending then self:refreshPreview() end
    if not self.valid then return end
    for _,key in ipairs({'width','font','scale','background'}) do
        G_reader_settings:saveSetting(S[key],self.draft[key])
    end
    G_reader_settings:saveSetting(S.auto_fit,false)
    UIManager:close(self)
end
function AppearanceEditor:onCancel() UIManager:close(self);return true end
function AppearanceEditor:onSuspend() self:onCancel();return false end
AppearanceEditor.onSetRotationMode=AppearanceEditor.onSuspend
function AppearanceEditor:onCloseWidget()
    self.closed=true
    UIManager:unschedule(self.refresh_callback)
    if self.backdrop then self.backdrop:free();self.backdrop=nil end
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
        checked_func=function()return G_reader_settings:readSetting(S.weather_city)==nil end,
        callback=function()
            G_reader_settings:delSetting(S.weather_city)
            WEATHER.pending=false;store:saveSetting('weather',WEATHER);store:flush()
        end}}
    for _,region in ipairs(WEATHER_REGIONS) do
        local rows={}
        for _,city in ipairs(region.cities) do
            rows[#rows+1]={
                radio=true,text=city.name..(city.code=='' and '（气象台暂无数据）' or ''),
                enabled=city.code~='',keep_menu_open=true,
                checked_func=function() return city.code~='' and G_reader_settings:readSetting(S.weather_city)==city.code end,
                callback=function()
                    if city.code=='' then return end
                    if G_reader_settings:readSetting(S.weather_city)==city.code then return end
                    G_reader_settings:saveSetting(S.weather_city,city.code)
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
        {text='已读页数（固定）',checked_func=function()return true end,enabled=false},
    }
    for _,item in ipairs(PROGRESS_ITEMS) do
        local key=item.key
        local function available()return Inkfolio.progressEnabled(key) or Inkfolio.progressCount()<2 end
        rows[#rows+1]={text=item.label,keep_menu_open=true,
            help_text=key==S.word_book and '全书正文字数乘当前进度，属于折算值。' or key==S.word_session and '此次唤醒后实际翻阅的正文，同一位置去重。' or nil,
            checked_func=function()return Inkfolio.progressEnabled(key)end,
            enabled_func=available,callback=function()
                if not available() then return end
                G_reader_settings:saveSetting(key,not Inkfolio.progressEnabled(key))
            end}
    end
    return rows
end

local function summaryMenu()
    local rows={{text='显示摘要',keep_menu_open=true,
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
        rows[#rows+1]={text=item.label,keep_menu_open=true,checked_func=checked,
            enabled_func=available,callback=function()
                if not available() then return end
                local chosen={}
                local was_checked=checked()
                for _,selected in ipairs(summaryItems()) do
                    if selected.id~=item.id then chosen[#chosen+1]=selected.id end
                end
                if not was_checked then chosen[#chosen+1]=item.id end
                G_reader_settings:saveSetting(S.summary,chosen)
            end}
    end
    for _,item in ipairs({{id='week',label='本周时长柱状图'},{id='month',label='本月时长柱状图'}}) do
        rows[#rows+1]={text=item.label,keep_menu_open=true,
            checked_func=function()return G_reader_settings:readSetting(S.curve)==item.id end,
            enabled_func=function()return enabled(S.stats) end,
            callback=function()
                if not enabled(S.stats) then return end
                local chosen=G_reader_settings:readSetting(S.curve)
                if chosen==item.id then G_reader_settings:saveSetting(S.curve,false)
                else G_reader_settings:saveSetting(S.curve,item.id) end
            end}
    end
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
            nextLibraryScan=0
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
        title='更新日志 · v1.1.0',text="v1.1.0｜2026-10-13\n\n新增\n• 墨笺截图及设置、截图手势入口。\n• 周／月阅读时长柱状图及已读字数统计。\n• 图书匹配确认、重新检索、来源查询、复现记录及脱敏诊断导出。\n\n调整\n• 完善豆瓣匹配、评分均分及获取规则，减少重复联网。\n• 整理设置层级与界面，修复菜单图标、返回、取消和缓存保留问题。\n• 新用户默认黑色背景、关闭进度弹窗，首次显示时自动适配比例；旧用户设置保留。\n\n升级注意\n已安装 v1.0.0 的用户：本次补丁文件更名为 2-inkfolio.lua。升级前请删除旧文件 2-book-receipt-shortcut-and-lockscreen.lua，再安装新补丁。已有设置和字体可继续使用。",
        justified=false,show_menu=false,add_default_buttons=true,
    })
end

local function showAbout()
    local text="墨笺 · Inkfolio\nv1.1.0｜2026-10-13\n\n小票风格的阅读信息卡，展示图书封面、豆瓣评分、简介、阅读进度和城市天气，支持休眠显示与截图。\n\n图书信息\n自动或手动联网获取，支持匹配确认、重新检索及来源查询。\n\n阅读统计\n自定义组合本书／全局的今日与累计数据，展示周／月时长柱状图；支持本书已读字数折算和本次唤醒翻阅字数统计。\n\n外观与操作\n实时预览并调整宽度、字号、比例和背景，支持手势调用及诊断信息导出。\n\n开发与设计：zacharykim88\n开发辅助：OpenAI Codex\n推荐项目：墨享 · InkShare——分享 KOReader 截图。\n\n上游致谢\nEstela-Zelin84/KOReader_Book-Receipt\nu/hundredpercentcocoa\nomer-faruq/koreader-user-patches\n\n代码：GPL-3.0｜随包字体：SIL OFL 1.1\n\n兼容性\nKobo Sage 实机测试暂未发现问题，其他设备尚未验证。Android 不替换系统锁屏，F-Droid 版不支持本补丁。"
    UIManager:show(require('ui/widget/textviewer'):new{
        title='关于墨笺',text=text,justified=false,show_menu=false,
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
        return {
            text='墨笺设置',
            sub_item_table={
                {text='启用休眠显示',keep_menu_open=true,
                    help_text='使用墨笺作为休眠壁纸；关闭后保持屏幕原样。此功能仅在支持休眠壁纸的平台启用。',
                    enabled_func=function()return Device:supportsScreensaver()end,
                    checked_func=function()return G_reader_settings:readSetting('screensaver_type')=='book_receipt'end,
                    callback=function()
                        if not Device:supportsScreensaver() then return end
                        local selected=G_reader_settings:readSetting('screensaver_type')=='book_receipt'
                        G_reader_settings:saveSetting('screensaver_type',selected and 'disable' or 'book_receipt')
                    end},
                {text='显示内容',sub_item_table={
                    {text='图书信息',sub_item_table={toggle('封面',S.cover),toggle('评分',S.score),
                        toggle('简介',S.intro),toggle('二维码',S.qr)}},
                    {text='阅读进度',sub_item_table=progressMenu()},
                    {text='阅读摘要',sub_item_table=summaryMenu()},
                    {text='底部文字',callback=editFooter},
                }},
                {text='外观调整',callback=editAppearance},
                {text='联网设置',text_func=function()local n=Inkfolio.pendingCount();return n>0 and ('联网设置 · '..n..'本待确认') or '联网设置' end,sub_item_table={
                    toggle('允许联网',S.online,function(now)
                        if not now then MANUAL_CONNECT_PENDING=false;abortRound() else dailyCheck();startPoll() end
                    end),
                    {text='更新信息',enabled_func=function()
                        return networkingEnabled() and not RUN.active and not RUN.worker
                    end,callback=updateManually,help_text='阅读界面：重新获取当前书籍并更新一次天气。非阅读界面：扫描整个书库，补全未完整获取的书籍并更新一次天气。'},
                    {text='信息状态',callback=Inkfolio.showInformation},
                    {text_func=function()return '待确认图书（'..Inkfolio.pendingCount()..'）' end,callback=Inkfolio.showPendingMatches},
                    {text='重新匹配本书',callback=function()Inkfolio.editMatchQuery(currentBook())end,
                        enabled_func=function()return currentBook()~=nil and not RUN.active and not RUN.worker end},
                    {text='解除本书匹配',callback=Inkfolio.clearCurrentMatch,
                        enabled_func=function()local b=currentBook();return b and Inkfolio.matchState.choices[Inkfolio.fileMatchKey(b)]~=nil and not RUN.active and not RUN.worker end},

                    {text='天气城市',help_text='单选城市；选择“不设置城市”可清除选择。',sub_item_table=weatherCityMenu()},
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
end

-- Settings and the sleep toggle live exclusively in Tools / Inkfolio.
-- No sleep-menu injection: other native sleep modes are left untouched.
local receiptMenuWidget={name='read_receipt_settings'}
function receiptMenuWidget:addToMainMenu(items)
    items.read_receipt={text='墨笺',keep_menu_open=true,callback=Inkfolio.settings}
    items.read_receipt.text_func=function()local n=Inkfolio.pendingCount();return n>0 and ('墨笺 · '..n..'本待确认') or '墨笺' end
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
        assert(type(order.tools)=='table','Inkfolio: KOReader 工具菜单不可用')
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
    Inkfolio.recordAction('墨笺设置')
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
        menu.sub_item_table.icon='appbar.tools';menu.sub_item_table.text='墨笺'
        container[1]=require('ui/widget/touchmenu'):new{width=Screen:getWidth(),
            tab_item_table={menu.sub_item_table},show_parent=container}
    else
        local Menu=require('ui/widget/menu')
        container[1]=Menu:new{title='墨笺',width=Screen:getWidth(),
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
    category='none',event='QuickLook',title='墨笺预览',general=true})
Dispatcher:registerAction('inkfolio_settings',{
    category='none',event='InkfolioSettings',title='墨笺设置',general=true})
Dispatcher:registerAction('inkfolio_screenshot',{
    category='none',event='InkfolioScreenshot',title='保存墨笺截图',general=true})

-- Guard only Inkfolio entry points and editor methods. Do not hook UIManager,
-- KOReader's global exception handler, or another plugin's callbacks.
for _,entry in ipairs({{'preview','小票渲染'},{'settings','墨笺设置'},{'saveScreenshot','保存截图'}})do
    local name,stage=entry[1],entry[2];local original=Inkfolio[name]
    Inkfolio[name]=function(...)return Inkfolio.guard(stage,original,...)end
end
for _,entry in ipairs({{'init','外观调整'},{'refreshPreview','外观调整'},{'save','外观保存'},{'onCancel','菜单返回'}})do
    local name,stage=entry[1],entry[2];local original=AppearanceEditor[name]
    AppearanceEditor[name]=function(...)return Inkfolio.guard(stage,original,...)end
end
