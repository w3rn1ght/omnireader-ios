#import "ORPagedAssets.h"
#import "ORUtil.h"

@implementation ORPagedAssets

+ (NSString *)documentHTMLWithBody:(NSString *)body
                          extraCSS:(NSString *)extraCSS
                             title:(NSString *)title
                          settings:(ORSettings *)settings {
    NSString *template = [self htmlTemplate];
    NSMutableString *html = [template mutableCopy];
    NSString *css = [self cssForSettings:settings];

    NSRange full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"__CSS__" withString:css options:0 range:full];
    full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"__EXTRA__" withString:extraCSS ?: @"" options:0 range:full];
    full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"__BODY__" withString:body ?: @"" options:0 range:full];
    full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"__JS__" withString:[self paginatorScript] options:0 range:full];
    full = NSMakeRange(0, html.length);
    [html replaceOccurrencesOfString:@"__TITLE__" withString:title ?: @"" options:0 range:full];
    return html;
}

+ (NSString *)styleConfigurationForSettings:(ORSettings *)settings {
    return [NSString stringWithFormat:
        @"{fontSize:%ld, lineHeight:%f, margin:%ld, fontFamily:%@, bg:%@, fg:%@, muted:%@, justify:%@, hyphenate:%@, animate:%@}",
        (long)settings.fontSize,
        settings.lineHeight,
        (long)settings.margin,
        [self jsString:settings.cssFontFamily],
        [self jsString:settings.cssBackgroundColor],
        [self jsString:settings.cssTextColor],
        [self jsString:[ORUtil cssColorFromUIColor:[settings themeSecondaryColor]]],
        settings.justify ? @"true" : @"false",
        settings.hyphenate ? @"true" : @"false",
        settings.animatePages ? @"true" : @"false"];
}

+ (NSString *)jsString:(NSString *)value {
    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

+ (NSString *)cssForSettings:(ORSettings *)settings {
    return [NSString stringWithFormat:
        @":root{--bg:%@;--fg:%@;--muted:%@;--font-family:%@;--font-size:%ldpx;--line-height:%f;--gutter:%ldpx;--pw:390px;}",
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
           "<style>"
           "html,body{margin:0;padding:0;height:100%;overflow:hidden;background:var(--bg);color:var(--fg);}"
           "#viewport{position:fixed;top:0;left:0;right:0;bottom:0;overflow:hidden;background:var(--bg);}"
           "#content{"
           "width:calc(var(--pw) - 2 * var(--gutter));"
           "margin-left:var(--gutter);"
           "height:100%;box-sizing:border-box;"
           "padding-top:6px;padding-bottom:6px;"
           "-webkit-column-width:calc(var(--pw) - 2 * var(--gutter));"
           "-webkit-column-gap:calc(2 * var(--gutter));"
           "-webkit-column-fill:auto;"
           "column-width:calc(var(--pw) - 2 * var(--gutter));"
           "column-gap:calc(2 * var(--gutter));"
           "column-fill:auto;"
           "font-family:var(--font-family);font-size:var(--font-size);line-height:var(--line-height);"
           "text-rendering:optimizeLegibility;-webkit-text-size-adjust:100%;}"
           "body.justify #content{text-align:justify;}"
           "body.hyphenate #content{-webkit-hyphens:auto;hyphens:auto;}"
           "p{margin:0 0 .5em 0;text-indent:1.4em;}"
           "p:first-child{margin-top:0;}"
           "h1,h2,h3,h4,h5{text-indent:0;line-height:1.28;margin:1.05em 0 .55em 0;font-weight:600;}"
           "h1{font-size:1.35em;}h2{font-size:1.18em;}h3{font-size:1.05em;}"
           "hr{margin:1.1em 0;border:none;border-top:1px solid rgba(128,128,128,.35);}"
           "blockquote{margin:1em .5em;padding:.15em 0 .15em .85em;border-left:3px solid rgba(128,128,128,.3);}"
           "img{max-width:100%;height:auto;}"
           "table{border-collapse:collapse;max-width:100%;}"
           "td,th{border:1px solid rgba(128,128,128,.35);padding:.28em .4em;font-size:.95em;}"
           "pre{white-space:pre-wrap;font-size:.85em;}"
           "a{color:inherit;text-decoration:underline;}"
           ".office-table{width:100%;}"
           ".office-table td,.office-table th{font-size:.85em;padding:.24em .34em;}"
           ".pptx-slide{margin:1.3em 0 .3em;}"
           ".docx-empty{height:.65em;}"
           "</style>"
           "<style id=\"or-extra\">__EXTRA__</style>"
           "</head>"
           "<body>"
           "<div id=\"viewport\"><div id=\"content\">__BODY__</div></div>"
           "<script>__JS__</script>"
           "</body></html>";
}

+ (NSString *)paginatorScript {
    return @"(function(){'use strict';"
           "var vp=document.getElementById('viewport'),content=document.getElementById('content');"
           "var gutter=18,pageWidth=390,total=1,current=0,animating=false,animate=true;"
           "var chapterEls=[],readyFired=false;"
           "function post(p){try{window.webkit.messageHandlers.omni.postMessage(p);}catch(e){}}"
           "function measure(){"
           "pageWidth=Math.max(100,Math.round(vp.clientWidth||window.innerWidth));"
           "document.documentElement.style.setProperty('--pw',pageWidth+'px');"
           "void content.offsetHeight;"
           "var sw=vp.scrollWidth;"
           "total=Math.max(1,Math.ceil(sw/pageWidth-0.02));"
           "}"
           "function fractionOf(){return total>1?(current/(total-1)):0;}"
           "function chapterForPage(index){"
           "var x=index*pageWidth,found='';"
           "for(var i=0;i<chapterEls.length;i++){var el=chapterEls[i];"
           "if(el.getBoundingClientRect().left+vp.scrollLeft<=x+gutter+4)found=el;else break;}"
           "return found?found.getAttribute('data-chapter')||'':'';"
           "}"
           "function notify(){post({type:'state',page:current,total:total,fraction:fractionOf(),chapter:chapterForPage(current)});}"
           "function animateTo(x){"
           "var start=vp.scrollLeft,delta=x-start;"
           "if(!animate||Math.abs(delta)<2){vp.scrollLeft=x;return;}"
           "animating=true;var t0=null;"
           "function step(ts){if(t0===null)t0=ts;var p=Math.min(1,(ts-t0)/200);"
           "var e=1-Math.pow(1-p,3);vp.scrollLeft=start+delta*e;"
           "if(p<1)requestAnimationFrame(step);else{animating=false;current=Math.round(vp.scrollLeft/pageWidth);notify();}}"
           "requestAnimationFrame(step);"
           "}"
           "function goTo(index,anim){"
           "index=Math.max(0,Math.min(total-1,Math.round(index)));current=index;var x=index*pageWidth;"
           "if(anim)animateTo(x);else{vp.scrollLeft=x;notify();}"
           "}"
           "function prepare(fraction){"
           "chapterEls=Array.prototype.slice.call(document.querySelectorAll('[data-chapter]'));"
           "requestAnimationFrame(function(){"
           "measure();"
           "current=Math.max(0,Math.min(total-1,Math.round((fraction||0)*Math.max(0,total-1))));"
           "vp.scrollLeft=current*pageWidth;readyFired=true;"
           "post({type:'ready',page:current,total:total,fraction:fractionOf()});notify();"
           "});"
           "}"
           "function relayout(fraction){"
           "measure();"
           "current=Math.max(0,Math.min(total-1,Math.round((fraction||0)*Math.max(0,total-1))));"
           "vp.scrollLeft=current*pageWidth;notify();"
           "}"
           "function goToAnchor(id){"
           "var el=document.getElementById(id);if(!el)return false;"
           "var abs=el.getBoundingClientRect().left+vp.scrollLeft;"
           "goTo(Math.max(0,Math.floor(abs/pageWidth)),true);return true;"
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
           "}"
           "window.Omni={"
           "prepare:prepare,relayout:relayout,next:function(){goTo(current+1,animate);},"
           "prev:function(){goTo(current-1,animate);},goTo:goTo,goToAnchor:goToAnchor,applyStyle:applyStyle,"
           "state:function(){return{page:current,total:total,fraction:fractionOf()};},"
           "text:function(){try{return document.getElementById('content').innerText||'';}catch(e){return '';}},"
           "pageWidth:function(){return pageWidth;}"
           "};"
           "vp.addEventListener('scroll',function(){"
           "if(!readyFired||animating)return;"
           "var p=Math.round(vp.scrollLeft/pageWidth);if(p!==current){current=p;notify();}"
           "},{passive:true});"
           "window.addEventListener('resize',function(){if(readyFired)relayout(fractionOf());});"
           "})();";
}

@end
