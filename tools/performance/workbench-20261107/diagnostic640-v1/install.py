from pathlib import Path
import sys,json,hashlib,shutil
D=Path(__file__).resolve().parent;P=Path(sys.argv[1]).resolve()
assert P.is_relative_to(D) and P!=D, 'Require independent prepared project inside diagnostic640-v1; never locked A'
source=P/'tools/performance/fixture.gd';check=json.loads((D/'static-check.json').read_text())
assert hashlib.sha256(source.read_bytes()).hexdigest()==check['original_sha256']
assert not (P/'diagnostic640-driver.gd').exists()
shutil.copyfile(D/'fixture.diagnostic.gd',source);shutil.copyfile(D/'driver.gd',P/'diagnostic640-driver.gd')
print('Installed diagnostic-only fixture and driver:',P)
