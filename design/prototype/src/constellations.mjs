/* Constellation stick figures, from d3-celestial (Olaf Frohn, BSD 3-Clause):
   https://github.com/ofrohn/d3-celestial/blob/master/data/constellations.lines.json
   node constellations.mjs <path to constellations.lines.json>   writes constellations.json
   Output: [[id,[[ra,dec,ra,dec,...],...]],...] in degrees, J2000, matching the star catalogue. */
import fs from 'node:fs';
const j=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const r=x=>Math.round(x*100)/100;
const out=j.features.map(f=>[f.id,f.geometry.coordinates.map(l=>l.flatMap(([lon,lat])=>[r((lon+360)%360),r(lat)]))]);
fs.writeFileSync(new URL('./constellations.json',import.meta.url),JSON.stringify(out));
console.log('figures',out.length,'bytes',JSON.stringify(out).length);
