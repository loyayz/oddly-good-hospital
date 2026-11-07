from pathlib import Path
import sys,json,hashlib,shutil
D=Path(__file__).resolve().parent;P=Path(sys.argv[1]).resolve()
assert P.is_relative_to(D) and P!=D
check=json.loads((D/'static-check.json').read_text());f=P/'tools/performance/fixture.gd'
assert hashlib.sha256(f.read_bytes()).hexdigest()==check['original_sha256']
for source,target in [('fixture.candidate.gd',f),('placement_query.gd',P/'tools/performance/placement_query.gd'),('oracle.gd',P/'placement-oracle.gd')]:
 if source!='fixture.candidate.gd':assert not target.exists()
 shutil.copyfile(D/source,target)
print(P)
