const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const crypto = require('crypto');
const root = path.resolve(process.argv[2]);
(async () => {
  const indexPath = path.join(root, 'assets/ui/supplement-index.json');
  const index = JSON.parse(fs.readFileSync(indexPath, 'utf8'));
  for (const graphic of index.graphics) {
    const target = path.join(root, graphic.path);
    fs.mkdirSync(path.dirname(target), {recursive: true});
    if (graphic.group !== 'roles') {
      await sharp(path.join(root, graphic.editable)).png({palette: true, colours: 96, compressionLevel: 9}).toFile(target);
    }
    if (!fs.existsSync(target)) continue; // Native role portraits are rendered after vector art.
    const bytes = fs.readFileSync(target);
    if (bytes.length >= 50000) throw Error('PNG budget: ' + graphic.path);
    const info = await sharp(bytes).metadata();
    Object.assign(graphic, {bytes: bytes.length, width: info.width, height: info.height,
      sha256: crypto.createHash('sha256').update(bytes).digest('hex')});
  }
  fs.writeFileSync(indexPath, JSON.stringify(index, null, 2) + '\n');
  console.log(JSON.stringify({graphics: index.graphics.length,
    rendered: index.graphics.filter(g => g.bytes).length,
    maxBytes: Math.max(...index.graphics.filter(g => g.bytes).map(g => g.bytes))}));
})();
