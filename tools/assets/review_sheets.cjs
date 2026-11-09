const fs=require('fs'),path=require('path'),sharp=require('sharp');
const root=path.resolve(process.argv[2]);
async function sheet(group,items){
 const columns=8,tile=132,height=Math.ceil(items.length/columns)*156;
 const layers=[];
 for(let i=0;i<items.length;i++){
  const item=items[i],x=i%columns*tile,y=Math.floor(i/columns)*156;
  const input=await sharp(path.join(root,item.path)).resize(124,128,{fit:'contain',background:'#f3eee500'}).toBuffer();
  layers.push({input,left:x+4,top:y});
  const label=Buffer.from(`<svg width="132" height="24"><text x="66" y="17" text-anchor="middle" font-size="13" font-family="sans-serif" fill="#283c49">${item.id.split(':').pop()}</text></svg>`);
  layers.push({input:label,left:x,top:y+130});
 }
 const target=path.join(root,'.cache/asset-previews',group+'.png');
 await sharp({create:{width:columns*tile,height,channels:4,background:'#f3eee5'}}).composite(layers).png().toFile(target);
 console.log(target);
}
async function main(){
 const index=JSON.parse(fs.readFileSync(path.join(root,'assets/ui/icon-index.json'),'utf8')).icons;
 await sheet('review-bodies',index.filter(x=>x.id.startsWith('species:')));
 await sheet('review-equipment',index.filter(x=>x.id.startsWith('equipment:')));
 const diseases=index.filter(x=>x.id.startsWith('diseases:'));
 await sheet('review-cases-1',diseases.slice(0,80));await sheet('review-cases-2',diseases.slice(80));
}
main().catch(e=>{console.error(e);process.exit(1)});
