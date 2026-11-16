import fs from 'node:fs';
const [,, csv, out] = process.argv;
const lines = fs.readFileSync(csv,'utf8').split('\n');
const hdr = lines[0].split(',').map(s=>s.replace(/"/g,''));
const ix = n=>hdr.indexOf(n);
const iRa=ix('ra'), iDec=ix('dec'), iMag=ix('mag'), iCi=ix('ci'), iP=ix('proper'), iCon=ix('con');
const rows=[]; const named=[];
for (let i=1;i<lines.length;i++){
  const c = lines[i].split(','); if (c.length<20) continue;
  const mag = parseFloat(c[iMag]); if (!(mag>-2) || mag>10.2) continue; // drops the Sun (-26.7)
  const ra = parseFloat(c[iRa]), dec=parseFloat(c[iDec]); if (isNaN(ra)||isNaN(dec)) continue;
  let ci = parseFloat(c[iCi]); if (isNaN(ci)) ci=0.6;
  rows.push([ra,dec,mag,ci]);
  const p=c[iP].replace(/"/g,''); if (p && mag<2.6) named.push([p, +ra.toFixed(4), +dec.toFixed(3), mag, c[iCon].replace(/"/g,'')]);
}
rows.sort((a,b)=>a[2]-b[2]);
const buf = Buffer.alloc(rows.length*6);
rows.forEach((r,i)=>{
  buf.writeUInt16LE(Math.min(65535,Math.round(r[0]/24*65536)%65536), i*6);
  buf.writeInt16LE(Math.round(r[1]/90*32767), i*6+2);
  buf.writeUInt8(Math.max(0,Math.min(255,Math.round((r[2]+2)*20))), i*6+4);
  buf.writeUInt8(Math.max(0,Math.min(255,Math.round((r[3]+0.5)*100))), i*6+5);
});
fs.writeFileSync(out, buf.toString('base64'));
fs.writeFileSync(out+'.named.json', JSON.stringify(named));
const h={}; rows.forEach(r=>{const k=Math.floor(r[2]); h[k]=(h[k]||0)+1}); console.log(rows.length, h, named.length);
