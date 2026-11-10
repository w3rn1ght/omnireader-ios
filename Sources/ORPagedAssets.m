#import "ORPagedAssets.h"
#import "ORUtil.h"

@implementation ORPagedAssets

+ (NSString *)documentHTMLWithBody:(NSString *)body
                          extraCSS:(NSString *)extraCSS
                             title:(NSString *)title
                          settings:(ORSettings *)settings {
    NSString *template = [self htmlTemplate];
    NSMutableString *html = [template mutableCopy];
    NSRange full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"__CSS__" withString:[self cssForSettings:settings] options:0 range:full];
    full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"__EXTRA__" withString:extraCSS ?: @"" options:0 range:full];
    full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"__BODY__" withString:body ?: @"" options:0 range:full];
    full = NSMakeRange(0, html.length);
    NSString *mode = settings.pageDirection == ORPageDirectionVertical ? @"mode-vertical" : @"mode-horizontal";
    [html replaceOccurrencesOfString:@"__MODE__" withString:mode options:0 range:full];
    full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"__JS__" withString:[self paginatorScript] options:0 range:full];
    full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"__TITLE__" withString:title ?: @"" options:0 range:full];
    return html;
}

+ (NSString *)styleConfigurationForSettings:(ORSettings *)settings {
    return [NSString stringWithFormat:
        @"{fontSize:%ld, lineHeight:%f, margin:%ld, fontFamily:%@, bg:%@, fg:%@, muted:%@, justify:%@, hyphenate:%@, animate:%@, direction:%@}",
        (long)settings.fontSize,
        settings.lineHeight,
        (long)settings.margin,
        [self jsString:settings.cssFontFamily],
        [self jsString:settings.cssBackgroundColor],
        [self jsString:settings.cssTextColor],
        [self jsString:[ORUtil cssColorFromUIColor:[settings themeSecondaryColor]]],
        settings.justify ? @"true" : @"false",
        settings.hyphenate ? @"true" : @"false",
        settings.animatePages ? @"true" : @"false",
        settings.pageDirection == ORPageDirectionVertical ? @"\"vertical\"" : @"\"horizontal\""];
}

+ (NSString *)jsString:(NSString *)value {
    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, escaped.length)];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

+ (NSString *)cssForSettings:(ORSettings *)settings {
    return [NSString stringWithFormat:
        @":root{--bg:%@;--fg:%@;--muted:%@;--font-family:%@;--font-size:%ldpx;--line-height:%f;--gutter:%ldpx;}",
        settings.cssBackgroundColor,
        settings.cssTextColor,
        [ORUtil cssColorFromUIColor:[settings themeSecondaryColor]],
        settings.cssFontFamily,
        (long)settings.fontSize,
        settings.lineHeight,
        (long)settings.margin];
}

+ (NSString *)htmlTemplate {
    return @"<!DOCTYPE html><html><head>"
           "<meta charset=\"utf-8\"/>"
           "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover\"/>"
           "<title>__TITLE__</title>"
           /* Book CSS first: the reader's own rules below must win over EPUB
              styles that position titles and text over the cover image. */
           "<style id=\"or-book\">__EXTRA__</style>"
           "<style>"
           "html,body{margin:0;padding:0;background:var(--bg);color:var(--fg);-webkit-text-size-adjust:100%;}"
           "body{overflow-x:hidden;font-family:var(--font-family);}"
           "body.mode-horizontal{height:100%;overflow:hidden;}"
           "body.mode-vertical{height:auto;min-height:100%;}"
           "#viewport{position:relative;background:var(--bg);}"
           "body.mode-horizontal #viewport{position:fixed;top:0;left:0;right:0;bottom:0;overflow:hidden;padding:6px 0;}"
           "body.mode-vertical #viewport{position:static;overflow:visible;padding:6px 0;}"
           "#content{margin-left:var(--gutter);margin-right:var(--gutter);"
           "font-size:var(--font-size);line-height:var(--line-height);}"
           "body.mode-horizontal #content{height:100%;-webkit-column-width:calc(100vw - 2 * var(--gutter));"
           "-webkit-column-gap:calc(2 * var(--gutter));-webkit-column-fill:auto;"
           "column-width:calc(100vw - 2 * var(--gutter));column-gap:calc(2 * var(--gutter));column-fill:auto;}"
           "body.mode-vertical #content{height:auto;}"
           /* Vertical rhythm inside columns: no padding on the multicol box,
              it would shrink the column height and spill text downwards. */
           "#content > p:first-child{margin-top:0;}"
           "body.justify #content{text-align:justify;}"
           "body.hyphenate #content{-webkit-hyphens:auto;hyphens:auto;}"
           /* Hanging indent: every paragraph starts at the ruler, the first line
              is pulled into the margin, body text is aligned to the ruler. */
           "p{margin:0 0 .38em 0;padding-left:1.6em;text-indent:-1.6em;orphans:2;widows:2;}"
           "p:first-child{margin-top:0;}"
           "h1,h2,h3,h4,h5,h6{text-indent:0;padding-left:0;line-height:1.3;margin:1.1em 0 .6em 0;font-weight:600;page-break-after:avoid;}"
           "h1{font-size:1.35em;}h2{font-size:1.18em;}h3{font-size:1.06em;}"
           "hr{margin:1.1em 0;border:none;border-top:1px solid rgba(128,128,128,.35);}"
           "blockquote{margin:1em .4em;padding:.15em 0 .15em .85em;border-left:3px solid rgba(128,128,128,.3);}"
           "img{max-width:100%;height:auto;}"
           "table{border-collapse:collapse;max-width:100%;}"
           "td,th{border:1px solid rgba(128,128,128,.35);padding:.28em .4em;font-size:.95em;}"
           "pre{white-space:pre-wrap;font-size:.85em;}"
           "a{color:inherit;text-decoration:underline;}"
           ".office-table{width:100%;}"
           ".office-table td,.office-table th{font-size:.85em;padding:.24em .34em;}"
           ".pptx-slide{margin:1.3em 0 .3em;}"
           ".docx-empty{height:.65em;}"
           "/* EPUBs often absolutely position title text on top of the cover.
              In a paginated reader that overlaps body text. */
           "#content *{float:none!important;position:static!important;max-width:100%!important;}"
           "#content img{display:block;margin:.6em auto;height:auto!important;max-height:85vh;}"
           "#content svg{max-width:100%;height:auto!important;}"
           "::selection{background:rgba(255,190,60,.55);}"
           "</style>"
           "</head>"
           "<body class=\"__MODE__\">"
           "<div id=\"viewport\"><div id=\"content\">__BODY__</div></div>"
           "<script>__JS__</script>"
           "</body></html>";
}

+ (NSString *)paginatorScript {
    return @"(function(){'use strict';"
           "var vp=document.getElementById('viewport');"
           "var content=document.getElementById('content');"
           "var gutter=18,pageWidth=390,pageHeight=600,total=1,current=0;"
           "var animate=true,animating=false,ready=false,queued=false;"
           "function post(msg){try{window.webkit.messageHandlers.omni.postMessage(msg);}catch(e){}}"
           "function isVertical(){return document.body.classList.contains('mode-vertical');}"
           "function setDirection(dir){"
           "var horizontal=(dir!=='vertical');"
           "document.body.classList.toggle('mode-vertical',!horizontal);"
           "document.body.classList.toggle('mode-horizontal',horizontal);"
           "}"
           "function metrics(){"
           "pageWidth=Math.max(120,Math.round(window.innerWidth||document.documentElement.clientWidth||320));"
           "pageHeight=Math.max(120,Math.round(window.innerHeight||document.documentElement.clientHeight||480));"
           "document.documentElement.style.setProperty('--pw',pageWidth+'px');"
           "var g=gutter;"
           "content.style.boxSizing='border-box';"
           "content.style.marginLeft=g+'px';"
           "content.style.marginRight=g+'px';"
           "content.style.width=(pageWidth-2*g)+'px';"
           "if(isVertical()){"
           "content.style.height='auto';"
           "content.style.columnWidth='auto';"
           "content.style.columnCount='auto';"
           "content.style.columnGap='normal';"
           "content.style.columnFill='balance';"
           "}else{"
           "content.style.height=pageHeight+'px';"
           "content.style.columnWidth=(pageWidth-2*g)+'px';"
           "content.style.columnCount='auto';"
           "content.style.columnGap=(2*g)+'px';"
           "content.style.columnFill='auto';"
           "}"
           "void content.offsetHeight;"
           "}"
           "function maxScroll(){"
           "if(isVertical()){"
           "var doc=document.documentElement;"
           "return Math.max(0,(doc.scrollHeight||document.body.scrollHeight)-(window.innerHeight||doc.clientHeight));"
           "}"
           "return Math.max(0,vp.scrollWidth-vp.clientWidth);"
           "}"
           "function scrollPos(){"
           "if(isVertical())return window.pageYOffset||document.documentElement.scrollTop||0;"
           "return vp.scrollLeft;"
           "}"
           "function setScrollPos(x){"
           "if(isVertical())window.scrollTo(0,x);"
           "else vp.scrollLeft=x;"
           "}"
           "function stepSize(){return isVertical()?Math.max(1,window.innerHeight):pageWidth;}"
           "function fraction(){return total>1?current/(total-1):0;}"
           "var lastW=0,lastH=0;"
           "function recalc(){"
           "metrics();"
           "var max=maxScroll();"
           "if(isVertical()){"
           "var step=Math.max(1,pageHeight);"
           "total=Math.max(1,Math.ceil((max+step*0.9)/step));"
           "lastW=0;lastH=0;"
           "}else{"
           "total=Math.max(1,Math.ceil((max+pageWidth-1)/pageWidth));"
           "lastW=pageWidth;lastH=pageHeight;"
           "}"
           "}"
           "function chapter(){"
           "var points=[[gutter+6,10],[Math.round(pageWidth/2),10],[gutter+6,60]];"
           "for(var i=0;i<points.length;i++){"
           "var el=document.elementFromPoint(points[i][0],points[i][1]);"
           "if(!el)continue;"
           "var sec=el.closest?el.closest('[data-chapter]'):null;"
           "if(sec)return sec.getAttribute('data-chapter')||'';"
           "}"
           "return '';"
           "}"
           "function notify(){"
           "if(queued)return;queued=true;"
           "requestAnimationFrame(function(){queued=false;"
           "post({type:'state',page:current,total:total,fraction:fraction(),chapter:chapter(),mode:isVertical()?'vertical':'horizontal'});});"
           "}"
           "function syncFromScroll(){"
           "var pos=scrollPos(),step=stepSize();"
           "current=Math.max(0,Math.min(total-1,Math.round(pos/step)));"
           "}"
           "function animateTo(target){"
           "var start=scrollPos(),delta=target-start;"
           "if(!animate||Math.abs(delta)<2){setScrollPos(target);syncFromScroll();notify();return;}"
           "animating=true;var t0=null;"
           "function tick(ts){if(t0===null)t0=ts;var p=Math.min(1,(ts-t0)/190);"
           "var e=1-Math.pow(1-p,3);setScrollPos(start+delta*e);"
           "if(p<1)return requestAnimationFrame(tick);"
           "animating=false;syncFromScroll();notify();}"
           "requestAnimationFrame(tick);"
           "}"
           "function targetFor(index){"
           "index=Math.max(0,Math.min(total-1,index));"
           "if(isVertical()){var max=maxScroll();"
           "return total>1?(index/(total-1))*max:0;}"
           "return index*pageWidth;"
           "}"
           "function goTo(index,animated){"
           "index=Math.max(0,Math.min(total-1,Math.round(index)));current=index;"
           "var t=targetFor(index);"
           "if(animated)animateTo(t);else{setScrollPos(t);notify();}"
           "}"
           "function prepare(f){"
           "recalc();"
           "var index=total>1?Math.round((f||0)*(total-1)):0;"
           "goTo(index,false);ready=true;"
           "post({type:'ready',page:current,total:total,fraction:fraction(),mode:isVertical()?'vertical':'horizontal'});notify();"
           "}"
           "function relayout(f){"
           "recalc();"
           "var index=total>1?Math.round((f||0)*(total-1)):0;"
           "goTo(index,false);"
           "}"
           "function goToAnchor(id){"
           "var el=document.getElementById(id);if(!el)return false;"
           "if(isVertical()){"
           "var y=el.getBoundingClientRect().top+(window.pageYOffset||0)-8;"
           "window.scrollTo(0,Math.max(0,y));syncFromScroll();notify();return true;"
           "}"
           "var abs=el.getBoundingClientRect().left+vp.scrollLeft;"
           "var page=Math.floor((abs-gutter)/pageWidth);"
           "goTo(page,true);return true;"
           "}"
           "function find(query){"
           "if(!query)return {found:0,index:-1};"
           "var raw=content.innerText||'';"
           "var hay=raw.toLowerCase(),needle=query.toLowerCase();"
           "var idx=hay.indexOf(needle);"
           "if(idx<0)return {found:0,index:-1};"
           "var max=maxScroll();"
           "var ratio=raw.length?idx/raw.length:0;"
           "var page=Math.round(ratio*(total-1));"
           "goTo(page,true);"
           "try{var range=document.createRange();var walker=document.createTreeWalker(content,NodeFilter.SHOW_TEXT,null,false);"
           "var pos=0,node,hits=0;"
           "while((node=walker.nextNode())){var len=node.nodeValue.length;"
           "if(pos+len>idx){var start=idx-pos;range.setStart(node,start);range.setEnd(node,Math.min(len,start+needle.length));hits=1;break;}pos+=len;}"
           "if(hits){var sel=window.getSelection();sel.removeAllRanges();sel.addRange(range);}}catch(e){}"
           "return {found:1,index:page};"
           "}"
           "function applyStyle(cfg){"
           "var r=document.documentElement.style;"
           "if(cfg.fontSize)r.setProperty('--font-size',cfg.fontSize+'px');"
           "if(cfg.lineHeight)r.setProperty('--line-height',String(cfg.lineHeight));"
           "if(cfg.margin!=null){gutter=cfg.margin;r.setProperty('--gutter',cfg.margin+'px');}"
           "if(cfg.fontFamily)r.setProperty('--font-family',cfg.fontFamily);"
           "if(cfg.bg)r.setProperty('--bg',cfg.bg);"
           "if(cfg.fg)r.setProperty('--fg',cfg.fg);"
           "if(cfg.muted)r.setProperty('--muted',cfg.muted);"
           "if(cfg.justify!=null)document.body.classList.toggle('justify',!!cfg.justify);"
           "if(cfg.hyphenate!=null)document.body.classList.toggle('hyphenate',!!cfg.hyphenate);"
           "if(cfg.animate!=null)animate=!!cfg.animate;"
           "var f=fraction();"
           "if(cfg.direction)setDirection(cfg.direction);"
           "recalc();goTo(Math.round(f*(total-1)),false);"
           "}"
           "window.Omni={"
           "prepare:prepare,relayout:relayout,find:find,"
           "next:function(){goTo(current+1,true);},prev:function(){goTo(current-1,true);},"
           "goTo:goTo,goToAnchor:goToAnchor,applyStyle:applyStyle,"
           "state:function(){return{page:current,total:total,fraction:fraction(),mode:isVertical()?'vertical':'horizontal'};},"
           "text:function(){try{return content.innerText||'';}catch(e){return '';}},"
           "pageWidth:function(){return pageWidth;}"
           "};"
           "function onScroll(){"
           "if(!ready||animating)return;"
           "/* Programmatic scrollTo() may not fire a scroll event; the timer below reconciles. */"
           "syncFromScroll();notify();"
           "}"
           "vp.addEventListener('scroll',onScroll,{passive:true});"
           "window.addEventListener('scroll',onScroll,{passive:true});"
           "var lastPos=-1,lastTotal=-1;"
           "setInterval(function(){"
           "if(!ready||animating)return;"
           "var pos=scrollPos();"
           "if(total!==lastTotal){lastTotal=total;lastPos=pos;return;}"
           "if(Math.abs(pos-lastPos)>4){lastPos=pos;onScroll();}"
           "},320);"
           "window.addEventListener('resize',function(){if(!ready)return;"
           "var dw=Math.abs((window.innerWidth||0)-lastW),dh=Math.abs((window.innerHeight||0)-lastH);"
           "if(dw<2&&dh<2&&lastW>0)return;"
           "var f=fraction();recalc();goTo(Math.round(f*(total-1)),false);});"
           "})();";
}

@end
