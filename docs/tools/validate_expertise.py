"""Static checks for the small medical catalog, abilities and species talents."""
import copy
import math
from fractions import Fraction
from validate_clinical import indexed, require
from validate_care import upgrade_cost

ABILITIES = {'diagnosis': {'doctor','nurse'}, 'treatment': {'doctor'},
             'surgery': {'doctor','nurse'}, 'care': {'nurse'}}
CORE = {'FUR02','M09','M37','M17','EQ01','EQ05'}
GROUPS = {'T01':'M09','T05':'M09','T09':'M09','T02':'M37','T03':'M37',
          'T04':'M37','T08':'M37','T10':'M37','T06':'M17','T07':'M17'}
ACTION_NAMES = {'gp':'初诊','test':'检查','outpatient':'门诊治疗','or_assist':'手术准备',
                'registration':'登记','guidance':'导诊','ward_visit':'主动床边照护',
                'bed_transfer':'安全转床','maintenance':'维修/保养','cleanup':'清扫',
                'research':'实际研究','surface_unit':'表面装修','floor_module':'楼板施工',
                'course':'医护课程','thaw':'解冻照护'}
CONDITION_NAMES = {'always':'本人完成相应工作','late_shift':'晚班',
                   'tall_patient':'患者高于2.4米','large_patient':'患者通行宽度3格',
                   'micro_patient':'患者为micro骨架'}


def validate_expertise(c, b):
    require(b['diagnostic_flow'] == {
        'completed_test_limit':'once_per_mode_per_visit','skip_at_threshold':True,
        'progress_source':'actual_completed_service','duplicate_guard':'visit_evidence_by_source',
        'skipped_service_effects':False}, 'diagnosis repeats paid tests or invents skipped work')
    abilities = indexed(c['clinical_abilities'])
    require(set(abilities) == set(ABILITIES), 'medical skills expanded beyond four readable abilities')
    for key, roles in ABILITIES.items():
        require(set(abilities[key]) == {'id','name','roles','initial_level','work_summary'}
                and isinstance(abilities[key]['work_summary'],str) and abilities[key]['work_summary'].strip()
                and set(abilities[key]['roles']) == roles
                and abilities[key]['initial_level'] == (0 if key=='surgery' else 1), 'wrong ability role or entry')
    expected_sources = {
        ('doctor','diagnosis'):{'gp_completed','test_completed'},
        ('doctor','treatment'):{'outpatient_completed','discharge_round_completed'},
        ('doctor','surgery'):{'surgery_completed','anesthesia_completed','observation_completed'},
        ('nurse','diagnosis'):{'test_completed'},
        ('nurse','care'):{'guidance_corrected','incident_care_completed','ward_visit_completed','bed_transfer_completed'},
        ('nurse','surgery'):{'or_assistance_completed'}}
    rows = indexed(c['clinical_practice_sources'])
    require(len(rows)==6 and {(r['role'],r['ability']) for r in rows.values()}==set(expected_sources), 'missing clinical practice mapping')
    for r in rows.values():
        require(set(r)=={'id','role','ability','sources'} and set(r['sources'])==expected_sources[(r['role'],r['ability'])], 'invalid clinical practice fact')
    growth=b['clinical_ability_growth']
    require(growth['auto_level_thresholds']=={'2':20,'3':50,'4':100,'5':180}
            and growth['practice_total_cap']==180 and growth['promotion_phase']==9
            and growth['entry_requires_course'] is True and growth['practice_advances_during_course'] is True
            and 'defer_while_course_active' not in growth
            and growth['superseded_course'] == 'cancel_and_refund_unfinished'
            and growth['settlement_order'] == 'completed_course_then_practice_then_superseded_refund'
            and growth['practice_grants_course_fact'] is False
            and growth['promotion_requires_paid_courses'] is False, 'unbounded or duplicated clinical growth')
    require(growth['doctor_initial_profile']=={'diagnosis':1,'treatment':1,'surgery':0}
            and growth['nurse_initial_profile']=={'diagnosis':1,'care':1,'surgery':0}, 'too many initial clinical skills')
    require(all('completed_courses' not in r['promotion'] for r in c['doctor_titles'] if r['promotion']), 'practical progression blocked by course count')
    require(indexed(c['tasks'])['Q13']['metric']=='doctors_with_two_abilities'
            and indexed(c['tasks'])['Q13'].get('metric_parameters') == {
                'minimum_ability_count':2,'minimum_ability_level':2},
            'task still needs per-specialty skills or lacks ability thresholds')

    machines=indexed(c['machines']); clinical=indexed(c['clinical_equipment'])
    furniture=indexed(c['furniture_equipment'],'definition_id')
    profiles=indexed(c['medical_equipment_profiles']); seen=set()
    require(set(machines)=={'M09','M37','M17'} and set(clinical)=={'EQ01','EQ05'}
            and not {'FUR03','FUR04'} & set(furniture), 'separate treatment or diagnostic devices reintroduced')
    require(furniture['FUR02']['price']==800 and clinical['EQ01']['price']==11100
            and clinical['EQ05']['price']==1850, 'core device quote mismatch')
    expected_ops = {
        'FUR02': [('doctor','diagnosis',1,[]),('nurse','diagnosis',1,[])],
        'EQ01': [('doctor','surgery',2,['R34']),('nurse','surgery',1,['R34'])],
        'EQ05': [('nurse','care',1,['R33'])]}
    for r in profiles.values():
        require(set(r)=={'id','definition_id','effect_kind','operators','upgrade_tier_source','operator_summary','upgrade_summary'}
                and all(isinstance(r[k],str) and r[k].strip() for k in ('operator_summary','upgrade_summary')), 'equipment profile duplicates state or lacks readable roles and benefits')
        did=r['definition_id'];require(did in CORE and did not in seen,'duplicate or unknown equipment profile');seen.add(did)
        ops=[(o['role'],o['track'],o['min_level'],o['requires_research']) for o in r['operators']]
        require(ops==expected_ops.get(did,[('doctor','treatment',1,[])]), 'unqualified equipment operator')
        require(r['upgrade_tier_source']=='upgrade_tiers', 'separate component upgrade tree')
    require(seen==CORE,'incomplete six-device catalog')
    for r in c['treatment_routines']:
        require(set(r)=={'id','name','equipment_id','specialty_id','service_seconds','beats'}
                and r['equipment_id']==GROUPS[r['specialty_id']], 'routine becomes a purchased or manually installed item')
    modes=indexed(c['diagnostic_modes'])
    require({r['service'] for r in modes.values()}=={'gp','spectrum','resonance'}
            and len(modes)==3 and all(r['equipment_id']=='FUR02' for r in modes.values()), 'diagnostic modes split into devices')
    require(modes['DM_GP']['operators']==[{'role':'doctor','ability':'diagnosis','min_level':1,'requires_research':[]}]
            and all(modes[key]['operators']==[
                {'role':'doctor','ability':'diagnosis','min_level':2,'requires_research':['R11']},
                {'role':'nurse','ability':'diagnosis','min_level':1,'requires_research':[]}]
                for key in ['DM_SPECTRUM','DM_RESONANCE'])
            and modes['DM_SPECTRUM']['unlock']=='first_profile_B'
            and modes['DM_RESONANCE']['unlock']=='R11', 'wrong diagnostic role or unlock')
    require(clinical['EQ01']['integrated_functions']==['operate','anesthesia','monitor','instruments']
            and clinical['EQ05']['integrated_functions']==['bed','monitor','care_record'], 'incomplete integrated medical function')
    effects=b['medical_equipment_effects']
    require(effects['utilization_by_level']==[0,0.6,0.7,0.8,0.9,1.0]
            and effects['qualification_before_utilization'] is True
            and effects['equipment_grade_changes_min_skill'] is False
            and effects['freeze_attempt'] is True and effects['ward_rate_freeze']=='coverage_segment'
            and effects['surgery_aggregation']=='one_table_mean_three_operators'
            and effects['ward_aggregation']=='one_bed_actual_covering_nurse', 'unsafe equipment utilization or duplicate component effect')
    for k,v in effects.items():
        if '_per_' in k:require(isinstance(v,(int,float)) and not isinstance(v,bool) and 0<v<=3, 'invalid equipment coefficient')
    require(b['clinical']['or_setup_seconds']==8, 'undefined assisted preparation work')

    species=indexed(c['species']); roles={r['role'] for r in c['staff_role_profiles']}
    rigs={r['rig'] for r in c['species']}; adapters=indexed(c['staff_rig_adapters'])
    require({r['rig'] for r in adapters.values()}==rigs and len(adapters)==len(rigs), 'staff rig coverage incomplete')
    for r in adapters.values():
        require(set(r)=={'id','rig','roles','anchors','actions','scene','sleep_scene','wake_scene','low_motion_sleep_scene'} and set(r['roles'])==roles
                and set(r['anchors'])=={'operator','tool','badge','handoff'}
                and set(r['actions'])=={'operate','record','carry','repair','clean','build','teach','rest','sleep','wake'}
                and all(isinstance(r[k],str) and r[k].strip() for k in ('scene','sleep_scene','wake_scene','low_motion_sleep_scene')), 'rig excludes role or lacks actual work')
    policy=b['staff_species']
    require(policy=={'eligibility':'all_loaded_species_all_staff_roles','passive_weights':'equal',
            'targeted_species_filter':'exact_optional','standard_species_id':'S49',
            'talent_stacking':'strongest_per_attribute','talent_mood_cap_per_visit':5,
            'talent_mood_scope':'all_staff_combined','talent_grants_qualification':False,
            'talent_changes_wage':False,'body_source':'SpeciesDef','operator_max_clearance':3,
            'operator_max_height_m':6.5}, 'racial gate, hidden wage or repeated talent reward')
    handlers=indexed(c['staff_talent_handlers']); talents=indexed(c['staff_talents'])
    actions={'work_speed':set(ACTION_NAMES)-{'course','thaw','outpatient'},
             'service_mood':{'gp','registration','guidance','ward_visit'},
             'treatment_success':{'outpatient'},'training_work':{'course'},'care_work':{'thaw'}}
    require(set(handlers)==set(actions) and len(talents)==len(species)
            and {r['species_id'] for r in talents.values()}==set(species), 'missing talent or unknown effect handler')
    names=set()
    for r in talents.values():
        require(set(r)=={'id','species_id','name','handler_id','action','condition','value','scene'}, 'talent carries qualification or live state')
        require(r['handler_id'] in handlers,'unknown talent handler');h=handlers[r['handler_id']]
        require(r['name'] not in names and r['name'] and r['scene'],'missing distinct talent name or scene');names.add(r['name'])
        require(r['action'] in actions[h['id']] and math.isfinite(r['value'])
                and h['min_value']<=r['value']<=h['max_value'] and h['version']==1, 'invalid talent action or magnitude')
        valid_conditions=set(GROUPS) if h['id']=='treatment_success' else set(CONDITION_NAMES)
        require(r['condition'] in valid_conditions,'unregistered talent condition')


def effective_grade(grade, level, b):
    require(grade in (0,1,2) and level in range(1,6), 'unqualified operator')
    return grade*b['medical_equipment_effects']['utilization_by_level'][level]


def outpatient_reference_seconds(base_seconds, level, grade, b):
    """Design arithmetic: ordinary outpatient work with no fatigue or context modifiers."""
    require(level in range(1,6) and grade in (0,1,2), 'unqualified reference operator')
    effects=b['medical_equipment_effects']
    effective=grade*Fraction(str(effects['utilization_by_level'][level]))
    rate=1+Fraction('0.05')*(level-1)+Fraction(str(effects['outpatient_speed_per_effective_level']))*effective
    tick=Fraction(str(b['tick_seconds']))
    return float(math.ceil(Fraction(base_seconds)/rate/tick)*tick)


def diagnostic_reference(profile,gp_level,gp_grade,test_level,test_grade,known_cures,c,b):
    # Exact design arithmetic; no clinical scheduler or live prediction is executed.
    effects=b['medical_equipment_effects']
    gp_e=gp_grade*Fraction(str(effects['utilization_by_level'][gp_level]))
    test_e=test_grade*Fraction(str(effects['utilization_by_level'][test_level]))
    initial=min(Fraction(100),Fraction(c['profiles'][profile]['gp_confidence']+2*(gp_level-1)+min(6,known_cures))
                +Fraction(str(effects['gp_evidence_per_effective_level']))*gp_e)
    evidence=initial; after_spectrum=None; performed=[]
    for mode in c['profiles'][profile]['tests']:
        if evidence>=b['diagnosis_threshold']:break
        evidence+=Fraction(b['tests'][mode]['confidence']
                           +effects['test_evidence_per_extra_skill']*(test_level-1))
        evidence+=Fraction(str(effects['test_evidence_per_effective_level']))*test_e
        performed.append(mode)
        if mode=='spectrum':after_spectrum=evidence
    return initial,after_spectrum,performed


def practical_level(current, practice, unlocked=True):
    if current==0 or not unlocked:return current
    return max(current, max((level for level,limit in [(2,20),(3,50),(4,100),(5,180)] if practice>=limit),default=1))


def check_expertise_examples(c,b,check):
    check(len(c['medical_equipment_profiles'])==6 and len(c['clinical_abilities'])==4,
          '六类可购医疗设备、四种能力；每位医护仅三条能力')
    check(len(c['treatment_routines'])==84 and all('price' not in r for r in c['treatment_routines']),
          '84套门诊演出自动复用三主体，不增购买升级项目')
    check(len(c['species'])*len(c['staff_role_profiles'])==560 and len(c['staff_talents'])==80,
          '全部80种族与七岗位组合可用，天赋逐种族覆盖')
    def cells(x,y,w,h):return {(a,z) for a in range(x,x+w) for z in range(y,y+h)}
    regions=[cells(3,3,2,2),cells(3,5,3,3),cells(6,4,3,3),cells(4,0,3,3)]
    check(all(region<=cells(0,0,10,10) for region in regions)
          and all(not a.intersection(z) for i,a in enumerate(regions) for z in regions[i+1:]),
          '三格患者与三格职员/维修员静态站位可分离，不用缩身或重叠')
    for level in range(1,6):
        values=[effective_grade(g,level,b) for g in range(3)]
        check(values[0]<values[1]<values[2],f'能力{level}设备升级发挥单调提高')
    reference_expected={1:[36,32.2,29.1],3:[32.8,28.6,25.4],5:[30,25.8,22.5]}
    for level,expected in reference_expected.items():
        check([outpatient_reference_seconds(36,level,g,b) for g in range(3)]==expected,
              f'36标准秒门诊能力{level}按真实发挥率与最终tick取整，三级工时{expected}')
    diagnostic_cases=[
        (('A',1,0,1,0,0),(Fraction(92),None,[])),
        (('B',1,0,1,0,0),(Fraction(62),Fraction(97),['spectrum'])),
        (('C',1,0,1,0,0),(Fraction(42),Fraction(77),['spectrum','resonance'])),
        (('C',3,2,3,2,0),(Fraction('49.2'),Fraction(93),['spectrum'])),
        (('C',1,1,4,1,3),(Fraction('46.2'),Fraction('89.9'),['spectrum','resonance']))]
    for inputs,expected in diagnostic_cases:
        check(diagnostic_reference(*inputs,c,b)==expected,
              '诊断证据与实际检查次序精确匹配：'+str(inputs))
    effects=b['medical_equipment_effects']
    speed=effects['outpatient_speed_per_effective_level']
    e=effective_grade(2,1,b)
    check(math.isclose(.88+effects['outpatient_success_per_effective_level']*e,.91) and math.ceil(40/(1+speed*e)*10)/10==32.3,
          '入门医生奇想型：普通B档91%，40标准秒变32.3秒')
    e=effective_grade(2,3,b)
    check(math.isclose(.88+.02*2+effects['outpatient_success_per_effective_level']*e,.96) and math.ceil(40/(1+.05*2+speed*e)*10)/10==28.2,
          '治疗3同设备：96%，工时28.2秒；无新科室技能')
    check(min(.98,.97+effects['outpatient_success_per_effective_level']*2)==.98 and 1/(1+speed*2)<1,
          '成功率封顶仍可提高效率，不声称额外概率')
    check(math.isclose(2*sum([.7,.7,.6])/3,4/3)
          and math.ceil(180/(1+effects['ward_recovery_speed_per_effective_level']*2)*10)/10==138.5,
          '手术单台按三人发挥；护理5奇想床180标准秒在138.5秒边界完成')
    check(math.ceil(120/(1+effects['surgery_speed_per_effective_level']*4/3)*10)/10==105.9,
          '一级手术最低团队奇想台120标准秒变105.9秒，不替代苏醒和真实转床')
    check(math.ceil(18/(1+effects['diagnostic_speed_per_effective_level']*1.2)*10)/10==15.3,
          '诊断1奇想台18秒检查变15.3秒，证据和次数仍按原规则')
    check([practical_level(1,n) for n in [19,20,49,50,100,180]]==[1,2,2,3,4,5]
          and practical_level(0,180)==0 and practical_level(1,50,False)==1,
          '累计经验自然成长；未学手术及未解锁研究不越权')
    check(practical_level(1,20)==2 and practical_level(2,50)==3 and 400*60//120==200,
          '课程不阻止实操，20实践升2级；400学费剩一半退200且不伪造结课')
    mutations=[
        (lambda x,y:x['clinical_abilities'][0].pop('work_summary'), '能力缺少可读用途'),
        (lambda x,y:x['clinical_abilities'].append({'id':'anesthesia','name':'麻醉','roles':['doctor'],'initial_level':0}), '增加第五种操作能力'),
        (lambda x,y:x['medical_equipment_profiles'][0].pop('operator_summary'), '医疗设备缺人员分工说明'),
        (lambda x,y:x['medical_equipment_profiles'][0]['operators'][0].update(track='diagnosis'), '诊断代替治疗'),
        (lambda x,y:x['treatment_routines'][0].update(price=100), '给演出单独定价'),
        (lambda x,y:y['diagnostic_flow'].update(completed_test_limit='unlimited_fee_only'), '已完成检查重复收费'),
        (lambda x,y:y['diagnostic_flow'].update(skipped_service_effects=True), '省略检查仍产生经验和收费'),
        (lambda x,y:x['clinical_equipment'][0]['integrated_functions'].remove('monitor'), '手术台缺内置监护'),
        (lambda x,y:y['medical_equipment_effects'].update(equipment_grade_changes_min_skill=True), '升级使原员工不能工作'),
        (lambda x,y:y['clinical_ability_growth'].update(practice_grants_course_fact=True), '实操伪造课程'),
        (lambda x,y:x['clinical_practice_sources'][4]['sources'].append('ward_idle'), '空占床位刷护理经验'),
        (lambda x,y:x['diagnostic_modes'][0]['operators'][0].update(role='nurse'), '护士代替医生初诊'),
        (lambda x,y:x['staff_rig_adapters'][0]['roles'].remove('doctor'), '种族骨架排除医生岗位'),
        (lambda x,y:x['staff_talents'][0].update(species_id='S02'), '种族缺少天赋'),
        (lambda x,y:x['staff_talents'][0].update(grants_qualification=True), '天赋授专业资格'),
        (lambda x,y:y['staff_species'].update(talent_mood_cap_per_visit=999), '换人无限刷心情'),
        (lambda x,y:y['staff_species'].update(targeted_species_filter='preference_only'), '种族定向招聘仍抽不到目标')]
    for mutate,label in mutations:
        cc,bb=copy.deepcopy(c),copy.deepcopy(b);mutate(cc,bb)
        try:validate_expertise(cc,bb)
        except ValueError:check(True,'轻松经营合同负例被拒绝：'+label)
        else:raise ValueError('invalid expertise contract accepted: '+label)


def append_expertise_atlas(lines,c,b,table):
    species=indexed(c['species']);abilities=indexed(c['clinical_abilities'])
    lines += ['## 六类核心医疗设备与四种能力','',
              '医生：诊断、治疗、手术；护士：诊断、护理、手术。设备自动选择病例演出，内置组件一起购买、维护、升级。','']
    table(lines,['能力','实际用途'],[[r['name'],r['work_summary']] for r in c['clinical_abilities']])
    definitions={r['id']:r for key in ('machines','clinical_equipment') for r in c[key]}
    definitions['FUR02']={'name':'诊断台','price':indexed(c['furniture_equipment'],'definition_id')['FUR02']['price']}
    table(lines,['设备','基价','人员分工','升级后能改善什么'],[[definitions[r['definition_id']]['name'],
        definitions[r['definition_id']]['price'],r['operator_summary'],r['upgrade_summary']] for r in c['medical_equipment_profiles']])
    tiers=sorted(c['upgrade_tiers'],key=lambda r:r['level'])
    upgrade_rows=[]
    for r in c['medical_equipment_profiles']:
        definition=definitions[r['definition_id']]
        costs=[upgrade_cost(definition['price'],tier) for tier in tiers]
        upgrade_rows.append([definition['name'],costs[0],costs[1],sum(costs)])
    lines += ['六类设备的升级材料费如下，均从原基价按阶段分别向上取整。只比较材料，实际停诊、人员工资与研究另按原规则。','']
    table(lines,['设备','基础→精修材料','精修→奇想材料','两级材料合计'],upgrade_rows)
    lines += ['以下为同一36标准秒常规门诊的操作时间样例：零劳累、无沟通附加、无科室加速或天赋，仅比较治疗能力和已完成设备等级。数值由当前发挥率生成并最终向上取整到模拟步；不含候诊、会诊、苏醒、转床或住院。','']
    table(lines,['治疗能力','基础型操作秒','精修型操作秒','奇想型操作秒'],
          [[level]+[outpatient_reference_seconds(36,level,g,b) for g in range(3)] for level in (1,3,5)])
    lines += ['诊断证据参考：初诊由医生执行，检查由具备对应诊断能力的护士执行，模式与研究均已开放；数字取当前公式，实际排班、路线和完成收费另行核验。', '']
    diagnosis_rows=[]
    for profile,gp_level,gp_grade,test_level,test_grade,known in [
        ('A',1,0,1,0,0),('B',1,0,1,0,0),('C',1,0,1,0,0),
        ('C',3,2,3,2,0),('C',1,1,4,1,3)]:
        initial,after,modes=diagnostic_reference(profile,gp_level,gp_grade,test_level,test_grade,known,c,b)
        diagnosis_rows.append([profile,f'{gp_level} / {gp_grade}',f'{test_level} / {test_grade}',known,
            f'{float(initial):g}', '无需检查' if after is None else f'{float(after):g}',
            '→'.join({'spectrum':'光谱','resonance':'共振'}[mode] for mode in modes) or '无'])
    table(lines,['档位','初诊能力 / 台等级','护士诊断 / 台等级','本院已治愈此病','初诊证据','光谱后证据','必要检查'],diagnosis_rows)
    lines += ['89.9仍小于90，不能把显示取整当成确诊；少做的检查不收设施费，也不产生使用磨损和实践。', '']
    lines += ['## 所有职员都能睡个好觉', '', '九种骨架覆盖七岗位；睡眠仍使用实际床位、原睡眠时间与真实上下床路线。', '']
    table(lines,['骨架','入睡小戏','醒来小戏','低动态'],[[r['rig'],r['sleep_scene'],r['wake_scene'],r['low_motion_sleep_scene']] for r in c['staff_rig_adapters']])
    lines += ['## 全种族职员天赋' ,'', '任何种族都能担任七岗位。以下天赋只作用于本人实际合格工作，不授资格或改变薪资。','']
    departments=indexed(c['specialties'])
    def effect(r):
        if r['handler_id'] in ('training_work','care_work'):return '工作量×'+str(r['value'])
        if r['handler_id']=='service_mood':return f'心情+{r["value"]:g}，每次就诊全部职员合计≤5'
        return ('成功率+' if r['handler_id']=='treatment_success' else '工作速度+')+f'{r["value"]*100:g}'+('个百分点' if r['handler_id']=='treatment_success' else '%')
    table(lines,['种族 / 天赋','生效工作与情境','效果','轻巧表现'],[[species[r['species_id']]['name']+' / '+r['name'],
        ACTION_NAMES[r['action']]+'；'+(departments[r['condition']]['name'] if r['condition'] in departments else CONDITION_NAMES[r['condition']]),
        effect(r),r['scene']] for r in c['staff_talents']])
