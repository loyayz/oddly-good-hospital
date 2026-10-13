"""Validate design contracts and render book chapters; never runs the game."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import math
import re
import struct
import sys
from collections import Counter, defaultdict, deque
from datetime import date
from fractions import Fraction
from pathlib import Path

sys.dont_write_bytecode = True

from validate_life import validate_life, check_life_examples, append_life_atlas
from validate_progression import validate_progression, check_progression_examples, append_progression_atlas
from validate_operations import validate_operations, check_operations_examples, append_operations_atlas
from validate_care import validate_care, check_care_examples, append_care_atlas
from validate_expertise import validate_expertise, check_expertise_examples, append_expertise_atlas
from validate_comedy import validate_comedy, check_comedy_examples, append_comedy_atlas
from validate_expansion import (validate_expansion, check_expansion_examples, append_expansion_atlas,
                                validate_remodel_content, check_remodel_examples,
                                reference_arrival_capacity, planned_arrivals)
from validate_clinical import (validate_clinical, validate_roster, validate_layouts,
                               starter_staff_costs, plan_score, append_clinical_atlas, binding_body, validate_billing)

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs'
checks: list[str] = []

def check(ok: bool, label: str) -> None:
    if not ok:
        raise ValueError(label)
    checks.append(label)

def require(ok: bool, label: str) -> None:
    if not ok:
        raise ValueError(label)

def index(rows: list[dict], key: str = 'id') -> dict:
    result = {r[key]: r for r in rows}
    require(len(rows) == len(result), 'duplicate id')
    return result

def clearance(species: dict) -> int:
    return math.ceil(max(species['body']['width_m'], species['body']['depth_m']) / 1.5)

def door_span(species: dict, door: dict) -> int:
    width_cm = round(max(species['body']['width_m'], species['body']['depth_m'])*100)+10
    return max(door['span_cells'], math.ceil(width_cm/150))

def door_fits(species: dict, door: dict, available_span: int = 96, ceiling_m: float = 7.5) -> bool:
    body = species['body']
    # Definitions have at most centimetre precision; runtime imports integer centimetres.
    height_cm = round(body['height_m'] * 100) + 10
    return (door['fit_policy'] == 'automatic'
            and door_span(species, door) <= available_span
            and max(round(door['clear_height_m'] * 100), height_cm) <= round(ceiling_m * 100))

def time_values(c: dict, b: dict):
    """Inventory numeric durations/rates from the design data, not a world clock."""
    real_seconds=set(b['hospital_clock']['realtime_seconds_paths'])
    real_days=set(b['hospital_clock']['real_day_paths'])
    def walk(value, path):
        if isinstance(value, dict):
            for key, child in value.items():
                current=path+'.'+key
                if type(child) in (int,float):
                    unit=None
                    if key=='per_second' or key.endswith('_per_second') or key=='per_extra_wait_second' or path=='balance.movement_speeds': unit='rate'
                    elif key=='per_update' and path.startswith('balance.anger.causes['): unit='sample_delta'
                    elif key=='travel_penalty_per_10_seconds': unit='rate10'
                    elif key.endswith('_ms'): unit='real_ms'
                    elif re.search(r'(^|_)seconds($|_)',key): unit='real_seconds' if current in real_seconds else 'seconds'
                    elif re.search(r'(^|_)days($|_)',key) or key=='first_payment_day': unit='real_days' if current in real_days else 'days'
                    elif re.search(r'(^|_)ticks($|_)',key): unit='ticks'
                    if unit: yield current, child, unit
                if key=='leave_day_options':
                    for i,amount in enumerate(child): yield current+'['+str(i)+']',amount,'days'
                else:
                    yield from walk(child,current)
        elif isinstance(value,list):
            for i,child in enumerate(value):
                label=child.get('id',str(i)) if isinstance(child,dict) else str(i)
                yield from walk(child,path+'['+label+']')
    yield from walk(b,'balance')
    yield from walk(c,'catalog')
    for name in ('starter-layout','clinical-layouts'):
        yield from walk(json.loads((DOCS/'data'/f'{name}.json').read_text(encoding='utf-8')),name)


def validate_time_basis(c: dict, b: dict) -> None:
    clock=b['hospital_clock']
    require(set(clock)=={'basis_id','day_minutes','source','clock_format','duration_display','clock_rounding',
                        'remaining_rounding','numeric_units','real_day_paths','realtime_seconds_paths',
                        'published_basis_mutable','snapshot_clock_copy','runtime_measurement_available'},
            'hospital time has an unknown unit owner or duplicated clock')
    require(b['day_seconds']==1800 and b['tick_seconds']==.1 and clock['day_minutes']==1440
            and b['schedule']['shift_seconds']==600 and b['schedule']['shifts_per_day']==3,
            '30-real-minute hospital day or three 8-hour shifts drift')
    require([b['wellbeing'][k] for k in ('energy_work_per_second','energy_walk_per_second','energy_rest_per_second','energy_tea_per_second')]
            == [.08,.03,1,.4], 'time calibration changes existing energy rates')
    require(clock['basis_id']=='hospital-time-v1' and clock['source']=='single_sim_tick_and_fixed_day_seconds'
            and clock['clock_format']=='hospital_day_and_24h_HH_mm'
            and clock['duration_display']=='hospital_hours_minutes_with_simulation_seconds_in_details'
            and clock['clock_rounding']=='floor_exact_ratio_after_modulo_day_ticks'
            and clock['remaining_rounding']=='ceil_display_unit_until_actual_completion'
            and clock['numeric_units']=='seconds_simulation_days_hospital_unless_explicit_real'
            and clock['published_basis_mutable'] is False and clock['snapshot_clock_copy'] is False
            and clock['runtime_measurement_available'] is False, 'time display changes deadlines or claims runtime proof')
    rows=list(time_values(c,b)); units={p:u for p,_,u in rows}
    require(len(rows)==len(units) and all(math.isfinite(v) for _,v,_ in rows), 'invalid numeric time inventory')
    require(len(clock['realtime_seconds_paths'])==len(set(clock['realtime_seconds_paths']))
            and set(clock['realtime_seconds_paths'])=={
                'balance.save.autosave_real_seconds','balance.performance_targets.capture.warmup_real_seconds',
                'balance.performance_targets.capture.sample_real_seconds','balance.performance_targets.metrics.save_max_seconds',
                'balance.performance_targets.metrics.load_max_seconds','balance.performance_targets.spatial_samples.minimum_dense_sample_real_seconds',
                'balance.dialogue_presentation.minimum_read_real_seconds'}
            and clock['real_day_paths']==['balance.save.trash_days']
            and all(units.get(p)=='real_seconds' for p in clock['realtime_seconds_paths'])
            and all(units.get(p)=='real_days' for p in clock['real_day_paths']),
            'real autosave, benchmark, reading or trash retention converted to hospital time')
    require(all('_real_' not in p or u.startswith('real') for p,_,u in rows), 'explicit real duration has hospital units')


def validate_time_document_examples(c, b, sources):
    """Resolve the three published scenarios against their original data owners."""
    arrival=re.search(r'例如规模S=(\d+)且选择正常档时显示“正常接诊 · 明日预计(\d+)—(\d+)次机会”',
                      sources['03-experience.md'])
    require(arrival is not None, 'missing source-verifiable arrival card example')
    scale,lo,hi=map(int,arrival.groups())
    preset=b['arrival_presets']['normal']
    expected=planned_arrivals(preset,reference_arrival_capacity(c,b)*scale)
    require(scale==2 and (lo,hi)==expected[:2],
            'arrival card example disagrees with explicitly stated doubled clinical reference')
    horizon=re.search(r'覆盖预览查看未来(\d+)模拟秒（(\d+)医院小时）', sources['10-community-comedy.md'])
    require(horizon is not None, 'missing source-verifiable schedule horizon example')
    seconds,hours=map(int,horizon.groups())
    require(seconds==b['comedy']['schedule_proposal_horizon_seconds']
            and Fraction(seconds*b['hospital_clock']['day_minutes'],b['day_seconds'])==hours*60,
            'schedule preview example disagrees with the original full-day horizon')
    interruption=re.search(r'^\| V246 [^\n]*睡了(\d+)模拟秒[^\n]*剩余(\d+)模拟秒',
                           sources['06-validation.md'], re.M)
    require(interruption is not None, 'missing source-verifiable interrupted sleep example')
    elapsed,remaining=map(int,interruption.groups())
    require(0<elapsed<b['staff_sleep']['sleep_seconds']
            and elapsed+remaining==b['staff_sleep']['sleep_seconds'],
            'interrupted sleep example changes the original required actual sleep duration')
    return (lo,hi), (seconds,hours), (elapsed,remaining)


def check_time_document_examples(c,b):
    sources={name:(DOCS/'design'/name).read_text(encoding='utf-8') for name in
             ('03-experience.md','10-community-comedy.md','06-validation.md')}
    arrival,horizon,sleep=validate_time_document_examples(c,b,sources)
    check(arrival==(75,125), '接诊卡同等双组D09参考75…125次机会与原工时/90%负荷一致，非泛化规模配额')
    check(horizon==(1800,24), '排班覆盖预览为原1800模拟秒/24医院小时，跨日只读范围不改长期班表')
    check(sleep==(25,425), 'V246实际睡25模拟秒后保留425秒，完整实际睡眠仍为6医院小时')
    for name,old,new,label in [
        ('03-experience.md','明日预计75—125次机会','明日预计72—120次机会','两组工时参考套用固定档位配额'),
        ('10-community-comedy.md','未来1800模拟秒','未来600模拟秒','全天覆盖预览退回单班'),
        ('06-validation.md','剩余425模拟秒','剩余35模拟秒','睡眠中断沿用过期余量')]:
        invalid=dict(sources)
        require(old in invalid[name], 'missing document negative scenario source')
        invalid[name]=invalid[name].replace(old,new,1)
        try: validate_time_document_examples(c,b,invalid)
        except ValueError: check(True,'时间说明与源数据冲突被拒绝：'+label)
        else: raise ValueError('time document accepted '+label)


def check_time_examples(c, b):
    check_time_document_examples(c,b)
    tick=Fraction(str(b['tick_seconds'])); day_ticks=int(Fraction(b['day_seconds'])/tick)
    minute_ratio=Fraction(b['hospital_clock']['day_minutes'],b['day_seconds'])
    check(day_ticks==18000 and minute_ratio==Fraction(4,5)
          and [Fraction(b['day_seconds'],60*speed) for speed in (1,2,3)]==[30,15,10],
          '18000tick医院日为24小时，1倍30/2倍15/3倍10现实分钟，原步长不变')
    check((17999%day_ticks)*1440//day_ticks==1439 and (18000%day_ticks)*1440//day_ticks==0
          and 18000//day_ticks+1==2 and tick*minute_ratio*60==Fraction(24,5),
          '真实tick推导23:59到第2日00:00，每tick4.8医院秒，不另保存分钟面')
    check([v*minute_ratio for v in (12,18,22,30,58,120,150,180,505)]
          == [Fraction(48,5),Fraction(72,5),Fraction(88,5),24,Fraction(232,5),96,120,144,404],
          '诊疗与恢复换算有精确分数，三级完整下界404医院分钟含查房不重复加护理')
    check(planned_arrivals(b['arrival_presets']['normal'],reference_arrival_capacity(c,b))[2]==Fraction(50)
          and b['supplies']['reservation_seconds']*minute_ratio==24
          and b['wait_departure']['first_check_seconds']*minute_ratio==96,
          '客流参考按原工时/90%负荷推导，24分钟库存预留与96分钟起始弃候仍使用原真实时钟')
    check(b['staff_sleep']['sleep_seconds']*minute_ratio==360
          and b['staff_sleep']['awake_limit_seconds']*minute_ratio==1080
          and b['staff_sleep']['early_sleep_after_seconds']*minute_ratio==720,
          '睡眠6小时、最晚连续清醒18小时、12小时后可安全提前，短休独立')
    check(b['save']['autosave_real_seconds']==180 and b['save']['trash_days']==30
          and b['performance_targets']['capture']['sample_real_seconds']==600
          and b['dialogue_presentation']['minimum_read_real_seconds']==4,
          '自动保存、回收站、性能窗口与阅读使用现实时间，不按医院日缩放')
    for key,value,label in [
        ('day_seconds',600,'医院日回退10现实分钟'),
        ('tick_seconds',.3,'拉长日时改变固定步'),
        ('hospital_clock.day_minutes',480,'三班被误写为整个医院日8小时'),
        ('hospital_clock.snapshot_clock_copy',True,'保存并积分第二钟面'),
        ('hospital_clock.published_basis_mutable',True,'内容更新重定旧医院日界'),
        ('hospital_clock.clock_rounding','round_nearest','钟面提前跨分钟或日界'),
        ('hospital_clock.realtime_seconds_paths',[],'现实保存与采样换为医院时间')]:
        invalid=copy.deepcopy(b); target=invalid
        parts=key.split('.')
        for part in parts[:-1]: target=target[part]
        target[parts[-1]]=value
        try:validate_time_basis(c,invalid)
        except ValueError:check(True,'统一时间合同负例被拒绝：'+label)
        else:raise ValueError('hospital time accepted '+label)


def append_time_atlas(lines, c, b, table):
    minutes_per_second=Fraction(b['hospital_clock']['day_minutes'],b['day_seconds'])
    def number(v):
        return f'{float(v):.6f}'.rstrip('0').rstrip('.')
    rows=[]
    for path,value,unit in time_values(c,b):
        amount=Fraction(str(value))
        if unit=='seconds': original=f'{value}模拟秒'; converted=number(amount*minutes_per_second)+'医院分钟'
        elif unit=='ticks': original=f'{value}模拟tick'; converted=number(amount*Fraction(str(b['tick_seconds']))*minutes_per_second)+'医院分钟'
        elif unit=='days': original=f'{value}医院日 / 日序'; converted=number(amount*24)+'医院小时 / 日序位置'
        elif unit=='sample_delta':
            original=f'{value} / 每次原怒气采样'
            converted=f'{value} / 每'+number(Fraction(b['anger']['update_seconds'])*minutes_per_second)+'医院分钟的原条件采样，不改为连续增长'
        elif unit in ('rate','rate10'):
            original=f'{value} / '+('模拟秒' if unit=='rate' else '10模拟秒')
            converted=number(amount/minutes_per_second/(10 if unit=='rate10' else 1))+' / 医院分钟'
        else:
            original=str(value)+{'real_seconds':'现实秒','real_days':'现实日','real_ms':'现实毫秒'}[unit]
            converted='保持现实时间，不换算'
        rows.append([path,original,converted])
    lines += ['## 全部数值时间与速率换算','',
              '统一基准：1800模拟秒＝24医院小时＝1440医院分钟；0.1模拟秒一tick＝4.8医院秒。1×/2×/3×一天分别30/15/10现实分钟。原秒字段仍是唯一工时来源，以下换算不保存、不舍入后反写参数。日序字段表示相应日历位置；0附加工时表示没有新增时间，负数为原沟通节省。',
              '',f'当前自动覆盖{len(rows)}个数值时间/速率字段。原章节与其他索引未明确标医院或现实的“秒”均为模拟秒；以下表区分日历、工时、采样、速率和现实指标。速率按相同时间比换算，实际积分仍沿原0.1秒步。', '']
    table(lines,['事实来源','原始时间 / 速率','医院时间换算 / 现实归属'],rows)


def validate_catalog(c: dict, balance: dict) -> None:
    validate_time_basis(c, balance)
    validate_performance_targets(c, balance)
    require(balance['command_previews'] == {'revision_policy':'revalidate_relevant_facts',
            'material_change':'retain_draft_and_show_difference','substitute_target':False,
            'stale_session_input':'discard_before_enqueue'}, 'preview causes repeated confirmation or silent substitution')
    require(balance['save']['receipt_scope'] == 'hospital_session_request_revision'
            and balance['save']['exit_checkpoint'] == 'current_operation_frozen_revision'
            and balance['save']['cancel_exit_keeps_paused'] is True
            and balance['save']['draft_policy'] == 'confirm_discard_only_after_successful_leave',
            'save receipts or draft exit policy drift')
    tables = {key: index(c[key]) for key in (
        'families', 'specialties', 'species', 'diseases', 'machines', 'research',
        'treatment_bindings', 'doors', 'incidents', 'interactions', 'tasks')}
    s, d, m, research = (tables[k] for k in ('species', 'diseases', 'machines', 'research'))
    equipment = index(balance['equipment']['classes'])
    for item in s.values():
        require(item['family_id'] in tables['families'], 'missing family')
        require(all(isinstance(v, (int, float)) and math.isfinite(v) and 0 < v <= 7
                    for v in item['body'].values()), 'invalid body envelope')
        require(set(item['body']) == {'width_m', 'depth_m', 'height_m'}, 'incomplete body')
        require(clearance(item) <= 3, 'unsupported campus clearance')
        require('clearance' not in item and 'disease_ids' not in item, 'duplicated derived species data')
        require(any(door_fits(item, door) for door in tables['doors'].values()), 'species has no usable door')
    for door in tables['doors'].values():
        require(0 < door['clear_width_m'] < door['span_cells'] * 1.5, 'invalid door width')
        require(door['price'] > 0 and door['clear_height_m'] > 0, 'invalid door definition')
        require(door['equipment_class'] == 'door' and door['fit_policy'] == 'automatic', 'door cannot adapt')
    for item in m.values():
        require(item['equipment_class'] in equipment, 'machine lacks failure class')
        require(item['price'] > 0, 'invalid machine price')
    routines = index(c['treatment_routines'])
    for item in routines.values():
        require(item['specialty_id'] in tables['specialties'] and item['equipment_id'] in m, 'missing routine equipment or department')
        require(1 <= item['service_seconds'] <= 300 and 'price' not in item and 'upgrade_levels' not in item, 'routine became separately managed machine')
        require(len(item['beats']) == 4 and all(item['beats']), 'incomplete machine beats')
    bound_s, bound_d, bound_m, combinations = set(), set(), set(), set()
    case_bodies = {}
    for bind in tables['treatment_bindings'].values():
        sid, did, rid = (bind[k] for k in ('species_id', 'disease_id', 'routine_id'))
        require(rid in routines and 'machine_id' not in bind, 'missing routine or duplicate equipment owner')
        mid = routines[rid]['equipment_id']
        require(sid in s and did in d and mid in m, 'missing binding reference')
        require(bind['animation_profile'] == s[sid]['rig'], 'rig mismatch')
        require(all(bind.get(k) for k in ('symptom_variant', 'treatment_variant', 'recovery_variant')), 'incomplete case variant')
        require(not bind['treatment_variant'].rstrip('。；').endswith(bind['recovery_variant'].rstrip('。；')),
                'case procedure duplicates its post-cure recovery')
        if 'symptom_envelope' in bind:
            envelope = bind['symptom_envelope']
            require(set(envelope) == {'width_m','depth_m','height_m'}
                    and all(isinstance(v, (int, float)) and not isinstance(v, bool)
                            and math.isfinite(v) and 0 < v <= 7 for v in envelope.values()),
                    'invalid symptom envelope')
            require(all(envelope[k] >= s[sid]['body'][k] for k in envelope),
                    'case envelope shrinks species body')
        patient = {'body': binding_body(s[sid], bind)}
        body_key = tuple(patient['body'][axis] for axis in ('width_m','depth_m','height_m'))
        previous_body, previous_binding = case_bodies.setdefault((sid, did), (body_key, bind['id']))
        require(body_key == previous_body,
                f'conflicting case body for {sid}/{did}: {previous_binding} and {bind["id"]}')
        capacity = m[mid]['adapter_capacity']
        require(clearance(patient) <= min(3, capacity['max_clearance_cells'])
                and patient['body']['height_m'] <= capacity['max_height_m'], 'machine cannot accommodate case body')
        require(any(door_fits(patient, door) for door in tables['doors'].values()), 'case has no usable door')
        combo = sid, did, rid
        require(combo not in combinations, 'duplicate binding')
        combinations.add(combo)
        bound_s.add(sid); bound_d.add(did); bound_m.add(mid)
    require(bound_s == set(s) and bound_d == set(d) and bound_m == set(m), 'uncovered content')
    visiting, ancestors = set(), {}
    def visit(rid: str) -> set:
        require(rid in research, 'missing research prerequisite')
        require(rid not in visiting, 'research cycle')
        if rid in ancestors:
            return ancestors[rid]
        visiting.add(rid)
        result = set(research[rid]['requires'])
        for prior in research[rid]['requires']:
            result |= visit(prior)
        visiting.remove(rid); ancestors[rid] = result
        return result
    for rid in research:
        visit(rid)
    unlocks = {did: 'base' for did in c['initial_disease_ids']}
    require(len(unlocks) == len(c['initial_disease_ids']), 'duplicate initial unlock')
    for item in research.values():
        require(item['price'] >= 0 and item['work_seconds'] > 0, 'invalid research values')
        for did in item['disease_ids']:
            require(did in d and did not in unlocks, 'duplicate/missing research reward')
            unlocks[did] = item['id']
    require(set(unlocks) == set(d), 'disease has no unlock')
    for item in d.values():
        require(item['profile'] in c['profiles'] and item['cure_fee'] > 0, 'invalid disease')
        require('unlock_id' not in item, 'duplicated unlock owner')
        if item['profile'] == 'C':
            require(unlocks[item['id']] != 'base' and 'R11' in ancestors[unlocks[item['id']]], 'complex disease lacks diagnostics')

    all_tags = {tag for item in s.values() for tag in item['tags']}
    def validate_selector(value: dict) -> None:
        for key, val in value.items():
            require(key in ('species_any', 'tags_any', 'family', 'profession', 'quirk', 'disease', 'any_resident'), 'unknown selector')
            if key == 'species_any': require(bool(val) and set(val) <= set(s), 'unknown participant')
            elif key == 'tags_any': require(bool(val) and set(val) <= all_tags, 'unknown participant tag')
            elif key == 'family': require(val in tables['families'], 'unknown family selector')
            elif key == 'disease': require(val in d, 'unknown disease selector')
            elif key == 'profession': require(val in ('priest', 'mage', 'gardener', 'merchant', 'performer', 'resident'), 'unknown profession')
            elif key == 'quirk': require(val in ('ice_temper', 'smoke_shame'), 'unknown quirk')
            elif key == 'any_resident': require(val is True, 'invalid selector bool')
    effects = {'pause_actor', 'pause_station', 'mood_delta', 'spawn_cleanup', 'assign_care_task', 'relationship_change', 'play_gag', 'wear_equipment'}
    furniture = index(c['furniture_equipment'], 'definition_id')
    for item in furniture.values():
        require((item['equipment_class'] in equipment and item['passive_decoration'] is False)
                or (item['equipment_class'] is None and item['passive_decoration'] is True), 'unclassified furniture')
    for key in ('incidents', 'interactions'):
        for item in c[key]:
            validate_selector(item['actor_a']); validate_selector(item['actor_b'])
            require(set(item['effects']) <= effects, 'unknown event effect')
            require(not item['may_start_incident'] and bool(item['scene']), 'recursive or empty event')
            if 'required_object_id' in item['conditions']:
                require(item['conditions']['required_object_id'] in furniture, 'missing interaction object')
            if key == 'incidents':
                require(4 < item['max_duration_seconds'] <= 70 and item['restores_state'] and bool(item['resolution']), 'event lacks end')
                require(item['trigger'] in ('encounter', 'self', 'failure'), 'invalid trigger')
                require(item['care_role'] in {x['role'] for x in balance['staff']}, 'unknown rescue role')
                require(item['care_work_seconds'] > 0 and 4 + item['natural_resolution_seconds'] + item['actor_recovery_seconds'] <= item['max_duration_seconds'], 'event exceeds automatic end budget')
                require(0 <= item['cleanup_count'] <= 3 and item['observer_max'] <= 1 and item['followup_max'] == 1, 'unbounded event spillover')
                require(item['release_reservations_on_finish'] is True, 'event leaves reserved resources')
                if 'relationship_or_trait' in item['conditions']:
                    require('reconciled' in item['conditions'].get('excluded_relationships', []), 'reconciled pair can fight again')
            else:
                require(4 <= item['duration_seconds'] <= 8 and item['interrupt_seconds'] <= 1, 'interaction blocks service')
    metrics = {'cured_visits', 'payroll_days_all_staff_paid', 'employed_mechanics', 'owned_plots',
               'cured_clearance2_visits', 'completed_research', 'preventive_maintenance_jobs',
               'random_fault_repairs', 'distinct_cured_species', 'comfortable_visits',
               'completed_stories', 'cured_clearance3_visits', 'doctors_with_two_abilities',
               'distinct_cured_diseases', 'cured_tall_visits', 'positive_interactions',
               'completed_ability_courses', 'cleanup_jobs', 'diagnosed_b_visits'}
    for item in c['tasks']:
        require(item['metric'] in metrics and item['target'] > 0, 'unknown task metric')
        if item['metric'] == 'doctors_with_two_abilities':
            require(item.get('metric_parameters') == {'minimum_ability_count':2,'minimum_ability_level':2},
                    'doctor team task has ambiguous ability requirements')
        else:
            require('metric_parameters' not in item, 'unsupported task metric parameters')
        require(item['kind'] in ('milestone', 'commission') and item['repeatable'] == (item['kind'] == 'commission'), 'task repeat mismatch')
        require(item['deadline_days'] is None and 0 < item['reward_cash'] <= 1200, 'invalid task reward')
        validate_selector(item['filter'])
        rule = item['eligibility_rule']
        require(set(rule) <= {'requires_research','required_roles','ready_offer_filter','maintainable_equipment_min','degraded_equipment_min','condition_lte','available_residents_min','ready_comfort2_seat_min','trainable_doctors_min'}, 'unknown task eligibility condition')
        if 'maintainable_equipment_min' in rule:
            require(type(rule['maintainable_equipment_min']) is int and rule['maintainable_equipment_min'] > 0,
                    'maintainable equipment eligibility must be a positive integer')
        require(set(rule['requires_research']) <= set(research), 'missing task prerequisite')
        require(set(rule['required_roles']) <= {x['role'] for x in balance['staff']}, 'missing task role')
        require('task_id' not in rule and 'handler' not in rule, 'task-number dispatch instead of semantic conditions')
    for cls in equipment.values():
        require(0 < cls['base_failure_bp'] * max(balance['equipment']['risk_multipliers']) <= 10000, 'invalid equipment probability')
        require(cls['repair_parts'] > 0 and cls['repair_seconds'] > 0, 'invalid repair')
    require(all((x.get('pay_source') == 'doctor_pay' and 'wage_day' not in x and 'hire' not in x)
                if x['role'] == 'doctor' else (x['wage_day'] > 0 and x['hire'] > 0)
                for x in balance['staff']), 'unpaid staff role or duplicated doctor pay')
    validate_clinical(c, balance)
    validate_life(c, balance)
    validate_comedy(c, balance)
    validate_expansion(c, balance)
    validate_remodel_content(c, balance)
    validate_progression(c, balance)
    validate_operations(c, balance)
    validate_care(c, balance)
    validate_expertise(c, balance)

def cells(anchor: list, size: list) -> set:
    return {(x,y) for x in range(anchor[0],anchor[0]+size[0]) for y in range(anchor[1],anchor[1]+size[1])}

def edge(a: tuple, b: tuple) -> tuple:
    return tuple(sorted((a,b)))

def validate_layout(layout: dict, balance: dict, catalog: dict) -> dict:
    owned = cells([32,64],[32,32])
    room_cells, blocked, walls, openings = set(), set(), set(), {}
    rooms, doors, species = index(layout['rooms']), index(catalog['doors']), index(catalog['species'])
    for room in layout['rooms']:
        inside = cells(room['anchor'],room['size'])
        check(inside <= owned and not inside & room_cells, '房间边界与重叠：'+room['id'])
        room_cells |= inside
        for p in inside:
            for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                q=p[0]+dx,p[1]+dy
                if q not in inside: walls.add(edge(p,q))
        opening=room['door'];door=doors[opening['definition_id']]
        check(opening['edge']=='south', '预设门方向')
        x,y=room['anchor'];y+=room['size'][1]-1
        check(opening['offset']+door['span_cells'] <= room['size'][0], '门不超墙段')
        for i in range(door['span_cells']):
            dx=x+opening['offset']+i;e=edge((dx,y),(dx,y+1))
            walls.remove(e);openings[e]=door
    all_objects=layout['objects']+[layout['suggested_gift_placement']]
    for obj in all_objects:
        occupied=cells(obj['anchor'],obj['size'])
        check(occupied <= owned and not occupied & blocked, '物件/赠品不重叠：'+obj['definition_id'])
        if obj['room_id']:
            room=rooms[obj['room_id']]
            check(occupied <= cells(room['anchor'],room['size']), '物件在指定室内')
        blocked |= occupied
    entry=cells(layout['entry']['anchor'],layout['entry']['size'])
    check(entry <= owned and not entry & blocked and len(entry)==9,'起始3×3入口完整')
    def clear(region: set, actor: dict) -> bool:
        if not region <= owned or region & blocked:return False
        adapted_openings = set()
        for room in layout['rooms']:
            opening=room['door'];door=doors[opening['definition_id']]
            if not door_fits(actor,door,room['size'][0]-opening['offset']):continue
            x,y=room['anchor'];y+=room['size'][1]-1
            for i in range(door_span(actor,door)):
                dx=x+opening['offset']+i
                adapted_openings.add(edge((dx,y),(dx,y+1)))
        for x,y in region:
            for q in ((x+1,y),(x,y+1)):
                if q in region:
                    e=edge((x,y),q)
                    if (e in walls or e in openings) and e not in adapted_openings:return False
        return True
    def reach(actor: dict) -> set:
        k=clearance(actor);start=tuple(layout['entry']['anchor'])
        require(door_fits(actor,doors[layout['entry']['door_definition_id']]), 'entry cannot fit actor')
        require(clear(cells(list(start),[k,k]),actor),'invalid spawn')
        seen,todo={start},deque([start])
        while todo:
            p=todo.popleft()
            for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                q=p[0]+dx,p[1]+dy
                if q in seen:continue
                if clear(cells(list(p),[k,k])|cells(list(q),[k,k]),actor):seen.add(q);todo.append(q)
        return seen
    human,giraffe,giant=reach(species['S49']),reach(species['S01']),reach(species['S59'])
    for label,target in [('接待',(43,93)),('初诊',(36,88)),('人类治疗',(51,88)),('僵尸治疗',(45,87)),('休息',(57,88)),('员工床一',(56,88)),('员工床二',(59,88)),('医生办公',(36,82)),('护士工作台',(60,87)),('卫生间',(56,82))]:
        check(target in human,'起始人类全流程：'+label)
    for label,target in [('接待',(43,93)),('初诊',(36,88)),('赠品梳结架',(42,87))]:
        check(target in giraffe,'高顶门容纳长颈鹿：'+label)
    check((36,88) not in giant,'巨人不能误用未扩建的初诊室')
    for obj in all_objects:
        if obj['definition_id'].startswith('M'):
            x,y=obj['anchor'];w,h=obj['size']
            check((x+w,y+h-1) in human and (x+w-1,y-1) in human,'治疗机员工/维修位置可达')
    paved=set().union(*(cells(v['anchor'],v['size']) for v in layout['path_rectangles']))
    check(len(paved)==40 and not paved & blocked,'预设40格路面')
    door_cost=sum(doors[r['door']['definition_id']]['price'] for r in layout['rooms'])
    check(door_cost==480 and len(room_cells)==121,'两高顶门/四普通门480，含办公室室内121格')
    support={o['id']:o for o in layout['objects'] if o['definition_id'] in {'SE04','SE05','SE06'}}
    check(len(support)==4 and sum(o['definition_id']=='SE04' for o in support.values())==2,'开局两床、医生办公桌和护士台真实存在')
    for area in layout['staff_work_areas']:
        region=cells(area['anchor'],area['size'])
        check(region<=owned and not region & paved and all(cells(support[key]['anchor'],support[key]['size'])<=region for key in area['equipment_ids']), '员工工作角不占主要路面且包含对应设施')
    return dict(indoor_cells=len(room_cells),paved_cells=len(paved),doors=door_cost)

def table(lines: list, header: list[str], body: list[list]) -> None:
    lines += ['| '+' | '.join(header)+' |','| '+' | '.join('---' for _ in header)+' |']
    for row in body:
        lines.append('| '+' | '.join(str(x).replace('|','／').replace('\n','；') for x in row)+' |')
    lines.append('')

def selector_label(sel: dict, c: dict) -> str:
    species=index(c['species']);families=index(c['families']);diseases=index(c['diseases'])
    parts=[]
    for k,v in sel.items():
        if k=='species_any':parts.append(' / '.join(species[i]['name'] for i in v))
        elif k=='family':parts.append(families[v]['name'])
        elif k=='disease':parts.append(diseases[v]['name']+'患者')
        elif k=='tags_any':parts.append('标签：'+','.join(v))
        elif k=='profession':parts.append({'priest':'牧师'}.get(v,v))
        elif k=='quirk':parts.append({'ice_temper':'暴脾气冰法师','smoke_shame':'害羞吐烟小龙'}.get(v,v))
        elif k=='any_resident':parts.append('附近居民/指定目标')
    return '、'.join(parts) or '不限'

def render_atlas(c: dict,b: dict,layout: dict) -> str:
    s,d,m,f,departments=(index(c[k]) for k in ('species','diseases','machines','families','specialties'))
    by_species=defaultdict(list);by_disease=defaultdict(list)
    for bind in c['treatment_bindings']:
        by_species[bind['species_id']].append(bind);by_disease[bind['disease_id']].append(bind)
    unlock={did:'基础' for did in c['initial_disease_ids']}
    unlock.update({did:r['id'] for r in c['research'] for did in r['disease_ids']})
    lines=['# 基础内容完整索引','',
           '从content-catalog.json和balance.json生成；这里列的是设计内容，不代表正式资产已制作。',
           '',f'core {c["content_version"]}：80种族、154病症、三类门诊主体与84套自动演出、488门诊适配、332方案、53手术适配、两类整合临床设备、38研究、97互动、6熟客回访、5类社区活动与15变体、8位活动关联故事居民、3全体型设施、28经营任务、12居民故事、6门型、3竖向设施、7岗位介绍、6工作习惯、8履历、7空间蓝图与6改造引导。',
           '', '## 每个种族的身体与病例','',
           '宽×深×高单位米；微观/水生的载具已计入。所有种族病例名单由绑定派生，不能在此手改。','']
    body=[]
    for item in c['species']:
        dim=item['body'];names=[d[v['disease_id']]['name'] for v in by_species[item['id']]]
        body.append([item['id']+' '+item['name'],f[item['family_id']]['name'],
                     f'{dim["width_m"]}×{dim["depth_m"]}×{dim["height_m"]} / {clearance(item)}格',
                     '、'.join(door['id'] for door in c['doors'] if door_fits(item,door)),
                     '；'.join(names)])
    table(lines,['种族','家族','正常包络 / 通路','可通过门型','全部病症'],body)
    lines += ['## 六种可改建门','']
    table(lines,['编号 / 门型','跨度','收起净宽 / 净高','价格','故障行为'],[
        [x['id']+' '+x['name'],str(x['span_cells'])+'格',f'{x["clear_width_m"]} / {x["clear_height_m"]}米',x['price'],'按实际身体自动伸展，空间不足拒绝；免维护'] for x in c['doors']])
    lines += ['## 病症与治疗机器','', '职称初诊诊费20/30/45/60，设施按实际完成项目收取使用费；以下病症基价只用于成功后的治愈费，不包含前述费用。','']
    body=[]
    for item in c['diseases']:
        binds=by_disease[item['id']];routines=index(c['treatment_routines'])
        routine_ids=sorted({v['routine_id'] for v in binds})
        machine_text='；'.join(m[routines[rid]['equipment_id']]['name']+' / '+routines[rid]['name']+f' / {routines[rid]["service_seconds"]}秒' for rid in routine_ids)
        body.append([item['id']+' '+item['name'],item['symptom'],'、'.join(s[sid]['name'] for sid in sorted({v['species_id'] for v in binds})),machine_text,f'{item["profile"]} / {item["cure_fee"]}',unlock[item['id']]])
    table(lines,['病症','入院表现','适配种族','主体 / 自动演出 / 工时','档位 / 治愈费','研究'],body)
    lines += ['## 84套自动治疗演出','', '由三类门诊主体按病例自动切换，不单独购买或升级。', '']
    table(lines,['演出 / 主体 / 医疗专业','准备','过程','高潮','安全收尾'],[
        [x['id']+' '+x['name']+' / '+m[x['equipment_id']]['name']+' / '+departments[x['specialty_id']]['name'],*x['beats']] for x in c['treatment_routines']])
    lines += ['## 488条病例表现适配','', '同一种病症的不同身体表现逐一登记。场景中的实际操作区还必须经过宽高与占用检查。','']
    for item in c['species']:
        lines += ['### '+item['id']+' '+item['name'],'']
        table(lines,['病症 / 机器','该种族症状','治疗变体','康复变化'],[
            [v['disease_id']+' '+d[v['disease_id']]['name']+' / '+v['routine_id'],v['symptom_variant'],v['treatment_variant'],v['recovery_variant']] for v in by_species[item['id']]])
    append_clinical_atlas(lines,c,b,table)
    append_life_atlas(lines,c,b,table)
    append_comedy_atlas(lines,c,b,table)
    append_expansion_atlas(lines,c,b,table)
    append_progression_atlas(lines,c,b,table)
    append_operations_atlas(lines,c,b,table)
    append_care_atlas(lines,c,b,table)
    append_expertise_atlas(lines,c,b,table)
    append_performance_atlas(lines,c,b,table)
    append_time_atlas(lines,c,b,table)
    lines += ['## 25类主要互动事件','']
    table(lines,['事件','参与者与触发','额外条件','现场变化','救场与自然收尾','上限 / 附属笑点'],[
        [x['id']+' '+x['name'],selector_label(x['actor_a'],c)+' × '+selector_label(x['actor_b'],c)+'；'+x['trigger'],
         json.dumps(x['conditions'],ensure_ascii=False) if x['conditions'] else '通用近邻、候诊/空闲和冷静期条件',
         x['scene'],x['resolution'],str(x['max_duration_seconds'])+'秒；'+x['followup']] for x in c['incidents']])
    lines += ['## 72类日常互动','']
    personality_names={x['id']:x['name'] for x in c['patient_personalities']}
    table(lines,['互动','参与者','条件','性格选择偏好','演出 / 时长'],[
        [x['id']+' '+x['name'],selector_label(x['actor_a'],c)+' × '+selector_label(x['actor_b'],c),
         json.dumps(x['conditions'],ensure_ascii=False) if x['conditions'] else '可达且空闲/候诊',
         '、'.join(personality_names[p] for p in x.get('preferred_personality_ids',[])) or '通用',
         x['scene']+'；'+str(x['duration_seconds'])+'秒，叫号1秒内结束'] for x in c['interactions']])
    task_labels = {metric:label for guide in c['task_guides'] for metric,label in guide['metric_labels'].items()}
    lines += ['## 16项成长任务与12种社区委托','', '成长按医院只领一次；委托只统计接取后事实，周期刷新但已接任务不超时。12条具名故事另见内容规格。','']
    table(lines,['任务','类型','目标指标 / 数量','筛选与条件','奖励现金'],[
        [x['id']+' '+x['name'],'成长' if x['kind']=='milestone' else '可重复委托',task_labels[x['metric']]['text']+' / '+str(x['target'])+task_labels[x['metric']]['unit'],selector_label(x['filter'],c)+'；'+x['eligibility']+('；本人至少'+str(x['metric_parameters']['minimum_ability_count'])+'项能力均≥'+str(x['metric_parameters']['minimum_ability_level'])+'级' if 'metric_parameters' in x else ''),x['reward_cash']] for x in c['tasks']])
    lines += ['## 医疗专业与研究','']
    table(lines,['医疗专业','最小内部尺寸','资格'],[[x['id']+' '+x['name'],'×'.join(map(str,x['min_inner_size'])),x['doctor_qualification']] for x in c['specialties']])
    table(lines,['研究','全部前置','费用 / 工时','病例解锁'],[[x['id']+' '+x['name'],','.join(x['requires']) or '无',str(x['price'])+' / '+str(x['work_seconds'])+'秒',','.join(x['disease_ids']) or '功能奖励，见内容规格'] for x in c['research']])
    lines += ['## 工资、故障与补助','']
    table(lines,['岗位','每医院日工资','招聘费'],[[x['name'],x.get('wage_day','按职称'+ '/'.join(str(p['wage_day']) for p in b['doctor_pay'])),x.get('hire','按职称'+ '/'.join(str(p['hire']) for p in b['doctor_pay']))] for x in b['staff']])
    table(lines,['设备类别','完好时每60秒故障概率','维修工时 / 零件','保养工时 / 零件'],[
        [x['id'],str(x['base_failure_bp']/100)+'%',f'{x["repair_seconds"]}秒 / {x["repair_parts"]}',f'{x["maintenance_seconds"]}秒 / {x["maintenance_parts"]}'] for x in b['equipment']['classes'] if x['id'] in {'medical','workstation','utility'}])
    lines += ['磨损将风险乘1/3/8；故障必须由雇佣维修员修复。工资和零件费分别记账。',
              '', '每3医院日补助min(2400,1200+200×额外地块数)，首次第3日；第2…9块地价依次'+','.join(map(str,b['plot_prices'][1:]))+'。','',
              '## 起始建设预算','']
    table(lines,['项目','欢乐币'],[[x['item'],x['amount']] for x in b['starter_purchase']])
    construction=sum(v['amount'] for v in b['starter_purchase'])
    hire,_=starter_staff_costs(b,layout)
    supply_units=b['supplies']['initial_purchase_units']
    supply_price=index(c['medical_supplies'])[b['supplies']['definition_id']]['unit_price']
    supply_cost=supply_units*supply_price
    lines += [f'建设{construction}，招聘{hire}，实际采购{supply_units}包治疗包{supply_cost}，余款{b["starting_cash"]-construction-hire-supply_cost}。','',
              '完整规则与故事见[内容与扩展](design/02-content.md)。','']
    return '\n'.join(lines)

def check_links() -> int:
    total=0
    for path in DOCS.rglob('*.md'):
        for link in re.findall(r'!?\[[^\]]*\]\(([^)]+)\)',path.read_text(encoding='utf-8')):
            link=link.strip('<>').split('#')[0]
            if not link or re.match(r'[a-zA-Z]+://',link):continue
            check((path.parent/link).resolve().exists(),'本地链接存在：'+path.name+' → '+link)
            total+=1
    return total

def check_requirement_coverage() -> None:
    text = (DOCS/'design/06-validation.md').read_text(encoding='utf-8')
    ac = re.findall(r'^\| (AC\d+) \|', text, re.M)
    scenes = re.findall(r'^\| (V\d+) ', text, re.M)
    check(ac == [f'AC{i:02}' for i in range(1,317)], '316项产品验收编号连续且唯一')
    check(scenes == [f'V{i:02}' for i in range(1,676)], '675项规则场景编号连续且唯一')
    for prefix in ('AC', 'V'):
        positions = [i for i,line in enumerate(text.splitlines()) if re.match(r'^\| '+prefix+r'\d+ ',line)]
        check(all(end-start == 1 for start,end in zip(positions,positions[1:])),
              prefix+'条目保持同一连续Markdown表格，避免新增行被渲染成段落')
    sources = '\n'.join(p.read_text(encoding='utf-8') for p in (DOCS/'design').glob('*.md'))
    for obsolete in ('48条广播', '13种广播情境', '故障门常开', '门故障常开',
                     '自动收纳仲裁', '60秒自动收纳', 'consumables_entry_id',
                     '生成/到期tick', '余款11,890', '余额11,890',
                     'AC01…AC84与V01…V154', '临床布局schema3', 'schema25',
                     '48 件可购买家具', '初诊台、光谱仪、共振仪', '回访带梦团朋友',
                     '全院32人编制是否已满', '休假员工仍占编制', '进入角色预算不足时',
                     '复核来源、期限、资金和全院编制', '饮水机修好', '原BedStay',
                     '全院最多16份LRU缓存', '每步最多8个路径请求', '7张内置蓝图',
                     '7张内置图', '6张改造引导', 'schema29', '1.27.0',
                     '每步最多8条请求', '每步最多8次寻路', '图缓存最多16个',
                     '全院最多16份层内图', '16区上限', '现有物件、房间上限',
                     '七回应方式', '十八诊室互动', '标准工作量≤32项', '工时36/32.8/30秒', '陪诊满8',
                     '失败重试最多两次', '换方案不再收门诊费', '住院者仍计患者上限', 'schema30', 'schema53'):
        check(obsolete not in sources, '设计源稿没有过期规则：'+obsolete)

def scene_pixels(display: dict, scale_bp: int) -> list[int]:
    return [2*((value*scale_bp+10000)//20000) for value in display['window_pixels']]


def validate_camera_view(b: dict) -> None:
    camera=b['camera_view']
    require(camera == {
        'projection':'orthographic_vertical_size','default_yaw_degrees':45,'pitch_degrees':35.264,
        'yaw_step_degrees':90,'minimum_size_m':18,'default_size_m':42,'original_max_size_m':90,
        'overview_padding_bp':11000,
        'overview_bounds':'current_floor_legal_plate_corners_and_actual_display_envelopes',
        'safe_rect':'native_scene_rect_excluding_current_fixed_ui',
        'fit_size_rule':'axis_specific_actual_projection_scale_to_safe_rect',
        'max_size':'max_original_and_current_floor_overview',
        'center':'projected_bounds_center_at_safe_rect_center',
        'layout_change':'hold_manual_camera_until_explicit_overview_or_zoom',
        'follow':'overview_cancels_camera_follow_only',
        'native_projected_cell_metric':'shorter_grid_edge_using_actual_projection_in_native_output',
        'active_floor_origin':'same_local_zero_no_floor_number_height',
        'overview_trigger':'explicit_current_floor_button_or_home',
        'bounds_query':'logical_spatial_records_no_scene_loading',
        'invalid_extent':'retain_camera_and_explain_no_fit_request',
        'snapshot_state':False,'changes_simulation':False,'runtime_measurement_available':False},
        'camera view truncates large floors, ignores native safe rect or changes world state')
    require(all(type(camera[key]) is bool for key in
                ('snapshot_state','changes_simulation','runtime_measurement_available')),
            'camera view boolean fields must be booleans')


def camera_projected_bounds_example(bounds, b: dict, yaw=None) -> tuple:
    """Corner projection sample in meters; no Camera3D or game is executed."""
    require(bool(bounds), 'no legal floor bounds for overview')
    camera=b['camera_view']; angle=math.radians(camera['default_yaw_degrees'] if yaw is None else yaw)
    pitch=math.radians(camera['pitch_degrees']); points=[]
    for rect in bounds:
        require(len(rect)==6 and all(type(value) in (int,float) and math.isfinite(value) for value in rect),
                'invalid overview bounds')
        x0,y0,z0,x1,y1,z1=rect
        require(x0<=x1 and y0<=y1 and z0<=z1, 'inverted overview bounds')
        points.extend((math.cos(angle)*x-math.sin(angle)*z,
                       math.sin(angle)*math.sin(pitch)*x+math.cos(angle)*math.sin(pitch)*z+math.cos(pitch)*y)
                      for x in (x0,x1) for y in (y0,y1) for z in (z0,z1))
    left,right=min(row[0] for row in points),max(row[0] for row in points)
    bottom,top=min(row[1] for row in points),max(row[1] for row in points)
    require(right>left and top>bottom, 'empty projected floor extent')
    return (right-left,top-bottom,(left+right)/2,(bottom+top)/2)


def camera_fit_example(bounds, native, rendered, safe_rect, b: dict, yaw=None) -> dict:
    require(len(native)==len(rendered)==2 and all(type(value) is int and value>0 for value in (*native,*rendered)),
            'invalid overview viewport')
    require(len(safe_rect)==4 and all(type(value) in (int,float) and math.isfinite(value) for value in safe_rect),
            'invalid overview safe rect')
    ow,oh=native; x,y,sw,sh=safe_rect
    require(x>=0 and y>=0 and sw>0 and sh>0 and x+sw<=ow and y+sh<=oh, 'empty or outside safe rect')
    pw,ph,cx,cy=camera_projected_bounds_example(bounds,b,yaw)
    aspect=rendered[0]/rendered[1]; camera=b['camera_view']; padding=camera['overview_padding_bp']/10000
    size=max(camera['minimum_size_m'],padding*max(pw*ow/(aspect*sw),ph*oh/sh))
    return {'size_m':size,'max_size_m':max(camera['original_max_size_m'],size),
            'projected_center':(cx,cy),'safe_center':(x+sw/2,y+sh/2),
            'native_span':(pw*ow/(size*aspect),ph*oh/size)}


def camera_native_cell_example(size, native, rendered, b: dict, yaw=None) -> float:
    camera=b['camera_view']; angle=math.radians(camera['default_yaw_degrees'] if yaw is None else yaw)
    pitch=math.radians(camera['pitch_degrees']); aspect=rendered[0]/rendered[1]
    sx,sy=native[0]/(size*aspect),native[1]/size
    # One grid edge is 1.5 meters under simulation section 2.
    return min(math.hypot(1.5*math.cos(angle)*sx,1.5*math.sin(angle)*math.sin(pitch)*sy),
               math.hypot(1.5*math.sin(angle)*sx,1.5*math.cos(angle)*math.sin(pitch)*sy))


def check_camera_view_examples(b: dict) -> None:
    floor=[(0,0,0,144,0,144)]
    pw,ph,_,_=camera_projected_bounds_example(floor,b)
    check(math.isclose(pw,203.6467529817257) and math.isclose(ph,117.57437676074099)
          and pw>90*16/9 and ph>90,
          '九地块空平层投影约203.647×117.574米，固定90米不能完成全层概览')
    native=b['performance_targets']['display']['window_pixels']
    rendered=scene_pixels(b['performance_targets']['display'],7500)
    fit=camera_fit_example(floor,native,rendered,(0,0,*native),b)
    check(math.isclose(fit['size_m'],129.3318144368151)
          and fit['max_size_m']>90 and fit['native_span'][0]<native[0] and fit['native_span'][1]<native[1],
          '纯16:9画面空平层含10%余量概览约129.332米，只是几何算例')
    narrow=camera_fit_example(floor,[1280,720],[960,540],(0,56,928,592),b)
    check(narrow['size_m']>fit['size_m'] and narrow['safe_center']==(464,352)
          and narrow['native_span'][0]<=928/1.1+1e-8 and narrow['native_span'][1]<=592/1.1+1e-8,
          '窄窗口/侧栏安全矩形扩大概览尺寸并对齐可见中心，不能按整窗16:9裁边')
    tall=camera_fit_example(floor+[(143,0,143,144,7,144)],native,rendered,(0,0,*native),b)
    check(tall['size_m']>fit['size_m'] and all(math.isclose(camera_projected_bounds_example(floor,b,yaw)[0],pw)
          and math.isclose(camera_projected_bounds_example(floor,b,yaw)[1],ph) for yaw in (45,135,225,315)),
          '外缘7米真实显示包络扩大纵向范围，四个原镜头方向完整投影同一楼板')
    scaled=[camera_fit_example(floor,native,scene_pixels(b['performance_targets']['display'],scale),
                              (0,56,2168,1312),b) for scale in (10000,7500,6667)]
    check(all(row['native_span'][0]<=2168/1.1+1e-8 and row['native_span'][1]<=1312/1.1+1e-8 for row in scaled)
          and camera_native_cell_example(42,native,rendered,b)>24
          and camera_native_cell_example(fit['size_m'],native,rendered,b)<20,
          '100%/75%/约67%按实际视口到原生安全矩形适配，原24/20格边像素门槛可直接核验')
    check(camera_fit_example([(0,0,0,48,0,48)],native,rendered,(0,0,*native),b)['max_size_m']==90,
          '单地块概览仍保留原90米缩远余量，高层使用本层重定位坐标而非楼号高度')
    rejected=[]
    for args in [(floor,native,rendered,(0,0,0,720)),([],native,rendered,(0,0,*native)),
                 (floor,[0,0],rendered,(0,0,0,0)),(floor,native,[1920,0],(0,0,*native))]:
        try:camera_fit_example(*args,b)
        except ValueError:rejected.append(True)
        else:raise ValueError('invalid camera overview extent accepted')
    check(len(rejected)==4,'无合法楼板/零场景或视口拒绝概览计算，保留镜头而非除零/无限size')
    negatives=[
        (lambda row:row.update(max_size='fixed_90m'), '大平层仍固定90米'),
        (lambda row:row.update(safe_rect='whole_window_ignoring_ui'), '忽略侧栏和目录遮挡'),
        (lambda row:row.update(fit_size_rule='native_aspect_only'), '忽略实际三维视口取整'),
        (lambda row:row.update(overview_bounds='floor_ground_only'), '高身体和症状包络被裁'),
        (lambda row:row.update(bounds_query='load_every_floor_scene'), '概览常驻全院场景'),
        (lambda row:row.update(center='whole_window_center'), '中心落在侧栏遮挡'),
        (lambda row:row.update(layout_change='auto_fit_every_tick'), '工作和走动反复拉镜头'),
        (lambda row:row.update(native_projected_cell_metric='render_texture_pixels'), '低比例纹理冒充原生LOD格边'),
        (lambda row:row.update(active_floor_origin='floor_number_times_height'), '高层号码引入巨大真实坐标'),
        (lambda row:row.update(snapshot_state=True), '镜头保存成世界事实'),
        (lambda row:row.update(changes_simulation=True), '概览改变临床或时间')]
    for mutate,label in negatives:
        broken=copy.deepcopy(b);mutate(broken['camera_view'])
        try:validate_camera_view(broken)
        except ValueError:check(True,'楼层概览合同负例被拒绝：'+label)
        else:raise ValueError('invalid camera view contract accepted: '+label)


def validate_visual_batching(b: dict) -> None:
    rule=b['visual_batching']
    require(rule == {
        'scope':'current_view_actual_visible_parts',
        'group_key':['content_fingerprint','mesh_resource','material_layout','lod','render_state','prepared_pose_resource'],
        'part_identity':'logical_entity_id_and_registered_part_role','membership':'actual_visible_unique_parts',
        'eligibility':'opaque_or_cutout_rigid_parts_or_validated_unskinned_far_pose',
        'unsupported':'original_current_primary_projection','skinned_near':'original_per_entity_or_verified_skin_pose_instancing',
        'alpha_blend':'independent_current_sorting',
        'instance_parameters':'current_transform_color_and_allowed_values_only',
        'shared_material_mutation':False,'visible_layout':'dense_current_prefix',
        'slot_binding_key':['hospital_session','view_id','batch_key','batch_generation','slot_index',
                            'logical_entity_id','part_role','slot_generation'],
        'late_result':'reject_wrong_binding_or_slot_generation',
        'attach_parameters':'requery_current_original_pose_after_binding_check',
        'membership_refresh':'related_visibility_asset_and_pose_binding_change',
        'position_updates':'original_current_pose_without_resource_rebuild',
        'selection_transition':'detach_old_drawing_before_attach_current_projection',
        'budget_source':'spatial_view.view_build_budget_ms_per_frame',
        'draw_cost_source':'actual_renderer_stats_not_batch_or_entity_count',
        'unused_capacity_accounted':True,
        'memory_scope':'visible_idle_staging_upload_and_allocated_capacity',
        'replay_missed_state':False,'snapshot_state':False,'changes_simulation':False,
        'runtime_measurement_available':False}, 'visual batching loses identity, pose or actual rendering cost')
    require(all(type(rule[key]) is bool for key in ('shared_material_mutation','unused_capacity_accounted',
                'replay_missed_state','snapshot_state','changes_simulation','runtime_measurement_available')),
            'visual batching boolean fields must be booleans')


def visual_batch_groups_example(parts, b: dict) -> tuple:
    """Compatibility grouping sample only; never creates a mesh or actor."""
    def immutable(value):
        if isinstance(value,(list,tuple)):return tuple(immutable(item) for item in value)
        if isinstance(value,dict):return tuple(sorted((key,immutable(item)) for key,item in value.items()))
        return value
    unique={}; groups=defaultdict(list); fallback=[]
    for part in parts:
        identity=(part['logical_entity_id'],part['part_role'])
        if identity in unique:
            require(unique[identity]==part,'conflicting current visual part identity')
        else:unique[identity]=part
    for identity,part in sorted(unique.items()):
        if not part['visible']:continue
        compatible=(part['blend_mode'] in ('opaque','cutout') and not part['requires_original_skinning']
                    and (part['deformation']=='rigid' or
                         (part['deformation']=='prepared_unskinned_far' and part['pose_validated'] is True)))
        if compatible:
            groups[tuple(immutable(part[key]) for key in b['visual_batching']['group_key'])].append(identity)
        else:fallback.append(identity)
    return dict(groups),fallback


def visual_slot_matches_example(saved,current,b: dict) -> bool:
    if not isinstance(saved,dict) or not isinstance(current,dict):return False
    return all(key in saved and key in current and saved[key]==current[key]
               for key in b['visual_batching']['slot_binding_key'])


def check_visual_batching_examples(b: dict) -> None:
    base={'logical_entity_id':'object:1','part_role':'body','visible':True,'content_fingerprint':'core-ref',
          'mesh_resource':'fixture:chair','material_layout':('fixture:mint',),'lod':'far',
          'render_state':('opaque','no-shadow'),'prepared_pose_resource':'static',
          'blend_mode':'opaque','deformation':'rigid','pose_validated':True,
          'requires_original_skinning':False,'color':'mint'}
    parts=[base,dict(base,logical_entity_id='object:2',color='coral'),
           dict(base,logical_entity_id='object:3',material_layout=('fixture:linen',)),
           dict(base,logical_entity_id='object:4',deformation='skinned',requires_original_skinning=True),
           dict(base,logical_entity_id='object:5',blend_mode='alpha_blend'),
           dict(base,logical_entity_id='object:6',deformation='prepared_unskinned_far',prepared_pose_resource='fixture:pose3'),
           dict(base,logical_entity_id='object:7',deformation='prepared_unskinned_far',pose_validated=False),
           dict(base,logical_entity_id='object:8',visible=False),dict(base)]
    before=copy.deepcopy(parts); groups,fallback=visual_batch_groups_example(parts,b)
    check(len(groups)==3 and sum(map(len,groups.values()))==4 and len(fallback)==3
          and sum(map(len,groups.values()))+len(fallback)==7 and parts==before,
          '兼容性样例4部件分3组、3部件回退，重复引用去重且离屏不加入；组数不是真实drawcall')
    check(any(members==[('object:1','body'),('object:2','body')] for members in groups.values())
          and ('object:4','body') in fallback and ('object:5','body') in fallback and ('object:7','body') in fallback,
          '同网格/材质布局可独立染色；原骨骼、透明排序和未验证姿态保留原表现')
    split=visual_batch_groups_example([base,dict(base,part_role='symptom',mesh_resource='fixture:symptom')],b)
    check(sum(map(len,split[0].values()))==2 and len({member[0] for rows in split[0].values() for member in rows})==1,
          '主体/症状是两部件而仍一实际实体，部件不能增加Actor或收费')
    try:visual_batch_groups_example([base,dict(base,mesh_resource='fixture:other')],b)
    except ValueError:check(True,'同实体同角色的矛盾当前绑定被拒绝，不随机选一份重复绘制')
    else:raise ValueError('conflicting visual part accepted')
    saved={'hospital_session':'h1-load1','view_id':'floor-main','batch_key':'fixture:batch1',
           'batch_generation':2,'slot_index':0,'logical_entity_id':'object:1','part_role':'body','slot_generation':5}
    differences={'hospital_session':'h2-load1','view_id':'preview','batch_key':'fixture:batch2',
                 'batch_generation':3,'slot_index':1,'logical_entity_id':'object:2','part_role':'symptom','slot_generation':6}
    check(visual_slot_matches_example(saved,dict(saved),b)
          and not visual_slot_matches_example(saved,None,b)
          and all(not visual_slot_matches_example(saved,dict(saved,**{key:value}),b) for key,value in differences.items()),
          '医院/视图/批/槽索引/实体部件/复用代次变化拒绝旧绑定，槽位不作世界身份')
    visible,capacity,bytes_per_slot,idle_capacity=80,128,80,64
    check((visible*bytes_per_slot,capacity*bytes_per_slot,(capacity*2+idle_capacity)*bytes_per_slot)
          ==(6400,10240,25600),
          '假定每槽80字节示例：可见6400，已分配10240，含等容量暂存和空闲25600；实际格式/上传开销仍须实测')
    negatives=[
        (lambda row:row.update(membership='all_hospital_parts'), '离屏和其他楼层常驻实例'),
        (lambda row:row.update(group_key=['species_id','color']), '种族同色代替资源相容性'),
        (lambda row:row.update(eligibility='all_skinned_actors'), '强行合批原骨骼'),
        (lambda row:row.update(unsupported='hide_unbatchable_part'), '不兼容部件消失'),
        (lambda row:row.update(alpha_blend='unsorted_shared_batch'), '透明失去逐对象排序'),
        (lambda row:row.update(shared_material_mutation=True), '实例染色串到共享材料'),
        (lambda row:row.update(visible_layout='stale_holes_drawn'), '旧槽残留被画成当前成员'),
        (lambda row:row['slot_binding_key'].remove('slot_index'), '同代次换槽漏旧绑定'),
        (lambda row:row.update(attach_parameters='old_request_pose'), '迟到旧位置覆盖当前人物'),
        (lambda row:row.update(draw_cost_source='batch_count_only'), '纸面批数冒充引擎调用'),
        (lambda row:row.update(unused_capacity_accounted=False), '未用缓冲容量隐去'),
        (lambda row:row.update(snapshot_state=True), '批槽写入世界保存'),
        (lambda row:row.update(changes_simulation=True), '合批改变实际医疗')]
    for mutate,label in negatives:
        broken=copy.deepcopy(b);mutate(broken['visual_batching'])
        try:validate_visual_batching(broken)
        except ValueError:check(True,'可见合批合同负例被拒绝：'+label)
        else:raise ValueError('invalid visual batching contract accepted: '+label)


def validate_spatial_view(b: dict) -> None:
    validate_camera_view(b)
    validate_visual_batching(b)
    v = b['spatial_view']
    require(v == {
        'chunk_cells':[16,16],'scope':'current_floor_frustum_and_explicit_preview',
        'membership':'actual_display_envelope_overlap','entity_instance_key':'logical_entity_id_per_view',
        'static_revision_source':'relevant_geometry_or_material_commit',
        'dynamic_pose_source':'current_world_state_no_static_rebuild',
        'prefetch_ring_chunks':1,'prefetch_priority':'after_visible_and_selected','prefetch_instantiates':False,
        'request_key':['hospital_session','view_id','view_generation','floor_id','chunk',
                       'local_visual_revision','content_fingerprint','lod'],
        'late_result':'discard_unmatched_bindings','retire_old_floor':'detach_before_attach_new',
        'lod_pixels':'camera_view.native_projected_cell_metric','detail_enter_px':24,'detail_leave_px':20,
        'selected_visible_detail':True,'interaction_source':'logical_spatial_index_and_real_bounds',
        'view_build_budget_ms_per_frame':2,'view_chunk_starts_per_frame':2,
        'single_chunk_work':'incremental_objects_not_atomic_whole_chunk',
        'budget_includes':'instances_bindings_geometry_upload_and_retire',
        'snapshot_state':False,'changes_simulation':False}
        and all(type(v[k]) is bool for k in ('prefetch_instantiates','selected_visible_detail',
                                             'snapshot_state','changes_simulation'))
        and all(type(n) is int for n in v['chunk_cells']),
        'spatial view scans whole floors, misses bounds, duplicates entities or changes world facts')
    s = b['performance_targets']['spatial_samples']
    require(set(s) == {'wide_floor','wide_tall','camera_sequence','cache_modes','metrics_source','count_source',
                       'minimum_dense_sample_real_seconds','minimum_density_bp','fake_submesh_counts'},
            'spatial performance fixture lacks declared scope or count evidence')
    wide = s['wide_floor']
    require(wide == {'logical_size_cells':[96,96],'owned_plots':9,'active_floor':1,'actors':[160,640],
                     'rooms':64,'stations':128,'props':1200,
                     'layout_requirement':'actual_entities_with_legal_routes_and_body_fit'},
            'wide-floor fixture lacks full owned area, actual content or legal body routes')
    tall = s['wide_tall']
    require(set(tall) == {'completed_top_floor_per_plot','active_floors','actors','structure_expand'}
            and tall['completed_top_floor_per_plot'] == 10000 and tall['actors'] == 640
            and tall['structure_expand'] == 'never_all_empty_floors'
            and {1,10,1000,10000} <= set(tall['active_floors'])
            and len(tall['active_floors']) == len(set(tall['active_floors']))
            and all(type(f) is int and 1 <= f <= tall['completed_top_floor_per_plot'] for f in tall['active_floors']),
            'wide-tall fixture expands empty structure or omits distant active floors')
    require(s['camera_sequence'] == ['near_full_working_area','far_whole_floor','pan_both_axes',
                                    'repeated_zoom_thresholds','switch_active_floors','edit_local_geometry_during_view_load']
            and s['cache_modes'] == ['cold','warm','forced_eviction']
            and s['metrics_source'] == 'same_primary_frame_simulation_response_and_memory_targets'
            and s['count_source'] == 'actual_logical_entities_and_visible_instances_logged_separately'
            and s['fake_submesh_counts'] is False,
            'spatial benchmark hides camera/cache stress, real counts or original acceptance targets')
    require(type(s['minimum_density_bp']) is int and 9000 <= s['minimum_density_bp'] <= 10000
            and type(s['minimum_dense_sample_real_seconds']) in (int,float)
            and 60 <= s['minimum_dense_sample_real_seconds'] <= b['performance_targets']['capture']['sample_real_seconds'],
            'spatial benchmark claims dense performance from an empty or brief sample')


def spatial_chunks_example(rect, b):
    x0,y0,x1,y1 = rect
    if x1 <= x0 or y1 <= y0:
        return []
    width,height = b['spatial_view']['chunk_cells']
    return [(x,y) for y in range(math.floor(y0/height),math.ceil(y1/height))
            for x in range(math.floor(x0/width),math.ceil(x1/width))]


def spatial_lod_example(cell_px, previous, selected_visible, b):
    v = b['spatial_view']
    if selected_visible:
        return 'detail'
    if previous == 'detail':
        return 'overview' if cell_px <= v['detail_leave_px'] else 'detail'
    return 'detail' if cell_px >= v['detail_enter_px'] else 'overview'


def spatial_request_example(result, current, b):
    return (isinstance(result,dict) and isinstance(current,dict)
            and all(k in result and k in current and result[k] == current[k]
                    for k in b['spatial_view']['request_key']))


def check_spatial_view_examples(c: dict, b: dict) -> None:
    from validate_care import rejects
    check(len(spatial_chunks_example((0,0,96,96),b)) == 36,
          '96乘96满层分成36个16乘16显示块，不按楼层乘出整世界显示树')
    check(spatial_chunks_example((0,0,16,16),b) == [(0,0)],
          '半开显示范围在16格边界不多请求一个块')
    check(spatial_chunks_example((15,15,15,16),b) == []
          and spatial_chunks_example((0,0,16,0),b) == [], '空显示范围不建立块或预取待办')
    chunks = spatial_chunks_example((15,15,17,17),b)
    candidates = [('same_actual_entity',chunk) for chunk in chunks]
    check(len(chunks) == 4 and len({entity for entity,chunk in candidates}) == 1,
          '跨四块的大型对象索引有四处引用，实体和可见实例仍去重为一份')
    check([spatial_lod_example(px,prior,selected,b) for px,prior,selected in
           [(24,None,False),(22,'detail',False),(22,'overview',False),(20,'detail',False),(5,'overview',True)]]
          == ['detail','detail','overview','overview','detail'],
          '24进入20退出的镜头细节滞回保持稳定，选中可见对象保留完整表现')
    current = dict(hospital_session='A',view_id='main',view_generation=2,floor_id=10000,
                   chunk=[0,0],local_visual_revision=3,content_fingerprint='current',lod='detail')
    check(spatial_request_example(current,current,b)
          and not spatial_request_example(current,None,b)
          and all(not spatial_request_example(current | change,current,b) for change in
                  [{'floor_id':1},{'hospital_session':'B'},{'view_id':'preview'},
                   {'local_visual_revision':2},{'lod':'overview'}]),
          '同XY旧楼层、医院、预览、几何和细节请求均不能绑定当前显示块')
    density = b['performance_targets']['spatial_samples']['minimum_density_bp']
    check([math.ceil(n*Fraction(density,10000)) for n in (160,640)] == [144,576],
          '160与640档密集区间至少144与576真实角色，子网格不能补人数')
    rejects(c,b,validate_performance_targets,check,[
        (lambda x,y:y['spatial_view'].update(membership='anchor_center_only'), '只看中心漏掉跨块身体'),
        (lambda x,y:y['spatial_view'].update(interaction_source='rendered_proxy_colliders'), '远景网格改变实际选择与建造'),
        (lambda x,y:y['spatial_view'].update(snapshot_state=True), '显示任务写入世界快照'),
        (lambda x,y:y['spatial_view'].update(scope='all_completed_floors'), '已建空层预建显示树'),
        (lambda x,y:y['spatial_view']['request_key'].remove('floor_id'), '显示请求混淆同XY楼层'),
        (lambda x,y:y['spatial_view']['request_key'].remove('lod'), '旧细节资源绑定新视图需求'),
        (lambda x,y:y['spatial_view'].update(prefetch_instantiates=True), '预取圈偷偷常驻显示实例'),
        (lambda x,y:y['spatial_view'].update(single_chunk_work='atomic_whole_chunk'), '分帧预算隐藏单块长操作'),
        (lambda x,y:y['performance_targets']['spatial_samples'].update(fake_submesh_counts=True), '子网格假冒真实负载'),
        (lambda x,y:y['performance_targets']['spatial_samples'].update(minimum_density_bp=1000), '空院片段冒充640人密集性能')])


def validate_skin_pose_instancing(b: dict) -> None:
    expected={
        'scope':'verified_opaque_or_cutout_skinned_parts_in_current_view',
        'enable':'after_reference_backend_and_adapter_validation_only',
        'validation_key':['engine_version','renderer','device_id','driver_version','content_fingerprint',
            'skin_adapter_key','shader_fingerprint','palette_format','instance_parameter_layout'],
        'validation_source':'engine_and_asset_validation_evidence_not_content_flag',
        'unverified':'original_current_per_entity_skinning',
        'pose_source':'pose_sampling_original_model_local_skin_matrices','additional_pose_evaluation':False,
        'prepared_mesh':'original_rest_geometry_and_validated_bind_attributes_without_automatic_skinning',
        'eligibility':'verified_rigid_bone_transforms_four_weights_no_morph_or_alpha_blend',
        'palette':{'bone_limit':40,'weights_per_vertex_limit':4,'texels_per_bone':3,
            'channels_per_texel':4,'bytes_per_channel':4,
            'format':'RGBAF32_linear_data_nearest_no_mip_no_color_conversion',
            'width':'next_power_of_two_at_least_three_times_actual_bones','max_rows_per_page':64,
            'height':'smallest_power_of_two_for_current_page_members',
            'instance_row_channel':'INSTANCE_CUSTOM_x_local_exact_row_only'},
        'group_key':'visual_batching_resource_key_plus_skin_adapter_shader_and_palette_page',
        'row_key':['hospital_session','view_id','view_generation','floor_id','palette_page_key','page_generation',
            'row_index','row_generation','logical_entity_id','part_role','skin_adapter_key','pose_source_key',
            'pose_sample_generation','content_fingerprint'],
        'publication':'complete_staged_page_and_current_row_bindings_before_draw',
        'late_rows':'reject_mismatched_binding_then_current_pose_or_original_pipeline',
        'shader_deformation':'once_in_model_space_then_original_world_transform_and_render_passes',
        'main_shadow_pose':'same_current_palette_and_original_lighting_rules',
        'bounds_and_picking':'original_logical_actual_envelope_not_rest_mesh_aabb',
        'member_source':'original_current_visible_unique_parts_no_entity_cap',
        'upload_accounting':'actual_full_allocated_page_transfers_not_dirty_row_estimate',
        'memory_scope':'original_cpu_gpu_working_set_current_staging_and_pending_release_pages',
        'work_budget':'original_frame_cost_and_shared_spatial_view_build_budget',
        'adapter_position_error_m_max':0.005,'adapter_normal_tangent_error_degrees_max':1,
        'unknown_validation':'original_pipeline_no_equivalence_or_performance_claim',
        'snapshot_state':False,'changes_simulation':False,'capability_validation_available':False,
        'runtime_measurement_available':False}
    row=b['skin_pose_instancing']
    require(set(row)==set(expected) and all(type(row[key]) is type(value) and row[key]==value
            for key,value in expected.items()), 'skin pose instancing loses original bodies or hides unverified costs')
    require(all(type(row['palette'][key]) is type(value) for key,value in expected['palette'].items()),
            'bone palette numeric fields must retain declared types')


def skin_palette_size_example(members: int, bones: int, b: dict) -> dict:
    # Closed-form declared page arithmetic, not GPU allocation or transfer measurement.
    p=b['skin_pose_instancing']['palette']
    require(type(members) is int and members>=0 and type(bones) is int and 1<=bones<=p['bone_limit'],
            'invalid bone palette size fixture')
    used_width=bones*p['texels_per_bone']; width=1<<(used_width-1).bit_length()
    full,tail=divmod(members,p['max_rows_per_page'])
    tail_rows=1<<(tail-1).bit_length() if tail else 0
    allocated_rows=full*p['max_rows_per_page']+tail_rows
    texel_bytes=p['channels_per_texel']*p['bytes_per_channel']
    allocated_bytes=width*allocated_rows*texel_bytes
    return {'width':width,'pages':full+bool(tail),'allocated_rows':allocated_rows,
            'used_matrix_bytes':members*used_width*texel_bytes,
            'allocated_bytes':allocated_bytes,'current_and_staging_bytes':allocated_bytes*2}


def skin_row_matches_example(first,second,b: dict) -> bool:
    keys=b['skin_pose_instancing']['row_key']
    return (isinstance(first,dict) and isinstance(second,dict) and all(key in first and key in second for key in keys)
            and all(type(row['row_index']) is int and 0<=row['row_index']<b['skin_pose_instancing']['palette']['max_rows_per_page']
                    for row in (first,second))
            and all(first[key]==second[key] for key in keys))


def skin_adapter_eligible_example(asset,b: dict) -> bool:
    # Hypothetical verified input only; booleans do not prove actual backend or asset validation.
    p=b['skin_pose_instancing']['palette']
    return (isinstance(asset,dict) and asset.get('backend_verified') is True and asset.get('adapter_verified') is True
            and asset.get('pipeline') in ('opaque','cutout') and asset.get('rigid_bones') is True
            and asset.get('morph') is False and asset.get('automatic_skinning') is False
            and type(asset.get('bones')) is int and 1<=asset['bones']<=p['bone_limit']
            and type(asset.get('weights')) is int and 1<=asset['weights']<=p['weights_per_vertex_limit'])


def check_skin_pose_instancing_examples(b: dict) -> None:
    size=skin_palette_size_example(640,40,b)
    check(size=={'width':128,'pages':10,'allocated_rows':640,'used_matrix_bytes':1228800,
                 'allocated_bytes':1310720,'current_and_staging_bytes':2621440},
          '40骨640行10页的原始矩阵/分配/双份字节区分，非真实GPU分配')
    sixtyfour=skin_palette_size_example(64,40,b); sixtyfive=skin_palette_size_example(65,40,b)
    check(sixtyfour['pages']==1 and sixtyfive['pages']==2 and sixtyfive['allocated_rows']==65
          and sixtyfive['allocated_bytes']==133120, '第65成员分下一页，不截角色；最小尾页不预建64满行')
    check(skin_palette_size_example(0,40,b)['pages']==0
          and skin_palette_size_example(0,40,b)['allocated_bytes']==0
          and skin_palette_size_example(1,1,b)['width']==4, '无成员不分配页，宽按真实骨数向2次幂取整')
    check(size['allocated_bytes']*60==78643200 and size['allocated_bytes']*60>size['used_matrix_bytes']*30,
          '假设全页每60帧上传为78643200字节每秒，dirty行/30Hz不能冒充实际传输')
    values=[struct.unpack('e',struct.pack('e',float(row)))[0] for row in range(64)]
    check(values==list(range(64)) and struct.unpack('e',struct.pack('e',2049.0))[0]!=2049,
          'IEEE半精度示意局部0…63精确而2049丢精度，未验证真实Compatibility custom数据')
    asset={'backend_verified':True,'adapter_verified':True,'pipeline':'opaque','rigid_bones':True,
           'morph':False,'automatic_skinning':False,'bones':40,'weights':4}
    check(skin_adapter_eligible_example(asset,b), '假设完整验收的刚性40骨4权重输入符合路线，标记自身不是实际验收证据')
    for key,value,label in [('backend_verified',False,'后端未验'),('adapter_verified',False,'正式适配未验'),
        ('pipeline','alpha_blend','透明排序'),('rigid_bones',False,'非均匀骨变换'),('morph',True,'形态变形'),
        ('automatic_skinning',True,'叠自动骨变形'),('bones',41,'超过矩阵骨容量'),('weights',8,'八权重'),('bones',True,'布尔骨数')]:
        invalid=copy.deepcopy(asset); invalid[key]=value
        check(not skin_adapter_eligible_example(invalid,b), '专用路线不支持仍走原身体管线：'+label)
    row={'hospital_session':'hospital:1','view_id':'main','view_generation':8,'floor_id':'floor:1',
        'palette_page_key':'page:4','page_generation':2,'row_index':3,'row_generation':19,
        'logical_entity_id':'actor:17','part_role':'body','skin_adapter_key':('rig:biped','bind:v2'),
        'pose_source_key':('service:9','working'),'pose_sample_generation':36,'content_fingerprint':'core:v1'}
    check(skin_row_matches_example(row,copy.deepcopy(row),b), '矩阵行完整原绑定可匹配，不运行shader或写世界')
    for key in b['skin_pose_instancing']['row_key']:
        changed=copy.deepcopy(row); changed[key]=('different',key)
        check(not skin_row_matches_example(row,changed,b), '旧矩阵不能跨错误行/原姿态身份：'+key)
    check(not skin_row_matches_example(row,None,b) and not skin_row_matches_example(row,{},b),
          '无当前完整行身份不能采迟到页数据')
    for index,label in [(64,'页外行'),(-1,'负行'),(True,'布尔行'),(3.0,'浮点行声明')]:
        invalid_row=copy.deepcopy(row); invalid_row['row_index']=index
        check(not skin_row_matches_example(invalid_row,invalid_row,b), '同一非法行索引也不能允许采样：'+label)
    for members,bones,label in [(-1,40,'负成员'),(1,0,'零骨'),(1,41,'超过本适配骨容量'),(True,40,'布尔成员')]:
        try:skin_palette_size_example(members,bones,b)
        except ValueError:check(True,'骨页非法算例声明被拒绝：'+label)
        else:raise ValueError('invalid palette fixture accepted '+label)
    for mutate,label in [
        (lambda row:row.update(enable='enabled_from_same_mesh_id'),'未经正式验证启用'),
        (lambda row:row.update(validation_key=['content_fingerprint']),'旧引擎驱动验证沿用'),
        (lambda row:row.update(validation_source='content_verified_flag_only'),'内容自报标记代替验收'),
        (lambda row:row.update(unverified='hide_body'),'未知资产隐藏身体'),
        (lambda row:row.update(additional_pose_evaluation=True),'第二动画评估时钟'),
        (lambda row:row['palette'].update(format='sRGB_RGBA8_linear_filtered'),'矩阵当颜色插值'),
        (lambda row:row['palette'].update(instance_row_channel='float_world_actor_id'),'实体ID塞半精度'),
        (lambda row:row.update(group_key='species_only'),'种族替代inverse_bind相容'),
        (lambda row:row.update(publication='old_partial_rows_with_new_members'),'旧新行混拼'),
        (lambda row:row.update(shader_deformation='automatic_then_shader_skinning'),'双重变形'),
        (lambda row:row.update(main_shadow_pose='different_cached_palettes'),'阴影与主体姿态不同'),
        (lambda row:row.update(bounds_and_picking='rest_mesh_aabb'),'小rest框删伸展身体'),
        (lambda row:row.update(member_source='first_64_visible_actors'),'第一页变角色上限'),
        (lambda row:row.update(upload_accounting='dirty_rows_times_30hz_only'),'低报整页上传'),
        (lambda row:row.update(unknown_validation='assume_screenshot_equivalent'),'未测等价性冒充通过'),
        (lambda row:row.update(snapshot_state=True),'矩阵行存世界'),
        (lambda row:row.update(changes_simulation=True),'shader结算医疗'),
        (lambda row:row.update(capability_validation_available=True),'规格宣称后端已验证'),
        (lambda row:row.update(runtime_measurement_available=True),'页算术假冒实测')]:
        invalid=copy.deepcopy(b); mutate(invalid['skin_pose_instancing'])
        try:validate_skin_pose_instancing(invalid)
        except ValueError:check(True,'独立骨矩阵合同负例被拒绝：'+label)
        else:raise ValueError('invalid skin pose contract accepted '+label)


def validate_preview_computation(b: dict) -> None:
    expected = {
        'scope':'original_active_build_move_blueprint_and_tryout_preview',
        'semantic_generation':'draft_geometry_binding_subject_and_options_changes_not_pointer_pixels_or_world_tick',
        'current_jobs':1,'pending_requests':1,'coalescing':'latest_semantic_request_in_original_preview_session',
        'superseded_job':'stop_at_next_safe_slice_and_release_original_references',
        'feedback':'current_original_outline_and_explicit_not_ready_until_complete',
        'old_ready_state':'revoke_on_semantic_request_or_relevant_fact_change',
        'request_key':['hospital_session','view_id','view_generation','view_floor_id','preview_session_id','draft_id','draft_generation',
            'source_floor_ids','target_floor_id','content_fingerprint','query_kind','subject_identity','traversal_envelope','query_options'],
        'view_change':'rebind_current_projection_reusing_valid_original_semantic_result',
        'draw_scope':'current_view_floor_equals_original_draft_target_floor',
        'dependencies':'complete_original_relevant_semantic_facts_not_global_revision',
        'empty_region_watch':'new_actual_body_geometry_or_reservation_entering_original_query_scope',
        'whole_reachability':'original_full_required_query_domain_not_local_only_permission',
        'readonly_context':'original_required_values_not_entire_world_deep_copy',
        'execution':'main_thread_no_worker_reads_of_live_world_or_shared_mutable_graph',
        'cross_slice_consistency':'same_complete_relevant_facts_or_restart_original_query',
        'unknown_dependencies':'original_complete_main_thread_query_no_ready_claim_from_partial_data',
        'publication':'whole_complete_matching_request_and_current_dependency_proof',
        'work_budget':'spatial_view.view_build_budget_ms_per_frame',
        'atomic_overrun':'record_actual_frame_cost_not_hidden_or_free_operation',
        'confirmation':'original_explicit_action_then_current_atomic_recheck_no_queued_auto_confirm',
        'business_queue_used':False,'creates_actor_or_reservation':False,
        'metrics':'original_latency_and_frame_targets_with_pending_superseded_and_overrun_records',
        'memory_scope':'original_working_set_current_result_active_pending_and_retiring_preview_values',
        'snapshot_state':False,'changes_simulation':False,'runtime_measurement_available':False}
    row=b['preview_computation']
    require(set(row)==set(expected) and all(type(row[key]) is type(value) and row[key]==value
            for key,value in expected.items()), 'preview computation accepts stale permission or changes original commands')


def preview_request_matches_example(result_request, current_request, b: dict) -> bool:
    keys=b['preview_computation']['request_key']
    return (isinstance(result_request,dict) and isinstance(current_request,dict)
            and all(key in result_request and key in current_request for key in keys)
            and all(result_request[key]==current_request[key] for key in keys))


def preview_draws_on_view_example(request) -> bool:
    return (isinstance(request,dict) and 'view_floor_id' in request and 'target_floor_id' in request
            and type(request['view_floor_id']) is str and bool(request['view_floor_id'])
            and request['view_floor_id']==request['target_floor_id'])


def preview_publication_example(result_request, current_request, result_complete,
                                dependencies_complete, captured, current, b: dict) -> bool:
    # Only synthetic identity/value guards; this does not prove any real query handler's dependency coverage.
    return (result_complete is True and dependencies_complete is True
            and isinstance(captured,dict) and bool(captured) and isinstance(current,dict)
            and preview_request_matches_example(result_request,current_request,b)
            and all(key in current and value==current[key] for key,value in captured.items()))


def check_preview_computation_examples(b: dict) -> None:
    request={'hospital_session':'hospital:1','view_id':'main','view_generation':7,'view_floor_id':'floor:1',
        'preview_session_id':'preview:4','draft_id':'draft:3','draft_generation':18,
        'source_floor_ids':('floor:1',),'target_floor_id':'floor:1','content_fingerprint':'core:1',
        'query_kind':'room_move','subject_identity':'actor:9','traversal_envelope':(1,1,180),
        'query_options':('normal_move','original_inventory','original_access')}
    original=copy.deepcopy(request)
    check(preview_request_matches_example(request,copy.deepcopy(request),b), '同当前请求的整份预览身份可匹配，静态守卫非真实空间查询')
    unrelated=copy.deepcopy(request); unrelated['world_revision']=9000; unrelated['pointer_pixels']=(710,230)
    check(preview_request_matches_example(request,unrelated,b), '无关世界修订/同格像素不替换当前草案身份')
    facts={'target_floor_geometry':12,'body_occupancy_scope':4,'original_required_reachability':9,
           'fixed_price_quote':800,'cash_sufficient_for_fixed_price':True,'original_inventory_owner':'object:17'}
    current=copy.deepcopy(facts); current['unrelated_other_floor_work']=42
    check(preview_publication_example(request,request,True,True,facts,current,b),
          '完整声明且当前相干值一致的示意可发布，无关额外值不使草案永久过期')
    rebound=copy.deepcopy(request); rebound['view_generation']=8
    check(not preview_publication_example(request,rebound,True,True,facts,current,b)
          and preview_publication_example(rebound,rebound,True,True,facts,current,b),
          '旧显示拒绝新绑定，相同原语义依据可当前重绑；守卫不证明真实结果缓存或投影实现')
    other_floor=copy.deepcopy(rebound); other_floor['view_floor_id']='floor:10000'
    check(preview_draws_on_view_example(request) and not preview_draws_on_view_example(other_floor),
          '原目标1F草案只在观察1F画地图叠加，观察10000F不把原物件串层')
    check(preview_publication_example(other_floor,other_floor,True,True,facts,current,b)
          and not preview_draws_on_view_example({}) and not preview_draws_on_view_example(None),
          '有效原层语义信息可留草案栏，与别层地图绘制分开；未知层不绘制')
    check(not preview_publication_example(request,request,False,True,facts,current,b)
          and not preview_publication_example(request,request,True,False,facts,current,b),
          '部分结果/未知完整依赖不输出就绪，不由true标记证明真实处理器覆盖')
    check(not preview_publication_example(request,request,True,True,None,current,b)
          and not preview_publication_example(request,request,True,True,{},current,b),
          '无相干依据或空依据不声称完整预检')
    occupied=copy.deepcopy(current); occupied['body_occupancy_scope']=5
    check(not preview_publication_example(request,request,True,True,facts,occupied,b),
          '原空区域后来身体进入的范围修订使旧就绪撤销，不能只看旧命中对象')
    missing=copy.deepcopy(current); del missing['original_required_reachability']
    check(not preview_publication_example(request,request,True,True,facts,missing,b),
          '缺必需全域安全依据不能把局部通过当整院安全')
    check(request==original, '预览身份/依据守卫只读源值，不建立预约或修改草案')
    for key in b['preview_computation']['request_key']:
        changed=copy.deepcopy(request); changed[key]=('different',key)
        check(not preview_request_matches_example(request,changed,b), '预览旧结果不能跨错误请求身份：'+key)
    check(not preview_request_matches_example(request,None,b)
          and not preview_request_matches_example(request,{},b), '无当前预览请求不能绑定迟到结果')
    for mutate,label in [
        (lambda row:row.update(semantic_generation='every_pointer_pixel_or_world_tick'),'同格微移永远取消'),
        (lambda row:row.update(pending_requests=1000),'鼠标轨迹积长队'),
        (lambda row:row.update(feedback='keep_previous_green_until_ready'),'旧草案绿色贴新格'),
        (lambda row:row.update(view_change='rescan_whole_world_for_camera_only'),'镜头变化又全院重算'),
        (lambda row:row.update(draw_scope='any_current_view_floor'),'原草案画错楼层'),
        (lambda row:row.update(dependencies='global_revision_only'),'世界tick频繁拒绝'),
        (lambda row:row.update(empty_region_watch='old_hits_only'),'漏新进入者'),
        (lambda row:row.update(whole_reachability='draft_neighbors_only'),'局部当全域安全'),
        (lambda row:row.update(readonly_context='copy_entire_world_for_each_pointer'),'每次拖动复制全院'),
        (lambda row:row.update(execution='worker_reads_live_astar_world'),'后台竞争活跃图'),
        (lambda row:row.update(publication='merge_old_price_with_new_partial_geometry'),'混拼旧新检查'),
        (lambda row:row.update(confirmation='auto_apply_when_finished'),'排自动确认'),
        (lambda row:row.update(business_queue_used=True),'预览占Actor移动额度'),
        (lambda row:row.update(creates_actor_or_reservation=True),'试试看造临床预约'),
        (lambda row:row.update(metrics='outline_only_or_time_from_worker_start'),'隐藏挂起当通过'),
        (lambda row:row.update(snapshot_state=True),'任务保存进世界'),
        (lambda row:row.update(changes_simulation=True),'预览推进业务'),
        (lambda row:row.update(runtime_measurement_available=True),'静态守卫冒充延迟实测')]:
        invalid=copy.deepcopy(b); mutate(invalid['preview_computation'])
        try:validate_preview_computation(invalid)
        except ValueError:check(True,'建造预览合同负例被拒绝：'+label)
        else:raise ValueError('preview computation contract accepted '+label)


def validate_pose_sampling(b: dict) -> None:
    expected = {
        'scope':'current_visible_actor_rig_bindings_and_explicit_previews',
        'near_hz':30,'far_hz':15,'clock':'hospital_view_monotonic_real_time',
        'rate_source':'spatial_view_lod_and_selected_visible_detail',
        'phase_key':['hospital_session','logical_entity_id'],'phase_bins':1024,
        'phase_hash':'sha256_utf8_length_prefixed_identity_first_u64_be_mod_bins',
        'due_storage':'sparse_current_visible_continuous_bindings_only',
        'next_due':'next_original_phase_grid_point_strictly_after_now',
        'late_samples':'latest_current_pose_once_no_catch_up',
        'pose_source':'original_stage_progress_and_reservation_envelope',
        'evaluation_owner':'single_pose_sampler_no_parallel_automatic_animation_advance',
        'root_transform':'per_frame_original_legal_movement_interpolation',
        'discontinuity':'invalidate_before_draw_and_read_current_original_pose',
        'refresh_coalescing':'one_latest_original_pose_per_binding_per_render_frame',
        'paused_or_static':'no_repeated_sampling_until_pose_source_or_camera_input_changes',
        'low_motion':'current_authorized_static_pose_on_source_change',
        'reentry':'current_pose_without_ended_animation_replay',
        'reuse':'exact_rig_pose_source_mode_and_registered_camera_inputs_only',
        'reuse_key':['hospital_session','logical_entity_id','rig_resource','pose_source_key','pose_mode','camera_pose_key'],
        'shared_rate':'highest_current_compatible_view_requirement',
        'independent_actors_share_phase_state':False,
        'late_binding':'original_visual_identity_check_then_requery_current_pose',
        'continuous_cost':'original_full_frame_targets_not_free_work',
        'binding_budget':'spatial_view.view_build_budget_ms_per_frame',
        'actor_count_cap':None,'snapshot_state':False,'changes_simulation':False,
        'business_random_used':False,'runtime_measurement_available':False}
    row = b['pose_sampling']
    require(set(row) == set(expected) and all(type(row[k]) is type(v) and row[k] == v
            for k,v in expected.items()), 'pose sampling duplicates clocks, hides state or changes simulation')


def pose_identity_bytes_example(identity) -> bytes:
    require(type(identity) in (list,tuple) and len(identity) == 2
            and all(type(v) is str and v for v in identity), 'invalid visual phase identity')
    encoded = [value.encode('utf-8') for value in identity]
    return b''.join(len(value).to_bytes(8,'big')+value for value in encoded)


def pose_phase_example(identity, b: dict) -> int:
    return int.from_bytes(hashlib.sha256(pose_identity_bytes_example(identity)).digest()[:8],'big') % b['pose_sampling']['phase_bins']


def next_pose_due_example(now, hz: int, phase: int = 0, bins: int = 1024) -> Fraction:
    # Rational phase-grid arithmetic, not an animation controller or game scheduler.
    require(type(now) in (int,Fraction) and now >= 0 and type(hz) is int and hz > 0
            and type(bins) is int and bins > 0 and type(phase) is int and 0 <= phase < bins,
            'invalid pose sampling time or phase')
    t = Fraction(now); p = Fraction(phase,bins)
    return (math.floor(t*hz-p)+1+p)/hz


def pose_reuse_matches_example(first, second, b: dict) -> bool:
    keys = b['pose_sampling']['reuse_key']
    return (isinstance(first,dict) and isinstance(second,dict) and all(key in first and key in second for key in keys)
            and all(first[key] == second[key] for key in keys))


def check_pose_sampling_examples(b: dict) -> None:
    check(next_pose_due_example(0,30) == Fraction(1,30)
          and next_pose_due_example(Fraction(1,5),30) == Fraction(7,30), '30Hz原相位到期0.2秒后7/30，不连补旧采样')
    check(next_pose_due_example(0,30,512) == Fraction(1,60)
          and next_pose_due_example(Fraction(1,5),30,512) == Fraction(13,60), '512/1024错相位保持原格，下一时刻严格晚于现在')
    check(next_pose_due_example(Fraction(1,5),15) == Fraction(4,15)
          and next_pose_due_example(Fraction(18001,5),30) == 3600+Fraction(7,30), '15Hz对照与一小时后相位不因周期截断漂移')
    check(all(next_pose_due_example(t,hz,phase) > t for t in (0,Fraction(1,5),3600)
              for hz in (15,30) for phase in (0,512,1023)), '全部边界下一相位严格在当前之后，错过周期仅重排当前一次')
    identity = ['hospital:甲','actor:18']; original = identity.copy()
    phase = pose_phase_example(identity,b)
    check(0 <= phase < 1024 and phase == pose_phase_example(identity,b) and identity == original
          and pose_identity_bytes_example(['ab','c']) != pose_identity_bytes_example(['a','bc']),
          'UTF8字节长度前缀散列稳定只读，字段拼接不混身份；相位碰撞不是业务共享')
    binding = {'hospital_session':'hospital:甲','logical_entity_id':'actor:18','rig_resource':'biped:v1',
               'pose_source_key':('service:7','working',12),'pose_mode':'standard','camera_pose_key':None}
    check(pose_reuse_matches_example(binding,copy.deepcopy(binding),b), '相同实体骨架/原阶段/模式/镜头输入可复用只读结果')
    check(640*b['pose_sampling']['near_hz'] == 19200 and 640*b['pose_sampling']['far_hz'] == 9600,
          '640连续绑定19200/9600次每现实秒仅理论，不含离散刷新且不证明帧率')
    for key in b['pose_sampling']['reuse_key']:
        changed = copy.deepcopy(binding); changed[key] = ('different',key)
        check(not pose_reuse_matches_example(binding,changed,b), '角色姿态不能跨错误复用键：'+key)
    check(not pose_reuse_matches_example(binding,None,b)
          and not pose_reuse_matches_example(binding,{},b), '缺失姿态来源不视作兼容')
    for now,hz,phase,bins,label in [(-1,30,0,1024,'负时间'),(0,0,0,1024,'零频率'),
        (0,30,1024,1024,'越界相位'),(0,30,0,0,'零相位箱'),(True,30,0,1024,'布尔时间')]:
        try:next_pose_due_example(now,hz,phase,bins)
        except ValueError:check(True,'角色采样非法声明被拒绝：'+label)
        else:raise ValueError('pose sampling accepted '+label)
    for mutate,label in [
        (lambda row:row.update(near_hz=90),'3倍变90Hz'),
        (lambda row:row.update(clock='simulation_ticks'),'模拟步驱动全骨架'),
        (lambda row:row.update(due_storage='every_actor_every_floor'),'全院动画任务'),
        (lambda row:row.update(late_samples='evaluate_all_missed_cycles'),'补演每个错过周期'),
        (lambda row:row.update(evaluation_owner='automatic_and_manual'),'骨架双重自动推进'),
        (lambda row:row.update(root_transform='bone_sample_clock'),'低频拖根位置'),
        (lambda row:row.update(discontinuity='wait_until_next_far_sample'),'旧身体延后撤掉'),
        (lambda row:row.update(refresh_coalescing='evaluate_every_intermediate_event'),'同帧重复算旧骨架'),
        (lambda row:row.update(paused_or_static='continuous_free_running'),'暂停还全员评骨架'),
        (lambda row:row.update(shared_rate='lowest_view_rate'),'远景拖低近景'),
        (lambda row:row.update(independent_actors_share_phase_state=True),'同种族共用业务阶段'),
        (lambda row:row.update(actor_count_cap=400),'每帧演员截断'),
        (lambda row:row.update(snapshot_state=True),'采样时钟保存进世界'),
        (lambda row:row.update(business_random_used=True),'消耗临床随机'),
        (lambda row:row.update(changes_simulation=True),'采样推进医疗'),
        (lambda row:row.update(runtime_measurement_available=True),'频率算术假装本机通过')]:
        invalid = copy.deepcopy(b); mutate(invalid['pose_sampling'])
        try:validate_pose_sampling(invalid)
        except ValueError:check(True,'角色采样合同负例被拒绝：'+label)
        else:raise ValueError('pose sampling contract accepted '+label)


def validate_transparency_view(b: dict) -> None:
    expected = {
        'scope':'current_scene_and_explicit_previews_separately_total_frame_cost',
        'material_source':'actual_imported_pipeline_not_species_or_visual_name',
        'coverage_target_bp':2000,
        'coverage_metric':'union_fragment_entry_pixels_over_actual_scene_pixels',
        'layer_load_metric':'fragment_entry_samples_over_actual_scene_sample_capacity',
        'layer_load_limit':None,
        'sample_normalization':'actual_sample_count_for_each_view',
        'pipeline_scope':'all_actual_transparent_blend_modes_particles_refraction_and_soft_shadows',
        'zero_alpha_work_counted':True,
        'bbox_is_measured_coverage':False,
        'measurement':'matching_actual_pipeline_capture_or_unavailable',
        'diagnostic_capture':'separate_from_primary_timed_run_same_world_pose_camera_and_settings',
        'continuous_diagnostic_maps':False,
        'material_choices':'opaque_or_cutout_only_if_validated_equivalent_current_body_and_state',
        'required_alpha':'original_current_depth_sorting_and_validated_material',
        'unsupported':'retain_original_primary_and_report_cost',
        'degrade_scope':'existing_optional_secondary_detail_only',
        'quality_changes':'explicit_player_setting_not_automatic_blend_toggle',
        'hide_body_or_necessary_state':False,
        'additional_world_work':False,
        'snapshot_state':False,'changes_simulation':False,'runtime_measurement_available':False}
    row = b['transparency_view']
    require(set(row) == set(expected) and all(type(row[k]) is type(v) and row[k] == v
            for k,v in expected.items()), 'transparent coverage hides layers, state or unmeasured cost')


def transparency_sample_metrics_example(entries, width: int, height: int, samples: int = 1):
    # Synthetic fragment-entry samples only; never calls a renderer or creates a runtime map.
    require(all(type(v) is int and v > 0 for v in (width,height,samples)), 'invalid diagnostic view extent')
    if entries is None:
        return None
    require(type(entries) is list, 'diagnostic entries must be explicit samples or unavailable')
    pixels = set()
    for entry in entries:
        require(type(entry) in (list,tuple) and len(entry) == 3 and all(type(v) is int for v in entry),
                'invalid fragment-entry sample')
        x,y,s = entry
        require(0 <= x < width and 0 <= y < height and 0 <= s < samples,
                'fragment-entry sample belongs outside its declared view or sample capacity')
        pixels.add((x,y))
    return {'coverage_bp':Fraction(len(pixels)*10000,width*height),
            'layer_load_bp':Fraction(len(entries)*10000,width*height*samples)}


def check_transparency_view_examples(b: dict) -> None:
    base = [(x,0,0) for x in range(10)]
    original = copy.deepcopy(base)
    one = transparency_sample_metrics_example(base,10,10)
    stacked = transparency_sample_metrics_example(base*12,10,10)
    check(one == {'coverage_bp':1000,'layer_load_bp':1000}, '10像素单层并集与负载均10%，仅静态示意')
    check(stacked == {'coverage_bp':1000,'layer_load_bp':12000}, '同10像素叠12层并集10%但负载120%，不夹100%')
    multi = [(x,0,s) for x in range(10) for s in range(4)]
    check(transparency_sample_metrics_example(multi*12,10,10,4) == stacked,
          '四采样按实际容量归一，重复绘制仍逐次计叠加')
    disjoint = base+[(x,1,0) for x in range(10)]
    check(transparency_sample_metrics_example(disjoint,10,10) == {'coverage_bp':2000,'layer_load_bp':2000},
          '不相交两区并集20%，不把正常两区当同像素重叠')
    thirty = [(x,y,0) for x in range(10) for y in range(3)]
    check(transparency_sample_metrics_example(thirty,10,10)['coverage_bp'] > b['transparency_view']['coverage_target_bp'],
          '30%并集超过原20%目标，示意判线不构成GPU完成证据')
    check(transparency_sample_metrics_example(None,10,10) is None
          and transparency_sample_metrics_example([],10,10) == {'coverage_bp':0,'layer_load_bp':0},
          '未知入口数据与已声明空样本不同，不可用不填0')
    check(base == original, '透明诊断算例只读原采样，重复位置和最终alpha不抹除已声明入口')
    for entries,width,height,samples,label in [
        ([(-1,0,0)],10,10,1,'负坐标'), ([(10,0,0)],10,10,1,'错视图宽度'),
        ([(0,10,0)],10,10,1,'错视图高度'), ([(0,0,4)],10,10,4,'错采样索引'),
        ([],0,10,1,'零视口'), ([],True,10,1,'布尔冒充像素数')]:
        try:transparency_sample_metrics_example(entries,width,height,samples)
        except ValueError:check(True,'透明诊断非法声明被拒绝：'+label)
        else:raise ValueError('transparent diagnostic accepted '+label)
    for mutate,label in [
        (lambda row:row.update(coverage_target_bp=5000),'放宽原覆盖目标'),
        (lambda row:row.update(coverage_metric='window_ui_and_scene_union'),'UI稀释分母'),
        (lambda row:row.update(layer_load_metric='union_only'),'叠加只算并集'),
        (lambda row:row.update(layer_load_limit=10000),'片元负载变角色上限'),
        (lambda row:row.update(zero_alpha_work_counted=False),'忽略零alpha已发生工作'),
        (lambda row:row.update(bbox_is_measured_coverage=True),'包围框假装精确测量'),
        (lambda row:row.update(measurement='missing_equals_zero'),'未知冒充零成本'),
        (lambda row:row.update(diagnostic_capture='included_in_primary_timing'),'诊断额外通道混进计时'),
        (lambda row:row.update(continuous_diagnostic_maps=True),'常驻逐像素图'),
        (lambda row:row.update(hide_body_or_necessary_state=True),'透明患者被隐去'),
        (lambda row:row.update(quality_changes='automatic_blend_toggle'),'材质自动突变'),
        (lambda row:row.update(snapshot_state=True),'派生显示写快照'),
        (lambda row:row.update(changes_simulation=True),'成本改变临床'),
        (lambda row:row.update(runtime_measurement_available=True),'静态算例冒充实机')]:
        invalid = copy.deepcopy(b); mutate(invalid['transparency_view'])
        try:validate_transparency_view(invalid)
        except ValueError:check(True,'透明成本合同负例被拒绝：'+label)
        else:raise ValueError('transparent cost contract accepted '+label)


def validate_ui_text(b: dict) -> None:
    rules = b['ui_text']
    expected = {
        'scope': 'existing_visible_controls_and_focused_panel',
        'refresh_source': 'existing_coalesced_ui_projection',
        'unchanged_text': 'existing_control_equality_without_shadow_text_copy',
        'binding_guard': 'existing_hospital_panel_query_entity_generation',
        'same_text_updates': 'retain_nontext_properties_and_source_rebinding',
        'input_priority': 'immediate_input_ime_focus_and_command_feedback',
        'font_ownership': 'shared_readonly_engine_font_resources',
        'glyph_population': 'on_demand_visible_text_no_world_or_unicode_prewarm',
        'missing_glyph': 'preserve_text_bundled_fallback_or_visible_missing_glyph',
        'cache_policy': 'engine_owned_no_parallel_global_text_or_glyph_cache',
        'cache_release': 'backend_supported_unreferenced_resources_only',
        'graphics_accounting': 'actual_glyph_pages_buffers_loading_and_retained_old_sizes',
        'memory_accounting': 'font_faces_shaped_runs_layout_temporaries_and_actual_extra_allocations',
        'allocation_accounting': 'unique_actual_allocation_not_font_file_bytes',
        'atomic_work': 'actual_frame_cost_no_assumed_slicing',
        'ui_resolution_source': 'performance_targets.display.ui_resolution',
    }
    flags = {'snapshot_state', 'changes_simulation', 'runtime_measurement_available'}
    require(set(rules) == set(expected) | flags | {'layout_dependencies'},
            'UI text owns an unknown cache or gameplay responsibility')
    require(all(rules[key] == value for key, value in expected.items())
            and all(rules[key] is False for key in flags),
            'UI text changes input, identity, resource accounting or original business facts')
    require(rules['layout_dependencies'] == [
        'final_text', 'font_resource_and_fallback_fingerprint',
        'effective_font_size_and_ui_scale', 'available_width_and_wrap_rules',
        'language_direction_and_shaping_options'], 'text equality hides a layout change')
    require(b['performance_targets']['display']['ui_resolution'] == 'native_window'
            and b['ui_input']['ime_confirmation_passes_through'] is False
            and b['ui_lists']['command_target'] == 'captured_entity_id_revalidated',
            'text optimization contradicts native UI or original input identity')


def check_ui_text_examples(b: dict) -> None:
    check(b['ui_text']['ui_resolution_source'] == 'performance_targets.display.ui_resolution',
          '文字处理引用原生UI目标，共用现有控件与字体资源，不新增经营状态')
    pages = [(1024, 1024, 1), (1024, 1024, 4)]
    check([width*height*pixel_bytes for width,height,pixel_bytes in pages] == [1048576,4194304],
          '1024方形无mip字形页单通道8位为1MiB、RGBA8为4MiB，仅原始字节算例')
    for mutate,label in [
        (lambda r:r['layout_dependencies'].remove('font_resource_and_fallback_fingerprint'), '字体回退改变仍沿用旧排版'),
        (lambda r:r['layout_dependencies'].remove('available_width_and_wrap_rules'), '窄面板沿用旧换行'),
        (lambda r:r.update(binding_guard='same_display_name'), '同名控件沿用旧操作对象'),
        (lambda r:r.update(same_text_updates='skip_entire_control'), '同文字吞掉进度与病例来源更新'),
        (lambda r:r.update(input_priority='wait_for_numeric_refresh'), '中文确认等待数值刷新'),
        (lambda r:r.update(font_ownership='one_font_copy_per_row'), '列表按行复制字库'),
        (lambda r:r.update(glyph_population='prewarm_all_hospital_names'), '全院名字预热字形'),
        (lambda r:r.update(missing_glyph='reject_name'), '字体缺字拒绝合法名称'),
        (lambda r:r.update(cache_release='assumed_per_glyph_lru'), '虚构后端逐字回收能力'),
        (lambda r:r.update(allocation_accounting='compressed_font_file_bytes'), '文件大小冒充驻留字节'),
        (lambda r:r.update(snapshot_state=True), '字形缓存写入医院快照'),
        (lambda r:r.update(runtime_measurement_available=True), '字节算例冒充实机通过')]:
        invalid = copy.deepcopy(b)
        mutate(invalid['ui_text'])
        try:validate_ui_text(invalid)
        except ValueError:check(True, '原生文字合同负例被拒绝：'+label)
        else:raise ValueError('UI text contract accepted '+label)


def validate_performance_targets(c: dict, b: dict) -> None:
    p = b['performance_targets']
    require(c['schema_version'] == b['schema_version'] == 100, 'performance target schema mismatch')
    require(set(p) == {'purpose','hardware_reference','world_source','quality','display','capture','metrics',
                      'graphics_accounting','resource_measurement','large_world_samples','spatial_samples','display_workload_samples','changes_simulation','runtime_measurement_available'}
            and p['purpose'] == 'acceptance_targets_not_gameplay_limits'
            and p['world_source'] == 'performance_reference'
            and p['quality'] == 'standard' and p['changes_simulation'] is False
            and p['runtime_measurement_available'] is False, 'performance target changes gameplay or claims an unmeasured result')
    validate_spatial_view(b)
    validate_transparency_view(b)
    validate_pose_sampling(b)
    validate_preview_computation(b)
    validate_skin_pose_instancing(b)
    validate_ui_text(b)
    h = p['hardware_reference']
    require(h['gpu'] == 'Intel(R) Arc(TM) Graphics'
            and h['virtual_display_is_renderer'] is False and h['wmi_adapter_ram_is_total_budget'] is False
            and h['physical_cores'] == 14 and h['logical_processors'] == 18
            and h['installed_memory_bytes'] == 32*1024**3, 'hardware reference mistakes virtual displays or reported memory')
    d = p['display']
    require(set(d) == {'window_pixels','default_scene_scale_bp','scene_scale_options_bp','pixel_rounding',
                      'ui_resolution','render_scale_changes_ui','automatic_scale_changes'}
            and d['default_scene_scale_bp'] == 7500 and d['scene_scale_options_bp'] == [10000,7500,6667]
            and d['pixel_rounding'] == 'nearest_even_dimension' and d['ui_resolution'] == 'native_window'
            and d['render_scale_changes_ui'] is False and d['automatic_scale_changes'] is False
            and len(d['window_pixels']) == 2 and all(type(v) is int and v > 0 for v in d['window_pixels']),
            'scene scaling reduces UI readability or silently changes settings')
    capture = p['capture']
    require(p['resource_measurement']=={
        'process_source':'release_target_process_os_working_set',
        'private_commit':'record_separately_not_working_set',
        'graphics_source':'original_graphics_scope_with_allocation_basis_and_engine_os_corroboration',
        'debug_only_monitors':'diagnostic_only_never_zero_as_release_usage',
        'size_kinds':['payload_bytes','allocated_bytes','engine_estimate','os_residency'],
        'payload_only':'not_complete_budget_evidence','peak_scope':'same_capture_ordinary_save_and_view_transition_work',
        'peak_record':'observed_peak_cadence_and_process_lifetime_peak_separate',
        'shared_allocation':'once_per_actual_allocation_not_content_fingerprint_or_reference',
        'overlapping_counters':'report_separately_do_not_sum',
        'unreleased':'count_current_loading_idle_and_retiring_actual_allocations',
        'unknown':'record_missing_evidence_not_zero',
        'data_scope':'local_acceptance_report_not_world_or_parallel_runtime_state'},
        'resource measurement hides Release monitor limits, allocations, peaks or overlapping counters')
    require(capture['statistics']=={
        'time_basis':'monotonic_real_time','frame_source':'actual_distinct_game_frame_display_change',
        'frame_population':'complete_original_ordinary_intervals_with_start_in_capture_window',
        'incomplete_tail':'continue_to_next_distinct_frame_or_mark_missing_evidence',
        'percentile':'nearest_rank_ceil_p_times_n','maximum':'same_complete_population',
        'grouping':'per_world_load_window_scale_ui_speed_and_capture_condition',
        'dense_segments':'same_rules_separate_population_for_each_dense_segment',
        'missing_samples':'no_pass_or_synthetic_frames','average_fps_substitutes_tail':False,
        'cpu_gpu_sum_substitutes_frame':False,'tool_record':'version_source_and_actual_process_renderer',
        'data_scope':'local_acceptance_artifacts_not_world_or_runtime_cache'},
        'frame statistics hide tail intervals, combine conditions or substitute average/CPU counters')
    samples=p['display_workload_samples']
    require(samples == {
        'window_sources':['display.window_pixels','hardware_reference.reported_gpu_mode'],
        'scene_scale_source':'display.scene_scale_options_bp','ui_scale_percent':[100,200],
        'load_source':'performance_reference_and_existing_large_world_samples',
        'metrics_source':'same_primary_frame_simulation_response_and_memory_targets',
        'record_actual_window_scene_and_ui_extent':True,
        'unavailable_mode':'record_missing_evidence_without_substitution',
        'extrapolate_fps_from_pixel_ratio':False,
        'resource_cost_basis':'actual_targets_samples_formats_and_unreleased_copies'}
        and len(h['reported_gpu_mode'])==2 and all(type(v) is int and v>0 for v in h['reported_gpu_mode']),
        'display workload omits actual mode, native UI, allocation cost or original performance targets')
    require(capture['speeds'] == [1,3] and capture['fps_target'] == 60
            and capture['warmup_real_seconds'] >= 60 and capture['sample_real_seconds'] >= 600
            and capture['record_actual_renderer'] is True
            and capture['record_refresh_and_sync'] is True
            and capture['power_condition'] == 'ac_record_actual_power_mode_and_background_load',
            'performance sample hides renderer, power or simulation speed')
    m = p['metrics']
    require(set(m) == {'frame_p95_ms','frame_p99_ms','ordinary_frame_max_ms','sim_step_p95_ms','sim_speed_ratio_min',
                      'input_preview_p95_ms','room_preview_p95_ms','snapshot_copy_p95_ms','save_max_seconds','load_max_seconds',
                      'working_set_target_bytes','graphics_resources_target_bytes'}
            and all(type(v) in (int,float) and math.isfinite(v) and v > 0 for v in m.values())
            and m['frame_p95_ms'] <= 16.7 and m['frame_p95_ms'] <= m['frame_p99_ms'] <= 25
            and m['frame_p99_ms'] <= m['ordinary_frame_max_ms'] <= 50
            and m['sim_step_p95_ms'] <= 4 and 0.99 <= m['sim_speed_ratio_min'] <= 1
            and m['input_preview_p95_ms'] <= 100 and m['room_preview_p95_ms'] <= 200
            and m['snapshot_copy_p95_ms'] <= 25 and m['save_max_seconds'] <= 2 and m['load_max_seconds'] <= 5
            and m['graphics_resources_target_bytes'] <= m['working_set_target_bytes'] < h['installed_memory_bytes'],
            'performance target relaxes fluency or accepts cosmetic simulation slowdown')
    large = p['large_world_samples']
    require(large['actors'] == [320,640] and large['empty_floors'] == 10000
            and large['metrics_source'] == 'same_primary_frame_and_simulation_targets' and large['reject_by_count'] is False
            and b['performance_reference']['purpose'] == 'benchmark_not_gameplay_limit'
            and p['graphics_accounting'] == 'visible_idle_loading_and_render_targets',
            'performance samples become capacity limits or omit resource allocations')


def check_performance_examples(c: dict, b: dict) -> None:
    check_camera_view_examples(b)
    check_visual_batching_examples(b)
    check_transparency_view_examples(b)
    check_pose_sampling_examples(b)
    check_preview_computation_examples(b)
    check_skin_pose_instancing_examples(b)
    check_ui_text_examples(b)
    check_spatial_view_examples(c, b)
    from validate_care import rejects
    p = b['performance_targets']
    check(scene_pixels(p['display'],7500) == [1920,1080]
          and scene_pixels(p['display'],6667) == [1706,960], '本机1440p界面对应1080p三维75%和1706乘960约67%')
    ticks = [math.ceil(p['capture']['sample_real_seconds']*speed/Fraction(str(b['tick_seconds']))*Fraction(str(p['metrics']['sim_speed_ratio_min'])))
             for speed in p['capture']['speeds']]
    check(ticks == [5940,17820], '600现实秒验收真实模拟速度，1倍5940步与3倍17820步下限')
    reported=dict(p['display'],window_pixels=p['hardware_reference']['reported_gpu_mode'])
    check([scene_pixels(reported,scale) for scale in p['display']['scene_scale_options_bp']]==
          [[2880,1920],[2160,1440],[1920,1280]], '本机当前2880乘1920模式逐项采用原三维比例与偶数取整')
    base_pixels=math.prod(scene_pixels(p['display'],7500)); reported_pixels=math.prod(scene_pixels(reported,7500))
    check(Fraction(reported_pixels,base_pixels)==Fraction(3,2) and [base_pixels*8,reported_pixels*8]==[16588800,24883200],
          '75%三维像素多50%，单色加深度算例不冒充帧率或全部图形内存')
    def rank(values,percent):
        ordered=sorted(values)
        return ordered[(percent*len(ordered)+99)//100-1]
    rare_hitch=[16]*990+[80]*10
    check(1000*len(rare_hitch)/sum(rare_hitch)>p['capture']['fps_target'] and rank(rare_hitch,95)==rank(rare_hitch,99)==16
          and max(rare_hitch)>p['metrics']['ordinary_frame_max_ms'],
          '平均60FPS及95/99百分位合格仍不能掩盖80ms普通长帧')
    tail=[16]*989+[40]*11
    check(rank(tail,95)==16 and rank(tail,99)==40>p['metrics']['frame_p99_ms'],
          '最近秩P99保留超过1%长帧，不使用平均FPS判尾部通过')
    easy=[16]*9900; slow=[30]*100
    check(rank(easy+slow,95)==rank(easy+slow,99)==16 and rank(slow,95)==rank(slow,99)==30,
          '不同工况混算会隐藏30ms失败，必须独立统计真实负载')
    mip_payload=sum((1024>>level)**2*4 for level in range(11))
    references=[('allocation:atlas',mip_payload)]*6
    allocated={allocation_id:size for allocation_id,size in references}
    check(1024**2*4==4194304 and mip_payload==5592404 and sum(allocated.values())==5592404 and mip_payload*3==16777212,
          '1024RGBA8完整mip原始量按实际副本计，不按共享引用或指纹合并；仍非GPU实测')
    rejects(c,b,validate_performance_targets,check,[
        (lambda x,y:y['performance_targets']['hardware_reference'].update(gpu='MuMu Virtual Display Adapter'), '虚拟显示器冒充实际显卡'),
        (lambda x,y:y['performance_targets']['hardware_reference'].update(wmi_adapter_ram_is_total_budget=True), '集显128MiB报告值当作全部预算'),
        (lambda x,y:y['performance_targets']['display'].update(render_scale_changes_ui=True), '缩三维连带缩文字'),
        (lambda x,y:y['performance_targets']['display'].update(automatic_scale_changes=True), '画面清晰度悄悄跳档'),
        (lambda x,y:y['performance_targets']['display_workload_samples'].update(extrapolate_fps_from_pixel_ratio=True), '像素比冒充实机帧率'),
        (lambda x,y:y['performance_targets']['display_workload_samples'].update(ui_scale_percent=[100]), '高分辨率漏测200%原生界面'),
        (lambda x,y:y['performance_targets']['display_workload_samples'].update(record_actual_window_scene_and_ui_extent=False), 'WMI模式冒充实际分配尺寸'),
        (lambda x,y:y['performance_targets']['display_workload_samples'].update(resource_cost_basis='visible_color_only'), '遗漏深度采样及未释放目标'),
        (lambda x,y:y['performance_targets']['capture']['statistics'].update(frame_source='engine_average_fps'), '渲染平均帧数冒充实际显示间隔'),
        (lambda x,y:y['performance_targets']['capture']['statistics'].update(incomplete_tail='discard'), '采样末尾停顿被删除'),
        (lambda x,y:y['performance_targets']['capture']['statistics'].update(grouping='all_windows_and_loads_merged'), '轻负载掩盖高负载尾部'),
        (lambda x,y:y['performance_targets']['capture']['statistics'].update(cpu_gpu_sum_substitutes_frame=True), '并行阶段相加冒充帧长'),
        (lambda x,y:y['performance_targets']['resource_measurement'].update(process_source='debug_memory_static'), '调试内存0值冒充Release工作集'),
        (lambda x,y:y['performance_targets']['resource_measurement'].update(private_commit='use_as_working_set'), '私有提交量冒充驻留'),
        (lambda x,y:y['performance_targets']['resource_measurement'].update(shared_allocation='deduplicate_by_content_fingerprint'), '真实副本被同指纹隐藏'),
        (lambda x,y:y['performance_targets']['resource_measurement'].update(unknown='zero'), '未知原生分配被当作0'),
        (lambda x,y:y['performance_targets']['resource_measurement'].update(overlapping_counters='sum'), 'OS和引擎集显视图重复相加'),
        (lambda x,y:y['performance_targets']['metrics'].update(sim_speed_ratio_min=0.5), '高帧率掩盖模拟降速'),
        (lambda x,y:y['performance_targets']['metrics'].update(frame_p99_ms=100), '平均帧率掩盖长帧'),
        (lambda x,y:y['performance_targets']['large_world_samples'].update(reject_by_count=True), '样例人数成为玩法上限'),
        (lambda x,y:y['performance_targets'].update(changes_simulation=True), '性能档跳过临床行为'),
        (lambda x,y:y['performance_targets'].update(runtime_measurement_available=True), '设计目标冒充实机通过')])


def machine_feasibility_projection(c: dict, b: dict) -> dict:
    # Design arithmetic quotes the existing production budget; never a game loader.
    ref=b['balance_reference']['machine_feasibility']; h=b['performance_targets']['hardware_reference']
    require(ref['purpose']=='current_hardware_workload_estimate_not_runtime_proof'
            and ref['hardware_source']=='performance_targets.hardware_reference' and ref['world_source']=='performance_reference'
            and ref['geometry_source']=='existing_production_triangle_and_material_budget'
            and ref['changes_simulation'] is False and ref['snapshot_state'] is False and ref['runtime_measurement_available'] is False,
            'machine feasibility estimate changes gameplay or claims measured FPS')
    require(ref['draw_case']=='one_surface_per_declared_common_material_plus_one_per_prop_base_pass_only'
            and ref['prop_surface_assumption']==1 and ref['maps_per_group']==1
            and ref['renovation_maps']=='one_common_atlas_size_map_per_defined_material'
            and ref['texture_bytes']=='rgba8_complete_mip_payload_only'
            and ref['render_target_case']=='default_scaled_rgba8_color_depth32_plus_native_rgba8_output_single_sample'
            and ref['pose_case']=='single_compatible_group_existing_max_bone_full_palette_page_upload_each_target_frame',
            'machine estimate omits its Surface, texture, target or single-group assumptions')
    require(ref['assessment']=={
        'baseline':'hardware_feasible_with_existing_culling_sharing_batching_and_caches_not_measured_fps',
        'dense_near':'high_geometry_submission_and_query_risk_no_fps_promise_or_actor_cap',
        'memory_storage':'capacity_headroom_plausible_timing_unmeasured'}, 'machine estimate substitutes a FPS promise or capacity cap')
    require(h['cpu_core_types']=={'performance':4,'efficient':8,'low_power_efficient':2} and h['gpu_xe_cores']==7,
            '125H core types or Arc workload reference mismatch')
    memory=h['memory_report']
    require(memory['reported_entries']*memory['entry_capacity_bytes']==h['installed_memory_bytes']
            and memory['aggregate_bus_width']=='not_inferred_from_smbios_entries'
            and memory['free_bytes_are_future_reservation'] is False and 0<memory['free_physical_bytes']<=memory['usable_memory_bytes']<=h['installed_memory_bytes'],
            'SMBIOS records become bus width or a future memory reservation')
    production=(DOCS/'design/05-production.md').read_text(encoding='utf-8')
    geometry=re.search(r'角色近景≤([\d,]+)三角面，常用≤([\d,]+)，远景≤([\d,]+)；单机器近景≤([\d,]+)、常用≤([\d,]+)；普通家具≤([\d,]+)。',production)
    materials=re.search(r'角色常用材质≤(\d+)、机器≤(\d+)；[^\n]*?共享(\d+)纹理图集，特写机器最多(\d+)',production)
    require(geometry is not None and materials is not None, 'production budget source unavailable for hardware arithmetic')
    a_near,a_common,a_far,m_near,m_common,prop=(int(x.replace(',','')) for x in geometry.groups())
    a_surfaces,m_surfaces,atlas_size,closeup_size=map(int,materials.groups())
    actors={'near':a_near,'common':a_common,'far':a_far}; machines={'near':m_near,'common':m_common}
    world=b['performance_reference']; largest=max(b['performance_targets']['large_world_samples']['actors'])
    require([x['id'] for x in ref['scene_cases']]==['PC01','PC02','PC03','PC04'], 'hardware scene reference IDs invalid')
    scenes=[]
    for case in ref['scene_cases']:
        require(case['actor_source'] in ('reference','largest_existing_actor_sample')
                and case['partition'] in ('uniform_over_reference_floors','whole_reference_on_one_floor')
                and case['actor_profile'] in actors and case['station_profile'] in machines, 'invalid hardware scene assumption')
        total=world['total_actors'] if case['actor_source']=='reference' else largest
        divisor=world['floors'] if case['partition']=='uniform_over_reference_floors' else 1
        require(all(x%divisor==0 for x in (total,world['stations'],world['props'])), 'uniform hardware reference requires complete objects')
        visible=total//divisor; stations=world['stations']//divisor; props=world['props']//divisor
        scenes.append(dict(case,actors=visible,stations=stations,props=props,
            triangles=visible*actors[case['actor_profile']]+stations*machines[case['station_profile']]+props*prop,
            base_submissions=visible*a_surfaces+stations*m_surfaces+props*ref['prop_surface_assumption']))
    cpu=[]; path=b['pathfinding']; cells=b['limits']['grid_width']*b['limits']['grid_height']
    for count in sorted({world['total_actors'],*b['performance_targets']['large_world_samples']['actors']}):
        requests=max(path['minimum_actor_requests_per_tick'],math.ceil(count/path['actors_per_request']))
        for speed in b['performance_targets']['capture']['speeds']:
            hz=Fraction(speed)/Fraction(str(b['tick_seconds']))
            cpu.append({'actors':count,'speed':speed,'actor_visits_per_second':int(count*hz),
                        'requests_per_second':int(requests*hz),'full_floor_node_touch_case':int(requests*hz*cells),
                        'whole_step_budget_per_actor_us':b['performance_targets']['metrics']['sim_step_p95_ms']*1000/count})
    def mip_payload(size):
        require(size>0 and size&(size-1)==0, 'hardware texture example requires power-of-two dimensions')
        return sum((size>>i)**2*4 for i in range(size.bit_length()))
    p=b['performance_targets']; reported=dict(p['display'],window_pixels=h['reported_gpu_mode'])
    scene_pixels_count=math.prod(scene_pixels(reported,p['display']['default_scene_scale_bp']))
    target_bytes=scene_pixels_count*8+math.prod(h['reported_gpu_mode'])*4
    palette=skin_palette_size_example(largest,b['skin_pose_instancing']['palette']['bone_limit'],b)
    textures=[]
    require([x['id'] for x in ref['texture_cases']]==['PT01','PT02','PT03'], 'hardware texture reference IDs invalid')
    for case in ref['texture_cases']:
        require(case['species_maps'] in ('one_per_family','one_per_species')
                and case['medical_size'] in ('common_atlas','closeup_max'), 'invalid shared texture assumption')
        groups=len(c['families']) if case['species_maps']=='one_per_family' else len(c['species'])
        medical_size=atlas_size if case['medical_size']=='common_atlas' else closeup_size
        payload=((groups+len(c['renovation_materials']))*mip_payload(atlas_size)
                 +len(c['medical_equipment_profiles'])*mip_payload(medical_size))*ref['maps_per_group']
        textures.append(dict(case,payload_bytes=payload,partial_graphics_bytes=payload+target_bytes+palette['current_and_staging_bytes']))
    require(ref['serialization_world_bytes']==[64*1024**2,128*1024**2], 'hardware storage examples mismatch existing large-world references')
    save_budget=b['save']['resource_budget']
    snapshots=[{'world_bytes':size,'extra_memory_bytes':size*save_budget['world_memory_factor']+save_budget['memory_headroom_bytes'],
                'staging_disk_bytes':size*save_budget['staging_disk_world_factor']+save_budget['disk_headroom_bytes']}
               for size in ref['serialization_world_bytes']]
    return {'scenes':scenes,'cpu':cpu,'textures':textures,'snapshots':snapshots,'target_bytes':target_bytes,
            'scene_pixels_per_second_at_target_fps':scene_pixels_count*p['capture']['fps_target'],
            'target_partial_writes_bytes_per_second':target_bytes*p['capture']['fps_target'],
            'palette_double_bytes':palette['current_and_staging_bytes'],
            'palette_full_upload_bytes_per_second':palette['allocated_bytes']*p['capture']['fps_target']}


def check_machine_feasibility_examples(c: dict, b: dict) -> None:
    estimate=machine_feasibility_projection(c,b)
    check([x['triangles'] for x in estimate['scenes']]==[396000,1584000,2304000,3648000],
          '本机几何估算引用现有预算，四层均分与160/640密集负载分别计算')
    check([x['base_submissions'] for x in estimate['scenes']]==[476,1904,2864,2864],
          '单Surface假设下未合批提交量476/1904/2864，未冒充实际draw calls')
    three=[x for x in estimate['cpu'] if x['speed']==3]
    check([x['actor_visits_per_second'] for x in three]==[4800,9600,19200]
          and [x['requests_per_second'] for x in three]==[240,480,960]
          and [x['full_floor_node_touch_case'] for x in three]==[2211840,4423680,8847360],
          '本机CPU算例为真实3倍步频下的访问与路径规模，不按14核推算FPS')
    check([x['whole_step_budget_per_actor_us'] for x in three]==[25,12.5,6.25],
          '整个4ms均摊每演员上限25/12.5/6.25微秒，未扣其他系统而非已测工时')
    textures=estimate['textures']; target=b['performance_targets']['metrics']['graphics_resources_target_bytes']
    check(round(textures[0]['payload_bytes']/1024**2)==144 and round(textures[1]['payload_bytes']/1024**2)==240
          and textures[2]['payload_bytes']>target and round(textures[2]['payload_bytes']/1024**2)==597,
          '共享图集原始量144/240MiB有安排空间，80独立图全常驻原始量597MiB超原512目标')
    check(estimate['target_bytes']==47001600 and estimate['scene_pixels_per_second_at_target_fps']==186624000
          and estimate['palette_double_bytes']==2621440 and estimate['palette_full_upload_bytes_per_second']==78643200,
          '显示输出与单相容组矩阵页分别算术，不冒充片元工作、实际驻留或本机帧率')
    check([x['extra_memory_bytes']//1024**2 for x in estimate['snapshots']]==[320,576]
          and [x['staging_disk_bytes']//1024**2 for x in estimate['snapshots']]==[256,448],
          '64/128MiB世界在本机按原保存预算测算容量，不推断编码或NVMe耗时')


def append_machine_feasibility_atlas(lines: list, c: dict, b: dict, table) -> None:
    estimate=machine_feasibility_projection(c,b)
    lines += ['### 本机配置对应的实际负载估算','',
              '判断：基础160人四层医院具备硬件可行性；640人密集近景的几何、提交与查询风险高。依赖原裁剪/LOD/共享/合批与缓存落实，当前没有游戏FPS证据。以下均为注明假设的数量级，不增加验收门槛或玩法上限。','']
    table(lines,['场景假设','当前层演员 / 服务位 / 道具','角色+机器+家具三角面上界','未合批基础提交算例'],[
        [x['name'],f'{x["actors"]} / {x["stations"]} / {x["props"]}',f'{x["triangles"]:,}',str(x['base_submissions'])]
        for x in estimate['scenes']])
    lines += ['四层均分只为布局假设；三角面未含墙/楼板/阴影。提交假设每常用材质一Surface、每道具一Surface，仅基础pass，不等于实际Surface或draw calls。','']
    table(lines,['全院演员 / 速度','一轮演员访问 / 现实秒','移动路径额度 / 现实秒','每请求全层节点触达算例 / 秒','整个4ms均摊 / 演员'],[
        [f'{x["actors"]} / {x["speed"]}×',str(x['actor_visits_per_second']),str(x['requests_per_second']),
         f'{x["full_floor_node_touch_case"]:,}',f'{x["whole_step_budget_per_actor_us"]:g}微秒'] for x in estimate['cpu']])
    lines += ['访问量不是指令或耗时；均摊尚未扣其他系统。14核不乘主线程性能，真实查询/修补/完整日界容量模型仍须实现验证。','']
    table(lines,['纹理假设','RGBA8完整mip原始量','加说明显示目标与640成员单相容组双份骨页','未包含'],[
        [x['name'],f'{x["payload_bytes"]/1024**2:.2f}MiB',f'{x["partial_graphics_bytes"]/1024**2:.2f}MiB',
         '网格/字体/阴影/其他贴图/实际格式对齐/多组尾页及未释放副本'] for x in estimate['textures']])
    lines += [f'2880×1920默认75%按60目标帧/秒的输出位置数{estimate["scene_pixels_per_second_at_target_fps"]:,}/秒，非实际片元调用；说明目标原始量{estimate["target_bytes"]/1024**2:.2f}MiB，完整各写一次约{estimate["target_partial_writes_bytes_per_second"]/10**9:.2f}GB/秒，非全部读写。640成员单相容组全页上传约{estimate["palette_full_upload_bytes_per_second"]/10**6:.2f}MB/秒，CPU/顶点/缓存/同步未知。','']
    table(lines,['世界文件体积算例','原估算额外内存','原估算暂存磁盘'],[
        [f'{x["world_bytes"]//1024**2}MiB',f'{x["extra_memory_bytes"]//1024**2}MiB',f'{x["staging_disk_bytes"]//1024**2}MiB'] for x in estimate['snapshots']])
    memory=b['performance_targets']['hardware_reference']['memory_report']
    lines += [f'本机核对时可用物理内存约{memory["free_physical_bytes"]/1024**3:.2f}GiB；该快照不是未来保留。容量安排有空间，JSON复制/编码/哈希/最终提交与持续CPU/GPU功耗未测，不能据32GiB/NVMe直接声称保存或帧率通过。','']


def append_performance_atlas(lines: list, c: dict, b: dict, table) -> None:
    p = b['performance_targets']; h = p['hardware_reference']; m = p['metrics']
    lines += ['## 本机流畅运行目标', '',
              f'{h["captured_on"]}硬件参考：{h["cpu"]}，{h["gpu"]}，32GiB内存，NVMe SSD。目标尚无游戏实测证据。', '']
    table(lines,['项目','目标或边界'],[
        ['主要负载','原performance_reference四层160人，以及320/640人与10000空结构样例；均不是玩法上限'],
        ['窗口/三维/界面',f'{p["display"]["window_pixels"]} / {scene_pixels(p["display"],p["display"]["default_scene_scale_bp"])} / 原生文字与控件'],
        ['帧耗时',f'P95≤{m["frame_p95_ms"]}ms；P99≤{m["frame_p99_ms"]}ms；普通帧≤{m["ordinary_frame_max_ms"]}ms'],
        ['真实模拟',f'1×/3×均达到档位的{m["sim_speed_ratio_min"]*100:.0f}%；模拟步P95≤{m["sim_step_p95_ms"]}ms'],
        ['响应',f'输入/预览P95≤{m["input_preview_p95_ms"]}ms；房间预览≤{m["room_preview_p95_ms"]}ms'],
        ['保存',f'主线程复制P95≤{m["snapshot_copy_p95_ms"]}ms；基线保存≤{m["save_max_seconds"]}秒、载入≤{m["load_max_seconds"]}秒'],
        ['资源',f'基线工作集目标{m["working_set_target_bytes"]//1024**3}GiB；合并图形资源目标{m["graphics_resources_target_bytes"]//1024**2}MiB'],
        ['采样',f'交流供电并记录电源/后台/实际适配器；预热{p["capture"]["warmup_real_seconds"]}秒，采样{p["capture"]["sample_real_seconds"]}秒']])
    lines += ['真实不同游戏帧的显示间隔按每工况/密集区间独立统计；P95/P99取升序第ceil(p×N)项，最大值使用同批完整普通间隔。末尾已开始区间继续捕获或标记证据不足，真实模拟仍计原600秒；平均FPS和CPU/GPU相加不能代替尾部。','']
    lines += ['Release工作集取目标进程OS观测，私有提交量另列；原始数据、已确认分配、引擎估计与OS驻留分别注明。共享按真实分配计一次，加载/退场副本仍计，未知不填0、重叠集显视图不相加。记录采样间隔及观测/生命周期峰值，静态字节不证明资源通过。','']
    lines += ['100%原生三维另测可读性和成本；75%为默认，约67%为明确可选比例。画面档不改变患者、行为、随机流、时间或医院事实。', '']
    table(lines,['窗口来源 / 原生尺寸','三维比例','算例三维尺寸','三维像素 / 单色加深度8字节算例'],[
        [label+' '+str(window),f'{scale/100:.2f}%',str(scene_pixels(dict(p['display'],window_pixels=window),scale)),
         str(math.prod(scene_pixels(dict(p['display'],window_pixels=window),scale)))+' / '+str(math.prod(scene_pixels(dict(p['display'],window_pixels=window),scale))*8)+'字节']
        for label,window in [('原对照',p['display']['window_pixels']),('本机当前报告',h['reported_gpu_mode'])]
        for scale in p['display']['scene_scale_options_bp']])
    lines += ['两尺寸各测原生UI100%/200%及原160/320/640人负载；记录实际窗口/三维分配，不推算fps。8字节只为单色加深度算例，不含UI、MSAA、对齐、驱动与未释放副本。当前报告模式不是已创建的游戏窗口或实测通过。','']
    append_machine_feasibility_atlas(lines,c,b,table)
    camera=b['camera_view']; native=p['display']['window_pixels']; rendered=scene_pixels(p['display'],7500)
    bounds=[(0,0,0,144,0,144)]; plain=camera_fit_example(bounds,native,rendered,(0,0,*native),b)
    narrow=camera_fit_example(bounds,[1280,720],[960,540],(0,56,928,592),b)
    lines += ['### 当前层全层概览', '',
              '以下为空楼板投影与安全矩形几何算例，尚未执行Camera3D、真实拾取或大院图形压测；实际高身体、症状和界面范围由当前查询纳入。', '']
    table(lines,['来源或边界','确定规则'],[
        ['原镜头',f'正交纵向锁定，yaw{camera["default_yaw_degrees"]}°/俯角{camera["pitch_degrees"]}°，四方向；最小{camera["minimum_size_m"]}米/默认{camera["default_size_m"]}米'],
        ['当前层范围','合法楼板角点与实际显示包络逐个投影，逻辑记录查询，不实例化其他层或未购地'],
        ['空96×96纯16:9',f'投影约203.647×117.574米，含10%余量概览{plain["size_m"]:.3f}米；原90米不足'],
        ['1280×720 / 安全928×592',f'实际三维960×540，概览{narrow["size_m"]:.3f}米；中心对齐安全区域，算例不承诺真实布局'],
        ['缩远与手动操作','max(原90米,当前层概览size)；Home/全层按钮主动触发，侧栏/工作/走动不每步自动拉镜头'],
        ['LOD与拾取','实际投影的原生两条地格边取较短长度，原24入20出；鼠标按同一真实矩阵转换'],
        ['范围失效与医院','无合法楼板/零安全矩形保留镜头并说明；本层重定位、原显示预算与完整模拟继续，镜头不入世界快照']])
    v=p['spatial_samples']; view=b['spatial_view']; wide=v['wide_floor']; tall=v['wide_tall']
    lines += ['### 真实可见部件的合批合同', '',
              '静态兼容性和缓冲算例不调用渲染器，不证明本机drawcall或帧率。所有主体、症状和当前临床状态保持原来源。', '']
    table(lines,['来源或边界','确定规则'],[
        ['名单','当前视图完整包络可见的唯一实体/部件；连续可见前缀，不预分配全院活跃演员'],
        ['相容性','内容指纹/真实网格/完整材质布局/LOD/渲染状态/已验证准备姿态，种族或同色不作组键'],
        ['原主表现','骨骼近景默认原管线，专用独立矩阵须正式验证；透明排序/未知远景/不支持资产保持原主表现，合法扩展可加载'],
        ['槽绑定','、'.join(b['visual_batching']['slot_binding_key'])+'；迟到结果拒绝，绑定后取当前原姿态'],
        ['共享资源','独立实例变换/染色，不写共享材质；一个实际实体仍一逻辑表现句柄'],
        ['成本','原2ms内处理压实/上传/回收，当前/空闲/暂存/未用分配容量全部计真实字节'],
        ['真实验收','原400调用/1.5M面用引擎统计及必要通道计账；超目标继续全部表现，批数不是医院上限']])
    skin=b['skin_pose_instancing']; palette=skin['palette']; skin_size=skin_palette_size_example(640,40,b)
    lines += ['### 密集近景的独立骨矩阵实例绘制', '',
              '正式适配与Compatibility/本机能力当前未验证。以下页/IEEE半精度算例不运行shader、生产资产或证明400调用/帧率。', '']
    table(lines,['来源或边界','确定规则'],[
        ['启用与原回退','后端/正式适配均验证才启用；原采样结果单次变形，未知/形态/alpha/非均匀骨等继续原完整身体管线'],
        ['小页',f'每骨{palette["texels_per_bone"]}RGBAF32 texel，实际骨宽向2次幂；每页≤{palette["max_rows_per_page"]}行，更多成员分页非医院上限'],
        ['半精度输入','Compatibility只0…63局部行号且实际往返验，世界ID/采样代次不进该通道，原参数各自声明'],
        ['行身份','、'.join(skin['row_key'])+'；当前整页发布，原可见唯一部件/真实包络/阴影姿态保持'],
        ['40骨640行示意',f'{skin_size["pages"]}页128×64，原始分配{skin_size["allocated_bytes"]}、双份{skin_size["current_and_staging_bytes"]}字节；假设全页60Hz传输{skin_size["allocated_bytes"]*60}字节/秒'],
        ['完整成本','真实整页API上传/CPU原姿态/当前暂存未释放计原预算，dirty行或30Hz不能低报，没有免费批调用'],
        ['正式等价',f'原九rig/症状/临床/暂停/低动态等真实测量，位置≤{skin["adapter_position_error_m_max"]}米/方向≤{skin["adapter_normal_tangent_error_degrees_max"]}°和原锚点门槛；未知非通过'],
        ['完整世界','所有实际角色/独立阶段/真实业务继续，矩阵页/行不保存，不隐藏第65人或共享同一动画进度']])
    preview = b['preview_computation']
    lines += ['### 大面积建造预览的计算与发布', '',
              '静态请求/值一致性守卫不证明真实处理器依赖完备，也未运行空间预览、并发输入或本机延迟。', '']
    table(lines,['来源或边界','确定规则'],[
        ['最新语义',f'原活动会话{preview["current_jobs"]}当前任务/{preview["pending_requests"]}最新请求；同格像素/无关tick不重启，旧任务安全切片停'],
        ['反馈','原当前轮廓和明确检查中，整份当前结果才就绪，旧绿格/清单不拼入新草案'],
        ['请求身份','、'.join(preview['request_key'])+'；原草案属原楼层，旧视图结果不串层'],
        ['相关依据','完备原语义条件/真实身体/空区进入/完整安全域；无关事实不重确认，分片不混修订'],
        ['执行与预算','主线程所需只读值，无后台活跃世界/整院副本；查询/上传/取消共用原2ms，单次越界真实计帧'],
        ['原应用','原明确确认后当前原子复核，未就绪无自动确认/付款/预约/停诊，预览不插Actor队列'],
        ['证据与保存','原100/200ms与帧目标，挂起/替换/取消/越界单记，只轮廓不算通过；派生任务不保存，世界业务保持']])
    pose = b['pose_sampling']
    lines += ['### 可见角色的姿态采样', '',
              '相位格、散列与采样次数为静态合同和算术，未运行AnimationMixer、正式九骨架或本机性能。', '']
    table(lines,['来源或边界','确定规则'],[
        ['频率',f'近{pose["near_hz"]}Hz/远{pose["far_hz"]}Hz现实时间，3×不乘频率；原LOD/选中可见规则'],
        ['唯一入口','关闭同绑定默认自动推进，由原当前阶段/进度求值；方法/结束/声音轨道不驱动业务或补播'],
        ['稀疏相位',f'仅当前可见连续绑定；UTF8长度前缀SHA256前64位mod{pose["phase_bins"]}，不抽业务随机，碰撞不截演员'],
        ['晚帧','0.2秒后30Hz零相位7/30秒、512相位13/60秒；只取当前一次，下一原格严格晚于现在'],
        ['必要状态','原身体/阶段/冻结等离散改变先撤旧姿态读当前；根位置每帧原合法插值，暂停/静态未变不重评'],
        ['复用与原结果','同实体/骨架/原姿态来源/模式/镜头输入才复用，最高需要频率；迟到绑定核验后取当前，不共享不同人阶段'],
        ['成本与保存','640连续近/远理论19200/9600次每现实秒非实测；全部求值/上传计原帧，新绑定仍原2ms；派生时钟/姿态不入世界快照']])
    lines += ['### 透明覆盖与叠加成本', '',
              '以下比例仅来自100像素/声明采样的静态示意，不调用渲染器，也不证明20%覆盖或本机帧率已经通过。', '']
    table(lines,['来源或边界','确定规则'],[
        ['覆盖目标',f'原{b["transparency_view"]["coverage_target_bp"]/100:.0f}%；实际本三维视图片元入口像素并集，原生UI/其他层不稀释'],
        ['叠加示意','10像素叠1层：10%/10%；叠12层：并集10%/负载120%；四采样按真实容量归一，不夹100%'],
        ['实际管线','透明混合各模式、粒子、折射/软影与已经发生的零alpha/丢弃入口计入；opaque/cutout仍计原帧成本'],
        ['准确证据','实际管线/采样捕获须验证工具；未知标不可用，包围框仅估计，最终截图不当精确计数'],
        ['计时与预览','诊断与正式计时分开、同世界/姿态/镜头/设置；每视图单列且总帧/资源合计，不常驻逐像素图'],
        ['必要表现','原透明排序与主体/症状/安全状态保留，等价低成本材料须验证，只简化原次要细节；设置明确，无业务/快照变化']])
    lines += ['### 大面积与高层的显示合同', '']
    table(lines,['项目','目标或边界'],[
        ['同层面积',f'{wide["owned_plots"]}已购地块、{wide["logical_size_cells"]}格；{wide["rooms"]}房/{wide["stations"]}服务位/{wide["props"]}实际道具，同层实际{wide["actors"]}角色'],
        ['显示块',f'{view["chunk_cells"]}格；满层{len(spatial_chunks_example((0,0,*wide["logical_size_cells"]),b))}个楼板块，只为视野/明确预览建实例，预取圈不实例化'],
        ['细节与选择',f'原生投影{view["detail_enter_px"]}像素进入/{view["detail_leave_px"]}退出；当前选中可见对象保留完整表现，选择查询真实空间'],
        ['新增显示工作',f'每帧{view["view_build_budget_ms_per_frame"]}ms目标、最多启动{view["view_chunk_starts_per_frame"]}块；块内继续分片，绑定/上传/退场共用预算'],
        ['高层组合',f'每地块完成至{tall["completed_top_floor_per_plot"]}层，活动层{tall["active_floors"]}，实际{tall["actors"]}角色；不展开空层'],
        ['密集证据',f'在完整{p["capture"]["sample_real_seconds"]}秒窗口中，至少{v["minimum_dense_sample_real_seconds"]}秒达到目标人数{v["minimum_density_bp"]/100:.0f}%；160档144人、640档576人，密集段沿原目标单独判定'],
        ['镜头与缓存','近/远、双轴平移、门槛往返、跳层与加载中改建；冷/热/主动回收，分别记录真实人数、可见ID、实例/片段和资源峰值']])
    lines += ['### 原生UI文字与字体资源', '']
    table(lines,['项目','合同与验证边界'],[
        ['处理范围','原可见行与聚焦面板；相关字段变化才格式化，相同文本复用控件已有能力，不另建全院文本缓存'],
        ['布局依赖','实际字体/回退内容、字号/UI缩放、宽度/换行、语言方向/排列变化仍重新处理；原生UI保持'],
        ['同名与输入','相同文字不跳过对象重绑、病例来源、进度或提示；中文输入、焦点及命令反馈保持即时'],
        ['共享与缺字','只读字体按实际资源共享，字形按需；随包回退不足时保留原文与缺字符号，不拒名或联网取字'],
        ['真实成本','字形页/旧字号/加载副本计原图形预算，字体面/排版暂存计原工作集，唯一分配不按文件大小估计'],
        ['字节示意',f'1024×1024无mip页：8位单通道{1024*1024:,}字节，RGBA8 {1024*1024*4:,}字节；实际后端格式与额外分配另测'],
        ['验收','冷暖、滚动、五档UI缩放、长名/罕见字/中文IME与切院；真实排版、字形未命中、资源峰值和原帧/响应目标待实测']])
    lines += ['以上为未实测的性能合同与静态算术；不生成游戏运行轨迹，不证明本机帧率达标。图块、显示队列、LOD与字体缓存不写世界快照，不减少后台医疗、角色或工作。', '']


def main(quiet: bool = False) -> dict:
    c=json.loads((DOCS/'data/content-catalog.json').read_text(encoding='utf-8'))
    b=json.loads((DOCS/'data/balance.json').read_text(encoding='utf-8'))
    layout=json.loads((DOCS/'data/starter-layout.json').read_text(encoding='utf-8'))
    clinical_layouts=json.loads((DOCS/'data/clinical-layouts.json').read_text(encoding='utf-8'))
    validate_catalog(c,b)
    check_time_examples(c,b)
    check_performance_examples(c,b)
    check_machine_feasibility_examples(c,b)
    validate_roster(c,b,layout)
    check(True,'完整内容引用、包络、设备与任务模型有效')
    counts={'families':13,'species':80,'diseases':154,'machines':3,'treatment_routines':84,'treatment_bindings':488,
            'specialties':10,'research':38,'doors':6,'incidents':25,'interactions':72,'tasks':28,'furniture_equipment':50,'chair_variants':4,
            'doctor_titles':4,'doctor_personalities':6,'treatment_protocols':5,'treatment_plans':332,'surgical_adapters':53,
            'clinical_equipment':2,'clinical_room_types':2,
            'patient_personalities':10,'patient_behaviors':12,'doctor_responses':6,'consultation_behaviors':17,
            'hospital_situations':24,'renovation_materials':8,'service_equipment':6,'staff_support_rooms':1,'staff_recreation_equipment':4,
            'species_gifts':80,'gratitude_abilities':80,'gratitude_effects':6,'incident_contexts':24,
            'memory_callbacks':6,'accessibility_equipment':3,'vertical_connectors':3,
            'staff_role_profiles':7,'staff_work_styles':6,'staff_biographies':8,'recruitment_examples':7,
            'community_activities':5,'community_cast':8,'story_activity_links':5,
            'blueprint_presets':9,'remodel_guides':8}
    for key,count in counts.items():check(len(c[key])==count,'基础交付数量 '+key)
    s,d,m,doors=(index(c[k]) for k in ('species','diseases','machines','doors'))
    for item in c['species']:
        dids={v['disease_id'] for v in c['treatment_bindings'] if v['species_id']==item['id']}
        check(len(dids)==(14 if item['id']=='S49' else 6),'每种族病例深度：'+item['id'])
    for sid,door_id in [('S49','DR01'),('S55','DR01'),('S55','DR03'),('S01','DR02'),
                        ('S01','DR04'),('S53','DR05'),('S59','DR05'),('S59','DR06')]:
        check(door_fits(s[sid],doors[door_id]),'有足够空间时门自动适配 '+sid+'/'+door_id)
    check(not door_fits(s['S59'],doors['DR01'],2) and door_fits(s['S59'],doors['DR01'],3),
          '门旁只余两格拒绝巨人，三格连续墙段才可展开')
    check(not door_fits(s['S55'],doors['DR01'],3,3.0), '自动长高不能突破实际净高')
    check(Counter(x['kind'] for x in c['tasks'])=={'milestone':16,'commission':12},'成长与委托数量')
    check(set(c['initial_disease_ids'])=={'D01','D09','D18','D37','D39'},'起始病例未被扩展替换')
    check(sum(b['plot_prices'])==66000 and len(b['plot_prices'])==9,'8块后续土地总价66000')
    def neighbors(a:int,b_:int)->bool:return abs(a%3-b_%3)+abs(a//3-b_//3)==1
    check(neighbors(7,4) and neighbors(7,6) and neighbors(7,8) and not neighbors(7,3),'土地共边而非对角')
    sub=b['subsidy']
    def grant(n:int)->int:return min(sub['cap'],sub['base_amount']+sub['per_extra_plot']*(n-1))
    check([grant(x) for x in (1,2,7,9)]==[1200,1400,2400,2400] and sub['interval_days']==3,'周期补助金额与封顶')
    protocols=index(c['treatment_protocols'])
    surgical_plans=[p for p in c['treatment_plans'] if protocols[p['protocol_id']]['kind']=='surgery']
    check(len(surgical_plans)==24,'24病症各增加一种专科手术')
    surgery_diseases={p['disease_id'] for p in surgical_plans}
    check({a['binding_id'] for a in c['surgical_adapters']} == {x['id'] for x in c['treatment_bindings'] if x['disease_id'] in surgery_diseases},'core手术覆盖全部53种族病例，扩展不强迫追加手术')
    pay=index(b['doctor_pay'],'title_id')
    day_ticks=int(Fraction(str(b['day_seconds']))/Fraction(str(b['tick_seconds'])))
    check((pay['DT01']['wage_day']*(day_ticks//2)+pay['DT02']['wage_day']*(day_ticks//2))//day_ticks==160,'日中晋级当日工资160，不追溯费率')
    check(2*pay['DT02']['hire']+2*index(b['staff'],'role')['nurse']['hire']==2400
          and 2*pay['DT02']['wage_day']+2*index(b['staff'],'role')['nurse']['wage_day']==560,'附加两主治两护士招聘2400与日薪560')
    course_cost={r['target_level']:r['cost'] for r in b['doctor_training']['courses']}
    retention_costs=[pay['DT02']['promotion_cost']+course_cost[2],
                     pay['DT03']['promotion_cost']+course_cost[3]+course_cost[2],
                     pay['DT04']['promotion_cost']+course_cost[4]+course_cost[3]]
    check(all(cost<pay[key]['hire'] for key,cost in zip(('DT02','DT03','DT04'),retention_costs)),
          '治疗方向老员工逐级补课晋级支出低于直接招聘同职称，不含沉没费用')
    longest=max(p['work_seconds'] for p in protocols.values() if p['kind']=='surgery')+b['clinical']['wake_seconds']+b['clinical']['surgery_guard_seconds']
    check(longest==215 and longest<b['schedule']['shift_seconds'],
          '180秒手术加苏醒与缓冲215秒可在600秒班内完成；临近换班仍逐项检查连续窗口')
    personalities=index(c['doctor_personalities'])
    def scores(pid):
        w=personalities[pid]['weights']
        return plan_score(w,.92,36,0),plan_score(w,.97,64.8,1)
    cautious,efficient=scores('DP01'),scores('DP05')
    check(cautious[1]>cautious[0] and efficient[0]>efficient[1],'同病例谨慎选舒缓、效率选常规的确定性评分样例')
    clinical_costs=validate_layouts(c,b,clinical_layouts,check)
    check_life_examples(c,b,layout,check)
    check_comedy_examples(c,b,check)
    check_expansion_examples(c,b,check)
    check_remodel_examples(c,b,layout,clinical_layouts,check)
    check_progression_examples(c,b,check)
    check_operations_examples(c,b,check)
    check_care_examples(c,b,check)
    check_expertise_examples(c,b,check)
    check_requirement_coverage()
    check(layout['floor_id'] == 'floor:1'
          and all(row['floor_id'] == 'floor:1' for row in clinical_layouts['layouts']),
          '初始与四套临床夹具明确位于地面，未冒充跨层路径实测')

    ext=copy.deepcopy(c)
    extra=copy.deepcopy(s['S06']);extra.update(id='garden:moss_person',name='苔藓人')
    ext['species'].append(extra)
    talent=copy.deepcopy(next(r for r in c['staff_talents'] if r['species_id']=='S06'))
    talent.update(id='garden:moss_talent',species_id=extra['id'],name='苔垫安心')
    ext['staff_talents'].append(talent)
    bind=copy.deepcopy(next(v for v in ext['treatment_bindings'] if v['species_id']=='S06' and v['disease_id']=='D04'))
    bind.update(id='garden:moss_binding',species_id=extra['id'])
    ext['treatment_bindings'].append(bind)
    case=copy.deepcopy(d['D42']);case.update(id='garden:firefly_yawn',name='萤火哈欠',profile='A')
    ext['diseases'].append(case);index(ext['research'])['R32']['disease_ids'].append(case['id'])
    bind=copy.deepcopy(next(v for v in ext['treatment_bindings'] if v['species_id']=='S49' and v['disease_id']=='D42'))
    bind.update(id='garden:human_case',disease_id=case['id']);ext['treatment_bindings'].append(bind)
    for suffix in ('COMMON','GENTLE'):
        plan=copy.deepcopy(next(p for p in ext['treatment_plans'] if p['id']=='P_D42_'+suffix))
        plan.update(id='garden:firefly_'+suffix.lower(),disease_id=case['id'])
        ext['treatment_plans'].append(plan)
    validate_catalog(ext,b)
    check(True,'扩展仅一条新种族病例仍可加载，旧人类可接新增病症')
    def alternate_case_fixture(sid, did, suffix):
        expanded = copy.deepcopy(c)
        binding = copy.deepcopy(next(r for r in expanded['treatment_bindings']
                                     if (r['species_id'],r['disease_id']) == (sid,did)))
        routine = copy.deepcopy(index(expanded['treatment_routines'])[binding['routine_id']])
        routine['id'] = 'fixture:alternate_'+suffix
        binding.update(id='fixture:binding_'+suffix, routine_id=routine['id'])
        expanded['treatment_routines'].append(routine)
        expanded['treatment_bindings'].append(binding)
        return expanded, binding
    same_case, _ = alternate_case_fixture('S06','D04','symptom')
    validate_catalog(same_case, b)
    same_case['treatment_bindings'].reverse()
    validate_catalog(same_case, b)
    check(True, '同病例不同routine且有效宽深高相同可加载，颠倒绑定顺序不改变合法性')
    explicit_base, extra_binding = alternate_case_fixture('S49','D42','base')
    extra_binding['symptom_envelope'] = copy.deepcopy(s['S49']['body'])
    validate_catalog(explicit_base, b)
    check(True, '未声明症状包络与显式正常身体等价，不强制只有一条治疗绑定')
    for changed_axis in (None, 'width_m', 'depth_m', 'height_m'):
        broken_case, extra_binding = alternate_case_fixture('S06','D04','conflict')
        if changed_axis is None:
            extra_binding.pop('symptom_envelope')
        else:
            extra_binding['symptom_envelope'][changed_axis] += 0.01
        try:
            validate_catalog(broken_case, b)
        except ValueError as error:
            check('conflicting case body for S06/D04' in str(error)
                  and 'B_S06_D04_M04' in str(error) and extra_binding['id'] in str(error),
                  '同病例身体冲突被拒绝并定位两条绑定：'+str(changed_axis))
        else:
            raise ValueError('conflicting case body accepted: '+str(changed_axis))
    q23 = index(c['tasks'])['Q23']
    check(q23['eligibility_rule'] == {'requires_research':[],'required_roles':['mechanic'],
                                    'maintainable_equipment_min':1}
          and q23['metric'] == 'preventive_maintenance_jobs' and q23['target'] == 3
          and q23['reward_cash'] == 240 and q23['filter'] == {} and q23['deadline_days'] is None,
          '保养委托资格为维修员及一件已放置维护对象，原三单与240奖励保持；未执行任务状态机')
    extra_threshold = copy.deepcopy(c)
    index(extra_threshold['tasks'])['Q23']['eligibility_rule']['maintainable_equipment_min'] = 2
    validate_catalog(extra_threshold, b)
    check(True, '维护对象资格为通用正整数阈值，不在加载器写死为一件')
    negatives=[
        (lambda x:x['species'].append(copy.deepcopy(x['species'][0])),'重复ID'),
        (lambda x:x['machines'].pop(0),'缺机器'),
        (lambda x:index(x['research'])['R02']['requires'].append('R11'),'研究环'),
        (lambda x:x['treatment_bindings'][0].update(animation_profile='wrong'),'骨架不匹配'),
        (lambda x:index(x['species'])['S59']['body'].update(height_m=8),'超包络'),
        (lambda x:x['doors'][0].update(fit_policy='ignore_space'),'门绕过空间适配'),
        (lambda x:x['furniture_equipment'][0].update(equipment_class=None),'功能设备无故障类别'),
        (lambda x:x['incidents'][0].update(may_start_incident=True),'事件递归'),
        (lambda x:x['tasks'][0].update(reward_cash=-1),'负任务奖励'),
        (lambda x:x['interactions'][0].update(actor_a={'species_any':['missing']}),'未知互动角色'),
        (lambda x:x['treatment_plans'].remove(index(x['treatment_plans'])['P_D37_COMMON']),'病症只剩一套方案'),
        (lambda x:x['surgical_adapters'][0].update(binding_id='missing'),'手术适配引用丢失'),
        (lambda x:x['surgical_adapters'][0].update(recovery_variant='重复的康复副本'),'手术适配复制病例康复事实'),
        (lambda x:x['treatment_bindings'][0].update(treatment_variant=x['treatment_bindings'][0]['treatment_variant']+'；'+x['treatment_bindings'][0]['recovery_variant']),'病例治疗过程复制康复尾句'),
        (lambda x:index(x['treatment_protocols'])['TP_SURGERY1'].update(requires_distinct_staff=False),'一人同时主刀和麻醉'),
        (lambda x:x['clinical_equipment'][0].update(equipment_class='none'),'临床设备无故障类别'),
        (lambda x:x['doctor_personalities'][0]['weights'].update(success=float('nan')),'医生偏好数值非法'),
        (lambda x:x['doctor_titles'][1]['promotion'].update(primary_level=6),'晋级条件超能力上限'),
    ]
    negatives += [(lambda x,value=value:index(x['tasks'])['Q23']['eligibility_rule'].update(
                        maintainable_equipment_min=value), '维护对象资格非法阈值：'+repr(value))
                  for value in (True, False, 0, -1, 1.5, '1', None)]
    for mutate,label in negatives:
        broken=copy.deepcopy(c);mutate(broken)
        try:validate_catalog(broken,b)
        except ValueError:check(True,'负例被拒绝：'+label)
        else:raise ValueError('negative case accepted: '+label)
    invalid_roster=copy.deepcopy(layout)
    invalid_roster['doctor_roster'][0]['shifts'][1]={'kind':'outpatient','pool':['diagnosis']}
    try:validate_roster(c,b,invalid_roster)
    except ValueError:check(True,'三班连续工作排班被拒绝')
    else:raise ValueError('unrested schedule accepted')
    dims=validate_layout(layout,b,c)
    hire,wages=starter_staff_costs(b,layout)
    construction=sum(x['amount'] for x in b['starter_purchase'])
    initial_supplies=b['supplies']['initial_purchase_units']*c['medical_supplies'][0]['unit_price']
    check(hire==1480 and wages==740 and construction==12720 and b['starting_cash']-hire-construction-initial_supplies==10600,'初始七员工、建造与真实采购预算')
    simulation_text=(DOCS/'design/01-simulation.md').read_text(encoding='utf-8')
    startup_quote=re.search(r'开院现金([\d,]+)。.*?建设与家具([\d,]+)，.*?招聘合计([\d,]+)；先采购(\d+)包治疗包支付([\d,]+)，余额([\d,]+)。',simulation_text)
    check(startup_quote is not None and [int(x.replace(',','')) for x in startup_quote.groups()]==
          [b['starting_cash'],construction,hire,b['supplies']['initial_purchase_units'],initial_supplies,b['starting_cash']-construction-hire-initial_supplies],
          '正文开院现金、预设支出与余额逐项对应源数据')
    empty_quote=re.search(r'空地开局[^\n]*?余([\d,]+)；不扣预设建造和招聘费',simulation_text)
    check(empty_quote is not None and int(empty_quote.group(1).replace(',',''))==b['starting_cash']-initial_supplies,
          '正文空地余额只扣同一初始治疗包采购')
    plot_quote=re.search(r'1F第2至第9块地的购买价依次为([\d,、]+)，共([\d,]+)。',simulation_text)
    check(plot_quote is not None and [int(x.replace(',','')) for x in plot_quote.group(1).split('、')]==b['plot_prices'][1:]
          and int(plot_quote.group(2).replace(',',''))==sum(b['plot_prices'][1:]),
          '正文地价逐项与合计对应原地价数据')
    check(math.ceil(60/day_ticks)==1 and (60*(day_ticks//2))//day_ticks==30,'离职极短在职向上结清，半日按比例')
    reference=b['balance_reference']
    check(reference['purpose']=='design_calibration_only' and reference['starter_case_mix']=='equal_initial_diseases',
          '数值参考仅用于设计校准，不改变真实到院、收费或账目')
    initial_cases=[d[key] for key in c['initial_disease_ids']]
    check(all(row['profile']=='A' for row in initial_cases),'开院解析样例适用实际初始A档病例')
    mean_cure_fee=sum(row['cure_fee'] for row in initial_cases)/len(initial_cases)
    patients=reference['starter_completed_visits_per_day'][3];p1=c['profiles']['A']['base_success']
    p2=min(0.98,p1+b['second_attempt_bonus'])
    cured=p1+(1-p1)*p2;attempts=1+(1-p1)
    doctor_fee=index(b['billing']['doctor_consultation_fees'],'title_id')['DT01']['amount']
    facility_fee={(x['equipment_id'],x['service_kind']):x['amount'] for x in b['billing']['facility_fees']}
    diagnostic_fee=facility_fee[('FUR02','gp')]
    routine_index=index(c['treatment_routines'])
    starter_machines={routine_index[row['routine_id']]['equipment_id'] for row in c['treatment_bindings'] if row['disease_id'] in c['initial_disease_ids']}
    check({facility_fee[(key,'outpatient')] for key in starter_machines}=={10}, '初始五病主体使用费均10')
    treatment_use_fee=10
    per_visit_revenue=doctor_fee+diagnostic_fee+attempts*treatment_use_fee+cured*mean_cure_fee
    revenue=patients*per_visit_revenue
    check([doctor_fee+diagnostic_fee+n*treatment_use_fee+(200 if ok else 0)
           for n,ok in [(1,True),(2,True),(2,False)]]==[235,245,45],
          'D09首试成功/重试成功/两次失败收入235/245/45，无重复初诊或虚构治愈费')
    for mutate,label in [
        (lambda x:x['billing']['doctor_consultation_fees'][1].update(amount=20),'高职称未提高诊费'),
        (lambda x:x['billing']['facility_fees'].pop(),'缺护理床收费'),
        (lambda x:x['billing']['facility_fees'].append(dict(x['billing']['facility_fees'][0],id='duplicate')),'同设备服务重复收费定义'),
        (lambda x:x['clinical'].update(care_fee=80),'重复旧住院照护费'),
        (lambda x:x['billing'].update(facility_charge_at='reservation'),'预约即收费')]:
        broken=copy.deepcopy(b);mutate(broken)
        try:validate_billing(c,broken)
        except ValueError:check(True,'收费合同反例被拒绝：'+label)
        else:raise ValueError('invalid fee accepted: '+label)
    consumables=patients*attempts*c['profiles']['A']['supply_units']*c['medical_supplies'][0]['unit_price']
    operations=b['daily_base_cost']+4*b['daily_cost_per_station']+dims['indoor_cells']*b['daily_cost_per_indoor_cell']
    exact_operations=(Fraction(str(b['daily_base_cost']))+4*Fraction(str(b['daily_cost_per_station']))
                      +dims['indoor_cells']*Fraction(str(b['daily_cost_per_indoor_cell'])))
    settled_days=[math.floor(day*exact_operations)-math.floor((day-1)*exact_operations) for day in range(1,21)]
    check(exact_operations==Fraction(1561,20) and settled_days==[78]*19+[79] and sum(settled_days)==1561,
          '运营按真实起始布局精确78.05/日，跨20日持余共结1561，不每日多收或丢零头')
    ticks_per_day=Fraction(str(b['day_seconds']))/Fraction(str(b['tick_seconds']))
    expanded_operations=exact_operations+Fraction(str(b['daily_cost_per_station']))+20*Fraction(str(b['daily_cost_per_indoor_cell']))
    operating_denominator=20*ticks_per_day
    midpoint_numerator=(exact_operations+expanded_operations)*operating_denominator/2
    check(exact_operations*operating_denominator/ticks_per_day==1561 and expanded_operations*operating_denominator/ticks_per_day==1741
          and divmod(midpoint_numerator,operating_denominator)==(82,198000),
          '日中真实新增1服务位和20室内格应付82余0.55，不按日末87.05追算全天')
    cls=index(b['equipment']['classes']);furniture=index(c['furniture_equipment'],'definition_id')
    equipment_classes=[m[o['definition_id']]['equipment_class'] if o['definition_id'] in m else furniture[o['definition_id']]['equipment_class'] for o in layout['objects']
                       if o['definition_id'] in b['equipment']['maintained_definition_ids']]
    # Conservative expected cost envelope: every roll uses the highest wear multiplier;
    # actual downtime/grace suppresses rolls, and normal equipment usually has lower risk.
    repairs=sum((b['day_seconds']/b['equipment']['scan_seconds'])*cls[k]['base_failure_bp']/10000*8*cls[k]['repair_parts'] for k in equipment_classes if k)
    maintenance_reserve=reference['maintenance_allowance_per_day']
    profit=revenue-consumables-wages-operations-repairs-maintenance_reserve
    fixed_reference_cost=wages+operations+repairs+maintenance_reserve
    contribution=per_visit_revenue-attempts*c['profiles']['A']['supply_units']*c['medical_supplies'][0]['unit_price']
    reference_rows=[(n,n*contribution-fixed_reference_cost) for n in reference['starter_completed_visits_per_day']]
    check(min(n for n in reference['starter_completed_visits_per_day'] if n>0)*contribution-fixed_reference_cost>=reference['slow_minimum_daily_margin'],
          '每日完成12人的条件参考余量不少于200，不依赖补助；不把机会数量当完成量')
    check((b['starting_cash']-construction-hire-initial_supplies)/fixed_reference_cost>=reference['minimum_zero_income_buffer_days'],
          '开院余款可覆盖至少十日零收入参考支出，不含补助和扩建')
    atlas = render_atlas(c,b,layout)
    check(f'建设{construction}，招聘{hire}，实际采购{b["supplies"]["initial_purchase_units"]}包治疗包{initial_supplies}，余款{b["starting_cash"]-construction-hire-initial_supplies}。' in atlas,
          '阅读页起始预算摘要包含真实治疗包采购，与源预算一致')
    link_count=check_links()
    lines=['# 设计核验报告','',f'日期：{date.today().isoformat()}；设计版本{c["content_version"]}。只验证设计数据、算术、静态几何和文档。',
           '',f'{len(checks)}项断言通过；{link_count}个本地Markdown链接有效。','',
           '## 内容与规则检查','',
           '- 80种族全部拥有至少6病例，普通人类14病例；154疾病、六类核心设备、84套自动演出、488适配互相可引用，原11种人类日常病保留。',
           '- 38项研究无环且所有病例有解锁路径，C档均有深度诊断前置，R33/R34不要求先完成住院或手术病例。',
           '- 原生UI文字的控件复用、完整布局依赖、同名重绑、即时中文输入与真实字体资源口径通过合同检查；12种负例被拒绝。1024方形页的1MiB/4MiB仅为无mip原始字节算例，实际字体后端、字形生成、排版、长帧及内存仍待实机验收。',
           '- 154病各至少2方案、24病另有手术，共332方案；53手术适配引用原绑定，四职称、六性格、两类临床主体及薪资表完整。',
           '- 医院/科室/医生/职工/病人五类评分权重闭合，10性格与6种专业回应引用有效，17诊室互动和24服务情境有界。',
           '- 80种族各有一件谢礼和一种回馈演出；8装修材料、6服务设施、4娱乐设备、付薪装修工与劳累休假参数可引用。',
           '- 怒气环境倍率、8…60秒问诊、不同医生回应、一天休假恢复和装修退款完成算术示例；10种生活合同负例被拒绝。',
           '- 接诊卡同等两组D09条件参考75…125次机会、原24小时排班覆盖预览及睡25秒后剩425秒与原数据一致；三种冲突负例被拒绝。实际病例混合客流、跨日建议权限与真实页面仍待实机验证。',
           '- 客流按病例与真实资源工时推导，四档75/90/100/110百分比和日波动、无偏整数舍入、床瓶颈及分班固定向量完成静态算术；12种合同负例被拒绝。原整日算法读取保留；完整投影求解、实际接诊压力、混合病例与日界性能尚未运行。',
           '- 关诊/满员到访机会先排除的原16种布尔组合、逐次同tick人数与18000个关诊机会完成静态对照；11种顺序/人数/随机/权限合同负例被拒绝。完整病例查询、真实随机序列与原取数成本仍待实机验证。',
           '- 初始三医生排班逐班覆盖初诊与两科治疗，循环跨日保留休息；三班连工负例被拒绝。',
           '- 四套手术/病房坐标夹具的物件、患者候位、普通人类团队与维修点通过静态BFS；不代表术中动画或实时避让已实现。',
           '- 180秒手术加15秒苏醒和20秒缓冲为215秒，可在600秒完整班内执行；临近换班仍查真实连续覆盖。日中晋级工资按18,000tick分母得160。',
           '- 同一无等待36秒A档样例，谨慎评分选择舒缓，讲效率评分选择常规；这是公式样例，不是玩法实测。',
           '- 80套身体在有足够墙段和净高时可由门自动适配；缺少墙段或净高的负例被拒绝。',
           '- 静态BFS检查初始人类完整路线、4.8米长颈鹿高门路线；石巨人不能误入尚未扩建的初诊室。',
           '- 25主事件、72日常互动的参与者、期限、非递归效果和场地引用完整；6回访引用真实来源定义，24情境具有6类生产者。',
           '- 3种全体型生活造型的容量覆盖80种族，操作/维修锚点不重叠本体，承托区足够；未证明实际房间路径和动画适配。',
           '- 轮换、滚动预算、600条记忆上限与工时合并公式完成合同及算术检查；11种喜剧合同负例被拒绝。',
           '- 五类活动的随机区间、必要设施、15性格/关系变体、八位固定身份和五条故事关联引用有效；原故事奖励仍由内容章拥有。',
           '- 4…10位合影场地、三位人类仍需三类邻居、独立场地配位和20人扩展活动完成定义及算术样例；18种活动合同负例被拒绝。未执行随机分布、真实配位、集合、散场或存档代码。',
           '- 集合预算的100F四人空返、完整前缀与异起终层、楼梯/缓降、同层/较大原报价及10000层算例通过；961模拟秒只是固定路线的设计算术，尚未执行真实集合或测量游戏性能。',
           '- 16成长与12委托有有效目标、奖励和解锁条件；维护集合与免维护家具明确区分；七岗位均有正工资。',
           '- 购地价序、共边规则、每3日补助及封顶、初始工资和换高门后的预算已核算。',
           '- 运营整币日结沿原累计持余，初始布局20日共1561、日中增建算例82余0.55及三种错误合同通过静态核验；尚未执行游戏日结、读档或预算代码。',
           '- 新包可只给新种族一条旧病例，旧人类可加新病症，不受core六病例与固定数量验收限制。',
           '- 随机到访窗口与期望闭合，6…60次机会的整数时刻范围严格互斥；时刻使用保存的日种子与序号派生，摘要和拒绝抽样样例仅校验设计算术，不证明Godot实现一致。',
           '- 等候120秒起的性格/环境概率样例为6%、2.6%、3%，环境分段与35%封顶有效；安全治疗阶段被排除。',
           '- 楼层与电梯站数无封顶；第5/10/100/1000/10000层具备设计数据样例，费用公式、下层前置、结构端口预算与稀疏记录合同有效。2…4F共27块楼板的129600费用仅为示例；高层实际性能尚未验证。',
           '- 上层单块购买的来源、下层Room内格交集与已完首块条件完成静态投影样例；电梯首两站同价、12600与6860采购算例、2133与928精确退款通过。尚未执行真实建造、派工、站点安装或事务恢复。',
           '- 七岗位介绍、六习惯、八履历和七招聘示例引用一致；24简历预算、付费寻访与标准保底参数完整。',
           '- 新增40病各4种身体，160条适配在同病内具有不同症状/治疗/康复文本；80种族各增加2病例，动画趣味仍须制作和试玩。',
           '- 到访跨窗、术中离院、悬空楼板、故障梯锁闭、重复候选等负例，以及楼层封顶、电梯四站、端口挤占设备名额和负增量楼价，加上选梯来源、下层房间、首块实完、完工交付与真实单站前置，共21种扩展合同负例被拒绝。',
           '- 合影康复对象/故事目标资格、同活动目标引用与五种错误定义通过静态核验；真实报名、完整配位、最小来源摘要恢复及同步故事完成仍须实施验收。',
           '- 十项开院引导与九类情境的真实来源、原两次教学来院及三种负例通过静态核验；未执行保存回执、引导切换或可访问性操作。',
           '- 两类生活服务与六种性格动作引用有效，368秒下次需求样例和三种负例通过；未执行生活占位、跨层与临床调度。',
           '- 十性格的八项实际选座条件、附近/环境带、定点排序和十种入座/低动态表现有效；2/8秒选择、边界与十种负例仅验证合同和算术，未运行占位、寻路或本机负载。',
           '- 真实到站叫梯、FIFO前缀、空载取消和同一时间轴合同有效；4/6秒闲梯、11/16/46秒前缀、11/19秒缓降、257组及600前缀/10000F条件算例只做数据算术，实际乘梯、出口占位与本机交通负载未运行。',
           '- 两种门诊表现模式、三台主体12段舒缓/低动态小戏与唯一冻结工作量合同有效；36/64.8秒累计边界、全84套映射和九种负例完成静态核验，正式身体动画、安抚边界、暂停/读档及本机负载未运行。',
           '- 十八场日常互动的36种回应各有静态定义；十二场指定回应的绑定角色/朋友/和解/普通选择与原6/8秒数据有效，四种内容合同负例被拒绝。柔光与第三倒影沿原槽和真实FUR42条件；打断、实际占位、会话恢复和本机负载仍待正式游戏验证。',
           '- 无语音对话、一张聚焦病例文字卡/两行/通常4现实秒、无语言叫号与非临床图符合同有效；八类32病例适配保留数量，六种违背媒体/显示边界的负例被拒绝。正式资源、字体布局、真实焦点切换和本机负载未运行。',
           '- 六岗位实践来源、55次实践与145秒研究样例、三种负例通过静态检查；未执行员工工作与交接。',
           '- 八类任务指引覆盖全部任务指标，换单/冷却样例与三种负例通过静态检查；未执行任务状态机或故事计数。',
           '- 六类财务视图、940成本/840资助与560结余算术、三种合同负例已做静态核验；未执行真实账目和预算界面。',
           '- 八类纪念册模板核对真实来源、可用字段和独立照片边界；三种伪造来源/结果与突破备份范围的反例被拒绝。',
           '- 九种就诊原因卡映射原事实来源；三种错误归因、附加评分和提前揭晓结果的反例被拒绝。',
           '- 六条研究路线引用原课题，120秒资料和双倍社区工作量保持原值；三种研究设计反例被拒绝。',
           '- 三档保养、四种维修表现、保养转维修差额及三种数据反例通过静态核验；实际派工仍待实现。',
           '- 六类医疗主体、四能力、实操与课程、80条种族职员天赋及九骨架覆盖完成静态合同和算术检查；实际调度、动画、成长与保存须在游戏中验证。',
           '- 自然回访、活动用途、清洁员唯一清理、升级和床边动作合同有效；广播定义与配置已移除。治疗包实际采购、预留、领用和温和罢工具备数据及算术边界；实际调度与保存仍待实现。',
           '- 六类医疗主体的18种结果表现、失败反馈来源与自动接续边界通过静态合同；四个条件性重试样例从病例/方案/收费数据推导，非法提前治愈、重复情绪效果与越过临床资源的样例被拒绝。实际失败接续、结果保密、身体动画和规模性能仍未运行。',
           '- 本机125H/Arc/32GiB基准、三维比例与原生界面、完整资源统计及真实模拟速度合同有效；75%/约67%尺寸、600秒真实tick下限和九种合同负例完成静态核验。没有运行游戏，不存在已测得的fps、功耗或显存峰值。',
           '- 六种成长片段、共同带教工时样例与三种反例完成静态核验；课堂调度与成长动作仍待实机验证。',
           '- 9张蓝图均解析到既有房间或临床布局，8张引导的蓝图/设备引用合法；70格地毯拆单总价与已装材料回收算术一致。13种蓝图引用、复制状态、床位绑定、自动应用和免费装修等设计合同负例被拒绝。',
           '- 改建腾空、库存复用原子性、临床连续性、共享资料库写入与屏风噪声传播尚无游戏运行证据；只完成规格、目录和静态检查。',
           '- 重复ID、缺引用、研究环、错误骨架、超大包络、绕过门伸展规则、未分类设备、事件递归、负奖励和未知互动角色均被拒绝。','',
           '## 起始预算与解析测算','']
    table(lines,['项目','设计计算'],[
        ['建设/招聘/初始60包采购/余款',f'{construction:,} / {hire:,} / {initial_supplies:,} / {b["starting_cash"]-construction-hire-initial_supplies:,}'],
        ['7人工资/日',wages],['运营精确均值/日',f'{operations:.2f}'],[f'{patients}次完成就诊的条件参考收入',f'{revenue:.2f}'],
        ['治疗包领用成本估算',f'{consumables:.2f}'],['最坏磨损档概率下的随机修理费期望上界',f'{repairs:.2f}'],
        ['预防保养预算假设',maintenance_reserve],['未计补助/任务的经营余量',f'{profit:.2f}'],
        ['1地块周期补助',f'每3日{grant(1)}；周期平均{grant(1)/3:.0f}/日，并非每天发'],
        ['额外8地块合计',sum(b['plot_prices'])],
        ['手术室/双床病房建设',f'{clinical_costs["or_standard"]:,} / {clinical_costs["ward_two_beds"]:,}'],
        ['全部成长现金奖励/全部委托模板各一次现金',f'{sum(q["reward_cash"] for q in c["tasks"] if q["kind"]=="milestone")} / {sum(q["reward_cash"] for q in c["tasks"] if q["kind"]=="commission")}']])
    table(lines,['每日完成就诊数','未计资助的长期成本口径余量','加一地块周期补助日均后的参考值'],[
        [n,f'{margin:.2f}',f'{margin+grant(1)/b["subsidy"]["interval_days"]:.2f}'] for n,margin in reference_rows])
    lines += [f'按实际五种初始病症等权，平均治愈费{mean_cure_fee:.0f}，全部指定常规门诊、治疗能力1、住院医师诊费20、初诊台5、每次主体10、无舒适/升级、首试92%和重试98%估算。完成数指已经到院并走完至两次上限或治愈的Visit，并非当日机会数；跨日结算可能使某天收入为零。默认医生自主可能选择舒缓，结果另需模拟。耗材按领用成本估算，实际现金支出由采购批次决定，不向账目重复扣除这一估算。故障费按维护集合内已放设备每60秒都处于最高风险计算期望上界，不是单日最大损失；保养120/医院日是预算假设。未计算随机弃候、会诊、故障停机、跨层走路、排班、休息、事件造成的吞吐下降，不能证明真实盈利或好玩。',
              f'无新采购、扩建或招聘、无任何收入和补助时，初始余款除以上述工资/运营/修理/保养预算约为{(b["starting_cash"]-construction-hire-initial_supplies)/fixed_reference_cost:.1f}日；这是期望预算缓冲，不是随机故障损失保证。补助每三日真实到账，日均列只作周期比较。balance_reference是设计校准输入，不提供玩家开关、自动收入或额外难度参数。','',
              '## 实施验证边界','',
              '未运行Godot游戏、生产正式资产、测量寻路/帧率、执行存档代码、构建安装包或开展试玩。医生选择、晋级排班、手术护理、随机故障、维修排队、补助经济、任务幂等、宽高改建、回访、来客离院、多层交通、招聘、喜剧频率、随机人数活动、实际带教、维修派工、研究资料、就诊复盘、照片保存、自然回诊、日常清洁、逐级施工、家属探视、库存采购、罢工复工与真实伸缩占地仍须按AC01…AC316、V01…V675在实现中验证。','',
              '## 复现','',
              '在项目根用PowerShell 7运行docs/tools/export-design.ps1。导出会先执行设计核验，再将自动生成的内容索引和本报告直接嵌入离线阅读本，不保留中间Markdown文件。只检查设计数据可单独运行Python 3的docs/tools/validate_design.py，不写入文件。',
              '', '对应[验收标准](design/06-validation.md)。','']
    result = {'atlas': atlas, 'report': '\n'.join(lines), 'checks': len(checks), 'local_links': link_count}
    if quiet:
        return result
    print(f'DESIGN_CHECKS_PASS={len(checks)}; LOCAL_LINKS={link_count}')
    print('CATALOG=80 species / 154 diseases / 6 medical devices / 84 routines / 488 bindings / 38 research')
    print('CLINICAL=332 plans / 24 surgeries / 53 surgical adapters / 2 integrated clinical devices / 4 titles / 6 personalities')
    print(f'LIFE={len(c["patient_personalities"])} patient personalities / {len(c["consultation_behaviors"])} consultation scenes / {len(c["hospital_situations"])} service situations / {len(c["species_gifts"])} gifts + {len(c["gratitude_abilities"])} ability scenes')
    print('SOCIAL=25 incidents + 72 interactions + 6 callbacks; ACCESS=3 facilities; TASKS=16 milestones + 12 commissions; DOORS=6')
    print('ACTIVITIES=6 random-size activities / 18 variations / 9 recurring identities / 6 story links; NOT_GAMEPLAY_MEASUREMENT')
    print('REMODEL=9 blueprint presets / 8 guides; STATIC_DESIGN_ONLY')
    print('GROWTH=no floor cap / 3 connectors / 7 roles / 6 work styles / 8 biographies / 7 example candidates')
    print(f'STARTER_CASH={b["starting_cash"]-construction-hire-initial_supplies}; WAGES_PER_DAY={wages}')
    print(f'ANALYTIC_OPERATING_MARGIN={profit:.2f}; NOT_GAMEPLAY_MEASUREMENT')
    return result

if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chapters-json', action='store_true', help='Render generated book chapters as JSON on stdout')
    args = parser.parse_args()
    result = main(quiet=args.chapters_json)
    if args.chapters_json:
        print(json.dumps(result, ensure_ascii=False))
