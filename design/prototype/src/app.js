(function(){
'use strict';
var DEG=Math.PI/180, TAU=Math.PI*2;
var $=function(id){return document.getElementById(id)};
var P={};location.hash.replace(/^#/,'').split('&').forEach(function(s){if(!s)return;var a=s.split('=');P[a[0]]=a.length>1?a[1]:true});
var SCREENS=['record','after','review','read','sky'];
var first=SCREENS.filter(function(s){return P[s]})[0]||'sky';
if(P.bare)document.documentElement.classList.add('bare');
var reduce=window.matchMedia&&matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ---------- palettes: 60 night, 30 page, 10 light. Lamplight is the chosen default, Vigil the alternate.
   Daybreak and Starlight were explored and set aside; they stay reachable with #pal=daybreak or #pal=starlight. ---------- */
var PALS={
 vigil:{css:{ground:'#070A12',surface:'#0C101A',raised:'#141927',ink:'#EEE7D8','ink-2':'#A9ADBB','ink-3':'#7D8297',light:'#F3D9A4',line:'rgba(238,231,216,.10)',e1:'#86C9A0',e2:'#E4BE6A',e3:'#EE8E7C'},
  sky:[.0011,.0016,.0034],tint:[1,1,1],o:[[1,.95,.85],[1,.8,.52],[.98,.6,.33]],l:[[1,.975,.93],[1,.83,.57],[1,.72,.42]]},
 lamplight:{css:{ground:'#0B0907',surface:'#13100C',raised:'#1D1913',ink:'#EFE6D4','ink-2':'#B5AB98','ink-3':'#8A806E',light:'#F0C987',line:'rgba(239,230,212,.10)',e1:'#9CC58D',e2:'#E8A552',e3:'#EC8672'},
  sky:[.0030,.0021,.0013],tint:[1.07,.98,.85],o:[[1,.94,.82],[1,.77,.46],[.98,.56,.28]],l:[[1,.97,.90],[1,.80,.50],[1,.66,.36]]},
 daybreak:{css:{ground:'#0A0814',surface:'#110E20',raised:'#1B1730',ink:'#EEE9F2','ink-2':'#AFA9C4','ink-3':'#847E9E',light:'#F5CDB6',line:'rgba(238,233,242,.10)',e1:'#8FCFAE',e2:'#E6C36C',e3:'#F27D8C'},
  sky:[.0024,.0014,.0042],tint:[1.02,.94,1.07],o:[[1,.95,.92],[1,.78,.66],[.96,.58,.56]],l:[[1,.965,.95],[1,.80,.68],[.98,.62,.58]]},
 starlight:{css:{ground:'#05090F',surface:'#0A111A',raised:'#121C28',ink:'#E9EEF3','ink-2':'#A4B0BE','ink-3':'#768493',light:'#C4DBFF',line:'rgba(233,238,243,.10)',e1:'#8ED0A8',e2:'#E8C36E',e3:'#F08E80'},
  sky:[.0008,.0020,.0037],tint:[.90,.98,1.10],o:[[.96,.98,1],[.70,.82,1],[.46,.62,1]],l:[[.97,.985,1],[.72,.84,1],[.50,.66,1]]}
};
var PAL=PALS.lamplight;
function setPal(n){
  if(!PALS[n])return;PAL=PALS[n];var st=document.documentElement.style,k;
  for(k in PAL.css)st.setProperty('--'+k,PAL.css[k]);
  ['ground','ink','light'].forEach(function(n){var h=PAL.css[n];st.setProperty('--'+n+'-rgb',parseInt(h.slice(1,3),16)+','+parseInt(h.slice(3,5),16)+','+parseInt(h.slice(5,7),16))});
  document.documentElement.setAttribute('data-pal',n);
  [].forEach.call(document.querySelectorAll('[data-pal-btn]'),function(b){b.setAttribute('aria-current',b.getAttribute('data-pal-btn')===n?'true':'false')});
}
setPal(typeof P.pal==='string'&&PALS[P.pal]?P.pal:'lamplight');
document.addEventListener('click',function(e){var b=e.target.closest&&e.target.closest('[data-pal-btn]');if(b)setPal(b.getAttribute('data-pal-btn'))});

/* ---------- the rule: a blessing sits at the point of sky that was overhead ---------- */
var PLACE={lat:40.23,lon:-111.66}; // placeholder home
function zenith(ms){
  var jd=ms/864e5+2440587.5;
  var gmst=280.46061837+360.98564736629*(jd-2451545.0);
  var lst=((gmst+PLACE.lon)%360+360)%360;
  return {ra:lst*DEG,dec:PLACE.lat*DEG};
}
var B=[
 {id:'fever',title:'Healing, the night of the fever',from:'Grandpa Ruiz',utc:Date.UTC(2024,5,3,5,30),date:'Sunday, June 2, 2024',short:'Jun 2, 2024',day:'Jun 2',time:'11:30 at night',kind:'Administering to the sick',hb:'18.13'},
 {id:'baby',title:'When the baby came early',from:'Mateo',utc:Date.UTC(2025,0,12,10,20),date:'Sunday, January 12, 2025',short:'Jan 12, 2025',day:'Jan 12',time:'3:20 in the morning',kind:'Comfort and counsel',hb:'18.14'},
 {id:'primary',title:'Set apart to teach Primary',from:'Bishop Alvarez',utc:Date.UTC(2025,7,24,18,50),date:'Sunday, August 24, 2025',short:'Aug 24, 2025',day:'Aug 24',time:'12:50 in the afternoon',daylight:true,kind:'Setting apart',hb:'18.11'},
 {id:'surgery',title:'Comfort before surgery',from:'Dad',utc:Date.UTC(2026,2,3,16,40),date:'Tuesday, March 3, 2026',short:'Mar 3, 2026',day:'Mar 3',time:'9:40 in the morning',daylight:true,kind:'Comfort and counsel',hb:'18.14'},
 {id:'job',title:'Before the new job',from:'Dad',utc:Date.UTC(2026,9,5,1,40),date:'Sunday, October 4, 2026',short:'Oct 4, 2026',day:'Oct 4',time:'7:40 in the evening',kind:'Father’s blessing',hb:'18.14'}
];
var TODAY=Date.UTC(2026,10,14,19);
B.forEach(function(b){var z=zenith(b.utc);b.ra=z.ra;b.dec=z.dec;b.v=vec(z.ra,z.dec);b.w=0});
var HB='https://www.churchofjesuschrist.org/study/manual/general-handbook/18-priesthood-ordinances-and-blessings?lang=eng#title_number';
var WORDS=[
 'Emma, I lay my hands upon your head{0} to give you a blessing of comfort.',
 'Your Heavenly Father knows you. He {1} the worry you have carried these weeks, and He wants you to know that you have not carried it alone.',
 'I bless you {2} as you go into this surgery, and I bless the hands of those who {3} for you. Be patient with your body as it heals. {4} in its time.',
 'I say these things in the name of Jesus Christ, amen.'
];
var E=[
 {lvl:'l',what:'Filler removed',was:', um, right now,',now:''},
 {lvl:'m',what:'Reworded',was:'knows about, He knows',now:'knows'},
 {lvl:'l',what:'Repeated word removed',was:'with, with peace',now:'with peace'},
 {lvl:'m',what:'Reworded',was:'are going to be caring',now:'will care'},
 {lvl:'h',what:'Reworded',was:'your strength, it’s going to come back to you',now:'Strength will return to you'}
];
var LVL={l:'Light change',m:'Moderate change',h:'Heavy change'};
E.forEach(function(e){e.back=false});

function vec(ra,dec){return [Math.cos(dec)*Math.cos(ra),Math.cos(dec)*Math.sin(ra),Math.sin(dec)]}
function ease(t){return t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2}
function clamp(x,a,b){return x<a?a:x>b?b:x}

/* ---------- state ---------- */
var screen=null, focus=3, clock=0;
var cam={ra:0,dec:0,fov:80,cy:.2,exp:1,st:1,orb:0,lights:1,solo:0,names:1},bump=0;
var goal={fov:80,cy:.2,exp:1,st:1,orb:0,lights:1,solo:0,names:1};
var glide=null, vel={ra:0,dec:0}, free=false;
var VIEW={
  record:{fov:74,cy:.14,exp:.018,st:.2,orb:1,lights:0,solo:1,names:0},
  after:{fov:74,cy:.3,exp:.72,st:.8,orb:0,lights:1,solo:1,names:0},
  sky:{fov:90,cy:.2,exp:1,st:1,orb:0,lights:1,solo:0,names:1},
  read:{fov:58,cy:.7,exp:1,st:1,orb:0,lights:1,solo:1,names:0},
  review:{fov:58,cy:.7,exp:.5,st:.5,orb:0,lights:1,solo:1,names:0}
};
function setGoal(name){var v=VIEW[name];for(var k in v)goal[k]=v[k]}
function snapCam(){for(var k in goal)cam[k]=goal[k];var b=B[focus];cam.ra=b.ra;cam.dec=b.dec;glide=null;vel.ra=vel.dec=0;free=false;B.forEach(function(x,i){x.w=i===focus?1:0})}
function lookAt(i,instant){
  var b=B[i];free=false;vel.ra=vel.dec=0;
  var d=b.ra-cam.ra;d=((d+Math.PI)%TAU+TAU)%TAU-Math.PI;
  var ang=Math.abs(d)*Math.cos(b.dec)+Math.abs(b.dec-cam.dec);
  if(instant||ang<1e-4){cam.ra=b.ra;cam.dec=b.dec;glide=null;return}
  glide={ra0:cam.ra,dec0:cam.dec,d:d,dec1:b.dec,t0:clock,dur:reduce?.01:(1.1+1.5*Math.min(1,ang/2.4)),ang:ang};
}


/* ---------- recording: a press to begin, and what moves while it listens ----------
   Constellations are the chosen animation. The rosette was explored and set aside; it stays reachable with #rec=rose. */
var REC=P.rec==='rose'?'rose':'stars';
var rec={state:'ready',t0:0,a:0,figs:[],T:60,amen:false},WINDOW=10; // seconds in which the button discards
var CON=(window.SKY_CONST||[]).map(function(c){
  var segs=[],pts=[],len=0;
  c[1].forEach(function(l){var prev=null;for(var i=0;i<l.length;i+=2){var v=vec(l[i]*DEG,l[i+1]*DEG);pts.push(v);
    if(prev){var a=Math.acos(clamp(prev[0]*v[0]+prev[1]*v[1]+prev[2]*v[2],-1,1));if(a>1e-6){segs.push({a:prev,b:v,s0:len,s1:len+a});len+=a}}prev=v}});
  return {id:c[0],segs:segs,pts:pts,len:len};
});
window.SKY_CONST=null;
/* the figures that will be on screen, nearest the light first */
function pickFigs(){
  var keep={ra:cam.ra,dec:cam.dec,fov:cam.fov,cy:cam.cy},b=B[focus],out=[];
  cam.ra=b.ra;cam.dec=b.dec;cam.fov=VIEW.record.fov;cam.cy=VIEW.record.cy;var bk=bump;bump=0;basis();
  var oy=(1-(cam.cy*.5+.5))*844;
  CON.forEach(function(f){if(!f.len)return;var n=0,sx=0,sy=0;
    f.pts.forEach(function(v){var p=project(v);if(p.z>.1&&p.x>-10&&p.x<400&&p.y>70&&p.y<690){n++;sx+=p.x;sy+=p.y}});
    if(n>=2&&n>=f.pts.length*.4)out.push({f:f,d:Math.hypot(sx/n-195,sy/n-oy)})});
  cam.ra=keep.ra;cam.dec=keep.dec;cam.fov=keep.fov;cam.cy=keep.cy;bump=bk;basis();
  out.sort(function(a,b){return a.d-b.d});
  /* one after another, a few seconds apart; each rests for most of the round, so the sky is never empty and never all moving at once */
  rec.T=Math.max(48,out.length*3.4+14);
  rec.figs=out.map(function(o,k){var D=clamp(o.f.len/(5*DEG),6,15);return {f:o.f,t:k*3.4,D:D,H:Math.max(8,rec.T-2*D-4)}});
}
function recGoal(){
  if(screen!=='record')return;var live=rec.state==='live',st=REC==='stars';
  goal.orb=live?(st?1:.5):.2;goal.st=live&&st?.5:.2;goal.exp=live&&st?.03:.018;
}
function recSet(st,snap){
  var s=$('s-record');
  if(snap)s.classList.add('snap');
  rec.state=st;s.classList.toggle('live',st==='live');
  $('rec-x').textContent=st==='live'?'Discard':'Close';
  $('rec-sheet').classList.remove('on');
  if(st==='live'){rec.t0=clock-(+P.rt||0);P.rt=0;pickFigs()}
  recPhase();recGoal();
  if(snap){void s.offsetWidth;s.classList.remove('snap')}
}
function recPhase(){
  var el=clock-rec.t0,live=rec.state==='live',am=live&&el>=WINDOW;
  if(am!==rec.amen){rec.amen=am;$('s-record').classList.toggle('amen',am);$('hold').setAttribute('aria-label',am?'Amen. Hold to finish':'Discard this recording')}
  if(live&&!am)$('hold-count').style.strokeDashoffset=(267.04*clamp(el/WINDOW,0,1)).toFixed(1);
}
function setRec(n){
  REC=n==='rose'?'rose':'stars';
  [].forEach.call(document.querySelectorAll('[data-rec-btn]'),function(b){b.setAttribute('aria-current',b.getAttribute('data-rec-btn')===REC?'true':'false')});
  recGoal();
}
$('begin').onclick=function(){if(rec.state!=='live')recSet('live')};
$('rec-x').onclick=function(){if(rec.state==='live')$('rec-sheet').classList.add('on');else go('sky')};
$('rec-keep').onclick=function(){$('rec-sheet').classList.remove('on')};
$('rec-discard').onclick=function(){go('sky')};
document.addEventListener('click',function(e){var b=e.target.closest&&e.target.closest('[data-rec-btn]');if(b)setRec(b.getAttribute('data-rec-btn'))});

/* ---------- screens ---------- */
function go(name,instant){
  if(name===screen)return;
  if(name==='record'||name==='after'||name==='review'){setFocus(3,true,instant||screen===null||screen==='sky')}
  screen=name;
  SCREENS.forEach(function(s){$('s-'+s).classList.toggle('on',s===name)});
  [].forEach.call(document.querySelectorAll('.rail [data-go]'),function(b){b.setAttribute('aria-current',b.getAttribute('data-go')===name?'true':'false')});
  setGoal(name);
  if(name==='record')recSet(P.live&&instant?'live':'ready',true);
  if(name==='after'){var af=$('s-after');af.classList.add('fresh');setTimeout(function(){af.classList.remove('fresh')},700)} // the finger that held Amen is resting where the buttons appear
  lookAt(focus);
  if(name==='read'){fillRead();$('readscroll').scrollTop=0;$('s-read').classList.remove('scrolled')}
  if(name==='sky'){showList(false)}
  if(name==='review'){selectEdit(sel,null,true)}
  if(instant){snapCam();rec.a=(name==='record'&&rec.state==='live')?1:0}
  if(!P.bare&&!P.shot){try{history.replaceState(null,'','#'+name)}catch(e){}}
}
function setFocus(i,quiet,instant){
  i=clamp(i,0,B.length-1);
  var changed=i!==focus;focus=i;
  var b=B[i];
  var cap=$('cap');
  function fill(){$('cap-date').textContent=b.date;$('cap-title').textContent=b.title;$('cap-from').textContent='From '+b.from;cap.classList.remove('swap')}
  if(changed&&!quiet&&!instant&&!document.documentElement.classList.contains('notrans')){cap.classList.add('swap');setTimeout(fill,220)}else fill();
  [].forEach.call($('track').querySelectorAll('em'),function(d,k){d.classList.toggle('on',k===i)});
  $('older').disabled=i===0;$('newer').disabled=i===B.length-1;
  if(!quiet)lookAt(i,instant);
}

/* ---------- reading ---------- */
function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;')}
function editHTML(n,marks){
      var e=E[n],t=e.back?e.was:e.now;
      if(!marks){if(e.now===''&&!e.back)return '';return (e.now===''?'':'')+esc(t)}
      if(e.now===''){return e.back?'<span class="e cut back '+e.lvl+'" tabindex="0" role="button" data-e="'+n+'">'+esc(t)+'</span>':'<span class="e cut '+e.lvl+'" tabindex="0" role="button" data-e="'+n+'" aria-label="Words removed"><svg viewBox="0 0 12 9"><path d="M1.5 7.5L6 1.5l4.500 6"/></svg></span>'}
      return '<span class="e '+e.lvl+(e.back?' back':'')+'" tabindex="0" role="button" data-e="'+n+'">'+esc(t)+'</span>';
}
function wordsHTML(marks){
  return WORDS.map(function(p){return '<p>'+esc(p).replace(/\{(\d)\}/g,function(_,n){return editHTML(+n,marks)})+'</p>'}).join('');
}
function fillRead(){
  var b=B[focus];
  $('r-date').textContent=b.date;$('r-title').textContent=b.title;$('r-from').textContent='A blessing from '+b.from;
  $('r-kind').textContent=b.kind;$('r-hb').firstChild.textContent='Handbook '+b.hb;$('r-hb').href=HB+(b.hb.split('.')[1]);
  var w=$('r-words'),has=b.id==='surgery';
  w.classList.toggle('ph',!has);
  w.innerHTML=has?wordsHTML(false):'<p>Only one sample blessing is written out in this prototype. Open Comfort before surgery to read a full page.</p>';
  var kept=E.filter(function(e){return !e.back}).length;
  $('r-polish').style.display=$('r-review').style.display=has?'':'none';
  $('r-polish').textContent=kept?('Polished from the spoken words, with '+kept+(kept===1?' small change':' small changes')+'. The original is kept beside it.'):'Exactly as it was spoken. Nothing has been changed.';
  $('r-sky').textContent='Its light keeps the place in the sky that was straight overhead at '+b.time+(b.daylight?', behind the daylight.':'.');
}

/* ---------- review ---------- */
var sel=4,shT=null,flipT=null,scTw=null;
function still(){return reduce||document.documentElement.classList.contains('notrans')}
function swapText(el,txt,instant){
  if(el._sw){clearTimeout(el._sw);el._sw=null;el.classList.remove('tsw')}
  if(el.textContent===txt)return;
  if(instant||still()||screen!=='review'){el.textContent=txt;return}
  el.classList.add('tsw');el._sw=setTimeout(function(){el._sw=null;el.textContent=txt;el.classList.remove('tsw')},140);
}
function markSel(){[].forEach.call($('rv-words').querySelectorAll('[data-e]'),function(s){s.classList.toggle('sel',+s.getAttribute('data-e')===sel)})}
function reviewHead(instant){
  var kept=E.filter(function(e){return !e.back}).length;
  swapText($('rv-count'),kept===E.length?E.length+' changes':kept===0?'Original words':kept+' of '+E.length+' kept',instant);
  swapText($('rv-all'),kept===0?'Use polished':'Restore all',instant);
}
function sheetButtons(instant){var e=E[sel];swapText($('sh-restore'),e.back?'Use polished':'Restore original',instant);swapText($('sh-keep'),e.back?'Next':'Keep',instant)}
function fillSheet(){
  var e=E[sel];
  $('sh-lvl').innerHTML='<span class="e '+e.lvl+'" style="cursor:default">'+LVL[e.lvl]+'</span>&ensp;'+e.what;
  $('sh-n').textContent=(sel+1)+' of '+E.length;
  $('sh-was').textContent=e.was;
  var now=$('sh-now');now.textContent=e.now||'Left out';now.className=e.now?'':'none';
}
function renderReview(){$('rv-words').innerHTML=wordsHTML(true);markSel();reviewHead(true);fillSheet();sheetButtons(true)}
/* moving between edits: the sheet's words slide out the way you are going and the next slide in behind them */
function selectEdit(i,dir,instant){
  var prev=sel,sh=$('sheet');sel=(i+E.length)%E.length;
  markSel();
  if(shT){clearTimeout(shT);shT=null}
  sh.classList.remove('out-n','out-p','in-n','in-p');
  if(instant||still()||screen!=='review'||prev===sel){fillSheet();sheetButtons(instant||screen!=='review')}
  else{
    var d=dir||(sel>prev?'n':'p');sheetButtons();
    sh.classList.add('out-'+d);
    shT=setTimeout(function(){shT=null;fillSheet();sh.classList.add('snap');sh.classList.remove('out-'+d);sh.classList.add('in-'+d);void sh.offsetWidth;sh.classList.remove('snap');sh.classList.remove('in-'+d)},140);
  }
  var s=$('rv-words').querySelector('[data-e="'+sel+'"]');
  if(s&&screen==='review'){var sc=$('revscroll'),r=s.getBoundingClientRect(),pr=sc.getBoundingClientRect(),k=pr.height/844,y=(r.top-pr.top)/k;
    if(y<190||y>500){if(instant||still())sc.scrollTop+=y-340;else scTw={sc:sc,a:sc.scrollTop,b:sc.scrollTop+y-340,t0:clock}}}
}
/* every word and cut mark in the document, with where it sits */
function tokens(root,ch){
  var out=[],rb=root.getBoundingClientRect(),rg=document.createRange();
  (function walk(node,ed){
    for(var c=node.firstChild;c;c=c.nextSibling){
      if(c.nodeType===3){var re=/\S+/g,m,txt=c.nodeValue;
        while((m=re.exec(txt))){var end=m.index+m[0].length;rg.setStart(c,m.index);rg.setEnd(c,end);var r=rg.getClientRects()[0];if(!r)continue;
          out.push({t:m[0]+(ed&&/\S/.test(txt.slice(end))?' ':''),x:(r.left-rb.left)/K,y:(r.top-rb.top)/K,h:r.height/K,cls:ed?ed.className:'',ch:!!(ed&&ch[ed.getAttribute('data-e')])})}}
      else if(c.nodeType===1&&!c.classList.contains('flipstage')){
        if(c.classList.contains('cut')&&!c.classList.contains('back')){var q=c.getBoundingClientRect();out.push({html:c.innerHTML,x:(q.left-rb.left)/K,y:(q.top-rb.top)/K,h:q.height/K,cls:c.className,ch:!!ch[c.getAttribute('data-e')]})}
        else walk(c,c.hasAttribute('data-e')?c:ed)}
    }
  })(root,null);
  return out;
}
/* apply a change to the document and let it be seen: unchanged words glide to where they now belong, the old words fade, the new ones arrive */
function flip(root,ch,mutate){
  if(flipT){clearTimeout(flipT);flipT=null;root.classList.remove('flip');var old=root.querySelector('.flipstage');if(old)old.remove()}
  if(still()||screen!=='review'){mutate();return}
  var A=tokens(root,ch);mutate();var Z=tokens(root,ch);
  var a=A.filter(function(t){return !t.ch}),z=Z.filter(function(t){return !t.ch}),h='';
  if(a.length!==z.length)return;
  function span(t,cls,dx,dy){return '<span class="fw '+t.cls+cls+'" style="left:'+t.x.toFixed(2)+'px;top:'+t.y.toFixed(2)+'px;'+(t.html?'':'line-height:'+t.h.toFixed(2)+'px;')+(dx||dy?'transform:translate('+dx.toFixed(2)+'px,'+dy.toFixed(2)+'px)':'')+'">'+(t.html||esc(t.t))+'</span>'}
  z.forEach(function(t,k){var dx=a[k].x-t.x,dy=a[k].y-t.y;
    if(Math.abs(dx)>1&&Math.abs(dy)>2)h+=span(a[k],' out',0,0)+span(t,' in',0,0); // a word that changes line dissolves, so it never flies across the others
    else h+=span(t,' mv',dx,dy)});
  A.forEach(function(t){if(t.ch)h+=span(t,' out',0,0)});
  Z.forEach(function(t){if(t.ch)h+=span(t,' in',0,0)});
  var st=document.createElement('div');st.className='flipstage';st.setAttribute('aria-hidden','true');st.innerHTML=h;
  [].forEach.call(st.querySelectorAll('.in'),function(el){el.style.opacity=0});
  root.appendChild(st);root.classList.add('flip');void st.offsetWidth;
  [].forEach.call(st.children,function(el){if(el.classList.contains('mv'))el.style.transform='none';else el.style.opacity=el.classList.contains('in')?1:0});
  flipT=setTimeout(function(){flipT=null;root.classList.remove('flip');st.remove()},540);
}
function setBack(list,val){
  var root=$('rv-words'),ch={},any=false;
  list.forEach(function(n){if(E[n].back!==val){ch[n]=1;any=true}});
  if(!any)return;
  flip(root,ch,function(){for(var n in ch){E[n].back=val;var el=root.querySelector('[data-e="'+n+'"]');if(el)el.outerHTML=editHTML(+n,true)}markSel()});
  reviewHead();sheetButtons();
}
$('rv-words').addEventListener('click',function(ev){var t=ev.target.closest('[data-e]');if(t)selectEdit(+t.getAttribute('data-e'))});
$('rv-words').addEventListener('keydown',function(ev){if(ev.key==='Enter'||ev.key===' '){var t=ev.target.closest('[data-e]');if(t){ev.preventDefault();selectEdit(+t.getAttribute('data-e'))}}});
$('sh-prev').onclick=function(){selectEdit(sel-1,'p')};
$('sh-next').onclick=function(){selectEdit(sel+1,'n')};
$('sh-restore').onclick=function(){setBack([sel],!E[sel].back)};
$('sh-keep').onclick=function(){selectEdit(sel+1,'n')};
$('rv-all').onclick=function(){var any=E.some(function(e){return !e.back});setBack(E.map(function(_,i){return i}),any)};
$('revscroll').addEventListener('wheel',function(){scTw=null},{passive:true});
$('revscroll').addEventListener('touchstart',function(){scTw=null},{passive:true});

/* ---------- ruler ---------- */
var T0=Date.UTC(2024,0,1),T1=Date.UTC(2027,0,1);
function buildRuler(){
  var h='',m,y;
  for(m=0;m<=36;m++){var t=Date.UTC(2024,m,1),x=(t-T0)/(T1-T0)*100;
    h+='<i class="'+(m%12===0?'y':'')+(t>TODAY?' future':'')+'" style="left:'+x.toFixed(3)+'%"></i>';
    if(m%12===0&&m<36)h+='<b style="left:'+(x+100/6).toFixed(3)+'%">'+(2024+m/12)+'</b>'}
  B.forEach(function(b,i){h+='<em data-i="'+i+'" style="left:'+((b.utc-T0)/(T1-T0)*100).toFixed(3)+'%"></em>'});
  $('track').innerHTML=h;
}
buildRuler();
(function(){
  var tr=$('track'),down=false;
  function pick(ev){var r=tr.getBoundingClientRect(),x=(ev.clientX-r.left)/r.width,best=0,bd=9;B.forEach(function(b,i){var d=Math.abs((b.utc-T0)/(T1-T0)-x);if(d<bd){bd=d;best=i}});if(best!==focus)setFocus(best);else if(free&&ev.type==='pointerdown')lookAt(focus)}
  tr.addEventListener('pointerdown',function(ev){down=true;tr.setPointerCapture(ev.pointerId);pick(ev)});
  tr.addEventListener('pointermove',function(ev){if(down)pick(ev)});
  tr.addEventListener('pointerup',function(){down=false});
  tr.addEventListener('pointercancel',function(){down=false});
})();
$('older').onclick=function(){setFocus(focus-1)};
$('newer').onclick=function(){setFocus(focus+1)};
$('cap').onclick=function(){go('read')};

/* ---------- list ---------- */
var listOn=false,TL={top:0,y0:0,yN:0,ys:[]};
function showList(on){
  listOn=on;$('list').classList.toggle('on',on);
  if(on){$('list').scrollTop=0;tlUpdate()}
  var vb=$('viewbtn');vb.setAttribute('aria-pressed',on?'true':'false');vb.setAttribute('aria-label',on?'Show as a sky':'Show as a list');
  $('ico-list').innerHTML=on?'<circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="5.500" cy="7" r="1" fill="currentColor" stroke="none"/><circle cx="18" cy="6" r="1" fill="currentColor" stroke="none"/><circle cx="17.500" cy="17.500" r="1" fill="currentColor" stroke="none"/><circle cx="6.500" cy="16.500" r="1" fill="currentColor" stroke="none"/>':'<path d="M9 7h11M9 12h11M9 17h11"/><path d="M4.5 7h.01M4.5 12h.01M4.5 17h.01" stroke-width="2.2"/>';
  $('foot').style.visibility=on?'hidden':'';
}
(function(){
  /* the ruler stood upright. Gaps follow the time between blessings, within limits so near ones never collide and far ones never leave a long blank. */
  var MPX=24,MIN=84,MAX=200,MONTH=30.4375*864e5,TOP=206,END=480,TAILPX=64;
  var h='',y=TOP,ys=[],yr=null,i,last=B.length-1;
  var top=TOP-clamp((TODAY-B[last].utc)/MONTH*MPX,20,48);
  function ticks(tNew,tOld,yNew,yOld){
    var d=new Date(tNew),m=Date.UTC(d.getUTCFullYear(),d.getUTCMonth(),1);
    while(m>tOld){var q=new Date(m);
      h+='<i'+(q.getUTCMonth()===0?' class="y"':'')+' style="top:'+(yNew+(tNew-m)/(tNew-tOld)*(yOld-yNew)).toFixed(1)+'px"></i>';
      m=Date.UTC(q.getUTCFullYear(),q.getUTCMonth()-1,1)}
  }
  ticks(TODAY,B[last].utc,top,TOP);
  for(i=last;i>=0;i--){var b=B[i];
    if(i<last){var gap=clamp((B[i+1].utc-b.utc)/MONTH*MPX,MIN,MAX);ticks(B[i+1].utc,b.utc,y,y+gap);y+=gap}
    ys[i]=y;var year=new Date(b.utc-7*36e5).getUTCFullYear();
    h+='<button data-i="'+i+'" style="top:'+(y-20).toFixed(1)+'px"><span class="d">'+b.day+(year!==yr?'<em>'+year+'</em>':'')+'</span><span class="dot"></span><span class="t">'+esc(b.title)+'</span><span class="f">From '+esc(b.from)+'</span></button>';yr=year}
  ticks(B[0].utc,B[0].utc-TAILPX/MPX*MONTH,y,y+TAILPX);
  $('list').innerHTML='<div class="tl" style="height:'+(y+844-END).toFixed(1)+'px"><div class="tl-base" style="top:'+top.toFixed(1)+'px;height:'+(y+TAILPX-top).toFixed(1)+'px"></div><div class="tl-fill" id="tl-fill" style="top:'+top.toFixed(1)+'px"></div>'+h+'</div>';
  TL={top:top,y0:TOP,yN:y,ys:ys};
  $('list').addEventListener('scroll',tlUpdate);
  $('list').addEventListener('click',function(ev){var t=ev.target.closest('[data-i]');if(t){setFocus(+t.getAttribute('data-i'),false,true);go('read')}});
  $('viewbtn').onclick=function(){showList(!listOn)};
})();
/* as the list scrolls, the lit part of the line runs down it and each blessing lights as it is reached */
function tlUpdate(){
  var sc=$('list'),max=Math.max(1,sc.scrollHeight-sc.clientHeight),p=clamp(sc.scrollTop/max,0,1);
  var head=TL.y0+(TL.yN-TL.y0)*p,best=0,bd=1e9,rows=sc.querySelectorAll('button'),k;
  $('tl-fill').style.height=(head-TL.top).toFixed(1)+'px';
  for(k=0;k<rows.length;k++){var i=+rows[k].getAttribute('data-i'),d=Math.abs(TL.ys[i]-head);rows[k].classList.toggle('lit',TL.ys[i]<=head+1);if(d<bd){bd=d;best=i}}
  for(k=0;k<rows.length;k++)rows[k].classList.toggle('cur',+rows[k].getAttribute('data-i')===best);
}

$('readscroll').addEventListener('scroll',function(){$('s-read').classList.toggle('scrolled',this.scrollTop>132)});

/* ---------- hold to finish ---------- */
(function(){
  var h=$('hold'),timer=null,hint=$('hint');
  function start(ev){if(!rec.amen)return;ev.preventDefault();h.classList.add('holding');timer=setTimeout(function(){timer=null;h.classList.remove('holding');go('after')},900)}
  function end(){if(timer){clearTimeout(timer);timer=null;h.classList.remove('holding');hint.classList.add('nudge');setTimeout(function(){hint.classList.remove('nudge')},900)}}
  h.addEventListener('pointerdown',start);h.addEventListener('pointerup',end);h.addEventListener('pointerleave',end);h.addEventListener('pointercancel',end);
  h.addEventListener('keydown',function(ev){if((ev.key===' '||ev.key==='Enter')&&!timer&&!ev.repeat)start(ev)});
  h.addEventListener('keyup',function(ev){if(ev.key===' '||ev.key==='Enter')end()});
  h.addEventListener('click',function(){if(rec.state==='live'&&!rec.amen)recSet('ready')}); // within the first seconds, one tap takes it back
})();
document.addEventListener('click',function(ev){var t=ev.target.closest('[data-go]');if(t){ev.preventDefault();go(t.getAttribute('data-go'))}});
document.addEventListener('keydown',function(ev){
  if(ev.target.closest&&ev.target.closest('.hold,[data-e]'))return;
  if(screen==='sky'&&!listOn){if(ev.key==='ArrowLeft')setFocus(focus-1);if(ev.key==='ArrowRight')setFocus(focus+1)}
  var n='12345'.indexOf(ev.key);if(n>=0&&!ev.metaKey&&!ev.ctrlKey)go(SCREENS[n]);
});

/* ---------- fit the phone to the window ---------- */
var K=1;
function fit(){
  if(P.bare){K=1}else{K=Math.min(1,(window.innerHeight-32)/868,(window.innerWidth-32)/414);var dv=$('device');dv.style.transform='scale('+K+')';dv.style.margin=(-(1-K)*434).toFixed(1)+'px '+(-(1-K)*207).toFixed(1)+'px'}
  resize();
}

/* ---------- WebGL sky ---------- */
var cv=$('sky'),gl=null,dpr=1,PX=1;
try{gl=cv.getContext('webgl',{alpha:false,antialias:false,powerPreference:'high-performance'})}catch(e){}
if(!gl){$('fallback').style.display='grid'}
function resize(){
  if(!gl)return;
  dpr=Math.min(3,window.devicePixelRatio||1);PX=dpr*(K<1?Math.max(K,.5):1);
  var w=Math.round(390*PX),h=Math.round(844*PX);
  if(cv.width!==w||cv.height!==h){cv.width=w;cv.height=h}
  if(fx&&(fx.width!==w||fx.height!==h)){fx.width=w;fx.height=h}
}
function sh(type,src){var s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(s));return s}
function prog(vs,fs,names){
  var p=gl.createProgram();gl.attachShader(p,sh(gl.VERTEX_SHADER,vs));gl.attachShader(p,sh(gl.FRAGMENT_SHADER,fs));gl.linkProgram(p);
  if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(p));
  var o={p:p};names.forEach(function(n){o[n]=n.charAt(0)==='a'?gl.getAttribLocation(p,n):gl.getUniformLocation(p,n)});return o;
}
var PROJ='uniform vec3 uF,uR,uU;uniform vec2 uT;uniform float uCy;'+
 'vec3 proj(vec3 p){float z=dot(p,uF);vec2 q=2.*vec2(dot(p,uR),dot(p,uU))/(1.0001+z);return vec3(q.x/uT.x,q.y/uT.y+uCy,z);}';
var pBg,pSt,pLi,pLn,quad,stars,nStars=0,ring,nRing=0,mwTex,mwReady=false;
function init(){
  pBg=prog('attribute vec2 aQ;varying vec2 vN;void main(){vN=aQ;gl_Position=vec4(aQ,0.,1.);}',
   'precision highp float;varying vec2 vN;uniform sampler2D uMW;uniform vec3 uF,uR,uU;uniform vec2 uT;uniform float uCy,uExp,uAsp,uHas;uniform vec4 uOrb;uniform vec3 uSky,uTint,uO1,uO2,uO3;'+
   'float hash(vec2 p){vec3 q=fract(vec3(p.xyx)*.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z);}'+
   'void main(){vec2 q=vec2(vN.x*uT.x,(vN.y-uCy)*uT.y);float r2=dot(q,q);'+
   'vec3 d=normalize(uF*(4.-r2)+(uR*q.x+uU*q.y)*4.);'+
   'vec2 uv=vec2(.5-atan(d.y,d.x)/6.28318531,.5-asin(clamp(d.z,-1.,1.))/3.14159265);'+
   'vec3 t=texture2D(uMW,uv).rgb*uHas;t=pow(t,vec3(1.3333*2.2));'+        /* undo the storage lift, then to linear light */
   'vec3 lin=t*uTint*uExp*3.4+uSky*(.35+.65*uExp);'+
   'vec3 c=1.-exp(-lin*1.9);c=pow(c,vec3(.4545));'+
   'vec2 e=vN*vec2(uAsp,1.);c*=1.-.22*smoothstep(.55,1.25,length(e));'+
   'float od=length((vN-uOrb.xy)*vec2(uAsp,1.))/uOrb.z;'+
   'vec3 orb=uO1*exp(-od*od*3.2)*.5+uO2*exp(-od*1.6)*.4+uO3*.15/(1.+od*od*1.1)*smoothstep(5.5,1.,od);'+
   'c+=orb*uOrb.w;c+=(hash(gl_FragCoord.xy)-.5)/255.*1.6;gl_FragColor=vec4(c,1.);}',
   ['aQ','uMW','uF','uR','uU','uT','uCy','uExp','uAsp','uHas','uOrb','uSky','uTint','uO1','uO2','uO3']);
  pSt=prog('attribute vec3 aP;attribute vec4 aC;'+PROJ+'uniform float uPx,uExp,uTime,uTw;varying vec4 vC;varying float vK;'+
   'void main(){vec3 n=proj(aP);float lum=pow(10.,.4*(6.-aC.w));float rad=.30+.16*pow(lum,.30);'+
   'float a=.66*pow(lum,.6)*uExp;a*=1.+uTw*.14*sin(uTime*(1.3+fract(aC.w*7.31)*2.6)+aP.x*311.+aP.y*173.);'+
   'float sd=rad*uPx;float sc=max(sd,.82);a*=sd*sd/(sc*sc);'+
   'float k=clamp((lum-5.)/110.,0.,1.);vK=k;float size=sc*6.4*(1.+3.*k);'+
   'if(n.z<-.6||a<.006)n.xy=vec2(4.);gl_Position=vec4(n.xy,0.,1.);gl_PointSize=max(size,2.);vC=vec4(aC.rgb,min(a,2.4));}',
   'precision mediump float;varying vec4 vC;varying float vK;void main(){vec2 p=gl_PointCoord*2.-1.;float d=length(p);float r=d*3.2*(1.+3.*vK);'+
   'float i=exp(-.5*r*r)+vK*.085/(1.+.22*r*r)*smoothstep(1.,.35,d);gl_FragColor=vec4(vC.rgb*vC.a*i,1.);}',
   ['aP','aC','uF','uR','uU','uT','uCy','uPx','uExp','uTime','uTw']);
  pLi=prog('attribute vec2 aQ;uniform vec2 uC,uH;varying vec2 vP;void main(){vP=aQ;gl_Position=vec4(uC+aQ*uH,0.,1.);}',
   'precision highp float;varying vec2 vP;uniform float uRad,uFoc,uA;uniform vec3 uL1,uL2,uL3;void main(){float d=length(vP);float r=d*uRad;float f=uFoc;'+
   'float s=mix(1.5,2.5,f);float core=exp(-r*r/(2.*s*s))*1.3;float glow=exp(-r/mix(4.5,9.,f))*mix(.5,.8,f);'+
   'float halo=mix(.05,.15,f)/(1.+r*r/mix(120.,520.,f));vec2 a=abs(vP)*uRad;float L=mix(7.,24.,f);'+
   'float sp=(exp(-a.y*a.y/.42)*exp(-a.x/L)+exp(-a.x*a.x/.42)*exp(-a.y/L))*mix(.1,.42,f);'+
   'vec3 col=uL1*core+uL2*(glow+sp)+uL3*halo;'+
   'gl_FragColor=vec4(col*smoothstep(1.,.45,d)*uA,1.);}',
   ['aQ','uC','uH','uRad','uFoc','uA','uL1','uL2','uL3']);
  pLn=prog('attribute vec3 aP;'+PROJ+'uniform float uA;varying float vA;void main(){vec3 n=proj(aP);vA=uA*smoothstep(-.2,.3,n.z);gl_Position=vec4(n.xy,0.,1.);}',
   'precision mediump float;varying float vA;uniform vec3 uLc;void main(){gl_FragColor=vec4(uLc*vA,1.);}',
   ['aP','uF','uR','uU','uT','uCy','uA','uLc']);
  quad=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,1,1]),gl.STATIC_DRAW);

  /* stars: 6 bytes each (ra u16, dec i16, magnitude u8, B-V u8) */
  var bin=atob(window.SKY_STARS),n=bin.length/6,arr=new Float32Array(n*7),i,o;
  for(i=0;i<n;i++){o=i*6;
    var ra=(bin.charCodeAt(o)|bin.charCodeAt(o+1)<<8)/65536*TAU;
    var dv=bin.charCodeAt(o+2)|bin.charCodeAt(o+3)<<8;if(dv>32767)dv-=65536;var dec=dv/32767*Math.PI/2;
    var mag=bin.charCodeAt(o+4)/20-2,bv=bin.charCodeAt(o+5)/100-.5;
    var c=bvColor(bv),j=i*7;
    arr[j]=Math.cos(dec)*Math.cos(ra);arr[j+1]=Math.cos(dec)*Math.sin(ra);arr[j+2]=Math.sin(dec);
    arr[j+3]=c[0];arr[j+4]=c[1];arr[j+5]=c[2];arr[j+6]=mag}
  stars=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,stars);gl.bufferData(gl.ARRAY_BUFFER,arr,gl.STATIC_DRAW);nStars=n;window.SKY_STARS=null;

  /* the circle of sky that passes overhead at this latitude: every light is strung on it */
  var seg=720,ra2,rr=new Float32Array((seg+1)*3);
  for(i=0;i<=seg;i++){ra2=i/seg*TAU;var v=vec(ra2,PLACE.lat*DEG);rr[i*3]=v[0];rr[i*3+1]=v[1];rr[i*3+2]=v[2]}
  ring=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,ring);gl.bufferData(gl.ARRAY_BUFFER,rr,gl.STATIC_DRAW);nRing=seg+1;

  mwTex=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,mwTex);
  gl.texImage2D(gl.TEXTURE_2D,0,gl.RGB,1,1,0,gl.RGB,gl.UNSIGNED_BYTE,new Uint8Array([0,0,0]));
  var img=new Image();
  img.onload=function(){
    var max=gl.getParameter(gl.MAX_TEXTURE_SIZE),src=img;
    if(img.width>max){var c2=document.createElement('canvas');c2.width=max;c2.height=max/2;c2.getContext('2d').drawImage(img,0,0,c2.width,c2.height);src=c2}
    gl.bindTexture(gl.TEXTURE_2D,mwTex);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGB,gl.RGB,gl.UNSIGNED_BYTE,src);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.REPEAT);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    mwReady=true;window.SKY_MW=null;ready();
  };
  img.src=window.SKY_MW;
}
function bvColor(bv){
  bv=clamp(bv,-.4,2);var T=4600*(1/(.92*bv+1.7)+1/(.92*bv+.62)),t=T/100,r,g,b;
  if(t<=66){r=255;g=99.47*Math.log(t)-161.12;b=t<=19?0:138.52*Math.log(t-10)-305.04}
  else{r=329.7*Math.pow(t-60,-.1332);g=288.12*Math.pow(t-60,-.0755);b=255}
  var c=[clamp(r,0,255)/255,clamp(g,0,255)/255,clamp(b,0,255)/255],m=Math.max(c[0],c[1],c[2]),s=.62;
  return [1-s+s*c[0]/m,1-s+s*c[1]/m,1-s+s*c[2]/m];
}


/* ---------- what moves while it listens (drawn over the sky, under the controls) ---------- */
var fx=$('fx'),fctx=fx&&fx.getContext?fx.getContext('2d'):null,fxOn=false;
function drawFx(){
  if(!fctx)return;
  var a=rec.a;
  if(a<.004){if(fxOn){fctx.setTransform(1,0,0,1,0,0);fctx.clearRect(0,0,fx.width,fx.height);fxOn=false}return}
  fxOn=true;fctx.setTransform(PX,0,0,PX,0,0);fctx.clearRect(0,0,390,844);
  var h=PAL.css.light,c=parseInt(h.slice(1,3),16)+','+parseInt(h.slice(3,5),16)+','+parseInt(h.slice(5,7),16);
  fctx.lineCap='round';fctx.globalCompositeOperation='lighter';
  if(REC==='rose')drawRose(clock-rec.t0,a,c);else drawFigs(clock-rec.t0,a,c);
}
/* each constellation overhead is drawn star to star, rests, then is taken up again the way it came */
function drawFigs(t,a,c){
  var GAP=5;
  rec.figs.forEach(function(g){
    if(t<g.t&&!reduce)return;
    var f=g.f,tau=reduce?g.D+1:((t-g.t)%rec.T+rec.T)%rec.T;
    var head=clamp(tau/g.D,0,1)*f.len,tail=clamp((tau-g.D-g.H)/g.D,0,1)*f.len;
    if(head<=tail)return;
    var hp=null,dots={},i;
    fctx.lineWidth=1;fctx.strokeStyle='rgba('+c+','+(.4*a).toFixed(3)+')';
    fctx.beginPath();
    for(i=0;i<f.segs.length;i++){var s=f.segs[i];if(s.s1<=tail||s.s0>=head)continue;
      var A=project(s.a),Q=project(s.b);if(A.z<.1||Q.z<.1)continue;
      var dx=Q.x-A.x,dy=Q.y-A.y,L=Math.hypot(dx,dy);if(L<1)continue;
      var u0=(Math.max(tail,s.s0)-s.s0)/(s.s1-s.s0),u1=(Math.min(head,s.s1)-s.s0)/(s.s1-s.s0);
      var p0=Math.max(u0*L,GAP),p1=Math.min(u1*L,L-GAP);
      if(p1>p0){fctx.moveTo(A.x+dx*p0/L,A.y+dy*p0/L);fctx.lineTo(A.x+dx*p1/L,A.y+dy*p1/L)}
      if(u1<1)hp={x:A.x+dx*u1,y:A.y+dy*u1};
      if(u0<=0)dots[Math.round(A.x)+','+Math.round(A.y)]=A;
      if(u1>=1)dots[Math.round(Q.x)+','+Math.round(Q.y)]=Q;
    }
    fctx.stroke();
    fctx.fillStyle='rgba('+c+','+(.75*a).toFixed(3)+')';
    for(var k in dots){fctx.beginPath();fctx.arc(dots[k].x,dots[k].y,1.5,0,TAU);fctx.fill()}
    if(hp&&!reduce){
      var gr=fctx.createRadialGradient(hp.x,hp.y,0,hp.x,hp.y,9);gr.addColorStop(0,'rgba('+c+','+(.55*a).toFixed(3)+')');gr.addColorStop(1,'rgba('+c+',0)');
      fctx.fillStyle=gr;fctx.beginPath();fctx.arc(hp.x,hp.y,9,0,TAU);fctx.fill();
    }
  });
}
/* or: a rose of twelve circles that opens and closes with the breath and turns a little */
function drawRose(t,a,c){
  var br=reduce?.6:breath(t),cx=195,cy=(1-(cam.cy*.5+.5))*844,N=12,i,th;
  var r=40+19*br,rot=(reduce?0:t*.014)+br*.2;
  fctx.lineWidth=1;
  fctx.strokeStyle='rgba('+c+','+((.16+.10*br)*a).toFixed(3)+')';
  fctx.beginPath();
  for(i=0;i<N;i++){th=rot+i/N*TAU;var x=cx+Math.cos(th)*r,y=cy+Math.sin(th)*r;fctx.moveTo(x+r,y);fctx.arc(x,y,r,0,TAU)}
  fctx.stroke();
  fctx.strokeStyle='rgba('+c+','+((.12+.08*br)*a).toFixed(3)+')';
  fctx.beginPath();fctx.arc(cx,cy,r*2,0,TAU);fctx.stroke();
}

/* ---------- labels ---------- */
var labEls=[],starEls=[];
(function(){
  var h='';B.forEach(function(b){h+='<span class="lab bl">'+b.short+'</span>'});
  (window.SKY_NAMED||[]).forEach(function(s){if(s[3]<1.7){h+='<span class="lab star">'+s[0]+'</span>'}});
  $('labels').innerHTML=h;
  var all=$('labels').children;
  B.forEach(function(b,i){labEls.push(all[i])});
  var k=B.length;(window.SKY_NAMED||[]).forEach(function(s){if(s[3]<1.7){starEls.push({el:all[k++],v:vec(s[1]/24*TAU,s[2]*DEG),mag:s[3]})}});
})();

var F=[1,0,0],R=[0,1,0],U=[0,0,1],TX=1,TY=1;
function basis(){
  var cd=Math.cos(cam.dec),sd=Math.sin(cam.dec),ca=Math.cos(cam.ra),sa=Math.sin(cam.ra);
  F=[cd*ca,cd*sa,sd];R=[sa,-ca,0];U=[-sd*ca,-sd*sa,cd];
  TY=2*Math.tan((cam.fov+bump)*DEG/4);TX=TY*390/844;
}
function project(v){
  var z=v[0]*F[0]+v[1]*F[1]+v[2]*F[2],x=v[0]*R[0]+v[1]*R[1],y=v[0]*U[0]+v[1]*U[1]+v[2]*U[2],k=2/(1.0001+z);
  var nx=x*k/TX,ny=y*k/TY+cam.cy;
  return {x:(nx*.5+.5)*390,y:(1-(ny*.5+.5))*844,nx:nx,ny:ny,z:z};
}

/* ---------- frame ---------- */
function breath(t){var p=t%10;return p<4?(.5-.5*Math.cos(Math.PI*p/4)):(.5+.5*Math.cos(Math.PI*(p-4)/6))}
function step(dt){
  clock+=dt;
  var k=1-Math.exp(-dt*3.2),key;
  for(key in goal)cam[key]+=(goal[key]-cam[key])*k;
  if(glide){
    var u=clamp((clock-glide.t0)/glide.dur,0,1),e=ease(u);
    cam.ra=glide.ra0+glide.d*e;cam.dec=glide.dec0+(glide.dec1-glide.dec0)*e;
    bump=Math.sin(Math.PI*u)*Math.min(1,glide.ang/1.2)*10*(screen==='sky'?1:0);
    if(u>=1){glide=null;bump=0}
  }else if(free&&!dragging){
    cam.ra+=vel.ra*dt;cam.dec=clamp(cam.dec+vel.dec*dt,-86*DEG,86*DEG);
    var f=Math.exp(-dt*4.2);vel.ra*=f;vel.dec*=f;
  }
  B.forEach(function(b,i){var g=i===focus?1:0;b.w+=(g-b.w)*(1-Math.exp(-dt*5))});
  var ra=(screen==='record'&&rec.state==='live')?1:0;rec.a+=(ra-rec.a)*(1-Math.exp(-dt*(ra?.9:3.5)));
  recPhase();
  if(scTw){var su=clamp((clock-scTw.t0)/.42,0,1);scTw.sc.scrollTop=scTw.a+(scTw.b-scTw.a)*(1-Math.pow(1-su,3));if(su>=1)scTw=null}
  draw();
}
function draw(){
  if(!gl||!pBg)return;
  basis();
  var W=cv.width,H=cv.height,asp=390/844;
  gl.viewport(0,0,W,H);gl.disable(gl.BLEND);
  gl.useProgram(pBg.p);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(pBg.aQ);gl.vertexAttribPointer(pBg.aQ,2,gl.FLOAT,false,0,0);
  gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,mwTex);gl.uniform1i(pBg.uMW,0);
  gl.uniform3fv(pBg.uF,F);gl.uniform3fv(pBg.uR,R);gl.uniform3fv(pBg.uU,U);gl.uniform2f(pBg.uT,TX,TY);gl.uniform1f(pBg.uCy,cam.cy);
  gl.uniform1f(pBg.uExp,cam.exp);gl.uniform3fv(pBg.uSky,PAL.sky);gl.uniform3fv(pBg.uTint,PAL.tint);gl.uniform3fv(pBg.uO1,PAL.o[0]);gl.uniform3fv(pBg.uO2,PAL.o[1]);gl.uniform3fv(pBg.uO3,PAL.o[2]);gl.uniform1f(pBg.uAsp,asp);gl.uniform1f(pBg.uHas,mwReady?1:0);
  var br=reduce?.6:breath(rec.state==='live'?clock-rec.t0:clock);
  gl.uniform4f(pBg.uOrb,0,cam.cy,.15+.075*br,cam.orb*(.55+.45*br));
  gl.drawArrays(gl.TRIANGLE_STRIP,0,4);

  gl.enable(gl.BLEND);gl.blendFunc(gl.ONE,gl.ONE);
  /* the overhead circle */
  if(cam.names>.02){
    gl.useProgram(pLn.p);gl.bindBuffer(gl.ARRAY_BUFFER,ring);gl.enableVertexAttribArray(pLn.aP);gl.vertexAttribPointer(pLn.aP,3,gl.FLOAT,false,0,0);
    gl.uniform3fv(pLn.uF,F);gl.uniform3fv(pLn.uR,R);gl.uniform3fv(pLn.uU,U);gl.uniform2f(pLn.uT,TX,TY);gl.uniform1f(pLn.uCy,cam.cy);
    gl.uniform1f(pLn.uA,.2*cam.names);gl.uniform3fv(pLn.uLc,PAL.l[1]);gl.drawArrays(gl.LINE_STRIP,0,nRing);
  }
  /* stars */
  gl.useProgram(pSt.p);gl.bindBuffer(gl.ARRAY_BUFFER,stars);
  gl.enableVertexAttribArray(pSt.aP);gl.vertexAttribPointer(pSt.aP,3,gl.FLOAT,false,28,0);
  gl.enableVertexAttribArray(pSt.aC);gl.vertexAttribPointer(pSt.aC,4,gl.FLOAT,false,28,12);
  gl.uniform3fv(pSt.uF,F);gl.uniform3fv(pSt.uR,R);gl.uniform3fv(pSt.uU,U);gl.uniform2f(pSt.uT,TX,TY);gl.uniform1f(pSt.uCy,cam.cy);
  gl.uniform1f(pSt.uPx,PX*Math.pow(80/cam.fov,.35));gl.uniform1f(pSt.uExp,cam.st);gl.uniform1f(pSt.uTime,clock);gl.uniform1f(pSt.uTw,reduce?0:1);
  gl.drawArrays(gl.POINTS,0,nStars);
  gl.disableVertexAttribArray(pSt.aC);

  /* the blessings */
  gl.useProgram(pLi.p);gl.uniform3fv(pLi.uL1,PAL.l[0]);gl.uniform3fv(pLi.uL2,PAL.l[1]);gl.uniform3fv(pLi.uL3,PAL.l[2]);gl.bindBuffer(gl.ARRAY_BUFFER,quad);gl.enableVertexAttribArray(pLi.aQ);gl.vertexAttribPointer(pLi.aQ,2,gl.FLOAT,false,0,0);
  var RAD=110;
  B.forEach(function(b,i){
    var p=project(b.v);b.p=p;
    var a=cam.lights*(1-cam.solo*(1-b.w));
    if(p.z<-.3||a<.01||Math.abs(p.nx)>1.6||Math.abs(p.ny)>1.4)return;
    gl.uniform2f(pLi.uC,p.nx,p.ny);gl.uniform2f(pLi.uH,RAD/195,RAD/422);gl.uniform1f(pLi.uRad,RAD);gl.uniform1f(pLi.uFoc,b.w);gl.uniform1f(pLi.uA,a);
    gl.drawArrays(gl.TRIANGLE_STRIP,0,4);
  });
  labels();
  drawFx();
}
function labels(){
  var show=screen==='sky'&&!listOn,i,p;
  for(i=0;i<B.length;i++){var b=B[i],el=labEls[i];p=b.p||project(b.v);
    var vis=show&&p.z>0&&p.x>-40&&p.x<430&&p.y>150&&p.y<470&&b.w<.5;
    el.style.opacity=vis?(1-b.w*2)*.95:0;
    if(vis){if(!b.lw)b.lw=el.offsetWidth;el.style.transform='translate('+(p.x-b.lw/2).toFixed(1)+'px,'+(p.y+15).toFixed(1)+'px)'}}
  for(i=0;i<starEls.length;i++){var s=starEls[i];p=project(s.v);
    var v2=show&&p.z>0&&p.x>8&&p.x<340&&p.y>150&&p.y<480;
    if(v2){for(var j=0;j<B.length;j++){var q=B[j].p;if(q&&Math.abs(q.x-p.x)<70&&Math.abs(q.y-p.y)<34){v2=false;break}}}
    s.el.style.opacity=v2?.85*cam.names:0;
    if(v2)s.el.style.transform='translate('+(p.x+9).toFixed(1)+'px,'+(p.y-8).toFixed(1)+'px)'}
}

/* ---------- looking around ---------- */
var dragging=false;
(function(){
  var t=$('touch'),sx=0,sy=0,lx=0,ly=0,lt=0,moved=0;
  function scale(){return TY/422/K}
  t.addEventListener('pointerdown',function(ev){dragging=true;moved=0;sx=lx=ev.clientX;sy=ly=ev.clientY;lt=performance.now();t.setPointerCapture(ev.pointerId);t.classList.add('drag');vel.ra=vel.dec=0});
  t.addEventListener('pointermove',function(ev){
    if(!dragging)return;var dx=ev.clientX-lx,dy=ev.clientY-ly,now=performance.now(),dt=Math.max(8,now-lt)/1000;
    moved+=Math.abs(dx)+Math.abs(dy);if(moved<5)return;
    if(!free){free=true;glide=null}
    var s=scale(),dra=dx*s/Math.max(.2,Math.cos(cam.dec)),dde=dy*s;
    cam.ra+=dra;cam.dec=clamp(cam.dec+dde,-86*DEG,86*DEG);
    vel.ra=clamp(.6*vel.ra+.4*dra/dt,-1.6,1.6);vel.dec=clamp(.6*vel.dec+.4*dde/dt,-1.6,1.6);lx=ev.clientX;ly=ev.clientY;lt=now;
  });
  function up(ev){
    if(!dragging)return;dragging=false;t.classList.remove('drag');
    if(performance.now()-lt>90){vel.ra=vel.dec=0}
    if(moved<5){
      var r=$('phone').getBoundingClientRect(),x=(ev.clientX-r.left)/K,y=(ev.clientY-r.top)/K,best=-1,bd=34;
      B.forEach(function(b,i){if(!b.p||b.p.z<0)return;var d=Math.hypot(b.p.x-x,b.p.y-y);if(d<bd){bd=d;best=i}});
      if(best>=0){if(best===focus&&!free)go('read');else setFocus(best)}
    }
  }
  t.addEventListener('pointerup',up);t.addEventListener('pointercancel',function(){dragging=false;t.classList.remove('drag')});
  t.addEventListener('wheel',function(ev){ev.preventDefault();goal.fov=clamp(goal.fov*Math.exp(ev.deltaY*.0022),34,104)},{passive:false});
})();

/* ---------- boot ---------- */
var booted=false;
function ready(){
  if(booted)return;
  var f=document.fonts&&document.fonts.ready?document.fonts.ready:Promise.resolve();
  f.then(function(){booted=true;draw();document.documentElement.setAttribute('data-ready','1')});
}
window.addEventListener('resize',fit);
try{if(gl)init()}catch(err){console.error(err);gl=null;$('fallback').style.display='grid'}
renderReview();
setFocus(P.focus!==undefined?Math.max(0,B.map(function(b){return b.id}).indexOf(P.focus)):3,true,true);
fit();
setRec(REC);
go(first,true);
if(P.sel!==undefined)selectEdit(+P.sel,null,true);
if(P.list)showList(true);
if(P.shot||P.bare)document.documentElement.classList.add('notrans');
if(P.t!==undefined)clock=+P.t;
if(!gl)ready();

/* live loop, or a clock driven from outside for stills and film */
var last=0,manual=!!P.manual;
function loop(ts){
  if(!manual){var dt=last?Math.min(.05,(ts-last)/1000):0;last=ts;step(dt)}
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
window.__sky={
  step:function(dt){step(dt)},
  manual:function(on){manual=on},
  go:function(n,instant){go(n,instant)},
  focus:function(i,instant){setFocus(i,false,instant)},
  look:function(ra,dec){free=true;glide=null;cam.ra=ra;cam.dec=dec},
  rec:rec,setRec:setRec,
  cam:cam,goal:goal,B:B,
  setClock:function(t){clock=t}
};
})();
