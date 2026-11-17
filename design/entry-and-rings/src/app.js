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
var part=/^(A|B1|B2|B3)$/.test(P.part)?P.part:'A';
var opt=P.opt==='s2'?'s2':'s1';
var flow='';

/* ---------- icons: 24 grid, 1.5 stroke, round ends, as app/lib/widgets/icons.dart ---------- */
function blessingPath(){
  var cx=12,cy=17,r=11.5,segs=[[-68,-50.3],[-29.7,-13],[13,29.7],[50.3,68]],d='';
  function pt(a){a*=DEG;return (cx+r*Math.sin(a)).toFixed(2)+' '+(cy-r*Math.cos(a)).toFixed(2)}
  segs.forEach(function(s){d+='M'+pt(s[0])+'A'+r+' '+r+' 0 0 1 '+pt(s[1])});
  return '<path d="'+d+'"/><circle class="dot" cx="12" cy="5.5" r="2"/><circle class="dot" cx="4.61" cy="8.19" r="1.4"/><circle class="dot" cx="19.39" cy="8.19" r="1.4"/><circle cx="12" cy="16" r="4.75"/>';
}
var G={
  blessing:blessingPath(),
  rec:'<circle cx="12" cy="12" r="8.25"/><circle class="dot" cx="12" cy="12" r="3.25"/>',
  enter:'<path d="M17.5 11V8.5l-5-5H6.5A1.5 1.5 0 0 0 5 5v14a1.5 1.5 0 0 0 1.5 1.5H11"/><path d="M12.5 3.5v5h5"/><path d="M8 12h5M8 15.5h3"/><path d="M14 20.5l.55-2.45 4.6-4.6a1.35 1.35 0 0 1 1.9 1.9l-4.6 4.6z"/>',
  text:'<path d="M5 6.5h14M5 10.5h14M5 14.5h14M5 18.5h8.5"/>',
  paste:'<rect x="6" y="5" width="12" height="15.5" rx="2"/><path d="M9.5 5V4.25c0-.7.55-1.25 1.25-1.25h2.5c.7 0 1.25.55 1.25 1.25V5"/><path d="M9 11h6M9 14.5h6"/>',
  cal:'<rect x="4" y="5.5" width="16" height="14.5" rx="2.5"/><path d="M4 10h16M8.5 3.5v4M15.5 3.5v4"/>',
  camera:'<path d="M4 8.5A1.5 1.5 0 0 1 5.5 7h2.3l1.5-2h5.4l1.5 2h2.3A1.5 1.5 0 0 1 20 8.5v9a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5z"/><circle cx="12" cy="12.75" r="3.5"/>',
  ring:'<ellipse cx="12" cy="12" rx="9" ry="4.5"/><circle class="dot" cx="5.6" cy="15.2" r="1.25"/><circle class="dot" cx="12" cy="16.5" r="1.7"/><circle class="dot" cx="18" cy="15.35" r="1.1"/>',
  hand:'<ellipse cx="10" cy="15" rx="7" ry="3.5"/><circle class="dot" cx="10" cy="18.5" r="1.4"/><path d="M13.5 9.5L20 3.5M15.5 3.5H20V8"/>',
  more:'<circle class="dot" cx="6" cy="12" r="1.4"/><circle class="dot" cx="12" cy="12" r="1.4"/><circle class="dot" cx="18" cy="12" r="1.4"/>',
  list:'<path d="M9.5 6.5h10M9.5 12h10M9.5 17.5h10"/><circle class="dot" cx="5" cy="6.5" r="1.25"/><circle class="dot" cx="5" cy="12" r="1.25"/><circle class="dot" cx="5" cy="17.5" r="1.25"/>',
  back:'<path d="M14.5 6l-6 6 6 6"/>',
  fwd:'<path d="M10 6l6 6-6 6"/>',
  down:'<path d="M7 10l5 5 5-5"/>',
  updown:'<path d="M8.5 9.5L12 6l3.5 3.5M8.5 14.5L12 18l3.5-3.5"/>',
  check:'<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  plus:'<path d="M12 5.5v13M5.5 12h13"/>',
  pencil:'<path d="M4.5 19.5l.8-3.6L15.6 5.6a1.9 1.9 0 0 1 2.7 2.7L8 18.6z"/><path d="M14 7.2l2.7 2.7"/>',
  share:'<path d="M9.25 9.75h-1.5A1.75 1.75 0 0 0 6 11.5v7a1.75 1.75 0 0 0 1.75 1.75h8.5A1.75 1.75 0 0 0 18 18.5v-7a1.75 1.75 0 0 0-1.75-1.75h-1.5"/><path d="M12 14V3.75M8.75 7L12 3.75 15.25 7"/>',
  play:'<path class="dot" d="M8 5.5v13l10.5-6.5z"/>',
  back10:'<path d="M6 12a6.5 6.5 0 1 0 2-4.7"/><path d="M8 3.5v3.8h3.8"/>',
  page:'<path d="M7 3.5h6.5l5 5V19a1.5 1.5 0 0 1-1.5 1.5H7A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5z"/><path d="M13.5 3.5v5h5"/><path d="M8.5 12.5h7M8.5 16h5"/>'
};
function ic(n,cls){return '<svg class="ico'+(cls?' '+cls:'')+'" viewBox="0 0 24 24" aria-hidden="true">'+G[n]+'</svg>'}

/* ---------- every word, English and Spanish ---------- */
var W={
en:{
 forMe:'For me',newBlessing:'New blessing',record:'Record',enter:'Enter',
 recTitle:'New blessing',close:'Close',begin:'Begin',nothingRec:'Nothing is recorded until you press.',langName:'English',
 enterPast:'Enter a past blessing',
 done:'Done',titlePh:'Blessing',given:'Given',whenAsk:'When was it given?',from:'From',forK:'For',namePh:'Name',
 whose:'Whose blessing',forMeChoice:'For me',passing:'Passing it along',tags:'Tags',addTag:'Add a tag',
 sug:['Family','Healing','Calling','Comfort','Work'],
 theWords:'The words',wordsPh:'Type the words here, or paste them in one go.',paste:'Paste',pasted:'Upon Thy Head pasted from Notes',
 dseg:['Full date','Month and year','Year only'],
 months:['January','February','March','April','May','June','July','August','September','October','November','December'],
 noteMonth:'Only the month is known. Its light sits at mid-August 1998.',
 noteYear:'Only the year is known. Its light sits at mid-1998.',
 count5:'Five blessings since June 2024',count6:'Six blessings since August 1998',
 me:{meta:'Sunday, October 4, 2026',title:'Before the new job',from:'From Dad',l1:'Aug 24, 2025',l2:'Mar 3, 2026',l0:'Jun 2024'},
 pastTitle:'Before college',pastFrom:'Dad',pastFor:'Daniel',pastWhen:'August 1998',pastFromLine:'From Dad',pastByLine:'A blessing from Dad',
 honest:'Entered from a written copy, not recorded.',asSpoken:'The words as they were spoken.',
 forDaniel:'For Daniel',tagFamily:'Family',ringNote:'Its light keeps its place in time on the ring of sky overhead.',del:'Delete this blessing',
 later:'A later idea',camLede:'The words are read on this phone. The photo is not kept.',camBtn:'Read the words',
 PAST:['Daniel, by the authority of the Melchizedek Priesthood which I hold, I lay my hands upon your head and give you a father’s blessing as you leave home for the first time.',
  'Your Heavenly Father knows you by name. He has watched over you all your life, and He will go with you to this new place. When you feel alone, remember that you are not.',
  'I bless you with a clear mind for your studies, and with the discipline to do hard things when no one is watching. I bless you that you will find good friends, and that you will be a good friend to them.',
  'I bless you to keep praying, morning and night, even on the days when it feels like no one is listening. Answers will come, sometimes slowly, and often through the people around you.',
  'Your mother and I love you. Come home often.',
  'I say these things in the name of Jesus Christ, amen.'],
 /* B */
 forX:function(n){return 'For '+n},
 rows:[['For me','Five blessings since June 2024'],['For Emma','Seven blessings since August 2008'],['For James','Four blessings since March 2013']],
 addSomeone:'Add someone',
 addLede:'For a child without a phone of their own. Their blessings are kept here until you hand them over.',
 nameK:'Name',bornK:'Born',bornV:'November 2, 2026',bornNote:'Optional. Their ring begins on this day.',add:'Add',
 noYet:'No blessings yet',claraEmpty:'When a blessing is recorded for Clara, a light appears here.',
 emmaCount:'Seven blessings since August 2008',jamesCount:'Four blessings since March 2013',
 emma:{meta:'Sunday, August 16, 2026',title:'Before leaving home',from:'From Dad',l1:'Aug 2022'},
 menuHand:'Hand over Emma’s ring',menuEdit:'Edit name and birth date',
 cardT:'Emma’s ring',keptBy:'Kept by',dad:'Dad',sendRing:'Send Emma’s ring',emmaCan:'Emma can keep them in Upon Thy Head.',
 handFoot:'This sends a link. Anyone who has it can read these blessings.',
 sent:'Sent',sentQ:'Keep Emma’s ring on this phone, or delete it now?',sentQ2:'If you keep it, blessings added later can be sent to Emma too.',
 delete:'Delete',keep:'Keep',
 openT:'Your blessings were kept for you.',openL:'Dad kept seven blessings for you, from August 2008. Read them first, then keep them.',cont:'Continue',
 nameBlessing:'A name and a blessing',nameDate:'Sunday, August 10, 2008',
 BABY:['Emma Grace, holding you in our arms, by the authority of the Melchizedek Priesthood, we give you a name and a blessing. The name by which you will be known is Emma Grace.',
  'We bless you with health and strength as you grow. We bless you with a quick mind and a gentle heart, and that you will come to know your Heavenly Father for yourself.',
  'We bless you that you will feel at home in this family, and that you will always know you are loved.',
  'We say these things in the name of Jesus Christ, amen.'],
 oneOf:'1 of 7',notNow:'Not now',keepThem:'Keep them',
 keptForYou:'Kept for you by Dad',
 handedOn:'Handed to Emma on November 16',oneNew:'One new · Send it',
 xmas:{meta:'Thursday, December 24, 2026',title:'Christmas, at home',from:'From Dad'},
 moreT:'Four more of your blessings',moreFrom:'Kept by Mom',moreMeta:'August 2014 to May 2024',moreQ:'They join your ring by their dates. Keep them?',
 keptBoth:'Kept for you by Dad and Mom',count11:'Eleven blessings since August 2008',
 today:'Monday, November 16, 2026',
 SPOKEN:['Emma I lay my hands upon your head as you go back to school after this visit home',
  'Your Heavenly Father is aware of you and the things that weigh on you this term'],
 handed:'handed over',
 passList:'To pass along',passLede:'Blessings recorded for someone else. They have no light in your sky.',
 gEmma:'Seven blessings · not sent yet',gJames:'Four blessings · not sent yet',gClara:'One blessing · not sent yet',sendAll:'Send all',
 fourMore:'Four more',threeMore:'Three more',fiveMore:'Five more',
 rowsE:[['Before leaving home','Aug 16, 2026'],['Before high school','Aug 21, 2022']],
 rowsJ:[['Before the move','Jun 3, 2025']],rowsC:[['A name and a blessing','Nov 1, 2026']],
 cardT3:'Emma’s blessings',sendAll7:'Send all seven to Emma',
 sentQ3:'Keep these seven on this phone, or delete them now?',sentQ23:'Each one also stays in this list as sent.',
 gEmmaSent:'Seven blessings · sent November 16'
},
es:{
 forMe:'Para mí',newBlessing:'Nueva bendición',record:'Grabar',enter:'Anotar',
 recTitle:'Nueva bendición',close:'Cerrar',begin:'Comenzar',nothingRec:'No se graba nada hasta que lo presiones.',langName:'Español',
 enterPast:'Anotar una bendición pasada',
 done:'Listo',titlePh:'Bendición',given:'Fecha',whenAsk:'¿Cuándo se dio?',from:'De',forK:'Para',namePh:'Nombre',
 whose:'De quién es',forMeChoice:'Para mí',passing:'Para entregar',tags:'Etiquetas',addTag:'Agregar una etiqueta',
 sug:['Familia','Sanación','Llamamiento','Consuelo','Trabajo'],
 theWords:'Las palabras',wordsPh:'Escribe aquí las palabras, o pégalas de una vez.',paste:'Pegar',pasted:'Upon Thy Head pegó desde Notas',
 dseg:['Fecha exacta','Mes y año','Solo el año'],
 months:['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'],
 noteMonth:'Solo se sabe el mes. Su luz se sitúa a mediados de agosto de 1998.',
 noteYear:'Solo se sabe el año. Su luz se sitúa a mediados de 1998.',
 count5:'Cinco bendiciones desde junio de 2024',count6:'Seis bendiciones desde agosto de 1998',
 me:{meta:'domingo, 4 de octubre de 2026',title:'Antes del nuevo trabajo',from:'De papá',l1:'24 ago 2025',l2:'3 mar 2026',l0:'jun 2024'},
 pastTitle:'Antes de la universidad',pastFrom:'Papá',pastFor:'Daniel',pastWhen:'agosto de 1998',pastFromLine:'De papá',pastByLine:'Una bendición de papá',
 honest:'Anotada de una copia escrita, no grabada.',asSpoken:'Las palabras tal como se dijeron.',
 forDaniel:'Para Daniel',tagFamily:'Familia',ringNote:'Su luz guarda su lugar en el tiempo, en el anillo del cielo que está en lo alto.',del:'Eliminar esta bendición',
 later:'Una idea para después',camLede:'Las palabras se leen en este teléfono. La foto no se guarda.',camBtn:'Leer las palabras',
 PAST:['Daniel, por la autoridad del Sacerdocio de Melquisedec que poseo, pongo mis manos sobre tu cabeza y te doy una bendición de padre al salir de casa por primera vez.',
  'Tu Padre Celestial te conoce por tu nombre. Ha velado por ti toda tu vida y te acompañará a este lugar nuevo. Cuando te sientas solo, recuerda que no lo estás.',
  'Te bendigo con una mente clara para tus estudios y con la disciplina para hacer cosas difíciles cuando nadie te ve. Te bendigo para que encuentres buenos amigos y para que tú seas un buen amigo para ellos.',
  'Te bendigo para que sigas orando, mañana y noche, aun en los días en que parezca que nadie escucha. Las respuestas llegarán, a veces despacio, y a menudo por medio de las personas que te rodean.',
  'Tu madre y yo te queremos. Ven a casa a menudo.',
  'Digo estas cosas en el nombre de Jesucristo. Amén.'],
 forX:function(n){return 'Para '+n},
 rows:[['Para mí','Cinco bendiciones desde junio de 2024'],['Para Emma','Siete bendiciones desde agosto de 2008'],['Para James','Cuatro bendiciones desde marzo de 2013']],
 addSomeone:'Agregar a alguien',
 addLede:'Para un hijo o una hija sin teléfono propio. Sus bendiciones se guardan aquí hasta que se las entregues.',
 nameK:'Nombre',bornK:'Nació',bornV:'2 de noviembre de 2026',bornNote:'Opcional. Su anillo comienza ese día.',add:'Agregar',
 noYet:'Todavía no hay bendiciones',claraEmpty:'Cuando se grabe una bendición para Clara, una luz aparecerá aquí.',
 emmaCount:'Siete bendiciones desde agosto de 2008',jamesCount:'Cuatro bendiciones desde marzo de 2013',
 emma:{meta:'domingo, 16 de agosto de 2026',title:'Antes de irse de casa',from:'De papá',l1:'ago 2022'},
 menuHand:'Entregar el anillo de Emma',menuEdit:'Editar nombre y nacimiento',
 cardT:'El anillo de Emma',keptBy:'Guardadas por',dad:'Papá',sendRing:'Enviar el anillo de Emma',emmaCan:'Emma podrá guardarlas en Upon Thy Head.',
 handFoot:'Esto envía un enlace. Quien lo tenga puede leer estas bendiciones.',
 sent:'Enviado',sentQ:'¿Guardar el anillo de Emma en este teléfono o eliminarlo ahora?',sentQ2:'Si lo guardas, las bendiciones que agregues después también se pueden enviar a Emma.',
 delete:'Eliminar',keep:'Guardar',
 openT:'Tus bendiciones se guardaron para ti.',openL:'Papá guardó siete bendiciones para ti, desde agosto de 2008. Léelas primero y luego guárdalas.',cont:'Continuar',
 nameBlessing:'Nombre y bendición',nameDate:'domingo, 10 de agosto de 2008',
 BABY:['Emma Grace, teniéndote en nuestros brazos, por la autoridad del Sacerdocio de Melquisedec, te damos un nombre y una bendición. El nombre por el cual se te conocerá es Emma Grace.',
  'Te bendecimos con salud y fuerza mientras creces. Te bendecimos con una mente despierta y un corazón amable, y para que llegues a conocer a tu Padre Celestial por ti misma.',
  'Te bendecimos para que te sientas en casa en esta familia, y para que siempre sepas que eres amada.',
  'Decimos estas cosas en el nombre de Jesucristo. Amén.'],
 oneOf:'1 de 7',notNow:'Ahora no',keepThem:'Guardarlas',
 keptForYou:'Guardadas para ti por papá',
 handedOn:'Entregado a Emma el 16 de noviembre',oneNew:'Una nueva · Enviarla',
 xmas:{meta:'jueves, 24 de diciembre de 2026',title:'Navidad, en casa',from:'De papá'},
 moreT:'Cuatro bendiciones más para ti',moreFrom:'Guardadas por mamá',moreMeta:'De agosto de 2014 a mayo de 2024',moreQ:'Se unen a tu anillo según sus fechas. ¿Guardarlas?',
 keptBoth:'Guardadas para ti por papá y mamá',count11:'Once bendiciones desde agosto de 2008',
 today:'lunes, 16 de noviembre de 2026',
 SPOKEN:['Emma pongo mis manos sobre tu cabeza ahora que regresas a la escuela después de esta visita a casa',
  'Tu Padre Celestial sabe de ti y de las cosas que te pesan este semestre'],
 handed:'entregado',
 passList:'Para entregar',passLede:'Bendiciones grabadas para otra persona. No tienen luz en tu cielo.',
 gEmma:'Siete bendiciones · aún no enviadas',gJames:'Cuatro bendiciones · aún no enviadas',gClara:'Una bendición · aún no enviada',sendAll:'Enviar todas',
 fourMore:'Cuatro más',threeMore:'Tres más',fiveMore:'Cinco más',
 rowsE:[['Antes de irse de casa','16 ago 2026'],['Antes de la preparatoria','21 ago 2022']],
 rowsJ:[['Antes de la mudanza','3 jun 2025']],rowsC:[['Nombre y bendición','1 nov 2026']],
 cardT3:'Las bendiciones de Emma',sendAll7:'Enviar las siete a Emma',
 sentQ3:'¿Guardar estas siete en este teléfono o eliminarlas ahora?',sentQ23:'Cada una sigue en esta lista como enviada.',
 gEmmaSent:'Siete bendiciones · enviadas el 16 de noviembre'
}};
var L=function(){return W[lang]};

/* ---------- the sky's overlay: the ring, its lights, their labels ---------- */
var SK=null,skT0=0;
var RING_R=760;
function ringY(r,x){return r.y-(RING_R-Math.sqrt(RING_R*RING_R-(x-195)*(x-195)))}
function homeRing(lights,o){o=o||{};return {y:o.y||343,a:o.a===undefined?.24:o.a,from:o.from===undefined?-20:o.from,to:o.to===undefined?410:o.to,lights:lights,name:o.name,nameA:o.nameA,la:o.la===undefined?1:o.la}}

/* ---------- the ruler of dates ---------- */
function ruler(o){
  var x0=48,x1=342,w=x1-x0,s='',y0=o.y0,y1=o.y1,sp=y1-y0;
  function X(t){return x0+(t-y0)/sp*w}
  var minorStep=sp<=5?.25:1,y;
  for(y=Math.ceil(y0/minorStep)*minorStep;y<=y1+1e-9;y+=minorStep){var major=Math.abs(y-Math.round(y))<1e-6&&(sp<=5||Math.round(y)%5===0);
    s+='<line x1="'+X(y).toFixed(1)+'" x2="'+X(y).toFixed(1)+'" y1="'+(major?7:11)+'" y2="21" stroke="rgba(239,230,212,'+(major?.45:.22)+')" stroke-width="1"/>'}
  o.dots.forEach(function(t,i){var sel=i===o.sel;s+='<circle cx="'+X(t).toFixed(1)+'" cy="15" r="'+(sel?6.5:3.2)+'" fill="'+(sel?'#F0C987':'rgba(240,201,135,.8)')+'"/>'});
  o.labels.forEach(function(l){var t=typeof l==='number'?l:l[0],tx=typeof l==='number'?String(l):l[1];s+='<text x="'+X(t+(sp<=5?.5:0)).toFixed(1)+'" y="42" fill="#8A806E" font-size="13" text-anchor="middle" font-family="-apple-system,system-ui,sans-serif">'+tx+'</text>'});
  return '<div class="ruler"><svg width="390" height="52" viewBox="0 0 390 52" aria-hidden="true"><g transform="translate(14 6)" fill="none" stroke="#B5AB98" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M8 4l-6 6 6 6"/></g><g transform="translate(362 6)" fill="none" stroke="rgba(181,171,152,.35)" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M2 4l6 6-6 6"/></g>'+s+'</svg></div>';
}
var R_ME={y0:2023.9,y1:2027.05,dots:[2024.45,2025.1,2025.65,2026.17,2026.76],sel:4,labels:[2024,2025,2026]};
var R_ME6={y0:1997.4,y1:2027.4,dots:[1998.6,2024.45,2025.1,2025.65,2026.17,2026.76],labels:[2000,2005,2010,2015,2020,2025]};
var R_EMMA={y0:2007.6,y1:2027.4,dots:[2008.6,2013.65,2015.05,2016.45,2019.65,2022.65,2026.62],sel:6,labels:[2010,2015,2020,2025]};
var R_JAMES={y0:2012.5,y1:2027.2,dots:[2013.2,2016.4,2020.7,2025.4],sel:3,labels:[2015,2020,2025]};
function cp(o,ex){var r={},k;for(k in o)r[k]=o[k];for(k in ex)r[k]=ex[k];return r}

/* ---------- pieces of the app ---------- */
function homeHead(o){
  var t=L();
  return '<div class="hd"><div class="tt"><h1'+(o.sw?' class="sw" data-go="'+o.sw+'"':'')+'>'+o.title+(o.chev?ic('down','chev'):'')+'</h1>'+
    (o.count?'<p class="count">'+o.count+'</p>':'')+(o.count2?'<p class="count2">'+o.count2+'</p>':'')+
    (o.handed?'<p class="handed">'+ic('hand')+'<span>'+o.handed+'</span></p>':'')+
    (o.newpill?'<button class="newpill"'+(o.newgo?' data-go="'+o.newgo+'"':'')+'>'+ic('blessing')+'<span>'+o.newpill+'</span></button>':'')+
    '</div><div class="tools"><button class="ib" aria-label="More"'+(o.more?' data-go="'+o.more+'"':'')+'>'+ic('more')+'</button><button class="ib" aria-label="List">'+ic('list')+'</button></div></div>';
}
function home(o){
  var t=L(),h='<div class="home">'+homeHead(o);
  if(o.empty)h+='<p class="empty">'+o.empty+'</p>';
  if(o.info)h+='<div class="info"><div class="x"><p class="meta">'+o.info.meta+'</p><h2 class="title">'+o.info.title+'</h2><p class="from">'+o.info.from+'</p></div><button class="go" aria-label="Read">'+ic('fwd')+'</button></div>';
  if(o.ruler)h+=ruler(o.ruler);
  h+='<div class="actions">';
  if(o.split){h+='<button class="pill" data-go="'+(o.recgo||'')+'">'+ic('rec')+'<span>'+t.record+'</span></button><button class="pill q" data-go="'+o.split+'">'+ic('enter')+'<span>'+t.enter+'</span></button>'}
  else h+='<button class="pill"'+(o.newgo?' data-go="'+o.newgo+'"':'')+'>'+ic('rec')+'<span>'+t.newBlessing+'</span></button>';
  h+='</div>'+(o.extra||'')+'</div>';
  return h;
}
function recScreen(o){
  var t=L();
  return '<div class="rec"><div class="top"><p class="t">'+t.recTitle+'</p>'+(o.forwho?'<button class="forwho">'+o.forwho+ic('down')+'</button>':'')+'</div><button class="close">'+t.close+'</button>'+
    '<button class="begin"'+(o.begin?' data-go="'+o.begin+'"':'')+'>'+t.begin+'</button><p class="hint">'+t.nothingRec+'</p><p class="lang">'+t.langName+' ⌃⌄</p>'+
    (o.enter?'<div class="enter"><button class="pill q" data-go="'+o.enter+'">'+ic('enter')+'<span>'+t.enterPast+'</span></button></div>':'')+'</div>';
}
function seg2(on){var t=L();return '<div class="whose"><p class="k">'+t.whose+'</p><div class="seg2"><span'+(on==='me'?' class="on"':'')+'>'+t.forMeChoice+'</span><span'+(on==='pass'?' class="on"':'')+'>'+t.passing+'</span></div></div>'}
function pillsWhose(on){var t=L(),o=[['me',t.forMeChoice],['Emma','Emma'],['James','James'],['Clara','Clara'],['pass',t.passing]];
  return '<div class="whose"><p class="k">'+t.whose+'</p><div class="pills">'+o.map(function(x){return '<span'+(x[0]===on?' class="on"':'')+'>'+x[1]+'</span>'}).join('')+'</div></div>'}
function tags(on){var t=L();return '<div class="tags"><p class="k">'+t.tags+'</p>'+(on?'<div class="sug"><span class="on">'+on+' ×</span></div>':'')+'<p class="add">'+t.addTag+'</p><div class="sug">'+t.sug.filter(function(s){return s!==on}).map(function(s){return '<span>+ '+s+'</span>'}).join('')+'</div></div>'}
function words(arr,cls){return '<div class="words'+(cls?' '+cls:'')+'">'+arr.map(function(w){return '<p>'+w+'</p>'}).join('')+'</div>'}
function frow(k,v,o){o=o||{};return '<div class="frow'+(o.hot?' hot':'')+'"'+(o.go?' data-go="'+o.go+'" style="cursor:pointer"':'')+'><span class="k">'+k+'</span><span class="v'+(o.cls?' '+o.cls:'')+'">'+v+'</span>'+(o.icon?ic(o.icon):'')+'</div>'}
/* the entry page: the review page, with "Given" and the words to type or paste */
function entry(o){
  var t=L(),h='<div class="pg"><div class="scrim"></div><div class="gd"></div><div class="bar"><button class="ib" aria-label="Back">'+ic('back')+'</button><span class="sp"></span><button class="done'+(o.doneDim?' dim':'')+'"'+(o.done?' data-go="'+o.done+'"':'')+'>'+t.done+'</button></div>';
  var body='<h1 class="ptitle'+(o.title?'':' ph')+'">'+(o.title||t.titlePh)+'</h1><div class="rows">'+
    frow(t.given,o.when||t.whenAsk,{cls:o.when?'':'ask',icon:'cal',hot:!o.when,go:o.dateGo})+
    frow(t.from,o.from||t.namePh,{cls:o.from?'':'ph'})+frow(t.forK,o.forv||t.namePh,{cls:o.forv?'':'ph'})+'</div>'+
    (o.whosePills?pillsWhose(o.whosePills):seg2(o.whose||'me'))+tags(o.tag);
  if(o.words)body+='<p class="wordsk">'+t.theWords+'</p>'+words(o.words,'mt');
  else body+='<p class="wordsk">'+t.theWords+'</p><div class="wbox"><p class="ph">'+t.wordsPh+'</p><button class="chip"'+(o.paste?' data-go="'+o.paste+'"':'')+'>'+ic('paste')+t.paste+'</button></div>';
  if(o.scrollTo!==undefined){h+='<div class="barfade"></div><div class="in" style="top:'+o.scrollTo+'px">'+body+'</div><div class="sbar" style="top:'+o.sbTop+'px;height:'+o.sbH+'px"></div>'}
  else h+='<div class="in">'+body+'</div>';
  if(o.banner)h+='<div class="pasted">'+ic('paste')+'<span>'+t.pasted+'</span></div>';
  return h+'</div>';
}
function review(o){
  var t=L();
  return '<div class="pg"><div class="scrim"></div><div class="gd"></div><div class="bar"><button class="ib">'+ic('back')+'</button><span class="sp"></span><button class="done">'+t.done+'</button></div>'+
    '<div class="in"><p class="meta">'+t.today+'</p><h1 class="ptitle ph" style="margin-top:4px">'+t.titlePh+'</h1><div class="rows">'+frow(t.from,o.from)+frow(t.forK,o.forv)+'</div>'+
    (o.whosePills?pillsWhose(o.whosePills):seg2(o.whose))+
    '<div class="listen">'+ic('play')+ic('back10')+'<span class="tr"></span><span class="tm">0:00 / 0:52</span></div>'+words(L().SPOKEN,'mt')+'</div></div>';
}
function readingTop(o){
  var t=L();
  return '<div class="pg"><div class="scrim"></div><div class="gd"></div><div class="bar"><button class="ib">'+ic('back')+'</button><span class="sp"></span>'+(o.noTools?'':'<button class="ib">'+ic('share')+'</button><button class="done">'+(lang==='es'?'Editar':'Edit')+'</button>')+'</div>'+
    '<div class="in"><p class="meta">'+o.meta+'</p><h1 class="ptitle" style="margin-top:4px">'+o.title+'</h1><p class="from" style="margin-top:4px">'+o.by+'</p>'+words(o.words,'mt')+'</div>'+(o.extra||'')+'</div>';
}
function readingEnd(){
  var t=L();
  return '<div class="pg"><div class="gd" style="top:0"></div><div class="bar"><button class="ib">'+ic('back')+'</button><span class="sp"></span><button class="ib">'+ic('share')+'</button><button class="done">'+(lang==='es'?'Editar':'Edit')+'</button></div><div class="barfade"></div>'+
    '<div class="in" style="top:auto;bottom:'+(big?-40:60)+'px">'+words(t.PAST.slice(big?3:2))+
    '<div class="endnote"><p class="honest">'+ic('page')+'<span>'+t.honest+'</span></p><p class="gap" style="color:var(--ink-2)">'+t.forDaniel+'</p><p>'+t.tagFamily+'</p><p class="gap">'+t.ringNote+'</p><p class="del">'+t.del+'</p></div></div><div class="sbar" style="top:690px;height:90px"></div></div>';
}
function sheet(inner,label){return '<div class="dimmer"></div><div class="sheet" role="dialog" aria-label="'+(label||'')+'"><div class="grab"></div>'+inner+'</div>'}
function dateSheet(mode){
  var t=L(),m=t.months,cols;
  function col(items,on){return '<div class="col">'+items.map(function(x,i){var d=Math.abs(i-on);return '<span class="'+(d===0?'on':d===1?'n1':'n2')+'">'+x+'</span>'}).join('')+'</div>'}
  var mo=col([m[5],m[6],m[7],m[8],m[9]],2),dy=col(['21','22','23','24','25'],2),yr=col(['1996','1997','1998','1999','2000'],2);
  cols=mode===0?(lang==='es'?dy+mo+yr:mo+dy+yr):mode===1?mo+yr:yr;
  var note=mode===1?t.noteMonth:mode===2?t.noteYear:'';
  return sheet('<h2>'+t.whenAsk+'</h2><div class="dseg">'+t.dseg.map(function(s,i){return '<span'+(i===mode?' class="on"':'')+' data-go="'+['a-date-day','a-date-month','a-date-year'][i]+'" style="cursor:pointer">'+s+'</span>'}).join('')+'</div>'+
    '<div class="wheels"><div class="band"></div>'+cols+'</div><p class="dnote'+(note?'':' blank')+'">'+ic('blessing')+'<span>'+(note||'.')+'</span></p>'+
    '<div style="margin-top:16px"><button class="btn primary" data-go="a-filled">'+t.done+'</button></div>',t.whenAsk);
}
function ringThumb(){
  var s='<svg width="64" height="64" viewBox="0 0 64 64"><defs><radialGradient id="lg"><stop offset="0" stop-color="#FFF4DE"/><stop offset=".25" stop-color="#F0C987" stop-opacity=".8"/><stop offset="1" stop-color="#F0C987" stop-opacity="0"/></radialGradient></defs>'+
    '<circle cx="14" cy="12" r=".6" fill="#fff" opacity=".5"/><circle cx="50" cy="16" r=".5" fill="#fff" opacity=".4"/><circle cx="40" cy="52" r=".5" fill="#fff" opacity=".35"/><circle cx="22" cy="50" r=".4" fill="#fff" opacity=".3"/>'+
    '<path d="M-4 30 Q32 44 68 30" fill="none" stroke="rgba(240,201,135,.35)" stroke-width=".8"/>';
  [[6,32.6,3],[17,35.6,3.4],[27,37,3.8],[38,36.9,4.4],[49,34.8,5],[58,32.4,7]].forEach(function(p){s+='<circle cx="'+p[0]+'" cy="'+p[1]+'" r="'+p[2]+'" fill="url(#lg)"/>'});
  return s+'</svg>';
}
function handSheet(o){
  var t=L();
  return sheet('<div class="card"><div class="top"><span class="thumb">'+ringThumb()+'</span><span><span class="t">'+o.title+'</span><span class="f">'+t.emmaCount+'</span></span></div>'+
    frow(t.keptBy,t.dad,{icon:'pencil'})+
    '<button class="btn primary main" data-go="'+o.next+'">'+ic('blessing')+'<span>'+o.btn+'</span></button><p class="under">'+t.emmaCan+'</p></div><p class="foot">'+t.handFoot+'</p>',o.title);
}
function sentSheet(q,q2,next){
  var t=L();
  return '<div class="keepq">'+sheet('<h2>'+t.sent+'</h2><p class="q">'+q+'</p><p class="q2">'+q2+'</p><div class="pairbtn"><button class="btn warn">'+t.delete+'</button><button class="btn primary" data-go="'+next+'">'+t.keep+'</button></div>',t.sent)+'</div>';
}
function switchSheet(on){
  var t=L();
  return sheet('<div class="rlist">'+t.rows.map(function(r,i){var go=['b1-home','b1-emma','b1-emma'][i];return '<button class="'+(i===on?'on':'')+'" data-go="'+go+'">'+ic('ring','rg')+'<span class="x"><span class="t">'+r[0]+'</span><span class="m">'+r[1]+'</span></span>'+(i===on?ic('check','ck'):'')+'</button>'}).join('')+
    '<button class="add" data-go="b1-add">'+ic('plus','rg')+'<span class="x"><span class="t">'+t.addSomeone+'</span></span></button></div>',t.forMe);
}
function addPage(next){
  var t=L();
  return '<div class="pg plain"><div class="scrim"></div><div class="gd"></div><div class="bar"><button class="ib">'+ic('back')+'</button></div>'+
    '<div class="form"><h1 class="ptitle">'+t.addSomeone+'</h1><p class="lede">'+t.addLede+'</p><div class="rows">'+frow(t.nameK,'Clara')+frow(t.bornK,t.bornV,{icon:'cal'})+'</div><p class="under">'+t.bornNote+'</p>'+
    '<button class="btn primary" data-go="'+next+'">'+t.add+'</button></div></div>';
}
function passList(o){
  var t=L();
  function grp(n,m,rows,more,sendGo,cls){return '<div class="grp'+(cls?' '+cls:'')+'"><div class="gh"><div class="x"><p class="n">'+n+'</p><p class="m">'+m+'</p></div>'+(sendGo!==null?'<button class="send" data-go="'+sendGo+'">'+ic('blessing')+t.sendAll+'</button>':'')+'</div>'+
    rows.map(function(r){return '<div class="r"><div class="x"><p class="t">'+r[0]+'</p><p class="m">'+r[1]+'</p></div>'+ic('fwd')+'</div>'}).join('')+(more?'<p class="more">'+more+'</p>':'')+'</div>'}
  return '<div class="pg plain"><div class="scrim"></div><div class="gd"></div><div class="bar"><button class="ib">'+ic('back')+'</button></div>'+
    '<div class="list"><h1 class="ptitle">'+t.passList+'</h1><p class="lede">'+t.passLede+'</p>'+
    (o.sent?grp('Emma',t.gEmmaSent,[],null,null,'sent'):grp('Emma',t.gEmma,t.rowsE,t.fiveMore,'b3-hand'))+
    grp('James',t.gJames,t.rowsJ,t.threeMore,'')+
    (o.clara?grp('Clara',t.gClara,t.rowsC,null,''):'')+'</div></div>';
}

/* ---------- the lights of each sky ---------- */
function meLights(){var t=L().me;return [{x:12,lab:t.l1,lp:'a'},{x:95,lab:t.l2,lp:'b'},{x:195,f:1}]}
function emmaLights(){var t=L().emma;return [{x:34,lab:t.l1,lp:'a'},{x:195,f:1}]}
function wideBefore(){return [{x:60,lab:L().me.l0,lp:'b'},{x:132},{x:193},{x:251},{x:317,f:1}]}
function wideAfter(){var b=wideBefore(),a=[204,236,263,288,317];return b.map(function(l,i){return {x:a[i],x0:l.x,f:l.f,lab:l.lab,lp:l.lp}})}

/* ---------- the steps ---------- */
var S={};
function def(id,name,fn){S[id]={name:name,fn:fn}}
/* Part A */
def('a-home','Home, as today',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(meLights())]},html:home({title:t.forMe,count:t.count5,info:t.me,ruler:R_ME,newgo:'a-record'})}});
def('a-home2','S2: home with Record and Enter',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(meLights())]},html:home({title:t.forMe,count:t.count5,info:t.me,ruler:R_ME,split:'a-entry',recgo:''})}});
def('a-record','S1: the recording screen',function(){return {scene:'rec',html:recScreen({enter:'a-entry'})}});
def('a-entry','The entry page, empty',function(){return {scene:'read',html:entry({paste:'a-pasted',dateGo:'a-date-day',doneDim:1})}});
def('a-pasted','Pasted in one go',function(){var t=L();return {scene:'read',html:entry({words:t.PAST,scrollTo:big?-470:-300,sbTop:250,sbH:200,banner:1,dateGo:'a-date-day',doneDim:1})}});
def('a-date-day','When: the full date',function(){var t=L();return {scene:'read',html:entry({words:t.PAST,dateGo:'a-date-day'})+dateSheet(0)}});
def('a-date-month','When: month and year',function(){var t=L();return {scene:'read',html:entry({words:t.PAST})+dateSheet(1)}});
def('a-date-year','When: year only',function(){var t=L();return {scene:'read',html:entry({words:t.PAST})+dateSheet(2)}});
def('a-filled','Filled in, its light appears',function(){var t=L();return {scene:'read',sk:{head:1},html:entry({title:t.pastTitle,when:t.pastWhen,from:t.pastFrom,forv:t.pastFor,whose:'me',tag:t.tagFamily,words:t.PAST,done:'a-saved',dateGo:'a-date-month'})}});
def('a-saved','Saved: the light arrives',function(){var t=L();return {scene:'home',sk:{rings:[homeRing([{x:195,f:1,arrive:1}],{from:195})]},html:home({title:t.forMe,count:t.count6,info:{meta:t.pastWhen,title:t.pastTitle,from:t.pastFromLine},ruler:cp(R_ME6,{sel:0}),newgo:'a-record'})}});
def('a-before','Earliest moves: before',function(){var t=L();return {scene:'wide',sk:{rings:[homeRing(wideBefore(),{from:60,y:330})]},html:home({title:t.forMe,count:t.count5,info:t.me,ruler:R_ME})}});
def('a-after','Earliest moves: after',function(){var t=L();return {scene:'wide',sk:{rings:[homeRing(wideAfter(),{y:330})]},html:home({title:t.forMe,count:t.count6,info:t.me,ruler:cp(R_ME6,{sel:5})})}});
def('a-reading','Its reading page',function(){var t=L();return {scene:'read',sk:{head:1},html:readingTop({meta:t.pastWhen,title:t.pastTitle,by:t.pastByLine,words:t.PAST})}});
def('a-reading-end','The end of its reading page',function(){return {scene:'off',html:readingEnd()}});
def('a-photo','Later idea: read a printed page',function(){var t=L();return {scene:'cam',html:'<div class="camv"><div class="vf"></div><p class="later"><span>'+t.later+'</span></p><div class="paper">'+'<i style="width:60%"></i><i class="p"></i><i></i><i style="width:85%"></i><i></i><i style="width:40%"></i><i class="p"></i><i></i><i style="width:90%"></i><i></i><i style="width:70%"></i><i class="p"></i><i style="width:55%"></i>'+'</div><div class="frame"></div><div class="bot"><p class="lede">'+t.camLede+'</p><button class="btn primary">'+ic('camera')+'<span>'+t.camBtn+'</span></button></div></div>'}});

/* B1: a ring for each person */
def('b1-home','Home: the title is a switch',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(meLights())]},html:home({title:t.forMe,chev:1,sw:'b1-switch',count:t.count5,info:t.me,ruler:R_ME})}});
def('b1-switch','The switch between rings',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(meLights())]},html:home({title:t.forMe,chev:1,count:t.count5,info:t.me,ruler:R_ME})+switchSheet(0)}});
def('b1-emma','Emma’s sky',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(emmaLights())]},html:home({title:t.forX('Emma'),chev:1,sw:'b1-switch',more:'b1-menu',count:t.emmaCount,info:t.emma,ruler:R_EMMA,newgo:'b1-record'})}});
def('b1-add','Adding a child',function(){return {scene:'page',html:addPage('b1-clara')}});
def('b1-clara','A new ring, empty',function(){var t=L();return {scene:'home',html:home({title:t.forX('Clara'),chev:1,count:t.noYet,empty:t.claraEmpty})}});
def('b1-record','Recording for Emma',function(){var t=L();return {scene:'rec',html:recScreen({forwho:t.forX('Emma'),begin:'b1-review',enter:'b1-enter'})}});
def('b1-review','Review: whose blessing',function(){var t=L();return {scene:'read',sk:{head:1},html:review({from:t.dad,forv:'Emma',whosePills:'Emma'})}});
def('b1-enter','Entering a past one for Emma',function(){var t=L();return {scene:'read',sk:{head:1},html:entry({title:t.nameBlessing,when:lang==='es'?'agosto de 2008':'August 2008',from:t.dad,forv:'Emma',whosePills:'Emma',words:t.BABY})}});
def('b1-menu','Emma’s sky, the ··· menu',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(emmaLights())]},html:home({title:t.forX('Emma'),chev:1,count:t.emmaCount,info:t.emma,ruler:R_EMMA,extra:'<div class="menu"><button class="hot" data-go="b1-hand">'+ic('hand')+t.menuHand+'</button><button>'+ic('pencil')+t.menuEdit+'</button></div>'})}});
def('b1-hand','Handing over: the parent sends',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(emmaLights())]},html:home({title:t.forX('Emma'),chev:1,count:t.emmaCount,info:t.emma,ruler:R_EMMA})+handSheet({title:t.cardT,btn:t.sendRing,next:'b1-sent'})}});
def('b1-sent','Sent: keep a copy or delete',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(emmaLights())]},html:home({title:t.forX('Emma'),chev:1,count:t.emmaCount,info:t.emma,ruler:R_EMMA})+sentSheet(t.sentQ,t.sentQ2,'c-open')}});
def('c-open','Emma’s phone: the app opens',function(){var t=L();return {scene:'open',sk:{rings:[homeRing([{x:40},{x:110},{x:170},{x:226},{x:282},{x:330},{x:368,f:1}],{y:300,a:.3})]},html:'<div class="opening"><h1 class="title">'+t.openT+'</h1><p class="lede">'+t.openL+'</p><button class="btn primary" data-go="c-read">'+t.cont+'</button></div>'}});
def('c-read','Emma’s phone: reading first',function(){var t=L();return {scene:'read',sk:{head:1},html:readingTop({meta:t.nameDate,title:t.nameBlessing,by:lang==='es'?'Una bendición de papá':'A blessing from Dad',words:t.BABY,noTools:1,extra:'<div class="readbar"><div class="nav3"><span class="ib">'+ic('back')+'</span><span>'+t.oneOf+'</span><span class="ib">'+ic('fwd')+'</span></div><div class="pairbtn"><button class="btn tonal">'+t.notNow+'</button><button class="btn primary" data-go="c-kept">'+t.keepThem+'</button></div></div>'})}});
def('c-kept','Emma’s phone: her sky',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(emmaLights())]},html:home({title:t.forMe,count:t.emmaCount,count2:t.keptForYou,info:t.emma,ruler:R_EMMA})}});
def('b1-after','Parent, afterwards',function(){var t=L();return {scene:'home',sk:{rings:[homeRing([{x:56,lab:lang==='es'?'16 ago 2026':'Aug 16, 2026',lp:'b'},{x:195,f:1}])]},html:home({title:t.forX('Emma'),chev:1,count:t.emmaCount.replace(/Seven|Siete/,lang==='es'?'Ocho':'Eight'),handed:t.handedOn,newpill:t.oneNew,info:t.xmas,ruler:cp(R_EMMA,{y1:2027.6,dots:R_EMMA.dots.concat([2026.98]),sel:7})})}});
def('c-second','Two parents: the second hand-over',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(emmaLights())]},html:home({title:t.forMe,count:t.emmaCount,count2:t.keptForYou,info:t.emma,ruler:R_EMMA})+
  '<div class="keepq">'+sheet('<h2>'+t.moreT+'</h2><p class="from">'+t.moreFrom+'</p><p class="meta" style="font-size:calc(15px*var(--t))">'+t.moreMeta+'</p><div class="rule"></div><p class="q" style="margin-top:16px">'+t.moreQ+'</p><div class="pairbtn"><button class="btn tonal">'+t.notNow+'</button><button class="btn primary">'+t.keepThem+'</button></div>',t.moreT)+'</div>'}});

/* B2: one sky, several rings */
function b2rings(front,o){
  o=o||{};var t=L(),c=!!o.clara;
  function dim(ls){return ls.map(function(l){return {x:l.x}})}
  var Y=front==='emma'?{me:205,emma:335,james:450}:c?{me:270,emma:372,james:452,clara:524}:{me:290,emma:400,james:495};
  if(big){for(var kk in Y)Y[kk]+=28}
  var me=homeRing(front==='me'?meLights():dim(meLights()),{y:Y.me,a:front==='me'?.24:.12,la:front==='me'?1:.35,name:front==='me'?null:t.forMe,nameA:.6});
  var em=homeRing(front==='emma'?emmaLights():[{x:60},{x:150},{x:250}],{y:Y.emma,a:front==='emma'?.24:.13,la:front==='emma'?1:.42,name:front==='emma'?null:(o.emmaHanded?'Emma · '+t.handed:'Emma'),nameA:o.emmaHanded?.45:.75});
  if(o.emmaHanded){em.a=.07;em.la=.2}
  var ja=homeRing([{x:110},{x:285}],{y:Y.james,a:.1,la:.32,name:'James',nameA:.6});
  var r=[me,em,ja];
  if(c)r.push(homeRing([],{y:Y.clara,a:.09,name:'Clara',nameA:.6}));
  return {rings:r};
}
def('b2-home','Home: one sky, three rings',function(){var t=L();return {scene:'home',sk:b2rings('me'),html:home({title:t.forMe,count:t.count5,info:cp(t.me,{}),ruler:R_ME,newgo:''})}});
def('b2-emma','Emma’s ring brought forward',function(){var t=L();return {scene:'home',sk:b2rings('emma'),html:home({title:t.forX('Emma'),count:t.emmaCount,info:t.emma,ruler:R_EMMA})}});
def('b2-add','A child added: a new ring',function(){var t=L();return {scene:'home',sk:b2rings('me',{clara:1}),html:home({title:t.forMe,count:t.count5,info:t.me,ruler:R_ME})}});
def('b2-review','Review: whose blessing',function(){var t=L();return {scene:'read',sk:{head:1},html:review({from:t.dad,forv:'Emma',whosePills:'Emma'})}});
def('b2-hand','Handing over Emma’s ring',function(){var t=L();return {scene:'home',sk:b2rings('emma'),html:home({title:t.forX('Emma'),count:t.emmaCount,info:t.emma,ruler:R_EMMA})+handSheet({title:t.cardT,btn:t.sendRing,next:'b2-after'})}});
def('b2-after','Afterwards: a ring handed over',function(){var t=L();return {scene:'home',sk:b2rings('me',{emmaHanded:1}),html:home({title:t.forMe,count:t.count5,info:t.me,ruler:R_ME})}});

/* B3: no rings for children; a kept list */
def('b3-home','Home: unchanged',function(){var t=L();return {scene:'home',sk:{rings:[homeRing(meLights())]},html:home({title:t.forMe,count:t.count5,info:t.me,ruler:R_ME})}});
def('b3-list','To pass along, by child',function(){return {scene:'page',html:passList({clara:1})}});
def('b3-review','Review: passing it along',function(){var t=L();return {scene:'read',sk:{head:1},html:review({from:t.dad,forv:'Emma',whose:'pass'})}});
def('b3-hand','Sending all of Emma’s',function(){var t=L();return {scene:'page',html:passList({clara:1})+handSheet({title:t.cardT3,btn:t.sendAll7,next:'b3-sent'})}});
def('b3-sent','Sent: keep or delete',function(){var t=L();return {scene:'page',html:passList({clara:1})+sentSheet(t.sentQ3,t.sentQ23,'b3-after')}});
def('b3-after','Afterwards',function(){return {scene:'page',html:passList({sent:1,clara:1})}});

var PATHS={
  A:{s1:['a-home','a-record','a-entry','a-pasted','a-date-day','a-date-month','a-date-year','a-filled','a-saved','a-before','a-after','a-reading','a-reading-end','a-photo'],
     s2:['a-home2','a-entry','a-pasted','a-date-day','a-date-month','a-date-year','a-filled','a-saved','a-before','a-after','a-reading','a-reading-end','a-photo']},
  B1:['b1-home','b1-switch','b1-emma','b1-add','b1-clara','b1-record','b1-review','b1-enter','b1-menu','b1-hand','b1-sent','c-open','c-read','c-kept','b1-after','c-second'],
  B2:['b2-home','b2-emma','b2-add','b2-review','b2-hand','b2-after'],
  B3:['b3-home','b3-list','b3-review','b3-hand','b3-sent','b3-after']
};
function path(){return part==='A'?PATHS.A[opt]:PATHS[part]}
function partOf(s){if(/^a-/.test(s))return 'A';if(/^(b1-|c-)/.test(s))return 'B1';if(/^b2-/.test(s))return 'B2';return 'B3'}
var step=path()[0];

/* ---------- notes beside the phone ---------- */
var NOTE={
 'a-home':'<h2>Where it starts: S1 (recommended)</h2><p>The home is unchanged. “New blessing” still opens the recording screen in one tap, for someone standing ready with hands about to be laid on a head.</p><p>Tap New blessing.</p>',
 'a-home2':'<h2>Where it starts: S2</h2><p>The one pill becomes two: Record (the gold dot, as today) and Enter. Recording is still one tap, and entering is visible from the first look.</p><p>It costs the home its single, quiet action, and two choices sit side by side every time the app opens. Drawn to compare; S1 is recommended.</p>',
 'a-record':'<h2>S1: inside New blessing</h2><p>The recording screen gains one quiet line at its foot, far from Begin: “Enter a past blessing”. Someone about to record never has to look at it.</p><p>It also helps anyone who refused the microphone: they can still put their blessings in.</p><p>The empty sky’s line stays as it is.</p>',
 'a-entry':'<h2>The entry page</h2><p>The review page the app already has: title, From, For, “For me” or “Passing it along”, tags, the words. Two differences: a first row, <b>Given</b>, and the words start empty, with Paste.</p><p>There is no listening bar, because there is no recording. The light in the header waits until the date is known.</p>',
 'a-pasted':'<h2>Pasted in one go</h2><p>A long blessing from Notes or an email keeps its paragraphs. The banner at the top is iOS’s own, drawn from memory.</p><p>Nothing is polished or changed: what was pasted is what is kept, and it can be edited like any review.</p>',
 'a-date-day':'<h2>When it was given</h2><p>A sheet with three honest choices: the full date, the month and year, or only the year. The wheels change to match.</p><p>A recording knows its minute; a past blessing usually does not, so time of day is never asked.</p>',
 'a-date-month':'<h2>Month and year</h2><p>The light sits at the middle of the month. The page and the ring say “August 1998”, never a day that was not known.</p>',
 'a-date-year':'<h2>Only the year</h2><p>The light sits at the middle of the year (July 2), so it never claims to be first or last in its year. Everywhere it is shown, it reads “1998”.</p><p>If a full date from the same year is added, the two are ordered by that middle day.</p>',
 'a-filled':'<h2>Filled in</h2><p>With a date, the light appears in the header, as a recorded blessing’s does.</p><p><b>Where it was given:</b> nothing is asked. A past blessing takes the rough place this phone already keeps, the same one a recording would use. The place only matters for the earliest blessing, which sets the ring’s height, so the ring stays at the same height and only its start moves.</p>',
 'a-saved':'<h2>Saved</h2><p>The sky turns to the new light, which brightens in place. The count says “Six blessings since August 1998”, and the ruler of dates now reaches back to 1998.</p><p>The other five are far along the ring to the right. With Reduce Motion the light fades in and the sky does not turn.</p>',
 'a-before':'<h2>The ring’s start: before</h2><p>Pinched out. The ring begins at the first blessing, June 2024, and the five lights are spread at 24° a year.</p>',
 'a-after':'<h2>The ring’s start: after</h2><p>Now the ring begins in August 1998, off to the left. The span is 28 years, so the whole of it is fitted into the ring and the same five lights slide closer together (as the placement rule already allows).</p><p>With Reduce Motion they cross-fade to their new places instead of sliding.</p>',
 'a-reading':'<h2>Its reading page</h2><p>The date reads “August 1998”, with no weekday, because the day is not known.</p>',
 'a-reading-end':'<h2>Honesty about the words</h2><p>Where a recorded blessing says “The words as they were spoken.”, an entered one says, with a page icon: <b>“Entered from a written copy, not recorded.”</b></p><p>The rest of the page is as built.</p>',
 'a-photo':'<h2>Later, not now</h2><p>One sketch: photograph a printed page and the phone reads the words, on the device, into the same entry page. The photo is not kept. Not part of this design.</p>',
 'b1-home':'<h2>B1: a ring for each person</h2><p>The title gains a small chevron. Tap it to switch rings.</p>',
 'b1-switch':'<h2>The switch</h2><p>One row per ring, each with its count, and “Add someone”. No pictures and no coloured circles, only the same small ring mark.</p>',
 'b1-emma':'<h2>Emma’s sky</h2><p>Her own ring, her own count and her own ruler, from August 2008. New blessing, here, is for Emma.</p><p>Tap ··· to hand it over.</p>',
 'b1-add':'<h2>Adding a child</h2><p>A name, and a birth date if the ring should begin at birth. Nothing else.</p>',
 'b1-clara':'<h2>A new ring</h2><p>Empty, with the empty sky’s line in her name.</p>',
 'b1-record':'<h2>Recording for a child</h2><p>The recording screen says whose it is, and that can be changed before Begin. It follows the sky that was open.</p><p>“Enter a past blessing” is here too, as in Part A.</p>',
 'b1-review':'<h2>Review: whose blessing</h2><p>“For me / Passing it along” becomes a row of names: me, each ring, and “Passing it along” for anyone else.</p>',
 'b1-enter':'<h2>Entering a past one for Emma</h2><p>Part A’s entry page, with Emma chosen. A baby blessing from 2008, the month known.</p>',
 'b1-menu':'<h2>Where the hand-over lives</h2><p>In the ··· menu of Emma’s sky. It is rare and deliberate, so it is not on the sky itself.</p>',
 'b1-hand':'<h2>The parent sends the ring</h2><p>The S3 card the owner chose, holding the ring instead of one blessing. “Kept by” is what Emma will read; it is filled from the most common From name and can be changed.</p><p>It sends one link, as every blessing does now.</p>',
 'b1-sent':'<h2>Keep a copy or delete</h2><p>The owner’s ruling for single blessings, for the whole ring. Keep is the default here, because a family will want to send later ones too.</p>',
 'c-open':'<h2>On Emma’s phone</h2><p>The link opens the app. On a first install, this comes before the welcome, as a shared blessing already does: read first, keep after.</p>',
 'c-read':'<h2>Reading first</h2><p>Her blessings, oldest first, one at a time. Keep them takes all seven. Face ID is asked only then, as for a single shared blessing.</p>',
 'c-kept':'<h2>Her sky</h2><p>“For me”, with seven lights from before she could remember, and one line saying who kept them. Each reading page also says “Kept by Dad” under its giver.</p><p>The ring’s height is her phone’s place; its start is her naming.</p>',
 'b1-after':'<h2>The parent, afterwards</h2><p>Kept: the ring stays, marked “Handed to Emma on November 16”. A blessing added later shows “One new · Send it”, and the pill sends only the new ones. It can be done again whenever there are more.</p><p>Deleted: the ring and its blessings leave this phone.</p>',
 'c-second':'<h2>Two parents</h2><p>Mom kept four on her phone. When she hands them over, Emma’s phone asks once, and they join the same ring by date. A blessing both phones already share (the same one sent between them) is kept once. The line becomes “Kept for you by Dad and Mom”.</p>',
 'b2-home':'<h2>B2: one sky, several rings</h2><p>The parent’s ring, and each child’s, fainter, lower in the sky, with the name at its left end. One sky to look at, and every family member in it.</p>',
 'b2-emma':'<h2>A ring brought forward</h2><p>Tap Emma’s ring: it brightens and rises, the title, count and ruler become hers.</p>',
 'b2-add':'<h2>Adding a child</h2><p>The same page as B1. A new faint ring appears, here Clara’s, with nothing on it yet. With four rings the sky is already crowded.</p>',
 'b2-review':'<h2>Recording</h2><p>The same as B1: a row of names on the review page.</p>',
 'b2-hand':'<h2>Handing over</h2><p>The same sheet as B1, from Emma’s ring brought forward.</p>',
 'b2-after':'<h2>Afterwards</h2><p>Kept: Emma’s ring stays, very faint, labelled “handed over”.</p>',
 'b3-home':'<h2>B3: no rings for children</h2><p>The home is as today. A child’s blessings have no light anywhere on this phone.</p>',
 'b3-list':'<h2>To pass along, grouped</h2><p>The list the app is getting now, grouped by the For name, with “Send all”. No adding step: a group forms when a blessing is marked for a name. A birth date has nowhere to go.</p>',
 'b3-review':'<h2>Recording</h2><p>As built today: “Passing it along”, and For Emma.</p>',
 'b3-hand':'<h2>Sending all of them</h2><p>The same card and link, holding the group.</p>',
 'b3-sent':'<h2>Keep or delete</h2><p>The ruled choice, for the group.</p>',
 'b3-after':'<h2>Afterwards</h2><p>The group shows as sent. Emma’s side is the same as B1: her sky begins with these lights.</p>'
};
function notes(){
  var p=path(),i=p.indexOf(step);
  $('notes').innerHTML=(NOTE[step]||'')+'<div class="nav2" style="margin-bottom:22px"><button data-nav="-1">‹ Back</button><button data-nav="1">Next ›</button></div><h2>Full notes</h2><p>notes.md beside this file: every word in English and Spanish, the reasons, the comparison of B1, B2 and B3, and the questions.</p>';
}

/* ---------- show ---------- */
var SCENEV=null;
function show(s,opts){
  opts=opts||{};step=s;part=partOf(s);
  var r=S[s].fn();
  $('screen').innerHTML=r.html;
  root.lang=lang;
  SK=r.sk||null;skT0=performance.now();
  setScene(r.scene||'off',opts.instant||SHOT);
  var el=$('screen');
  if(el.querySelector('.sheet')){if(SHOT||opts.instant)el.classList.add('up');else{el.classList.remove('up');requestAnimationFrame(function(){requestAnimationFrame(function(){el.classList.add('up')})})}}
  else el.classList.remove('up');
  if(!P.bare&&!SHOT){try{history.replaceState(null,'','#part='+part+'&step='+s+(part==='A'?'&opt='+opt:'')+(lang==='es'?'&lang=es':'')+(big?'&big':''))}catch(e){}}
  buildNav();notes();
}
document.addEventListener('click',function(e){
  var t=e.target.closest&&e.target.closest('[data-go],[data-part],[data-opt],[data-lang],[data-step],[data-nav]');if(!t)return;
  var a;
  if((a=t.getAttribute('data-go'))&&S[a]){if(partOf(a)==='A'&&a==='a-home2')opt='s2';show(a)}
  if((a=t.getAttribute('data-step')))show(a);
  if((a=t.getAttribute('data-part'))){part=a;show(path()[0])}
  if((a=t.getAttribute('data-opt'))){opt=a;part='A';var p=path();show(p.indexOf(step)>=0?step:p[0])}
  if((a=t.getAttribute('data-lang'))){lang=a;show(step,{instant:true})}
  if((a=t.getAttribute('data-nav'))){var p2=path(),i=p2.indexOf(step)+(+a);if(i>=0&&i<p2.length)show(p2[i])}
});
document.addEventListener('keydown',function(e){if(e.key==='ArrowRight'||e.key==='ArrowLeft'){var p=path(),i=p.indexOf(step)+(e.key==='ArrowRight'?1:-1);if(i>=0&&i<p.length)show(p[i])}});
$('t-big').addEventListener('click',function(){big=!big;applyToggles();show(step,{instant:true})});
$('t-reduce').addEventListener('click',function(){reduce=!reduce;applyToggles();show(step)});
function applyToggles(){root.classList.toggle('big',big);root.classList.toggle('reduce',reduce);$('t-big').setAttribute('aria-pressed',big);$('t-reduce').setAttribute('aria-pressed',reduce)}
function buildNav(){
  $('nav').innerHTML=path().map(function(s,i){return '<li><button data-step="'+s+'" aria-current="'+(s===step)+'"><span class="n">'+(i+1)+'</span>'+S[s].name+'</button></li>'}).join('');
  [].forEach.call(document.querySelectorAll('[data-part]'),function(b){b.setAttribute('aria-pressed',b.getAttribute('data-part')===part)});
  [].forEach.call(document.querySelectorAll('[data-opt]'),function(b){b.setAttribute('aria-pressed',b.getAttribute('data-opt')===opt)});
  $('seg-opt').style.opacity=part==='A'?1:.35;$('opt-lbl').style.opacity=part==='A'?1:.35;
  [].forEach.call(document.querySelectorAll('[data-lang]'),function(b){b.setAttribute('aria-pressed',b.getAttribute('data-lang')===lang)});
}

/* ---------- the overlay: drawn every frame over the sky ---------- */
var ov=$('ov'),oc=ov.getContext('2d');
function lightAt(x,y,f,a,s){
  if(a<=.003)return;
  var rg=(f?54:17)*s,g=oc.createRadialGradient(x,y,0,x,y,rg);
  g.addColorStop(0,'rgba(255,248,232,'+a+')');
  g.addColorStop(f?.07:.14,'rgba(255,232,185,'+(.95*a)+')');
  g.addColorStop(f?.2:.35,'rgba(244,196,120,'+((f?.38:.3)*a)+')');
  g.addColorStop(.55,'rgba(240,170,90,'+(.07*a)+')');
  g.addColorStop(1,'rgba(240,160,80,0)');
  oc.fillStyle=g;oc.beginPath();oc.arc(x,y,rg,0,TAU);oc.fill();
  if(f){
    [[0,-1,110],[0,1,110],[-1,0,72],[1,0,72]].forEach(function(d){var L2=d[2]*s,gg=oc.createLinearGradient(x,y,x+d[0]*L2,y+d[1]*L2);
      gg.addColorStop(0,'rgba(255,225,170,'+(.6*a)+')');gg.addColorStop(.35,'rgba(240,190,120,'+(.16*a)+')');gg.addColorStop(1,'rgba(240,190,120,0)');
      oc.strokeStyle=gg;oc.lineWidth=1.1;oc.beginPath();oc.moveTo(x,y);oc.lineTo(x+d[0]*L2,y+d[1]*L2);oc.stroke()});
  }
}
function drawOv(){
  var w=Math.round(390*PX),h=Math.round(844*PX);if(ov.width!==w||ov.height!==h){ov.width=w;ov.height=h}
  oc.setTransform(1,0,0,1,0,0);oc.clearRect(0,0,w,h);oc.setTransform(PX,0,0,PX,0,0);
  if(!SK||!booted)return;
  var t=SHOT?99:(performance.now()-skT0)/1000,k=smooth(.15,1.6,t);
  if(SK.head){oc.globalCompositeOperation='lighter';lightAt(195,127,1,1,1);oc.globalCompositeOperation='source-over'}
  (SK.rings||[]).forEach(function(r){
    /* the line */
    var x0=Math.max(-20,r.from),x1=r.to,x,first=true;
    oc.globalCompositeOperation='lighter';
    var lg=oc.createLinearGradient(x0,0,x0+40,0);lg.addColorStop(0,'rgba(240,201,135,'+(r.from>-20?0:r.a)+')');lg.addColorStop(1,'rgba(240,201,135,'+r.a+')');
    oc.strokeStyle=r.from>-20?lg:'rgba(240,201,135,'+r.a+')';oc.lineWidth=.9;oc.beginPath();
    for(x=x0;x<=x1;x+=4){var y=ringY(r,x);if(first){oc.moveTo(x,y);first=false}else oc.lineTo(x,y)}oc.stroke();
    /* the lights */
    r.lights.forEach(function(l){
      var lx=l.x,a=r.la,s=1;
      if(l.x0!==undefined){if(reduce){a*=k<.5?1-k*2:(k-.5)*2;lx=k<.5?l.x0:l.x}else lx=l.x0+(l.x-l.x0)*k}
      if(l.arrive){a*=reduce?k:k;s=reduce?1:.35+.65*k}
      lightAt(lx,ringY(r,lx),l.f,a,s);
      if(l.lab){oc.globalCompositeOperation='source-over';oc.font='400 '+(12*(big?1.15:1))+'px -apple-system,system-ui,sans-serif';oc.fillStyle='rgba(181,171,152,'+(.9*a)+')';
        oc.textAlign='center';var ty=ringY(r,lx)+(l.lp==='a'?-17:24);var hw=oc.measureText(l.lab).width/2+14;oc.fillText(l.lab,Math.max(hw,Math.min(390-hw,lx)),ty);oc.globalCompositeOperation='lighter'}
    });
    if(r.name){oc.globalCompositeOperation='source-over';oc.font='400 '+(13*(big?1.15:1))+'px -apple-system,system-ui,sans-serif';oc.fillStyle='rgba(181,171,152,'+(r.nameA||.6)+')';oc.textAlign='left';oc.fillText(r.name,22,ringY(r,22)-9)}
    oc.globalCompositeOperation='source-over';
  });
}

/*@@SKY@@*/

/* ---------- boot ---------- */
var booted=false;
function ready(){if(booted)return;var f=document.fonts&&document.fonts.ready?document.fonts.ready:Promise.resolve();
  f.then(function(){booted=true;draw();drawOv();setTimeout(function(){root.setAttribute('data-ready','1')},SHOT?80:0)})}
window.addEventListener('resize',fit);
applyToggles();
if(SHOT||P.bare)root.classList.add('notrans');
var first=typeof P.step==='string'&&S[P.step]?P.step:path()[0];
target=NOW;
show(first,{instant:true});
fit();
try{if(gl)init()}catch(err){console.error(err);gl=null;$('fallback').style.display='grid'}
if(!gl)ready();
var last=0;
function loop(ts){var dt=last?Math.min(.05,(ts-last)/1000):0;last=ts;step_(dt);requestAnimationFrame(loop)}
requestAnimationFrame(loop);
})();
