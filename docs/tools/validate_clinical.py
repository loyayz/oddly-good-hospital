"""Static clinical design checks and readable tables, independent of game runtime."""
from collections import defaultdict, deque
import math


def require(ok, message):
    if not ok:
        raise ValueError(message)


def indexed(rows, key='id'):
    result = {row[key]: row for row in rows}
    require(len(result) == len(rows), 'duplicate clinical definition')
    return result


def expanded_footprint(base, body, reclined=False):
    """Reference geometry for a real, fixed-origin expansion; not runtime code."""
    depth = max(body['depth_m'], body['height_m']) if reclined else body['depth_m']
    return [max(base[0], math.ceil(body['width_m']/1.5)),
            max(base[1], math.ceil(depth/1.5))]


def binding_body(species, binding):
    """Static reference for an active, uncured case's physical envelope."""
    base = species['body']
    symptom = binding.get('symptom_envelope', base)
    return {key: max(base[key], symptom[key]) for key in base}


def starter_staff_costs(balance, layout):
    pay = indexed(balance['doctor_pay'], 'title_id')
    hire = sum(pay[d['title_id']]['hire'] for d in layout['doctor_roster'])
    wages = sum(pay[d['title_id']]['wage_day'] for d in layout['doctor_roster'])
    for role in balance['staff']:
        if role['role'] == 'doctor':
            continue
        count = balance['starting_staff'].get(role['role'], 0)
        hire += count * role['hire']
        wages += count * role['wage_day']
    return hire, wages



def validate_billing(c, b):
    policy = b['billing']
    titles = indexed(c['doctor_titles'])
    fees = indexed(policy['doctor_consultation_fees'], 'title_id')
    require(set(fees) == set(titles), 'doctor fee title coverage')
    amounts = [fees[t['id']]['amount'] for t in sorted(titles.values(), key=lambda t:t['rank'])]
    require(all(type(n) is int and n > 0 for n in amounts)
            and all(a < z for a,z in zip(amounts,amounts[1:])), 'doctor title fee must increase')
    facilities = indexed(policy['facility_fees'])
    equipment_ids = {x['definition_id'] for x in c['medical_equipment_profiles']}
    require({x['equipment_id'] for x in facilities.values()} == equipment_ids, 'facility fee coverage')
    expected = {(x['equipment_id'], x['service']) for x in c['diagnostic_modes']}
    expected |= {(x['definition_id'], x['effect_kind']) for x in c['medical_equipment_profiles']
                 if x['effect_kind'] != 'diagnostic'}
    pairs = [(x['equipment_id'],x['service_kind']) for x in facilities.values()]
    require(len(pairs) == len(set(pairs)) and set(pairs) == expected, 'duplicate or missing service fee')
    require(all(type(x['amount']) is int and x['amount'] > 0 and x['name']
                for x in facilities.values()), 'invalid facility fee')
    require('gp_fee' not in b and 'care_fee' not in b['clinical']
            and all('charges_care_fee' not in p for p in c['treatment_protocols']), 'duplicate old tariff')
    require(policy['doctor_quote_at'] == 'first_actual_gp_start'
            and policy['doctor_charge_at'] == 'gp_completed'
            and policy['facility_quote_at'] == 'service_or_attempt_start'
            and policy['facility_charge_at'] == 'actual_service_completed'
            and policy['retry_facility_fee'] == 'each_completed_attempt'
            and policy['ward_fee'] == 'once_per_completed_recovery_in_attempt'
            and policy['cure_fee'] == 'once_per_successful_visit'
            and policy['charge_key'] == 'owner_id_and_component'
            and policy['upgrade_fee_multiplier'] == 1
            and policy['unfinished_service_fee'] == 0
            and policy['price_management'] is False and policy['payment_debt'] is False,
            'billing charges unperformed or repeated work')
    price = c['medical_supplies'][0]['unit_price']
    outpatient_max = max(x['amount'] for x in facilities.values() if x['service_kind']=='outpatient')
    ward = next(x['amount'] for x in facilities.values() if x['service_kind']=='ward')
    surgery = next(x['amount'] for x in facilities.values() if x['service_kind']=='surgery')
    require(outpatient_max <= c['profiles']['A']['supply_units']*price
            and surgery+ward < min(p['supply_units'] for p in c['treatment_protocols']
                                   if p['kind']=='surgery')*price
            and all(outpatient_max+(ward if profile['recovery_seconds'] else 0)
                    <= profile['supply_units']*price
                    for p in c['treatment_protocols'] if p['kind']=='outpatient' and not p['uses_disease_profile']
                    for profile in p['clinical_profiles'].values()),
            'failed treatment earns more facility fees than supply cost')


def validate_clinical(catalog, balance):
    validate_billing(catalog, balance)
    require(balance['plan_reassessment'] == {
        'probability_change':'decrease_only','threshold_source':'clinical.reconsult_probability_delta',
        'automatic_owner':'consulting_doctor','manual_choice':'retain_plan_until_explicit_change',
        'temporary_resource_wait_reconsults':False,'max_pending_per_visit':1,
        'affects_committed_attempt':False}, 'plan review adds repeated confirmations or overrides manual intent')
    diseases = indexed(catalog['diseases'])
    research = indexed(catalog['research'])
    protocols = indexed(catalog['treatment_protocols'])
    plans = indexed(catalog['treatment_plans'])
    bindings = indexed(catalog['treatment_bindings'])
    equipment = indexed(catalog['clinical_equipment'])
    classes = indexed(balance['equipment']['classes'])
    titles = indexed(catalog['doctor_titles'])
    personalities = indexed(catalog['doctor_personalities'])
    pay = indexed(balance['doctor_pay'], 'title_id')
    require(set(pay) == set(titles), 'title pay coverage')
    require(sorted(t['rank'] for t in titles.values()) == list(range(len(titles))), 'title order')
    for title in titles.values():
        cost = pay[title['id']]
        require(cost['wage_day'] > 0 and cost['hire'] > 0, 'unpaid doctor title')
        require(set(title['recruitment']['requires_research']) <= set(research), 'unknown recruitment unlock')
        promotion = title['promotion']
        if title['rank'] == 0:
            require(promotion is None, 'entry title has predecessor')
            continue
        require(promotion is not None and promotion['prior_title_id'] in titles, 'missing prior title')
        require(titles[promotion['prior_title_id']]['rank'] + 1 == title['rank'], 'promotion skips title')
        require(set(promotion['requires_research']) <= set(research), 'unknown promotion research')
        require(1 <= promotion['primary_level'] <= 5 and 1 <= promotion['diagnosis_level'] <= 5
                and 0 <= promotion['secondary_level'] <= 5, 'impossible promotion ability')
        require(promotion['cured_case_count'] > 0 and 'completed_courses' not in promotion
                and cost['promotion_cost'] > 0 and cost['promotion_seconds'] > 0, 'empty promotion')
    for personality in personalities.values():
        weights = personality['weights']
        require(set(weights) == {'success', 'time', 'burden', 'familiarity', 'novelty', 'team'}, 'incomplete personality weights')
        require(all(math.isfinite(v) and 0 <= v <= 10 for v in weights.values())
                and weights['success'] > 0, 'invalid personality weights')
    for protocol in protocols.values():
        require(protocol['kind'] in ('outpatient', 'surgery'), 'unknown treatment protocol')
        require(0 <= protocol['complex_penalty'] < 1 and protocol['cure_fee_multiplier'] > 0, 'invalid plan adjustment')
        if protocol['kind'] == 'surgery':
            require(protocol['min_surgeon_title_id'] in titles and protocol['min_anesthetist_title_id'] in titles, 'unknown surgical title')
            require(protocol['requires_distinct_staff'] is True, 'surgeon doubles as anesthetist')
            require(set(protocol['required_equipment_ids']) <= set(equipment), 'missing surgical equipment')
            require(all(1 <= protocol[k] <= 5 for k in ['min_surgeon_surgery', 'min_anesthetist_surgery', 'min_nurse_surgery']), 'unreachable surgery skill')
            require(0 < protocol['base_success'] < 1 and protocol['supply_units'] > 0
                    and protocol['recovery_seconds'] > 0 and protocol['work_seconds'] > 0, 'invalid surgery values')
        elif protocol['uses_disease_profile']:
            require('clinical_profiles' not in protocol, 'routine duplicates disease profile values')
        else:
            require(set(protocol['clinical_profiles']) == set(catalog['profiles']), 'missing gentle profile')
            for profile in protocol['clinical_profiles'].values():
                require(0 < profile['base_success'] < 1 and 1 <= profile['min_treatment'] <= 5
                        and profile['supply_units'] > 0 and profile['recovery_seconds'] >= 0, 'invalid gentle profile')
        if protocol['kind'] == 'outpatient':
            require(protocol['work_multiplier'] > 0, 'invalid outpatient work')
    by_disease = defaultdict(set)
    for plan in plans.values():
        require(plan['disease_id'] in diseases and plan['protocol_id'] in protocols, 'missing plan reference')
        require(set(plan['requires_research']) <= set(research), 'missing plan unlock')
        by_disease[plan['disease_id']].add(plan['protocol_id'])
        if protocols[plan['protocol_id']]['kind'] == 'surgery':
            require(len(plan.get('beats', [])) == 4 and all(plan['beats']), 'missing surgical beats')
    require(set(by_disease) == set(diseases) and all(len(v) >= 2 for v in by_disease.values()), 'disease lacks multiple plans')
    adapter_pairs = set()
    covered_plans = set()
    for adapter in indexed(catalog['surgical_adapters']).values():
        require(adapter['binding_id'] in bindings and adapter['plan_id'] in plans, 'missing surgical adapter reference')
        binding, plan = bindings[adapter['binding_id']], plans[adapter['plan_id']]
        require(binding['disease_id'] == plan['disease_id']
                and protocols[plan['protocol_id']]['kind'] == 'surgery', 'wrong surgery case binding')
        require(set(adapter) == {'id', 'binding_id', 'plan_id', 'patient_pose', 'target_description', 'required_anchors'}, 'surgical adapter duplicates binding facts or has unknown fields')
        require(all(isinstance(adapter.get(k), str) and adapter[k].strip() for k in ['patient_pose', 'target_description']), 'incomplete surgical variant')
        require(set(adapter['required_anchors']) == {'patient_support', 'symptom_target', 'exit'}, 'missing surgical anchor contract')
        pair = adapter['binding_id'], adapter['plan_id']
        require(pair not in adapter_pairs, 'duplicate surgical adaptation')
        adapter_pairs.add(pair)
        covered_plans.add(plan['id'])
    require(covered_plans == {p['id'] for p in plans.values() if protocols[p['protocol_id']]['kind'] == 'surgery'}, 'surgery has no body adaptation')
    for eq in equipment.values():
        require(eq['equipment_class'] in classes and eq['price'] > 0, 'clinical equipment missing fault class')
        require(set(eq['requires_research']) <= set(research) and len(eq['footprint']) == 2
                and all(1 <= v <= 10 for v in eq['footprint']), 'invalid clinical equipment definition')
        if 'adapter_capacity' in eq:
            cap = eq['adapter_capacity']
            require(1 <= cap['max_clearance_cells'] <= 3 and 0 < cap['max_height_m'] <= 7, 'invalid bed/table capacity')
    for room in indexed(catalog['clinical_room_types']).values():
        require(set(room['requires_research']) <= set(research), 'missing clinical room research')
        require(set(room['required_equipment_ids'] + room.get('bed_equipment_ids', [])) <= set(equipment), 'missing room equipment')
    training = balance['doctor_training']
    courses = indexed(training['courses'], 'target_level')
    require(set(courses) == {1, 2, 3, 4, 5}, 'missing training level')
    require(courses[1]['practice_required'] == courses[2]['practice_required'] == 0, 'surgical training bootstrap deadlock')
    require(all(x['cost'] > 0 and x['work_seconds'] > 0 and x['practice_required'] >= 0 for x in courses.values()), 'invalid doctor training')
    require({training[k] for k in ['advanced_research', 'surgical_research', 'discount_research']} <= set(research), 'missing training unlock')
    require(training['mentor_min_title_id'] in titles and 'max_specialties' not in training, 'invalid training mentor or per-department skill tree')
    schedule = balance['schedule']
    require(schedule['shift_seconds'] * schedule['shifts_per_day'] == balance['day_seconds'], 'shift day mismatch')
    clinical = balance['clinical']
    require(0 < clinical['minimum_predicted_success'] < 1 and clinical['beds_per_nurse'] > 0, 'invalid clinical bounds')
    require(clinical['max_beds_per_room'] == clinical['beds_per_nurse'] == 8
            and clinical['max_ward_beds'] is None, 'ward growth has a global cap or loses care workload bounds')


def validate_roster(c, b, layout):
    titles, personalities, departments = (indexed(c[k]) for k in ['doctor_titles', 'doctor_personalities', 'specialties'])
    roster = indexed(layout['doctor_roster'])
    require(len(roster) == b['starting_staff']['doctor'], 'starter doctor count mismatch')
    for doctor in roster.values():
        require(doctor['title_id'] in titles and doctor['personality_id'] in personalities, 'unknown starter doctor traits')
        require(1 <= doctor['diagnosis'] <= 5 and 1 <= doctor['treatment'] <= 5 and 0 <= doctor['surgery'] <= 5, 'invalid starter ability')
        require(not {'specialties','anesthesia'} & set(doctor)
                and doctor['primary_track'] in {'diagnosis','treatment','surgery'}, 'obsolete or excessive starter abilities')
        work = [s['kind'] != 'rest' for s in doctor['shifts']]
        require(len(work) == b['schedule']['shifts_per_day'] and work.count(False) >= b['schedule']['minimum_rest_shifts'], 'missing rest shift')
        repeated = work + work
        span = b['schedule']['max_consecutive_work_shifts'] + 1
        require(not any(all(repeated[i:i+span]) for i in range(len(work))), 'cross-day work limit')
        for shift in doctor['shifts']:
            require(shift['kind'] in ('rest', 'outpatient', 'surgery', 'rounds', 'training'), 'unknown shift task')
            if shift['kind'] == 'outpatient':
                require(0 < len(shift['pool']) <= 3 and set(shift['pool']) <= {'diagnosis', *departments}, 'unqualified clinic assignment')
    for shift_index in range(b['schedule']['shifts_per_day']):
        covered = set()
        for doctor in roster.values():
            shift = doctor['shifts'][shift_index]
            if shift['kind'] == 'outpatient':
                covered.update(shift['pool'])
        require({'diagnosis', 'T01', 'T10'} <= covered, 'starter shift lacks diagnosis or treatment')


def validate_bed_links(layout):
    objects = layout['objects']
    beds = {i for i, obj in enumerate(objects) if obj['definition_id'] == 'EQ05'}
    linked_beds = set()
    for link in layout['bed_links']:
        require(set(link) == {'bed_index'}, 'bed carries separately managed components')
        require(all(type(i) is int and 0 <= i < len(objects) for i in link.values()), 'bed link index out of range')
        bed = link['bed_index']
        require(bed in beds and bed not in linked_beds, 'duplicate or invalid linked bed')
        linked_beds.add(bed)
    require(linked_beds == beds, 'incomplete clinical bed links')


def validate_layouts(c, b, data, check):
    equipment, doors = indexed(c['clinical_equipment']+c['service_equipment']), indexed(c['doors'])
    costs = {}
    def cells(anchor, size):
        return {(x, y) for x in range(anchor[0], anchor[0]+size[0]) for y in range(anchor[1], anchor[1]+size[1])}
    for layout in data['layouts']:
        validate_bed_links(layout)
        check(True, layout['id']+' 主体床索引唯一完整，内置功能不重复摆放')
        w, h = layout['size']
        area = cells([0, 0], [w, h])
        blocked = set()
        for obj in layout['objects']:
            body = indexed(c['species'])[layout['sample_species_id']]['body']
            definition=equipment[obj['definition_id']]
            footprint=expanded_footprint(definition['footprint'], body, True) if obj['definition_id'] in {'EQ01','EQ05'} else definition['footprint']
            occupied = cells(obj['anchor'], footprint)
            check(occupied <= area and not occupied & blocked, layout['id']+' 设备真实展开后在房内且不重叠')
            blocked |= occupied
        door = doors[layout['door_id']]
        check(layout['door_offset']+max(door['span_cells'],layout['patient_clearance']) <= w, layout['id']+' 门展开后墙段跨度足够')
        def reachable(k):
            start = layout['door_offset'], h-k
            def valid(p):
                region = cells(p, [k, k])
                return region <= area and not region & blocked
            require(valid(start), 'blocked clinical entry')
            seen, todo = {start}, deque([start])
            while todo:
                x, y = todo.popleft()
                for dx, dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                    q = x+dx, y+dy
                    if q not in seen and valid(q):
                        seen.add(q); todo.append(q)
            return seen
        reserved = set()
        for point in layout['service_points']:
            region = cells(point['anchor'], [point['clearance']]*2)
            check(tuple(point['anchor']) in reachable(point['clearance']) and not region & reserved, layout['id']+' '+point['kind']+' 可达且工作区不重叠')
            reserved |= region
        maintained=[o for o in layout['objects'] if o['definition_id'] in b['equipment']['maintained_definition_ids']]
        check(len(layout['repair_points']) == len(maintained), layout['id']+' 维护设备有维修点，护士台免维护')
        if layout['room_type_id']=='ward':
            check(any(o['definition_id']=='SE06' for o in layout['objects'])
                  and any(p['kind']=='nurse_base' for p in layout['service_points']),layout['id']+' 包含真实护士工作台和操作点')
        for point in layout['repair_points']:
            check(tuple(point) in reachable(1), layout['id']+' 维修点可达')
        costs[layout['id']] = w*h*(b['floor_cost_cell']+b['room_fitout_cost_cell']) + door['price'] + sum(equipment[x['definition_id']]['price'] for x in layout['objects'])
    check(costs['or_standard'] == 13800 and costs['ward_two_beds'] == 6700, '普通手术室与含护士台双床病房造价20500')
    return costs


def plan_score(weights, probability, seconds, burden, familiarity=0, novelty=1, team=1):
    return (weights['success']*probability*100 - weights['time']*seconds/10 - weights['burden']*burden
            + weights['familiarity']*familiarity + weights['novelty']*novelty + weights['team']*team)


def append_clinical_atlas(lines, c, b, table):
    titles, pay = indexed(c['doctor_titles']), indexed(b['doctor_pay'], 'title_id')
    diseases, protocols, plans, bindings, species = (indexed(c[k]) for k in ['diseases', 'treatment_protocols', 'treatment_plans', 'treatment_bindings', 'species'])
    lines += ['## 医生职称与性格', '', '医生能力、课程、晋级、排班与完整医疗流程见[临床团队规格](design/07-clinical-team.md)。', '']
    fees = indexed(b['billing']['doctor_consultation_fees'], 'title_id')
    table(lines, ['职称', '初诊诊费', '日工资 / 招聘费', '晋级评估费用 / 工时'], [
        [x['name'], fees[x['id']]['amount'], f"{pay[x['id']]['wage_day']} / {pay[x['id']]['hire']}", f"{pay[x['id']]['promotion_cost']} / {pay[x['id']]['promotion_seconds']}秒"] for x in titles.values()])
    lines += ['诊费只在本次初诊完成后收一次；设施按真实完成服务收费，治愈费仍只在成功后收一次。失败重试是新的实际使用，暂停接续、换床与读档不重复收费。', '']
    table(lines, ['医疗设施项目', '使用费', '设备 / 服务'], [
        [x['name'], x['amount'], x['equipment_id']+' / '+x['service_kind']] for x in b['billing']['facility_fees']])
    table(lines, ['性格', '成功', '时间', '负担', '熟悉', '探索', '协作'], [
        [x['name'], *[x['weights'][k] for k in ['success','time','burden','familiarity','novelty','team']]] for x in c['doctor_personalities']])
    lines += ['评分=成功权重×预测百分数−时间权重×总秒数/10−负担权重×负担+其余三项奖励。只能在满足能力、路线、资源及75%底线的方案中比较。', '', '## 154病症的332套治疗方案', '',
              '常规沿用病症档位；舒缓工时×1.8，基础成功率A97%/B95%/C93%，C档需180秒观察。以下全部方案均须病例原研究已解锁，手术另外需要R34。','']
    rows = []
    for disease in diseases.values():
        choices = [p for p in plans.values() if p['disease_id'] == disease['id']]
        operation = next((p for p in choices if protocols[p['protocol_id']]['kind'] == 'surgery'), None)
        surgery = '无'
        if operation:
            protocol = protocols[operation['protocol_id']]
            surgery = f"{operation['name']} / 难度{protocol['difficulty']} / {protocol['work_seconds']}秒+恢复{protocol['recovery_seconds']}秒 / 治疗包{protocol['supply_units']}"
        rows.append([disease['id']+' '+disease['name'], '常规 + 舒缓', surgery])
    table(lines, ['病症', '门诊方案', '专科手术方案'], rows)
    lines += ['## 24种搞怪手术四段演出', '']
    table(lines, ['方案', '准备', '过程', '高潮', '安全收尾'], [[p['id']+' '+p['name'], *p['beats']] for p in plans.values() if 'beats' in p])
    lines += ['## 53条手术身体适配', '']
    table(lines, ['身体 / 方案', '承托姿态', '操作目标', '最终治愈表现（引用病例）'], [
        [species[bindings[a['binding_id']]['species_id']]['name']+' / '+plans[a['plan_id']]['name'], a['patient_pose'], a['target_description'], bindings[a['binding_id']]['recovery_variant']] for a in c['surgical_adapters']])
    lines += ['## 手术与住院专用设备', '']
    table(lines, ['设备', '占地 / 价格', '患者容量', '故障类别', '研究'], [
        [e['id']+' '+e['name'], '×'.join(map(str,e['footprint']))+' / '+str(e['price']),
         str(e['adapter_capacity']['max_clearance_cells'])+'格 / 最高6.5米' if 'adapter_capacity' in e else '由实际人员操作区验证',
         e['equipment_class'], ','.join(e['requires_research'])] for e in c['clinical_equipment']])
    clinical_hire=2*pay['DT02']['hire']+2*indexed(b['staff'],'role')['nurse']['hire']
    lines += [f'四套[带坐标房间预设](data/clinical-layouts.json)包含普通/巨型手术室与双床/巨型病房。普通手术室13,800，含护士台双普通床病房6,700；另招两位主治和两位护士{clinical_hire:,}，增加工资560/日；未取得的手术能力还需培训。', '']
