from pathlib import Path
import hashlib,shutil,json,sys
D=Path(__file__).resolve().parent;V=D.parent/'tool-adaptation640-v1';P=Path(sys.argv[1]).resolve()
assert P.is_relative_to(D) and P!=D
check=json.loads((D/'static-check.json').read_text())
assert hashlib.sha256((P/'tools/performance/fixture.gd').read_bytes()).hexdigest()==check['candidate_sha256']
assert (P/'tools/performance/placement_query.gd').read_bytes()==(V/'placement_query.gd').read_bytes()
target=P/'supplemental-oracle-v2.gd';assert not target.exists()
shutil.copyfile(D/target.name,target)
print(target)
