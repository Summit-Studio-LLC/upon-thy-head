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
  read:{fov:56,cy:.70,exp:.85,st:.9,orb:0,ring:0,light:1},
  page:{fov:56,cy:.66,exp:.8,st:.85,orb:0,ring:0,light:1},
  keep:{fov:90,cy:.2,exp:.55,st:.8,orb:0,ring:.2,light:1},
  dim:{fov:84,cy:.3,exp:.3,st:.5,orb:0,ring:0,light:0},
  off:{fov:84,cy:.3,exp:0,st:0,orb:0,ring:0,light:0}
};
var cam={ra:NOW.ra,dec:NOW.dec,fov:80,cy:.15,exp:0,st:0,orb:0,ring:0,light:0},goal={},scene='open',clock=0,opening=0,target=NOW,ringK=1;
function setScene(n,instant){
  scene=n;var v=VIEW[n],k;for(k in v)goal[k]=v[k];
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

