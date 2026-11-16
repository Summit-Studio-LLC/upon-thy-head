(function(){
'use strict';
var DEG=Math.PI/180,TAU=Math.PI*2;
var $=function(id){return document.getElementById(id)};
var P={};location.hash.replace(/^#/,'').split('&').forEach(function(s){if(!s)return;var a=s.split('=');P[a[0]]=a.length>1?decodeURIComponent(a[1]):true});
var root=document.documentElement;
if(P.bare)root.classList.add('bare');
var reduce=!!P.reduce||(window.matchMedia&&matchMedia('(prefers-reduced-motion: reduce)').matches);
var big=!!P.big;
var lang=P.lang==='es'?'es':'en';
var variant=P.v==='b'?'b':'a';
var SHOT=!!P.shot;

/* ---------- every word, English and Spanish ---------- */
var T={
en:{
 name:'Upon Thy Head',
 w1:'Record a blessing as it is given.',
 w2:'The words are written on this phone. Nothing leaves it unless you share it.',
 w3:'The words as they were spoken are always kept.',
 wq:'Free. No account. No ads.',
 cont:'Continue',
 perm:{
  mic:{label:'Microphone',title:'To hear the blessing as it is given.',sub:'It listens only while you record.',refused:'The microphone is off. You can turn it on in Settings, under Upon Thy Head.'},
  speech:{label:'Speech recognition',title:'To write the words down, here on this phone.',sub:'',refused:'Speech recognition is off. You can turn it on in Settings, under Upon Thy Head.'},
  loc:{label:'Location',title:'To find the sky above you.',sub:'Without it, the sky above the Salt Lake Temple is used.',refused:'The sky above the Salt Lake Temple will be used. You can change this in the app’s settings.'},
  face:{label:'Face ID',title:'Your blessings are locked. Face ID opens them.',sub:'You can turn the lock off in settings.',refused:'Your passcode will open them instead.'}
 },
 sys:{
  mic:{h:'“Upon Thy Head” Would Like to Access the Microphone',p:'Upon Thy Head listens only while you record a blessing. The audio stays on this phone.',b:['Don’t Allow','Allow']},
  speech:{h:'“Upon Thy Head” Would Like to Access Speech Recognition',p:'Speech is turned into text on this phone. Nothing is sent anywhere.',b:['Don’t Allow','Allow']},
  loc:{h:'Allow “Upon Thy Head” to use your location?',p:'Used once to place your first blessing’s light in the sky where it was given. Allow Once is enough.',b:['Allow Once','Allow While Using App','Don’t Allow'],map:'Approximate location'},
  face:{h:'Do you want to allow “Upon Thy Head” to use Face ID?',p:'Unlocks your blessings.',b:['Don’t Allow','OK']}
 },
 forMe:'For me',more:'Settings',
 firstRun:'When a blessing is recorded, its light appears here.',
 newBlessing:'New blessing',
 tryTitle:'Try a few words first?',
 tryLede:'Say anything, then hold Amen. You will see what the phone wrote. Nothing is kept.',
 tryIt:'Try it',notNow:'Not now',
 practice:'Practice',begin:'Begin',beginHint:'This is only practice. Nothing is kept.',
 listening:'Listening, for practice',amen:'Amen',holdHint:'Hold to finish',
 wrote:'What the phone wrote',
 said:'This is only a practice. I am trying it out before Sunday.',
 wroteLede:'Nothing from the practice is kept.',
 sharedLine:'A blessing has been shared with you.',
 sharedSub:'It opens after one more step.',
 sDate:'Sunday, October 4, 2026',sTitle:'Before the new job',sFrom:'From Dad',
 ask:'Keep it with your blessings?',keep:'Keep',
 one:'One blessing',read:'Read this blessing',
 nav:{opening:'Opening',welcome:'Welcome',mic:'Microphone',speech:'Speech recognition',loc:'Location',face:'Face ID',home:'Their sky',
  'try':'Try a few words?',begin:'Practice: Begin',listen:'Practice: listening',written:'Practice: what it wrote',
  's-opening':'Opening','s-line':'One line','s-face':'Face ID','s-keep':'Keep it?','s-kept':'Their sky, with it'}
},
es:{
 name:'Upon Thy Head',
 w1:'Graba una bendición mientras se da.',
 w2:'Las palabras se escriben en este teléfono. Nada sale de él si tú no lo compartes.',
 w3:'Las palabras tal como se dijeron siempre se guardan.',
 wq:'Gratis. Sin cuenta. Sin anuncios.',
 cont:'Continuar',
 perm:{
  mic:{label:'Micrófono',title:'Para oír la bendición mientras se da.',sub:'Solo escucha mientras grabas.',refused:'El micrófono está desactivado. Puedes activarlo en Configuración, en Upon Thy Head.'},
  speech:{label:'Reconocimiento de voz',title:'Para escribir las palabras, aquí en este teléfono.',sub:'',refused:'El reconocimiento de voz está desactivado. Puedes activarlo en Configuración, en Upon Thy Head.'},
  loc:{label:'Ubicación',title:'Para encontrar el cielo sobre ti.',sub:'Sin ella, se usa el cielo sobre el Templo de Salt Lake.',refused:'Se usará el cielo sobre el Templo de Salt Lake. Puedes cambiarlo en los ajustes de la app.'},
  face:{label:'Face ID',title:'Tus bendiciones están bloqueadas. Face ID las abre.',sub:'Puedes quitar el bloqueo en los ajustes.',refused:'Tu código las abrirá en su lugar.'}
 },
 sys:{
  mic:{h:'“Upon Thy Head” quiere acceder al micrófono',p:'Upon Thy Head escucha solo mientras grabas una bendición. El audio se queda en este teléfono.',b:['No permitir','Permitir']},
  speech:{h:'“Upon Thy Head” quiere acceder al reconocimiento de voz',p:'La voz se convierte en texto en este teléfono. No se envía nada a ningún lado.',b:['No permitir','Permitir']},
  loc:{h:'¿Permitir que “Upon Thy Head” use tu ubicación?',p:'Se usa una vez para poner la luz de tu primera bendición en el cielo donde se dio. Con «Permitir una vez» basta.',b:['Permitir una vez','Permitir al usar la app','No permitir'],map:'Ubicación aproximada'},
  face:{h:'¿Quieres permitir que “Upon Thy Head” use Face ID?',p:'Desbloquea tus bendiciones.',b:['No permitir','Aceptar']}
 },
 forMe:'Para mí',more:'Ajustes',
 firstRun:'Cuando se grabe una bendición, su luz aparecerá aquí.',
 newBlessing:'Nueva bendición',
 tryTitle:'¿Probar primero con unas palabras?',
 tryLede:'Di cualquier cosa y luego mantén presionado Amén. Verás lo que escribió el teléfono. No se guarda nada.',
 tryIt:'Probar',notNow:'Ahora no',
 practice:'Práctica',begin:'Comenzar',beginHint:'Es solo una práctica. No se guarda nada.',
 listening:'Escuchando, de práctica',amen:'Amén',holdHint:'Mantén presionado para terminar',
 wrote:'Lo que escribió el teléfono',
 said:'Esto es solo una práctica. Lo estoy probando antes del domingo.',
 wroteLede:'No se guarda nada de la práctica.',
 sharedLine:'Alguien compartió una bendición contigo.',
 sharedSub:'Se abre después de un paso más.',
 sDate:'Domingo, 4 de octubre de 2026',sTitle:'Antes del nuevo trabajo',sFrom:'De papá',
 ask:'¿Guardarla con tus bendiciones?',keep:'Guardar',
 one:'Una bendición',read:'Leer esta bendición',
 nav:null
}};
T.es.nav=T.en.nav;
var L=function(){return T[lang]};

/* ---------- the steps ---------- */
var MAIN=['opening','welcome','mic','speech','loc','face'];
var FOUR_A=['home'],FOUR_B=['try','begin','listen','written','home'];
var SHARED=['s-opening','s-line','s-face','s-keep','s-kept'];
var SCENE={opening:'open','s-opening':'open',welcome:'welcome',mic:'dim',speech:'dim',loc:'dim',face:'dim','s-line':'welcome','s-face':'dim',
  home:'home','try':'dim',begin:'rec0',listen:'rec',written:'after','s-keep':'keep','s-kept':'kept'};
var step=null,refused={},dialog=null,flow='main';

function nextOf(s){
  if(s==='opening')return 'welcome';
  if(s==='s-opening')return 's-line';
  var i=MAIN.indexOf(s);if(i>=0)return i<MAIN.length-1?MAIN[i+1]:(variant==='b'?'try':'home');
  i=FOUR_B.indexOf(s);if(i>=0&&i<FOUR_B.length-1)return FOUR_B[i+1];
  i=SHARED.indexOf(s);if(i>=0&&i<SHARED.length-1)return SHARED[i+1];
  return null;
}

/* ---------- screens ---------- */
function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;')}
function permHTML(id,k){var p=L().perm[k];return '<section class="screen perm" id="s-'+id+'" data-perm="'+k+'"><div class="scrim-b" style="height:520px"></div><div class="content">'+
  '<p class="meta">'+p.label+'</p><h2 class="title">'+p.title+'</h2>'+(p.sub?'<p class="lede sub">'+p.sub+'</p>':'')+'<p class="lede refused">'+p.refused+'</p>'+
  '<div class="actions"><button class="btn primary" data-act="ask">'+L().cont+'</button></div></div></section>'}
function render(){
  var t=L(),h='';
  h+='<section class="screen" id="s-opening" data-act="next"><p class="name">'+t.name+'</p></section>';
  h+='<section class="screen" id="s-s-opening" data-act="next"><p class="name">'+t.name+'</p></section>';
  h+='<section class="screen" id="s-welcome"><div class="scrim-b" style="height:600px"></div><div class="content">'+
     '<p class="wl">'+t.w1+'</p><p class="wl">'+t.w2+'</p><p class="wl">'+t.w3+'</p><p class="wq">'+t.wq+'</p>'+
     '<div class="actions"><button class="btn primary" data-act="next">'+t.cont+'</button></div></div></section>';
  h+=permHTML('mic','mic')+permHTML('speech','speech')+permHTML('loc','loc')+permHTML('face','face')+permHTML('s-face','face');
  h+='<section class="screen" id="s-home"><div class="scrim-t"></div><div class="scrim-b" style="height:300px"></div>'+
     '<div class="head"><h2 class="title">'+t.forMe+'</h2><button class="iconbtn" aria-label="'+t.more+'"><svg class="ico" viewBox="0 0 24 24"><path d="M5.5 12h.01M12 12h.01M18.5 12h.01" stroke-width="2.4"/></svg></button></div>'+
     '<p class="empty">'+t.firstRun+'</p><div class="newrow"><button class="new"><span></span>'+t.newBlessing+'</button></div></section>';
  h+='<section class="screen" id="s-try"><div class="scrim-b" style="height:520px"></div><div class="content"><h2 class="title">'+t.tryTitle+'</h2>'+
     '<p class="lede" style="margin-top:calc(12px*var(--t))">'+t.tryLede+'</p><div class="actions"><button class="btn primary" data-act="next">'+t.tryIt+'</button>'+
     '<button class="btn quiet" data-act="go:home">'+t.notNow+'</button></div></div></section>';
  h+='<section class="screen" id="s-begin"><div class="scrim-t"></div><button class="cancel" data-act="go:home">'+t.notNow+'</button><p class="toplabel">'+t.practice+'</p>'+
     '<button class="begin" data-act="next">'+t.begin+'</button><p class="ready-hint">'+t.beginHint+'</p></section>';
  h+='<section class="screen" id="s-listen"><div class="scrim-t"></div><div class="scrim-b" style="height:230px"></div><p class="toplabel">'+t.listening+'</p>'+
     '<button class="hold" id="hold" aria-label="'+t.amen+'. '+t.holdHint+'"><svg viewBox="0 0 88 88" aria-hidden="true"><circle class="track" cx="44" cy="44" r="42.5"/><circle class="prog" cx="44" cy="44" r="42.5"/></svg><span>'+t.amen+'</span></button>'+
     '<p class="hint">'+t.holdHint+'</p></section>';
  h+='<section class="screen" id="s-written"><div class="scrim-b" style="height:560px"></div><div class="content"><p class="meta">'+t.wrote+'</p>'+
     '<p class="said">'+t.said+'</p><p class="lede">'+t.wroteLede+'</p><div class="actions"><button class="btn primary" data-act="next">'+t.cont+'</button></div></div></section>';
  h+='<section class="screen" id="s-s-line"><div class="scrim-b" style="height:480px"></div><div class="content"><h2 class="title">'+t.sharedLine+'</h2>'+
     '<p class="lede" style="margin-top:calc(12px*var(--t))">'+t.sharedSub+'</p><div class="actions"><button class="btn primary" data-act="next">'+t.cont+'</button></div></div></section>';
  h+='<section class="screen" id="s-s-keep"><div class="sheet" role="dialog" aria-label="'+t.ask+'"><p class="meta">'+t.sDate+'</p><h2 class="title">'+t.sTitle+'</h2><p class="from">'+t.sFrom+'</p>'+
     '<p class="ask">'+t.ask+'</p><div class="actions"><button class="btn tonal" data-act="go:home">'+t.notNow+'</button><button class="btn primary" data-act="next">'+t.keep+'</button></div></div></section>';
  h+='<section class="screen" id="s-s-kept"><div class="scrim-t"></div><div class="scrim-b" style="height:380px"></div>'+
     '<div class="head"><div><h2 class="title">'+t.forMe+'</h2><p class="meta" style="margin-top:2px">'+t.one+'</p></div><button class="iconbtn" aria-label="'+t.more+'"><svg class="ico" viewBox="0 0 24 24"><path d="M5.5 12h.01M12 12h.01M18.5 12h.01" stroke-width="2.4"/></svg></button></div>'+
     '<button class="cap" aria-label="'+t.read+'"><span><span class="meta" style="display:block">'+t.sDate+'</span><span class="title" style="display:block">'+t.sTitle+'</span><span class="from" style="display:block">'+t.sFrom+'</span></span>'+
     '<span class="go"><svg class="ico" viewBox="0 0 24 24"><path d="M10 6l6 6-6 6"/></svg></span></button>'+
     '<div class="newrow"><button class="new"><span></span>'+t.newBlessing+'</button></div></section>';
  $('screens').innerHTML=h;
  root.lang=lang;
  wireHold();
  if(step){var cur=$('s-'+step);if(cur)cur.classList.add('on')}
  markRefused();
  if(dialog)showDialog(dialog,true);
  buildNav();
}
function markRefused(){[].forEach.call(document.querySelectorAll('.perm'),function(s){var id=s.id.slice(2);s.classList.toggle('was-refused',!!refused[id])})}

/* the system's question, as a look-alike */
function showDialog(k,instant){
  var s=L().sys[k],h='<h3>'+s.h+'</h3><p>'+s.p+'</p>';
  if(k==='loc'){h+='<div class="map"><span>'+s.map+'</span></div><div class="ab stack"><button data-sys="allow" class="pref">'+s.b[0]+'</button><button data-sys="allow">'+s.b[1]+'</button><button data-sys="deny">'+s.b[2]+'</button></div>'}
  else h+='<div class="ab"><button data-sys="deny">'+s.b[0]+'</button><button data-sys="allow">'+s.b[1]+'</button></div>';
  $('alert').innerHTML=h;dialog=k;$('veil').classList.add('on');
}
function hideDialog(){dialog=null;$('veil').classList.remove('on')}

/* ---------- moving between steps ---------- */
var openT0=0;
function go(s,opts){
  opts=opts||{};
  if(SHARED.indexOf(s)>=0)flow='shared';else if(s!=='home')flow='main';
  if(s==='home'&&opts.fromShared)flow='shared';
  hideDialog();
  var prev=step;step=s;
  [].forEach.call(document.querySelectorAll('#screens .screen'),function(el){el.classList.toggle('on',el.id==='s-'+s)});
  root.classList.toggle('at-opening',SCENE[s]==='open');
  setScene(SCENE[s],opts.instant);
  if(SCENE[s]==='open'){openT0=clock;opening=0;if(opts.instant&&SHOT)opening=9}
  clearTimeout(autoT);
  if(SCENE[s]==='open'&&!SHOT)autoT=setTimeout(function(){if(step===s)go(nextOf(s))},3800);
  if(!P.bare&&!SHOT){try{history.replaceState(null,'','#step='+s+(variant==='b'?'&v=b':'')+(lang==='es'?'&lang=es':''))}catch(e){}}
  buildNav();
}
var autoT=0;
document.addEventListener('click',function(e){
  var t=e.target.closest&&e.target.closest('[data-act],[data-sys],[data-go],[data-v],[data-l]');if(!t)return;
  var a=t.getAttribute('data-act');
  if(a==='next'){var n=nextOf(step);if(n)go(n)}
  else if(a&&a.indexOf('go:')===0)go(a.slice(3),{fromShared:flow==='shared'});
  else if(a==='ask'){var sec=t.closest('.perm'),id=sec.id.slice(2);if(refused[id]){go(nextOf(step))}else showDialog(sec.getAttribute('data-perm'))}
  var sy=t.getAttribute('data-sys');
  if(sy==='allow'){hideDialog();setTimeout(function(){go(nextOf(step))},250)}
  if(sy==='deny'){refused[step]=true;markRefused();hideDialog()}
  var g=t.getAttribute('data-go');if(g){refused={};markRefused();go(g)}
  var v=t.getAttribute('data-v');if(v){variant=v;buildNav();if(FOUR_B.indexOf(step)>=0||step==='home'||step==='try')go(v==='b'?'try':'home')}
  var l=t.getAttribute('data-l');if(l&&l!==lang){lang=l;render()}
});
$('t-big').addEventListener('click',function(){big=!big;applyToggles()});
$('t-reduce').addEventListener('click',function(){reduce=!reduce;applyToggles()});
function applyToggles(){if(scene)setScene(scene);root.classList.toggle('big',big);root.classList.toggle('reduce',reduce);$('t-big').setAttribute('aria-pressed',big);$('t-reduce').setAttribute('aria-pressed',reduce)}
function buildNav(){
  var nv=T.en.nav,mainList=MAIN.concat(variant==='b'?FOUR_B:FOUR_A),num={opening:'1',welcome:'2',mic:'3',home:'4','try':'4'};
  $('nav-main').innerHTML=mainList.map(function(s){return '<li><button data-go="'+s+'" aria-current="'+(s===step)+'"><span class="n">'+(num[s]||'')+'</span>'+nv[s]+'</button></li>'}).join('');
  $('nav-shared').innerHTML=SHARED.map(function(s,i){return '<li><button data-go="'+s+'" aria-current="'+(s===step)+'"><span class="n">'+(i===0?'▸':'')+'</span>'+nv[s]+'</button></li>'}).join('');
  [].forEach.call(document.querySelectorAll('[data-v]'),function(b){b.setAttribute('aria-pressed',b.getAttribute('data-v')===variant)});
  [].forEach.call(document.querySelectorAll('[data-l]'),function(b){b.setAttribute('aria-pressed',b.getAttribute('data-l')===lang)});
}
/* Amen: press and hold */
function wireHold(){
  var h=$('hold');if(!h)return;var timer=null;
  function start(ev){ev.preventDefault();h.classList.add('holding');timer=setTimeout(function(){timer=null;h.classList.remove('holding');go(nextOf(step))},900)}
  function end(){if(timer){clearTimeout(timer);timer=null}h.classList.remove('holding')}
  h.addEventListener('pointerdown',start);h.addEventListener('pointerup',end);h.addEventListener('pointerleave',end);h.addEventListener('pointercancel',end);
  h.addEventListener('keydown',function(e){if(e.key===' '||e.key==='Enter'){e.preventDefault();go(nextOf(step))}});
}

/* ---------- the sky (the prototype's renderer, cut down) ---------- */
var PALS={l:[[1,.97,.90],[1,.80,.50],[1,.66,.36]],o:[[1,.94,.82],[1,.77,.46],[.98,.56,.28]],sky:[.0030,.0021,.0013],tint:[1.07,.98,.85]};
var PLACE={lat:40.77,lon:-111.89}; // the Salt Lake Temple, the place used when location is refused
function vec(ra,dec){return [Math.cos(dec)*Math.cos(ra),Math.cos(dec)*Math.sin(ra),Math.sin(dec)]}
function zenith(ms){var jd=ms/864e5+2440587.5,gmst=280.46061837+360.98564736629*(jd-2451545.0),lst=((gmst+PLACE.lon)%360+360)%360;return {ra:lst*DEG,dec:PLACE.lat*DEG}}
function clamp(x,a,b){return x<a?a:x>b?b:x}
function smooth(a,b,x){var t=clamp((x-a)/(b-a),0,1);return t*t*(3-2*t)}
var NOW=zenith(Date.UTC(2026,10,16,3,0));          // the evening this is first opened
var SHARED_B=zenith(Date.UTC(2026,9,5,1,40));       // the shared blessing: Oct 4, 2026, 7:40 pm
var VIEW={
  open:{fov:80,cy:.15,exp:1,st:1,orb:0,ring:.22,light:1},
  welcome:{fov:80,cy:.32,exp:.5,st:.7,orb:0,ring:.14,light:.55},
  dim:{fov:84,cy:.3,exp:.38,st:.6,orb:0,ring:.1,light:0},
  home:{fov:90,cy:.2,exp:1,st:1,orb:0,ring:.2,light:0},
  rec0:{fov:74,cy:.14,exp:.25,st:.45,orb:0,ring:0,light:0},
  rec:{fov:74,cy:.14,exp:.018,st:.2,orb:1,ring:0,light:0},
  after:{fov:74,cy:.3,exp:.6,st:.75,orb:0,ring:0,light:0},
  keep:{fov:60,cy:.5,exp:.85,st:.95,orb:0,ring:.2,light:1},
  kept:{fov:90,cy:.2,exp:1,st:1,orb:0,ring:.2,light:1}
};
var cam={ra:NOW.ra,dec:NOW.dec,fov:80,cy:.15,exp:0,st:0,orb:0,ring:0,light:0},goal={},scene='open',clock=0,opening=0,target=NOW,ringK=1;
function setScene(n,instant){
  scene=n;var v=VIEW[n],k;for(k in v)goal[k]=v[k];if(big&&n==="welcome")goal.light=0; /* at large text the words reach up to where the light is */
  target=flow==='shared'?SHARED_B:NOW;
  if(instant){for(k in goal)cam[k]=goal[k];cam.ra=target.ra;cam.dec=target.dec}
}
var cv=$('sky'),gl=null,PX=1,K=1,F,R,U,TX,TY;
try{gl=cv.getContext('webgl',{alpha:false,antialias:false,preserveDrawingBuffer:true})}catch(e){}
if(!gl)$('fallback').style.display='grid';
function fit(){
  if(P.bare){K=1}else{K=Math.min(1,(window.innerHeight-32)/868,(window.innerWidth-32)/414);var dv=$('device');dv.style.transform='scale('+K+')';dv.style.margin=(-(1-K)*434).toFixed(1)+'px '+(-(1-K)*207).toFixed(1)+'px'}
  if(!gl)return;var dpr=Math.min(3,window.devicePixelRatio||1);PX=dpr*(K<1?Math.max(K,.5):1);
  var w=Math.round(390*PX),h=Math.round(844*PX);if(cv.width!==w||cv.height!==h){cv.width=w;cv.height=h}
}
function sh(type,src){var s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(s));return s}
function prog(vs,fs,names){var p=gl.createProgram();gl.attachShader(p,sh(gl.VERTEX_SHADER,vs));gl.attachShader(p,sh(gl.FRAGMENT_SHADER,fs));gl.linkProgram(p);
  if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(p));var o={p:p};names.forEach(function(n){o[n]=n.charAt(0)==='a'?gl.getAttribLocation(p,n):gl.getUniformLocation(p,n)});return o}
var PROJ='uniform vec3 uF,uR,uU;uniform vec2 uT;uniform float uCy;vec3 proj(vec3 p){float z=dot(p,uF);vec2 q=2.*vec2(dot(p,uR),dot(p,uU))/(1.0001+z);return vec3(q.x/uT.x,q.y/uT.y+uCy,z);}';
var pBg,pSt,pLi,pLn,quad,stars,nStars=0,rings,nRing=0,mwTex,mwReady=false,SEG=720;
function bvColor(bv){bv=clamp(bv,-.4,2);var T2=4600*(1/(.92*bv+1.7)+1/(.92*bv+.62)),t=T2/100,r,g,b;
  if(t<=66){r=255;g=99.47*Math.log(t)-161.12;b=t<=19?0:138.52*Math.log(t-10)-305.04}else{r=329.7*Math.pow(t-60,-.1332);g=288.12*Math.pow(t-60,-.0755);b=255}
  var c=[clamp(r,0,255)/255,clamp(g,0,255)/255,clamp(b,0,255)/255],m=Math.max(c[0],c[1],c[2]),s=.62;return [1-s+s*c[0]/m,1-s+s*c[1]/m,1-s+s*c[2]/m]}
function init(){
  pBg=prog('attribute vec2 aQ;varying vec2 vN;void main(){vN=aQ;gl_Position=vec4(aQ,0.,1.);}',
   'precision highp float;varying vec2 vN;uniform sampler2D uMW;uniform vec3 uF,uR,uU;uniform vec2 uT;uniform float uCy,uExp,uAsp,uHas;uniform vec4 uOrb;uniform vec3 uSky,uTint,uO1,uO2,uO3;'+
   'float hash(vec2 p){vec3 q=fract(vec3(p.xyx)*.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z);}'+
   'void main(){vec2 q=vec2(vN.x*uT.x,(vN.y-uCy)*uT.y);float r2=dot(q,q);vec3 d=normalize(uF*(4.-r2)+(uR*q.x+uU*q.y)*4.);'+
   'vec2 uv=vec2(.5-atan(d.y,d.x)/6.28318531,.5-asin(clamp(d.z,-1.,1.))/3.14159265);vec3 t=texture2D(uMW,uv).rgb*uHas;t=pow(t,vec3(1.3333*2.2));'+
   'vec3 lin=t*uTint*uExp*3.4+uSky*(.35+.65*uExp)*min(1.,uExp*8.);vec3 c=1.-exp(-lin*1.9);c=pow(c,vec3(.4545));'+
   'vec2 e=vN*vec2(uAsp,1.);c*=1.-.22*smoothstep(.55,1.25,length(e));'+
   'float od=length((vN-uOrb.xy)*vec2(uAsp,1.))/uOrb.z;vec3 orb=uO1*exp(-od*od*3.2)*.5+uO2*exp(-od*1.6)*.4+uO3*.15/(1.+od*od*1.1)*smoothstep(5.5,1.,od);'+
   'c+=orb*uOrb.w;c+=(hash(gl_FragCoord.xy)-.5)/255.*1.6*min(1.,uExp*8.);gl_FragColor=vec4(c,1.);}',
   ['aQ','uMW','uF','uR','uU','uT','uCy','uExp','uAsp','uHas','uOrb','uSky','uTint','uO1','uO2','uO3']);
  pSt=prog('attribute vec3 aP;attribute vec4 aC;'+PROJ+'uniform float uPx,uExp,uTime,uTw;varying vec4 vC;varying float vK;'+
   'void main(){vec3 n=proj(aP);float lum=pow(10.,.4*(6.-aC.w));float rad=.30+.16*pow(lum,.30);'+
   'float a=.66*pow(lum,.6)*uExp;a*=1.+uTw*.14*sin(uTime*(1.3+fract(aC.w*7.31)*2.6)+aP.x*311.+aP.y*173.);'+
   'float sd=rad*uPx;float sc=max(sd,.82);a*=sd*sd/(sc*sc);float k=clamp((lum-5.)/110.,0.,1.);vK=k;float size=sc*6.4*(1.+3.*k);'+
   'if(n.z<-.6||a<.006)n.xy=vec2(4.);gl_Position=vec4(n.xy,0.,1.);gl_PointSize=max(size,2.);vC=vec4(aC.rgb,min(a,2.4));}',
   'precision mediump float;varying vec4 vC;varying float vK;void main(){vec2 p=gl_PointCoord*2.-1.;float d=length(p);float r=d*3.2*(1.+3.*vK);'+
   'float i=exp(-.5*r*r)+vK*.085/(1.+.22*r*r)*smoothstep(1.,.35,d);gl_FragColor=vec4(vC.rgb*vC.a*i,1.);}',
   ['aP','aC','uF','uR','uU','uT','uCy','uPx','uExp','uTime','uTw']);
  pLi=prog('attribute vec2 aQ;uniform vec2 uC,uH;varying vec2 vP;void main(){vP=aQ;gl_Position=vec4(uC+aQ*uH,0.,1.);}',
   'precision highp float;varying vec2 vP;uniform float uRad,uFoc,uA;uniform vec3 uL1,uL2,uL3;void main(){float d=length(vP);float r=d*uRad;float f=uFoc;'+
   'float s=mix(1.5,2.5,f);float core=exp(-r*r/(2.*s*s))*1.3;float glow=exp(-r/mix(4.5,9.,f))*mix(.5,.8,f);'+
   'float halo=mix(.05,.15,f)/(1.+r*r/mix(120.,520.,f));vec2 a=abs(vP)*uRad;float L=mix(7.,24.,f);'+
   'float sp=(exp(-a.y*a.y/.42)*exp(-a.x/L)+exp(-a.x*a.x/.42)*exp(-a.y/L))*mix(.1,.42,f);'+
   'vec3 col=uL1*core+uL2*(glow+sp)+uL3*halo;gl_FragColor=vec4(col*smoothstep(1.,.45,d)*uA,1.);}',
   ['aQ','uC','uH','uRad','uFoc','uA','uL1','uL2','uL3']);
  pLn=prog('attribute vec3 aP;'+PROJ+'uniform float uA;varying float vA;void main(){vec3 n=proj(aP);vA=uA*smoothstep(-.2,.3,n.z);gl_Position=vec4(n.xy,0.,1.);}',
   'precision mediump float;varying float vA;uniform vec3 uLc;void main(){gl_FragColor=vec4(uLc*vA,1.);}',['aP','uF','uR','uU','uT','uCy','uA','uLc']);
  quad=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,1,1]),gl.STATIC_DRAW);
  var bin=atob(window.SKY_STARS),n=bin.length/6,arr=new Float32Array(n*7),i,o;
  for(i=0;i<n;i++){o=i*6;var ra=(bin.charCodeAt(o)|bin.charCodeAt(o+1)<<8)/65536*TAU,dv=bin.charCodeAt(o+2)|bin.charCodeAt(o+3)<<8;if(dv>32767)dv-=65536;
    var dec=dv/32767*Math.PI/2,mag=bin.charCodeAt(o+4)/20-2,c=bvColor(bin.charCodeAt(o+5)/100-.5),j=i*7;
    arr[j]=Math.cos(dec)*Math.cos(ra);arr[j+1]=Math.cos(dec)*Math.sin(ra);arr[j+2]=Math.sin(dec);arr[j+3]=c[0];arr[j+4]=c[1];arr[j+5]=c[2];arr[j+6]=mag}
  stars=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,stars);gl.bufferData(gl.ARRAY_BUFFER,arr,gl.STATIC_DRAW);nStars=n;window.SKY_STARS=null;
  /* the ring: the circle of sky that passes overhead, starting half a turn from tonight's zenith so the sweep crosses it midway */
  rings=[NOW,SHARED_B].map(function(c){var rr=new Float32Array((SEG+1)*3);
    for(var i=0;i<=SEG;i++){var v=vec(c.ra-Math.PI+i/SEG*TAU,PLACE.lat*DEG);rr[i*3]=v[0];rr[i*3+1]=v[1];rr[i*3+2]=v[2]}
    var b=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.bufferData(gl.ARRAY_BUFFER,rr,gl.STATIC_DRAW);return b});nRing=SEG+1;
  mwTex=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,mwTex);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGB,1,1,0,gl.RGB,gl.UNSIGNED_BYTE,new Uint8Array([0,0,0]));
  var img=new Image();img.onload=function(){var max=gl.getParameter(gl.MAX_TEXTURE_SIZE),src=img;
    if(img.width>max){var c2=document.createElement('canvas');c2.width=max;c2.height=max/2;c2.getContext('2d').drawImage(img,0,0,c2.width,c2.height);src=c2}
    gl.bindTexture(gl.TEXTURE_2D,mwTex);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGB,gl.RGB,gl.UNSIGNED_BYTE,src);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.REPEAT);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    mwReady=true;window.SKY_MW=null;ready()};
  img.src=window.SKY_MW;
}
function basis(){var cd=Math.cos(cam.dec),sd=Math.sin(cam.dec),ca=Math.cos(cam.ra),sa=Math.sin(cam.ra);F=[cd*ca,cd*sa,sd];R=[sa,-ca,0];U=[-sd*ca,-sd*sa,cd];TY=2*Math.tan(cam.fov*DEG/4);TX=TY*390/844}
function project(v){var z=v[0]*F[0]+v[1]*F[1]+v[2]*F[2],x=v[0]*R[0]+v[1]*R[1],y=v[0]*U[0]+v[1]*U[1]+v[2]*U[2],k=2/(1.0001+z);return {nx:x*k/TX,ny:y*k/TY+cam.cy,z:z}}
function breath(t){var p=t%10;return p<4?(.5-.5*Math.cos(Math.PI*p/4)):(.5+.5*Math.cos(Math.PI*(p-4)/6))}

/* The opening, second by second: black; the sky rises (0-1.4s), the ring crosses it (0.8-2.2s),
   one warm light arrives overhead (1.8-2.6s), the name (2.3-3.0s). It moves on at 3.8s, or at a tap. */
function openingFrame(t){
  var name=document.querySelector('.screen.on .name');
  if(reduce){var f=smooth(0,1.2,t);cam.exp=f;cam.st=f;ringK=1;cam.ring=.22*f;cam.light=f;cam.dec=target.dec;cam.cy=.15;if(name){name.style.opacity=smooth(.6,1.6,t);name.style.transform='none'}return}
  cam.exp=smooth(0,1.6,t);cam.st=smooth(.1,1.4,t);
  cam.dec=target.dec-(1-smooth(0,2.4,t))*22*DEG;cam.ra=target.ra;
  ringK=smooth(.8,2.3,t);cam.ring=.22*smooth(.8,1.2,t);
  cam.light=smooth(1.8,2.7,t);
  if(name){name.style.opacity=smooth(2.3,3.1,t);name.style.transform='translateY('+(6*(1-smooth(2.3,3.3,t))).toFixed(2)+'px)'}
}
function step_(dt){
  clock+=dt;
  if(scene==='open'){opening+=dt;openingFrame(SHOT?(P.t!==undefined?+P.t:9):opening)}
  else{
    ringK=Math.min(1,ringK+dt);
    var k=1-Math.exp(-dt*(reduce?6:2.2)),key;for(key in goal)cam[key]+=(goal[key]-cam[key])*k;
    var dr=target.ra-cam.ra;dr=((dr+Math.PI)%TAU+TAU)%TAU-Math.PI;cam.ra+=dr*k;cam.dec+=(target.dec-cam.dec)*k;
  }
  if(!reduce&&!SHOT)target={ra:target.ra+dt*.0025,dec:target.dec}; /* the sky turns, very slowly */
  draw();
}
function draw(){
  if(!gl||!pBg)return;basis();
  var W=cv.width,H=cv.height,asp=390/844;gl.viewport(0,0,W,H);gl.disable(gl.BLEND);
  gl.useProgram(pBg.p);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(pBg.aQ);gl.vertexAttribPointer(pBg.aQ,2,gl.FLOAT,false,0,0);
  gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,mwTex);gl.uniform1i(pBg.uMW,0);
  gl.uniform3fv(pBg.uF,F);gl.uniform3fv(pBg.uR,R);gl.uniform3fv(pBg.uU,U);gl.uniform2f(pBg.uT,TX,TY);gl.uniform1f(pBg.uCy,cam.cy);
  gl.uniform1f(pBg.uExp,Math.max(0,cam.exp));gl.uniform3fv(pBg.uSky,PALS.sky);gl.uniform3fv(pBg.uTint,PALS.tint);gl.uniform3fv(pBg.uO1,PALS.o[0]);gl.uniform3fv(pBg.uO2,PALS.o[1]);gl.uniform3fv(pBg.uO3,PALS.o[2]);
  gl.uniform1f(pBg.uAsp,asp);gl.uniform1f(pBg.uHas,mwReady?1:0);
  var br=reduce||SHOT?.6:breath(clock);gl.uniform4f(pBg.uOrb,0,cam.cy,.15+.075*br,cam.orb*(.55+.45*br));
  gl.drawArrays(gl.TRIANGLE_STRIP,0,4);
  gl.enable(gl.BLEND);gl.blendFunc(gl.ONE,gl.ONE);
  if(cam.ring>.004&&ringK>0){
    gl.useProgram(pLn.p);gl.bindBuffer(gl.ARRAY_BUFFER,rings[flow==='shared'?1:0]);gl.enableVertexAttribArray(pLn.aP);gl.vertexAttribPointer(pLn.aP,3,gl.FLOAT,false,0,0);
    gl.uniform3fv(pLn.uF,F);gl.uniform3fv(pLn.uR,R);gl.uniform3fv(pLn.uU,U);gl.uniform2f(pLn.uT,TX,TY);gl.uniform1f(pLn.uCy,cam.cy);
    gl.uniform1f(pLn.uA,cam.ring);gl.uniform3fv(pLn.uLc,PALS.l[1]);if(ringK>=1)gl.drawArrays(gl.LINE_STRIP,0,nRing);
    else{var a0=Math.round(nRing*.36),n=Math.max(2,Math.round(nRing*.28*ringK));gl.drawArrays(gl.LINE_STRIP,a0,n)}
  }
  gl.useProgram(pSt.p);gl.bindBuffer(gl.ARRAY_BUFFER,stars);
  gl.enableVertexAttribArray(pSt.aP);gl.vertexAttribPointer(pSt.aP,3,gl.FLOAT,false,28,0);gl.enableVertexAttribArray(pSt.aC);gl.vertexAttribPointer(pSt.aC,4,gl.FLOAT,false,28,12);
  gl.uniform3fv(pSt.uF,F);gl.uniform3fv(pSt.uR,R);gl.uniform3fv(pSt.uU,U);gl.uniform2f(pSt.uT,TX,TY);gl.uniform1f(pSt.uCy,cam.cy);
  gl.uniform1f(pSt.uPx,PX*Math.pow(80/cam.fov,.35));gl.uniform1f(pSt.uExp,Math.max(0,cam.st));gl.uniform1f(pSt.uTime,clock);gl.uniform1f(pSt.uTw,reduce?0:1);
  gl.drawArrays(gl.POINTS,0,nStars);gl.disableVertexAttribArray(pSt.aC);
  if(cam.light>.01){
    var lv=flow==='shared'?vec(SHARED_B.ra,SHARED_B.dec):vec(NOW.ra,NOW.dec),p=project(lv);
    if(p.z>-.3){gl.useProgram(pLi.p);gl.uniform3fv(pLi.uL1,PALS.l[0]);gl.uniform3fv(pLi.uL2,PALS.l[1]);gl.uniform3fv(pLi.uL3,PALS.l[2]);
      gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(pLi.aQ);gl.vertexAttribPointer(pLi.aQ,2,gl.FLOAT,false,0,0);
      var RAD=110;gl.uniform2f(pLi.uC,p.nx,p.ny);gl.uniform2f(pLi.uH,RAD/195,RAD/422);gl.uniform1f(pLi.uRad,RAD);gl.uniform1f(pLi.uFoc,scene==='open'?.75:1);gl.uniform1f(pLi.uA,cam.light);
      gl.drawArrays(gl.TRIANGLE_STRIP,0,4)}
  }
}

/* ---------- boot ---------- */
var booted=false;
function ready(){if(booted)return;var f=document.fonts&&document.fonts.ready?document.fonts.ready:Promise.resolve();
  f.then(function(){booted=true;draw();setTimeout(function(){root.setAttribute('data-ready','1')},SHOT?60:0)})}
window.addEventListener('resize',fit);
applyToggles();
if(P.shot||P.bare)root.classList.add('notrans');
render();
var first=typeof P.step==='string'?P.step:'opening';
if(SHARED.indexOf(first)>=0||P.shared)flow='shared';
if(P.refused)refused[first]=true;
go(first,{instant:true});
if(P.fromShared)flow='shared';
markRefused();
if(P.dialog){var sec=document.querySelector('.screen.on.perm');if(sec)showDialog(sec.getAttribute('data-perm'),true)}
if(P.t!==undefined){opening=+P.t}
fit();
try{if(gl)init()}catch(err){console.error(err);gl=null;$('fallback').style.display='grid'}
if(!gl)ready();
var last=0;
function loop(ts){var dt=last?Math.min(.05,(ts-last)/1000):0;last=ts;step_(dt);requestAnimationFrame(loop)}
requestAnimationFrame(loop);
window.__ob={go:go,cam:cam,setOpening:function(t){opening=t}};
})();
