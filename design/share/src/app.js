(function(){
'use strict';
var DEG=Math.PI/180,TAU=Math.PI*2;
var $=function(id){return document.getElementById(id)};
var P={};location.hash.replace(/^#/,'').split('&').forEach(function(s){if(!s)return;var a=s.split('=');P[a[0]]=a.length>1?decodeURIComponent(a[1]):true});
var root=document.documentElement;
if(P.bare)root.classList.add('bare');
var SHOT=!!P.shot;
var reduce=!!P.reduce||(!SHOT&&window.matchMedia&&matchMedia('(prefers-reduced-motion: reduce)').matches);
var big=!!P.big;
var lang=P.lang==='es'?'es':'en';
var layout=/^s[123]$/.test(P.layout)?P.layout:'s1';
var way=P.way==='v2'?'v2':'v1';
var rcv=/^(app|none|other)$/.test(P.rcv)?P.rcv:'app';
var flow='shared'; /* the sky renderer draws the shared blessing's light */

/* ---------- icons: 24 grid, 1.5 stroke, round ends, as app/lib/widgets/icons.dart; small lights are dots, as its sky glyph ---------- */
function blessingPath(){
  /* the app icon in line: a sphere, and over it an arch with three lights, the middle one largest */
  var cx=12,cy=17,r=11.5,segs=[[-68,-50.3],[-29.7,-13],[13,29.7],[50.3,68]],d='';
  function pt(a){a*=DEG;return (cx+r*Math.sin(a)).toFixed(2)+' '+(cy-r*Math.cos(a)).toFixed(2)}
  segs.forEach(function(s){d+='M'+pt(s[0])+'A'+r+' '+r+' 0 0 1 '+pt(s[1])});
  return '<path d="'+d+'"/><circle class="dot" cx="12" cy="5.5" r="2"/><circle class="dot" cx="4.61" cy="8.19" r="1.4"/><circle class="dot" cx="19.39" cy="8.19" r="1.4"/><circle cx="12" cy="16" r="4.75"/>';
}
var G={
  blessing:blessingPath(),
  text:'<path d="M5 6.5h14M5 10.5h14M5 14.5h14M5 18.5h8.5"/>',
  pdf:'<path d="M7 3.5h6.5l5 5V19a1.5 1.5 0 0 1-1.5 1.5H7A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5z"/><path d="M13.5 3.5v5h5"/>',
  file:'<path d="M7 3.5h6.5l5 5V19a1.5 1.5 0 0 1-1.5 1.5H7A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5z"/><path d="M13.5 3.5v5h5"/><path d="M7.75 16.5Q12 11.5 16.25 16.5"/><circle class="dot" cx="12" cy="14" r="1.35"/><circle class="dot" cx="9.45" cy="14.9" r=".95"/><circle class="dot" cx="14.55" cy="14.9" r=".95"/>',
  link:'<path d="M10.25 13.75a3.75 3.75 0 0 0 5.3 0l3-3a3.75 3.75 0 0 0-5.3-5.3l-.85.85"/><path d="M13.75 10.25a3.75 3.75 0 0 0-5.3 0l-3 3a3.75 3.75 0 0 0 5.3 5.3l.85-.85"/>',
  copy:'<rect x="9" y="9" width="10.5" height="11.5" rx="2"/><path d="M15 9V5.75A1.75 1.75 0 0 0 13.25 4h-7A1.75 1.75 0 0 0 4.5 5.75v7.5A1.75 1.75 0 0 0 6.25 15H9"/>',
  share:'<path d="M9.25 9.75h-1.5A1.75 1.75 0 0 0 6 11.5v7a1.75 1.75 0 0 0 1.75 1.75h8.5A1.75 1.75 0 0 0 18 18.5v-7a1.75 1.75 0 0 0-1.75-1.75h-1.5"/><path d="M12 14V3.75M8.75 7L12 3.75 15.25 7"/>',
  back:'<path d="M14.5 6l-6 6 6 6"/>',
  fwd:'<path d="M10 6l6 6-6 6"/>',
  offline:'<path d="M7.25 18h9.5a3.75 3.75 0 0 0 .9-7.4A5.75 5.75 0 0 0 6.6 9.3 4.35 4.35 0 0 0 7.25 18z"/><path d="M4 4.5l16 15"/>',
  bubble:'<path d="M12 4.5c4.7 0 8.5 3 8.5 6.75S16.7 18 12 18c-.95 0-1.85-.12-2.7-.34L5 19.5l1.25-3.1C4.6 15.15 3.5 13.3 3.5 11.25 3.5 7.5 7.3 4.5 12 4.5z"/>',
  mail:'<rect x="3.5" y="6" width="17" height="12" rx="2"/><path d="M4.25 7l7.75 6 7.75-6"/>',
  folder:'<path d="M3.5 7.25v10.25A1.5 1.5 0 0 0 5 19h14a1.5 1.5 0 0 0 1.5-1.5v-8A1.5 1.5 0 0 0 19 8h-7.25l-2-2.5H5.25A1.75 1.75 0 0 0 3.5 7.25z"/>',
  more:'<circle class="dot" cx="6" cy="12" r="1.3"/><circle class="dot" cx="12" cy="12" r="1.3"/><circle class="dot" cx="18" cy="12" r="1.3"/>',
  airdrop:'<circle cx="12" cy="12" r="2"/><path d="M8.2 15.8a5.4 5.4 0 1 1 7.6 0M5.6 18.4a9 9 0 1 1 12.8 0"/>',
  plus:'<path d="M12 5.5v13M5.5 12h13"/>',
  tabs:'<rect x="4.5" y="4.5" width="15" height="15" rx="3"/>',
  dots:'<circle class="dot" cx="6.5" cy="12" r="1.3"/><circle class="dot" cx="12" cy="12" r="1.3"/><circle class="dot" cx="17.5" cy="12" r="1.3"/>',
  lock:'<rect x="6" y="11" width="12" height="8.5" rx="2.5"/><path d="M8.75 11V8.25a3.25 3.25 0 0 1 6.5 0V11"/>',
  aback:'<path d="M19 12H5.5M11 6l-6 6 6 6"/>'
};
function ic(n,cls){return '<svg class="ico'+(cls?' '+cls:'')+'" viewBox="0 0 24 24" aria-hidden="true">'+G[n]+'</svg>'}

/* ---------- every word, English and Spanish ---------- */
var WORDS=['Emma, I lay my hands upon your head to give you a blessing of comfort.',
 'Your Heavenly Father knows you. He knows the worry you have carried these weeks, and He wants you to know that you have not carried it alone.',
 'I bless you with peace as you go into this surgery, and I bless the hands of those who will care for you. Be patient with your body as it heals. Strength will return to you in its time.',
 'I say these things in the name of Jesus Christ, amen.'];
var T={
en:{
 sheet:'Share this blessing',
 send:'Send this blessing',
 keepNote:'They can keep it in Upon Thy Head.',
 wBlessing:'Blessing',wText:'Text',wPdf:'PDF',
 onlyWords:'Only the words',
 footV1:'Whoever receives it can read it and pass it on.',
 footV2:'This sends a link. Anyone who has it can read the blessing.',
 linkMade:'Link made',
 linkLine:'Anyone with this link can read it. It stops working in 30 days.',
 linkLine2:'It is locked on this phone before it leaves. The server keeps the locked copy, never the key.',
 sendLink:'Send the link',copy:'Copy link',yourLinks:'Your links',
 offLine:'No internet, so a link cannot be made now.',
 sendFile:'Send as a file',fileNote:'It opens only in Upon Thy Head.',
 fileLine:'Open with Upon Thy Head: uponthyhead.app',
 settings:'Settings',
 linksLede:'Each link stops working on its date. You can stop one sooner.',
 rows:[['Comfort before surgery','Sent today · stops December 16',1],['Before the new job','Sent November 2 · stops December 2',1],['For Lucía, on her baptism','Stopped November 9',0]],
 stop:'Stop',stopQ:'Stop this link?',stopBody:'It will no longer open, and the locked copy is erased. Anyone who kept the blessing still has it.',cancel:'Cancel',stopLink:'Stop link',
 edit:'Edit',
 date:'Tuesday, March 3, 2026',title:'Comfort before surgery',from:'A blessing from Dad',
 ask:'Keep it with your blessings?',notNow:'Not now',keep:'Keep',
 emma:'Emma',
 emmaLine:'Dad’s blessing from before my surgery.',
 when:'Today 7:12 PM',
 fileName:'Comfort before surgery, March 3, 2026.blessing',
 kindApp:'Upon Thy Head · 2 KB',kindNone:'2 KB',qlKind:'Document · 2 KB',done:'Done',
 imsg:'iMessage',amsg:'Text message',
 cardTitle:'A blessing',site:'uponthyhead.app',
 toast:'No app can open this file',
 p1Title:'Someone sent you a blessing.',p1Lede:'Get the app, then tap the file again.',getApp:'Get Upon Thy Head',free:'Free. No account. No ads.',
 sharedUntil:'Shared with you · until December 16',keepIn:'Keep it in Upon Thy Head',thenOpen:'Get the app, then open this link again.',
 exTitle:'This link has stopped working.',exLede:'Links last 30 days, or less if the sender stops one. Ask them to send it again.',
 sysFileSub:'Blessing file and one line of text',
 people:['Mom','Ben'],apps:['Messages','Mail','Files','More'],acts:['Copy','Save to Files']
},
es:{
 sheet:'Compartir esta bendición',
 send:'Enviar esta bendición',
 keepNote:'Podrán guardarla en Upon Thy Head.',
 wBlessing:'Bendición',wText:'Texto',wPdf:'PDF',
 onlyWords:'Solo las palabras',
 footV1:'Quien la reciba puede leerla y reenviarla.',
 footV2:'Esto envía un enlace. Quien lo tenga puede leer la bendición.',
 linkMade:'Enlace creado',
 linkLine:'Quien tenga este enlace puede leerla. Deja de funcionar en 30 días.',
 linkLine2:'Se cierra en este teléfono antes de salir. El servidor guarda la copia cerrada, nunca la llave.',
 sendLink:'Enviar el enlace',copy:'Copiar enlace',yourLinks:'Tus enlaces',
 offLine:'Sin internet no se puede crear un enlace ahora.',
 sendFile:'Enviar como archivo',fileNote:'Solo se abre en Upon Thy Head.',
 fileLine:'Ábrela con Upon Thy Head: uponthyhead.app',
 settings:'Configuración',
 linksLede:'Cada enlace deja de funcionar en su fecha. Puedes detenerlo antes.',
 rows:[['Comfort before surgery','Enviado hoy · hasta el 16 de diciembre',1],['Before the new job','Enviado el 2 de noviembre · hasta el 2 de diciembre',1],['For Lucía, on her baptism','Detenido el 9 de noviembre',0]],
 stop:'Detener',stopQ:'¿Detener este enlace?',stopBody:'Ya no se abrirá y se borra la copia cerrada. Quien ya guardó la bendición la conserva.',cancel:'Cancelar',stopLink:'Detener',
 edit:'Editar',
 date:'martes, 3 de marzo de 2026',title:'Comfort before surgery',from:'Una bendición de Dad',
 ask:'¿Guardarla con tus bendiciones?',notNow:'Ahora no',keep:'Guardar',
 emma:'Emma',
 emmaLine:'La bendición de papá de antes de mi cirugía.',
 when:'Hoy 19:12',
 fileName:'Comfort before surgery, 3 de marzo de 2026.blessing',
 kindApp:'Upon Thy Head · 2 KB',kindNone:'2 KB',qlKind:'Documento · 2 KB',done:'OK',
 imsg:'iMessage',amsg:'Mensaje de texto',
 cardTitle:'Una bendición',site:'uponthyhead.app',
 toast:'Ninguna app puede abrir este archivo',
 p1Title:'Alguien te envió una bendición.',p1Lede:'Descarga la app y vuelve a tocar el archivo.',getApp:'Descargar Upon Thy Head',free:'Gratis. Sin cuenta. Sin anuncios.',
 sharedUntil:'Compartida contigo · hasta el 16 de diciembre',keepIn:'Guardarla en Upon Thy Head',thenOpen:'Descarga la app y vuelve a abrir este enlace.',
 exTitle:'Este enlace dejó de funcionar.',exLede:'Los enlaces duran 30 días, o menos si quien lo envió lo detiene. Pídele que lo vuelva a enviar.',
 sysFileSub:'Archivo de bendición y una línea de texto',
 people:['Mamá','Ben'],apps:['Mensajes','Mail','Archivos','Más'],acts:['Copiar','Guardar en Archivos']
}};
var L=function(){return T[lang]};

/* ---------- the steps ---------- */
var NAME={sheet:'The share sheet','sys-file':'iOS share sheet, holding the file',linkmade:'The link is made','sys-link':'iOS share sheet, holding the link',
  msg:'Their Messages','amsg':'Their Messages (Android)',toast:'They tap the file',keep:'The app opens: keep it?',reading:'Kept',
  ql:'They tap the file: iOS cannot open it',page1:'The address leads here',page2:'The link opens a page',
  offline:'No internet',links:'Your links (in Settings)','links-stop':'Stop a link',expired:'A link that has stopped'};
function path(){
  var p=['sheet'];
  if(way==='v1'){p.push('sys-file');
    if(rcv==='app')p.push('msg','keep','reading');
    else if(rcv==='none')p.push('msg','ql','page1');
    else p.push('amsg','toast','page1');
  }else{p.push('linkmade','sys-link');
    if(rcv==='app')p.push('msg','keep','reading');
    else if(rcv==='none')p.push('msg','page2');
    else p.push('amsg','page2');
  }
  return p;
}
var EXTRAS=['offline','links','links-stop','expired'];
var step='sheet';
function nextOf(s){var p=path(),i=p.indexOf(s);return i>=0&&i<p.length-1?p[i+1]:null}
function isAndroid(s){return rcv==='other'&&(s==='amsg'||s==='toast'||s==='page1'||s==='page2'||s==='expired')}

/* ---------- screens ---------- */
function reading(withBar){
  var t=L();
  return '<div class="reading"><div class="scrim"></div><div class="ground"></div>'+
    '<div class="bar"><button class="ib" aria-label="Back">'+ic('back')+'</button><span class="sp"></span><button class="ib" aria-label="'+t.sheet+'"'+(withBar?' data-go="sheet"':'')+'>'+ic('share')+'</button><button class="edit">'+t.edit+'</button></div>'+
    '<div class="body"><p class="meta">'+t.date+'</p><h1 class="title">'+t.title+'</h1><p class="from">'+t.from+'</p><div class="words">'+WORDS.map(function(w){return '<p>'+w+'</p>'}).join('')+'</div></div></div>';
}
function foot(){var t=L();return '<p class="foot">'+(way==='v2'?t.footV2:t.footV1)+'</p>'}
function quietPair(){var t=L();return '<div class="roundrow"><button class="round"><span class="c">'+ic('text')+'</span><span class="w">'+t.wText+'</span></button><button class="round"><span class="c">'+ic('pdf')+'</span><span class="w">'+t.wPdf+'</span></button></div>'}
function mainNext(){return way==='v2'?'linkmade':'sys-file'}
function sheetBody(lo){
  var t=L(),h='';
  if(lo==='s1'){
    h+='<button class="btn primary main" data-go="'+mainNext()+'">'+ic('blessing')+'<span>'+t.send+'</span></button>'+
       '<p class="under">'+t.keepNote+'</p>'+quietPair()+foot();
  }else if(lo==='s2'){
    h+='<div class="trio"><button class="round first" data-go="'+mainNext()+'" aria-label="'+t.send+'"><span class="c">'+ic('blessing')+'</span><span class="w">'+t.wBlessing+'</span></button>'+
       '<button class="round"><span class="c">'+ic('text')+'</span><span class="w">'+t.wText+'</span></button>'+
       '<button class="round"><span class="c">'+ic('pdf')+'</span><span class="w">'+t.wPdf+'</span></button></div>'+foot();
  }else{
    h+='<div class="card"><div class="top"><span class="thumb" aria-hidden="true"></span><span><span class="t" style="display:block">'+t.title+'</span><span class="f" style="display:block">'+t.from+'</span></span></div>'+
       '<button class="btn primary main" data-go="'+mainNext()+'">'+ic('blessing')+'<span>'+t.send+'</span></button><p class="under">'+t.keepNote+'</p></div>'+
       '<div class="words-only"><span class="k">'+t.onlyWords+'</span><button class="chip">'+ic('text')+t.wText+'</button><button class="chip">'+ic('pdf')+t.wPdf+'</button></div>'+foot();
  }
  return h;
}
function ourSheet(inner,label){return '<div class="dimmer"></div><div class="sheet" role="dialog" aria-label="'+(label||L().sheet)+'"><div class="grab"></div>'+inner+'</div>'}
function sysSheet(kind){
  var t=L(),thumb=kind==='file'?'<img src="'+window.APPICON+'" alt="">':'<span style="width:46px;height:46px;background:radial-gradient(circle at 50% 50%,#FFF0CD 0,#F0C987 2px,rgba(240,201,135,.3) 7px,rgba(240,201,135,0) 18px),#100D09"></span>';
  var title=kind==='file'?t.fileName.replace(/\.blessing$/,''):t.title,sub=kind==='file'?t.sysFileSub:'uponthyhead.app/b/x7Kp2';
  var appsI=['bubble','mail','folder','more'];
  return '<div class="dimmer"></div><div class="sys" role="dialog"><div class="hd"><span class="th">'+thumb+'</span><span><b>'+title+'</b><i>'+sub+'</i></span></div>'+
    '<div class="people"><div class="p"><span class="a">'+ic('airdrop')+'</span>AirDrop</div>'+t.people.map(function(n){return '<div class="p"><span class="a">'+n.charAt(0)+'</span>'+n+'</div>'}).join('')+'</div>'+
    '<div class="apps">'+t.apps.map(function(n,i){return '<button class="p'+(i===0?' hot':'')+'"'+(i===0?' data-act="next"':'')+'><span class="a">'+ic(appsI[i])+'</span>'+n+'</button>'}).join('')+'</div>'+
    '<div class="acts"><div>'+t.acts[0]+ic('copy')+'</div>'+(kind==='file'?'<div>'+t.acts[1]+ic('folder')+'</div>':'')+'</div></div>';
}
function docIcon(withApp){
  return '<span class="doc"><svg viewBox="0 0 40 50" width="40" height="50" aria-hidden="true"><path d="M3 1.5h23l12.5 12.5v32A2.5 2.5 0 0 1 36 48.5H4A2.5 2.5 0 0 1 1.5 46V4A2.5 2.5 0 0 1 4 1.5z" fill="#F2F2F4"/><path d="M26 1.5V12a2 2 0 0 0 2 2h10.5" fill="#D6D6DA"/></svg>'+(withApp?'<img src="'+window.APPICON+'" alt="">':'')+'</span>';
}
function messages(){
  var t=L(),h='<div class="msgs"><div class="hdr"><span class="bk">'+ic('back')+'</span><span class="av">E</span><span class="nm">'+t.emma+' ›</span></div><div class="list"><span class="when">'+t.when+'</span>';
  h+='<span class="b">'+t.emmaLine+'</span>';
  if(way==='v1'){
    h+='<button class="fileb" data-act="next">'+docIcon(rcv==='app')+'<span><b>'+t.fileName+'</b><i>'+(rcv==='app'?t.kindApp:t.kindNone)+'</i></span></button>';
    h+='<span class="b'+(rcv==='none'?' tap" data-go="page1':'')+'">'+t.fileLine.replace('uponthyhead.app','<u>uponthyhead.app</u>')+'</span>';
  }else{
    h+='<button class="card2" data-act="next"><div class="img"></div><div class="tx"><b>'+t.cardTitle+'</b><i>'+t.site+'</i></div></button>';
  }
  return h+'</div><div class="inp"><span class="pl">'+ic('plus')+'</span><span class="f">'+t.imsg+'</span></div></div>';
}
function amessages(toast){
  var t=L(),h='<div class="amsgs"><div class="hdr">'+ic('aback')+'<span class="av">E</span><span class="nm">'+t.emma+'</span></div><div class="list"><span class="when">'+t.when+'</span>';
  h+='<span class="b">'+t.emmaLine+'</span>';
  if(way==='v1'){
    h+='<button class="fileb" data-act="next">'+docIcon(false)+'<span><b>'+t.fileName+'</b><i>'+t.kindNone+'</i></span></button>';
    h+='<span class="b tap" data-go="page1">'+t.fileLine.replace('uponthyhead.app','<u>uponthyhead.app</u>')+'</span>';
  }else{
    h+='<span class="b tap" data-act="next" style="max-width:300px"><u>https://uponthyhead.app/b/x7Kp2#k=Qm9vT3...</u></span>';
  }
  h+='</div><div class="inp">'+t.amsg+'</div>'+(toast?'<div class="toast">'+t.toast+'</div>':'')+'</div>';
  return h;
}
function browser(url){
  if(isAndroid(step))return '<div class="chrome">'+ic('lock')+'<span class="u">uponthyhead.app<span>'+url+'</span></span>'+ic('tabs')+ic('dots')+'</div>';
  return '<div class="safari"><span class="c">'+ic('back')+'</span><span class="pill">uponthyhead.app</span><span class="c">'+ic('dots')+'</span></div>';
}
function page1(){
  var t=L();
  return '<div class="web"><div class="wgr"></div><div class="wgd"></div><div class="center"><img class="icon" src="'+window.APPICON+'" alt=""><h1 class="title">'+t.p1Title+'</h1><p class="lede">'+t.p1Lede+'</p>'+
    '<button class="btn primary">'+t.getApp+'</button><p class="small">'+t.free+'</p></div>'+browser('')+'</div>';
}
function page2(){
  var t=L();
  return '<div class="web"><div class="wgr"></div><div class="wgd"></div><div class="brand"><img src="'+window.APPICON+'" alt="">Upon Thy Head</div>'+
    '<div class="doc"><p class="meta">'+t.sharedUntil+'</p><h1 class="title">'+t.title+'</h1><p class="from">'+t.from+'</p><p class="meta" style="margin-top:4px;color:var(--ink-3)">'+t.date+'</p>'+
    '<div class="words">'+WORDS.map(function(w){return '<p>'+w+'</p>'}).join('')+'</div></div>'+
    '<div class="keepbar"><button class="btn primary"><img src="'+window.APPICON+'" alt="">'+t.keepIn+'</button><p class="under">'+t.thenOpen+'</p></div>'+browser('/b/x7Kp2')+'</div>';
}
function expired(){
  var t=L();
  return '<div class="web"><div class="wgr"></div><div class="wgd"></div><div class="brand"><img src="'+window.APPICON+'" alt="">Upon Thy Head</div><div class="center"><h1 class="title">'+t.exTitle+'</h1><p class="lede">'+t.exLede+'</p></div>'+browser('/b/x7Kp2')+'</div>';
}
function ql(){
  var t=L();
  return '<div class="ql"><div class="nav"><button data-go="msg">'+t.done+'</button><button class="s">'+ic('share')+'</button></div>'+
    '<div class="mid"><svg viewBox="0 0 40 50" width="96" height="120" aria-hidden="true"><path d="M3 1.5h23l12.5 12.5v32A2.5 2.5 0 0 1 36 48.5H4A2.5 2.5 0 0 1 1.5 46V4A2.5 2.5 0 0 1 4 1.5z" fill="#F2F2F4"/><path d="M26 1.5V12a2 2 0 0 0 2 2h10.5" fill="#D6D6DA"/></svg><b>'+t.fileName+'</b><i>'+t.qlKind+'</i></div></div>';
}
function keepSheet(){
  var t=L();
  return '<div class="keep"><div class="sheet" role="dialog" aria-label="'+t.ask+'"><h2 class="title">'+t.title+'</h2><p class="from">'+t.from+'</p><p class="meta">'+t.date+'</p>'+
    '<p class="q">'+t.ask+'</p><div class="actions"><button class="btn quiet">'+t.notNow+'</button><button class="btn primary" data-act="next">'+t.keep+'</button></div></div></div>';
}
function linkMade(){
  var t=L();
  return '<p class="made">'+ic('link')+t.linkMade+'</p>'+
    '<div class="linkrow"><span class="u">uponthyhead.app/b/x7Kp2<span>#k=Qm9vT3…</span></span><button class="ib" aria-label="'+t.copy+'">'+ic('copy')+'</button></div>'+
    '<p class="plain">'+t.linkLine+'</p><p class="plain2">'+t.linkLine2+'</p>'+
    '<div style="margin-top:22px"><button class="btn primary main" data-act="next">'+ic('share')+'<span>'+t.sendLink+'</span></button></div>'+
    '<button class="yours" data-go="links"><span>'+t.yourLinks+'</span>'+ic('fwd')+'</button>';
}
function offline(){
  var t=L();
  return '<p class="offline">'+ic('offline')+'<span>'+t.offLine+'</span></p>'+
    '<button class="btn primary main" data-go="sys-file">'+ic('file')+'<span>'+t.sendFile+'</span></button><p class="under">'+t.fileNote+'</p>'+quietPair()+'<p class="foot">'+t.footV1+'</p>';
}
function links(){
  var t=L();
  return '<div class="page"><div class="nav"><button class="ib">'+ic('back')+'</button><span>'+t.settings+'</span></div><div class="in"><h1 class="title">'+t.yourLinks+'</h1><p class="lede" style="margin-top:10px;margin-bottom:10px">'+t.linksLede+'</p>'+
    t.rows.map(function(r,i){return '<div class="row'+(r[2]?'':' ended')+'"><div class="x"><div class="t">'+r[0]+'</div><div class="m">'+r[1]+'</div></div>'+(r[2]?'<button class="stop"'+(i===0?' data-go="links-stop"':'')+'>'+t.stop+'</button>':'')+'</div>'}).join('')+'</div></div>';
}
function stopAsk(){
  var t=L();
  return ourSheet('<div class="ask"><h2 class="title">'+t.stopQ+'</h2><p class="lede">'+t.stopBody+'</p><div class="actions"><button class="btn tonal" data-go="links">'+t.cancel+'</button><button class="btn primary" data-go="links">'+t.stopLink+'</button></div></div>',t.stopQ);
}
var SCENE={sheet:'read','sys-file':'read',linkmade:'read','sys-link':'read',offline:'read',reading:'read',keep:'keep',page1:'page',page2:'page',expired:'page',links:'off','links-stop':'off',msg:'off',amsg:'off',toast:'off',ql:'off'};
function html(s){
  switch(s){
    case 'sheet':return reading(true)+ourSheet(sheetBody(layout));
    case 'sys-file':return reading()+sysSheet('file');
    case 'linkmade':return reading()+ourSheet(linkMade());
    case 'sys-link':return reading()+sysSheet('link');
    case 'offline':return reading()+ourSheet(offline());
    case 'msg':return messages();
    case 'amsg':return amessages(false);
    case 'toast':return amessages(true);
    case 'ql':return ql();
    case 'page1':return page1();
    case 'page2':return page2();
    case 'expired':return expired();
    case 'keep':return keepSheet();
    case 'reading':return reading();
    case 'links':return links();
    case 'links-stop':return links()+stopAsk();
  }
  return '';
}
function show(s,opts){
  opts=opts||{};step=s;
  var el=$('screen');el.innerHTML=html(s);
  root.lang=lang;
  root.classList.toggle('android',isAndroid(s));
  root.classList.toggle('has-back',s==='keep'||s==='reading');
  $('sback').textContent='◀ '+(way==='v1'&&false?'Files':(lang==='es'?'Mensajes':'Messages'));
  $('wifi').style.opacity=s==='offline'?'.25':'1';
  setScene(SCENE[s]||'off',opts.instant||SHOT);
  var w=el.firstElementChild&&el.querySelector('.sheet,.sys');
  if(w){if(SHOT||opts.instant)el.classList.add('up');else{el.classList.remove('up');requestAnimationFrame(function(){requestAnimationFrame(function(){el.classList.add('up')})})}}
  else el.classList.remove('up');
  if(!P.bare&&!SHOT){try{history.replaceState(null,'','#step='+s+'&layout='+layout+'&way='+way+'&rcv='+rcv+(lang==='es'?'&lang=es':'')+(big?'&big':''))}catch(e){}}
  buildNav();notes();
}
document.addEventListener('click',function(e){
  var t=e.target.closest&&e.target.closest('[data-act],[data-go],[data-layout],[data-way],[data-rcv],[data-lang],[data-step]');if(!t)return;
  var a;
  if((a=t.getAttribute('data-act'))==='next'){var n=nextOf(step);if(n)show(n)}
  if((a=t.getAttribute('data-go')))show(a);
  if((a=t.getAttribute('data-step')))show(a,{instant:false});
  if((a=t.getAttribute('data-layout'))){layout=a;show('sheet')}
  if((a=t.getAttribute('data-way'))){way=a;show(path().indexOf(step)>=0?step:'sheet')}
  if((a=t.getAttribute('data-rcv'))){rcv=a;show(path().indexOf(step)>=0?step:'sheet')}
  if((a=t.getAttribute('data-lang'))){lang=a;show(step,{instant:true})}
});
$('t-big').addEventListener('click',function(){big=!big;applyToggles();show(step,{instant:true})});
$('t-reduce').addEventListener('click',function(){reduce=!reduce;applyToggles()});
function applyToggles(){root.classList.toggle('big',big);root.classList.toggle('reduce',reduce);$('t-big').setAttribute('aria-pressed',big);$('t-reduce').setAttribute('aria-pressed',reduce)}
function buildNav(){
  $('nav').innerHTML=path().map(function(s,i){return '<li><button data-step="'+s+'" aria-current="'+(s===step)+'"><span class="n">'+(i+1)+'</span>'+NAME[s]+'</button></li>'}).join('');
  $('nav-x').innerHTML=EXTRAS.map(function(s){return '<li><button data-step="'+s+'" aria-current="'+(s===step)+'"><span class="n">·</span>'+NAME[s]+'</button></li>'}).join('');
  [].forEach.call(document.querySelectorAll('[data-layout]'),function(b){b.setAttribute('aria-pressed',b.getAttribute('data-layout')===layout)});
  [].forEach.call(document.querySelectorAll('[data-way]'),function(b){b.setAttribute('aria-pressed',b.getAttribute('data-way')===way)});
  [].forEach.call(document.querySelectorAll('[data-rcv]'),function(b){b.setAttribute('aria-pressed',b.getAttribute('data-rcv')===rcv)});
  [].forEach.call(document.querySelectorAll('[data-lang]'),function(b){b.setAttribute('aria-pressed',b.getAttribute('data-lang')===lang)});
}
var NOTE={
 sheet:'<h2>What to judge</h2><p>Whether the blessing itself reads as the first and best choice, and text and PDF as there but quiet. S1 is recommended (notes.md says why).</p><p>Every icon keeps a word under it. The words are also what VoiceOver reads.</p><p>The line at the foot says plainly what sending means. Under V2 it says a link is sent.</p>',
 'sys-file':'<h2>iOS’s own sheet</h2><p>Drawn as a look-alike, from memory. It holds two things: the file, and one line with the app’s address, so someone without the app has a way forward.</p><p>Tap Messages.</p>',
 'sys-link':'<h2>iOS’s own sheet</h2><p>Holding the link. The sender sees the title; the person receiving sees only “A blessing”, because the server never learns the title.</p><p>If this sheet is closed without sending, the link is erased at once.</p>',
 linkmade:'<h2>The link is made</h2><p>The blessing is locked on the phone, the locked copy goes to the server, and the key stays in the part after #, which a browser never sends to a server.</p><p>One plain line says who can read it and for how long. The second says what “locked” means, without the word “secure”.</p>',
 msg:'<h2>What arrives</h2><p>A look-alike of Messages, drawn from memory. Tap the blessing.</p>',
 amsg:'<h2>On Android</h2><p>A look-alike of Google Messages, drawn from memory.</p>',
 toast:'<h2>A dead end</h2><p>Android has nothing that opens a .blessing file until the Android app is installed. The wording of the message is Android’s, from memory.</p>',
 ql:'<h2>A dead end</h2><p>Honestly what an iPhone shows for a file it has no app for: a blank page, the name and the size. Nothing on it says what to do. Drawn from memory.</p><p>Only the line under the file gives a way forward.</p>',
 page1:'<h2>uponthyhead.app</h2><p>The best V1 can do: a page that says what was sent and how to open it. The page never sees the blessing.</p>',
 page2:'<h2>The link’s page</h2><p>The page fetches the locked copy and opens it in the browser with the key from the address. The blessing can be read by anyone, on any phone or computer.</p><p>“Keep it in Upon Thy Head” opens the app if it is there, and the App Store or Play Store if not.</p>',
 keep:'<h2>As built</h2><p>The app’s own “Keep it with your blessings?”, unchanged.</p>',
 reading:'<h2>Kept</h2><p>Its reading page, in the receiver’s app.</p>',
 offline:'<h2>No internet</h2><p>A link cannot be made, so the sheet offers the file in its place and says what that means.</p>',
 links:'<h2>Where links are seen</h2><p>Settings › Your links. Also reachable from “Your links” on the sheet after a link is made.</p>',
 'links-stop':'<h2>Stopping a link</h2><p>The server erases the locked copy. A blessing already kept stays kept: it cannot be taken back.</p>',
 expired:'<h2>After 30 days</h2><p>What a link shows once it has stopped.</p>'
};
function notes(){$('notes').innerHTML=(NOTE[step]||'')+'<h2>Full notes</h2><p>notes.md beside this file: every word in English and Spanish, the recommendation, V1 against V2, what would be built, and the questions.</p>'}

/*@@SKY@@*/

/* ---------- boot ---------- */
var booted=false;
function ready(){if(booted)return;var f=document.fonts&&document.fonts.ready?document.fonts.ready:Promise.resolve();
  f.then(function(){booted=true;draw();setTimeout(function(){root.setAttribute('data-ready','1')},SHOT?80:0)})}
window.addEventListener('resize',fit);
applyToggles();
if(SHOT||P.bare)root.classList.add('notrans');
var first=typeof P.step==='string'&&NAME[P.step]?P.step:'sheet';
target=SHARED_B;
show(first,{instant:true});
fit();
try{if(gl)init()}catch(err){console.error(err);gl=null;$('fallback').style.display='grid'}
if(!gl)ready();
var last=0;
function loop(ts){var dt=last?Math.min(.05,(ts-last)/1000):0;last=ts;step_(dt);requestAnimationFrame(loop)}
requestAnimationFrame(loop);
})();
