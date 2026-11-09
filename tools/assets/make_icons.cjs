/* Rasterize authored vectors and actual model renders with sharp/libvips. */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sharp = require('sharp');
const root = path.resolve(process.argv[2]);
const plan = JSON.parse(fs.readFileSync(path.join(root,'assets/asset-plan.json'),'utf8'));
const ink='#283b48', teal='#568d87', gold='#d9b275', ivory='#f3eddf', coral='#cf7562';

const glyphs={
 build:'<path d="M28 55 64 24l36 31v47H28Z"/><path d="M52 102V70h24v32"/>',
 staff:'<circle cx="64" cy="39" r="17"/><path d="M28 105V87a36 36 0 0 1 72 0v18"/><path d="M53 82h22m-11-11v22"/>',
 admissions:'<rect x="26" y="27" width="76" height="79" rx="10"/><path d="M44 27v-9m40 9v-9M42 53h44m-44 18h27m-27 18h32"/>',
 research:'<path d="M45 20h38m-26 0v32L30 98q-4 10 9 10h50q13 0 9-10L71 52V20M43 80h42"/>',
 tasks:'<rect x="31" y="24" width="66" height="84" rx="9"/><rect x="47" y="17" width="34" height="16" rx="4"/><path d="m43 59 9 9 17-20m-26 41 8 8 19-22m9-14h8m-8 29h8"/>',
 residents:'<circle cx="46" cy="43" r="14"/><circle cx="84" cy="47" r="12"/><path d="M20 104V88a26 26 0 0 1 52 0v16m7-36a24 24 0 0 1 29 24v12"/>',
 save:'<path d="M25 22h64l15 15v68H25Z"/><path d="M44 22v29h37V22M43 105V73h43v32"/>',
 load:'<path d="M23 99V31h33l12 13h37v55ZM23 99l13-43h74l-14 43Z"/>',
 pause:'<rect x="33" y="27" width="21" height="76" rx="4"/><rect x="74" y="27" width="21" height="76" rx="4"/>',
 play:'<path d="M40 24v82l62-41Z"/>',
 speed:'<path d="M23 35v58l42-29Zm45 0v58l42-29Z"/>',
 settings:'<path d="M52 22h24l3 15 15 8 14-5 11 20-12 10v17l-13 19-14-6-14 8-3 14H48l-3-15-15-9-14 5-9-22 12-9V55l-12-9 11-20 14 5 15-8Z"/><circle cx="62" cy="67" r="16"/>',
 close:'<path d="m35 35 58 58m0-58L35 93"/>',
 confirm:'<path d="m27 66 24 25 51-55"/>',
 cancel:'<circle cx="64" cy="64" r="41"/><path d="m35 93 58-58"/>',
 delete:'<path d="M29 36h70M47 36V22h34v14M36 36l6 70h44l6-70M54 53v36m20-36v36"/>',
 move:'<path d="M64 17v94M17 64h94M50 31l14-14 14 14m-28 66 14 14 14-14M31 50 17 64l14 14m66-28 14 14-14 14"/>',
 rotate_left:'<path d="M34 46a39 39 0 1 1-5 48M34 22v25H9"/>',
 rotate_right:'<path d="M94 46a39 39 0 1 0 5 48M94 22v25h25"/>',
 zoom_in:'<circle cx="55" cy="54" r="31"/><path d="m78 78 31 31M40 54h30M55 39v30"/>',
 zoom_out:'<circle cx="55" cy="54" r="31"/><path d="m78 78 31 31M40 54h30"/>',
 floor_up:'<path d="m20 89 44 21 44-21M20 65l44 21 44-21M36 47l28-28 28 28M64 19v48"/>',
 floor_down:'<path d="m20 38 44-21 44 21M20 62l44-21 44 21M36 81l28 28 28-28M64 109V61"/>',
 follow:'<circle cx="64" cy="64" r="29"/><path d="M64 13v24m0 54v24M13 64h24m54 0h24"/>',
 info:'<circle cx="64" cy="64" r="42"/><path d="M64 58v29M64 39v2"/>',
 repair:'<path d="M88 20a27 27 0 0 0-31 34l-34 34a12 12 0 0 0 17 17l34-34a27 27 0 0 0 34-31L88 55 73 40Z"/>',
 upgrade:'<path d="M35 78V54H19l45-36 45 36H93v24M35 94h58M35 109h58"/>',
 supplies:'<path d="m21 41 43-21 43 21v55l-43 21-43-21ZM21 41l43 21 43-21M64 62v55M43 30l43 21"/>',
 blueprint:'<rect x="24" y="19" width="80" height="90" rx="5"/><path d="M41 87V49h22V36h23v51ZM63 49v38m-22-19h45"/>',
 remodel:'<path d="M29 19h70v30H29ZM79 49v18H57v41H41V62h38"/>',
 camera:'<path d="M19 39h24l9-15h25l9 15h23v64H19Z"/><circle cx="64" cy="70" r="21"/>',
 sound:'<path d="M22 51h21l29-25v76L43 77H22ZM88 43q23 21 0 42m11-55q34 34 0 68"/>',
 note:'<path d="M52 91V31l48-12v61M52 48l48-12"/><ellipse cx="37" cy="93" rx="16" ry="11"/><ellipse cx="85" cy="82" rx="16" ry="11"/>',
 sun:'<circle cx="64" cy="64" r="25"/><path d="M64 12v14m0 76v14M12 64h14m76 0h14M27 27l10 10m54 54 10 10M27 101l10-10m54-54 10-10"/>',
 moon:'<path d="M85 22a44 44 0 1 0 22 69A42 42 0 0 1 85 22Z"/>',
 balance:'<path d="M64 24v82M35 106h58M27 40h74M34 40 18 78h32ZM94 40 78 78h32Z"/>',
 heart:'<path d="M64 104 23 64C-1 32 36 8 64 37c28-29 65-5 41 27Z"/>',
 cloud:'<path d="M31 94a24 24 0 0 1-3-47 34 34 0 0 1 64-4 26 26 0 0 1 6 51Z"/>',
 star:'<path d="m64 17 14 30 33 5-24 24 6 34-29-16-30 16 6-34-24-24 34-5Z"/>',
 posture:'<circle cx="63" cy="29" r="13"/><path d="M64 43v37M33 57l30 11 30-11M64 80l-23 30m23-30 23 30"/>',
 story:'<path d="M64 109V30Q40 11 17 27v73q22-15 47 9Zm0 0V30q24-19 47-3v73q-22-15-47 9Z"/>',
 milestone:'<path d="M35 110V19m0 4q19-13 36 0t33 0v48q-17 13-33 0t-36 0"/>',
 blob:'<path d="M33 99C0 84 24 66 27 44S59 7 76 32s35 20 29 45-47 33-72 22Z"/>',
 bed:'<path d="M20 105V44m0 44h90V62H59v26m-39-3V69h39M110 61v44"/><circle cx="40" cy="56" r="12"/>',
 toilet:'<path d="M30 20h45v43H30ZM30 63h74v12c0 20-33 20-33 20v16H47V89C35 82 30 75 30 63Z"/>',
 gp:'<circle cx="52" cy="50" r="29"/><path d="m74 74 31 31M52 34v32M36 50h32"/>',
 research_room:'<path d="M24 103h80M37 99V66l26-18M63 48l18-25 18 15-18 25ZM53 73q38 5 32 27M28 63h24"/>',
 office:'<path d="M17 70h94M26 70v40m76-40v40M26 27h55v36H26Zm23 36v7M90 36h17v21H90"/>',
 surgery:'<path d="M19 98V67h90v31M32 67V49h61v18M29 28h70M64 18v20M42 98v13m45-13v13"/>',
 commission:'<path d="M20 33h88v64H20Zm0 0 44 37 44-37M20 97l28-27m60 27L80 70"/>'
};
function vector(key){
 let body=glyphs[key]||glyphs.star;
 return `<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 128 128"><g fill="${ivory}" stroke="${ink}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">${body}</g></svg>`;
}
const roomMap={gp:'gp',research:'research_room',rest:'bed',toilet:'toilet',t01:'posture',t02:'balance',t03:'note',t04:'sun',t05:'blob',t06:'supplies',t07:'moon',t08:'cloud',t09:'repair',t10:'heart',operating_room:'surgery',ward:'bed',doctor_office:'office'};
async function png(input,target,edge=192){
 fs.mkdirSync(path.dirname(target),{recursive:true});
 let result;
 for(const colors of [128,96,64,32]){
   result=await sharp(input).trim({threshold:8}).resize(edge,edge,{fit:'contain',background:'#00000000'}).png({palette:true,colours:colors,dither:.35,compressionLevel:9,effort:10}).toBuffer();
   if(result.length<50000)break;
 }
 if(result.length>=50000)throw Error('PNG exceeds 50,000 bytes: '+target);
 fs.writeFileSync(target,result);
 const meta=await sharp(result).metadata();
 return {bytes:result.length,width:meta.width,height:meta.height,sha256:crypto.createHash('sha256').update(result).digest('hex')};
}
async function main(){
 const records=[];
 for(const req of plan.requirements.filter(x=>x.kind==='icon')){
   let input,source;
   const id=req.content_id.toLowerCase();
   if(['species','equipment','diseases'].includes(req.group)){
     source='.cache/asset-previews/'+(req.group==='diseases'?'disease_':'')+id+'.png';
     input=path.join(root,source);
     if(!fs.existsSync(input))throw Error('Missing actual model render '+source);
   }else{
     const key=req.group==='rooms'?roomMap[id]:id;
     input=Buffer.from(vector(key));
     source=`art-source/production/ui/icons/${req.group}/${id}.svg`;
     fs.mkdirSync(path.dirname(path.join(root,source)),{recursive:true});fs.writeFileSync(path.join(root,source),input);
   }
   const target=path.join(root,req.required_paths[0]);
   const info=await png(input,target);
   records.push({id:req.id,path:req.required_paths[0],source:source.startsWith('.cache')?'actual Blender model render':source,...info});
 }
 const trails=JSON.parse(fs.readFileSync(path.join(root,'content/core/research_trails.json'),'utf8'));
 for(let n=0;n<trails.length;n++){
   const glyph=['heart','sun','moon','balance','repair','star'][n%6];
   const art=`<svg xmlns="http://www.w3.org/2000/svg" width="384" height="224" viewBox="0 0 384 224"><rect width="384" height="224" rx="24" fill="${ivory}"/><path d="M76 112h232" fill="none" stroke="${gold}" stroke-width="5" stroke-dasharray="8 8"/><circle cx="76" cy="112" r="34" fill="${teal}"/><circle cx="308" cy="112" r="34" fill="${coral}"/><rect x="133" y="44" width="118" height="136" rx="16" fill="#fffaf0" stroke="${ink}" stroke-width="3"/><g transform="translate(143 64) scale(.76)" fill="none" stroke="${ink}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">${glyphs[glyph]}</g><path d="m59 112 13 13 23-26m199 0 12 13-12 13" fill="none" stroke="${ivory}" stroke-width="5" stroke-linecap="round"/></svg>`;
   const rel='assets/ui/research/'+trails[n].id.toLowerCase()+'.png';
   const svgrel='art-source/production/ui/research/'+trails[n].id.toLowerCase()+'.svg';
   fs.mkdirSync(path.dirname(path.join(root,svgrel)),{recursive:true});fs.writeFileSync(path.join(root,svgrel),art);
   records.push({id:'research:'+trails[n].id,path:rel,source:svgrel,...await png(Buffer.from(art),path.join(root,rel),320)});
 }
 fs.writeFileSync(path.join(root,'assets/ui/icon-index.json'),JSON.stringify({schema:1,icons:records},null,2)+'\n');
 console.log(JSON.stringify({icons:records.length,max_bytes:Math.max(...records.map(x=>x.bytes)),total_bytes:records.reduce((a,x)=>a+x.bytes,0)}));
}
main().catch(e=>{console.error(e);process.exit(1)});
