"""Product-design data checks and indexes; no hospital runtime is simulated."""
import copy
import math
from string import Formatter
from validate_clinical import require, indexed


def validate_progression(c, b):
    facts = {'first_course', 'second_ability_level2', 'first_observation',
             'first_mentoring', 'first_promotion', 'first_surgical_cure'}
    for row in indexed(c['growth_moments']).values():
        require(set(row) == {'id', 'name', 'fact', 'roles', 'scene', 'low_motion_scene'}, 'growth moment cannot award gameplay state')
        require(row['fact'] in facts and row['name'] and row['scene'] and row['low_motion_scene'], 'invalid growth moment fact')
        require(row['roles'] == (['doctor','nurse'] if row['fact'] in {'first_course','second_ability_level2','first_mentoring'} else ['doctor']), 'growth moment grants another role duties')
    require(b['staff_growth'] == {'goals_per_clinical_staff': 1, 'moment_seconds': 4, 'interrupt_seconds': 1,
                                'moment_scope': 'once_per_staff_definition',
                                'mentor_progress': 'joint_work_only'}, 'invalid staff growth policy')
    require(0 < b['doctor_training']['mentor_time_multiplier'] <= 1, 'invalid mentor rate')
    validate_maintenance(c, b)
    validate_research_workspace(c, b)
    validate_journey(c, b)
    validate_memory_book(c, b)


def check_progression_examples(c, b, check):
    check_maintenance_examples(c, b, check)
    check_research_examples(c, b, check)
    check_journey_examples(c, b, check)
    check_memory_examples(c, b, check)
    check(len(c['growth_moments']) == 6, '六种医护成长片段按岗位消费真实业务事实')
    course = b['doctor_training']['courses'][0]
    check(course['work_seconds'] == 120 and 60+(course['work_seconds']-60)*b['doctor_training']['mentor_time_multiplier'] == 108,
          '带教只作用剩余共同工作段：60秒独学加48秒带教合计108秒')
    for mutate, label in [
        (lambda x,y:x['growth_moments'][0].update(fact='hired_as_promoted'), '招聘冒充晋级'),
        (lambda x,y:x['growth_moments'][0].update(skill_reward=1), '成长演出赠技能'),
        (lambda x,y:x['growth_moments'].append(copy.deepcopy(x['growth_moments'][0])), '重复成长片段ID')]:
        cc, bb = copy.deepcopy(c), copy.deepcopy(b)
        mutate(cc, bb)
        try:
            validate_progression(cc, bb)
        except ValueError:
            check(True, '成长设计负例被拒绝：'+label)
        else:
            raise ValueError('invalid progression data accepted: '+label)


def append_progression_atlas(lines, c, b, table):
    lines += ['## 医院纪念册叙事模板', '', '只整理实际来源事实；置顶复用50条保护记录，照片另存本机。', '']
    table(lines, ['模板', '事实来源', '系统短句', '缺细节时'], [
        [r['name'], kind, caption, r['caption']] for r in c['history_templates']
        for kind,caption in r['source_captions'].items()])
    lines += ['## 就诊原因卡', '', '原因只映射既有事实和页面，不重算资格或评分。', '']
    table(lines, ['原因', '事实来源', '操作入口', '证据'], [[r['name'],r['source'],r['target_panel']+('；地面污渍→清洁' if r.get('blocker_panel_overrides') else ''),r['evidence']] for r in c['journey_reason_cards']])
    lines += ['## 六条研究兴趣路线', '', '路线只筛选目标，原研究前置、费用、资料和完成事实保持唯一。', '']
    research = indexed(c['research'])
    table(lines, ['路线', '目标课题', '插画文案', '建设念头'], [[r['name'], '、'.join(research[i]['name'] for i in r['research_ids']), r['flavor'], r['next_idea']] for r in c['research_trails']])
    lines += ['## 维修策略与小喜剧', '']
    table(lines, ['保养策略', '自动保养阈值', '说明'], [[r['name'], b['maintenance_dispatch']['auto_thresholds'][r['id']], r['description']] for r in c['maintenance_policies']])
    lines += ['以下仅为满状态、无随机故障、及时保养的医疗设备比较；不含路程、工资和拥堵，不是寿命保证。', '']
    table(lines, ['策略','使用次数','排单状态','保养标准秒','零件币','零件币/次'], maintenance_comparison(c,b))
    table(lines, ['表现', '设备选择', '开工', '实际检修', '暂停', '完成', '低动态'], [[r['name'], r['selector'], r['opening'], r['working_scene'], r['paused_scene'], r['finishing'], r['low_motion_scene']] for r in c['maintenance_scenes']])
    lines += ['## 医护成长片段', '', '片段只引用实际完成事实，每位适用医护每种一次；不赠技能或资源。', '']
    table(lines, ['片段', '事实 / 岗位', '小动作', '低动态'], [[r['id']+' '+r['name'], r['fact']+' / '+'、'.join({'doctor':'医生','nurse':'护士'}[role] for role in r['roles']), r['scene'], r['low_motion_scene']]
                                         for r in c['growth_moments']])


def maintenance_comparison(c,b):
    medical=indexed(b['equipment']['classes'])['medical']
    rows=[]
    for policy in c['maintenance_policies']:
        threshold=b['maintenance_dispatch']['auto_thresholds'][policy['id']]
        uses=math.ceil((b['equipment']['restored_condition']-threshold)/medical['wear_per_use'])
        condition=b['equipment']['restored_condition']-uses*medical['wear_per_use']
        rows.append([policy['name'],uses,condition,medical['maintenance_seconds'],medical['maintenance_parts'],
                     f"{medical['maintenance_parts']/uses:.2f}"])
    return rows


def validate_maintenance(c, b):
    policies = indexed(c['maintenance_policies'])
    dispatch = b['maintenance_dispatch']
    require(b['equipment']['medical_use_sources'] == {
        'FUR02':'first_actual_work_per_service','M09':'first_actual_work_per_attempt',
        'M17':'first_actual_work_per_attempt','M37':'first_actual_work_per_attempt',
        'EQ01':'first_actual_work_per_attempt','EQ05':'first_actual_admission_per_attempt'}
        and b['equipment']['medical_use_dedup']=='service_or_attempt_and_subject',
        'medical wear follows duplicate callbacks or non-use')
    require(dispatch['default_policy_id'] in policies and set(dispatch['auto_thresholds']) == set(policies), 'missing maintenance policy')
    require(dispatch['default_policy_id'] == 'MP02' and dispatch['auto_thresholds'][dispatch['default_policy_id']] == 45
            and all(0 < value <= dispatch['manual_threshold'] == 60 for value in dispatch['auto_thresholds'].values()), 'invalid maintenance thresholds')
    require(dispatch['orders_per_equipment'] == 1 and dispatch['charge_timing'] == 'work_start'
            and dispatch['scene_selection'] == 'lift_then_class', 'unsafe maintenance dispatch')
    selectors = {'class:'+r['id'] for r in b['equipment']['classes'] if r['id'] in {'medical','workstation','utility'}} | {'vertical_lift'}
    scenes = indexed(c['maintenance_scenes'])
    require({r['selector'] for r in scenes.values()} == selectors, 'missing maintenance class scene')
    for row in scenes.values():
        require(set(row) == {'id','name','selector','opening','working_scene','paused_scene','finishing','low_motion_scene'}
                and all(isinstance(row[k],str) and row[k].strip() for k in ('opening','working_scene','paused_scene','finishing','low_motion_scene')), 'maintenance presentation changes gameplay')
    for cls in b['equipment']['classes']:
        require(cls['repair_seconds'] >= cls['maintenance_seconds']
                and cls['repair_parts'] >= cls['maintenance_parts'], 'maintenance escalation gives negative work or refund')


def check_maintenance_examples(c, b, check):
    check(len(c['maintenance_policies']) == 3 and len(c['maintenance_scenes']) == 4, '三档保养与四种维修表现完整')
    medical = indexed(b['equipment']['classes'])['medical']
    threshold=b['maintenance_dispatch']['auto_thresholds'][b['maintenance_dispatch']['default_policy_id']]
    uses=math.ceil((b['equipment']['restored_condition']-threshold)/medical['wear_per_use'])
    queued_condition=b['equipment']['restored_condition']-uses*medical['wear_per_use']
    check(uses==28 and queued_condition>b['equipment']['risk_condition_bounds'][1]
          and medical['maintenance_parts']/uses<1,
          '默认保养28次到44，排单早于低维护线，单次使用零件摊费不足1币')
    check(medical['repair_seconds']-8 == 22 and medical['repair_parts']-medical['maintenance_parts'] == 20,
          '医疗保养完成8秒后转维修，剩22标准秒且只补20零件费')
    check([r[1:] for r in maintenance_comparison(c,b)] == [
        [35,30,20,20,'0.57'],[28,44,20,20,'0.71'],[20,60,20,20,'1.00']],
        '三档医疗保养比较由同一状态、磨损和零件价格生成')
    for mutate,label in [
        (lambda x,y:y['equipment']['medical_use_sources'].update(EQ05='every_nursing_callback'), '床边动作重复扣使用磨损'),
        (lambda x,y:y['equipment'].update(medical_use_dedup='visual_event'), '表现回调充当使用凭据'),
        (lambda x,y:y['maintenance_dispatch']['auto_thresholds'].update(MP01=100), '完好设备反复自动保养'),
        (lambda x,y:x['maintenance_scenes'][0].update(cash_reward=10), '维修演出发钱'),
        (lambda x,y:x['maintenance_scenes'][0].update(selector='unknown'), '维修表现缺设备类别')]:
        cc,bb=copy.deepcopy(c),copy.deepcopy(b);mutate(cc,bb)
        try:validate_maintenance(cc,bb)
        except ValueError:check(True,'维修设计负例被拒绝：'+label)
        else:raise ValueError('invalid maintenance data accepted: '+label)


def validate_research_workspace(c, b):
    research = indexed(c['research'])
    for row in indexed(c['research_trails']).values():
        require(set(row) == {'id','name','research_ids','flavor','next_idea'}, 'research trail cannot override price or prerequisites')
        require(row['research_ids'] and len(row['research_ids']) == len(set(row['research_ids']))
                and set(row['research_ids']) <= set(research), 'invalid research trail target')
        require(row['name'] and row['flavor'] and row['next_idea'], 'empty research trail')
    require(b['research_workspace'] == {'jobs_per_research':1,'mail_requests_per_research':1,
            'start_mode':'explicit','same_tick_source':'diagnosis','mode_switch':'cancel_then_restart'}, 'unsafe research workspace')


def check_research_examples(c, b, check):
    check(len(c['research_trails']) == 6 and b['research_mail_seconds'] == 120
          and b['community_research_time_multiplier'] == 2, '六条兴趣路线沿用120秒资料与双倍社区研究')
    for mutate,label in [
        (lambda x,y:x['research_trails'][0]['research_ids'].append('missing'), '兴趣路线指向未知研究'),
        (lambda x,y:x['research_trails'][0].update(price=0), '路线覆盖原课题费用'),
        (lambda x,y:y['research_workspace'].update(start_mode='automatic'), '待办自动花钱')]:
        cc,bb=copy.deepcopy(c),copy.deepcopy(b);mutate(cc,bb)
        try:validate_research_workspace(cc,bb)
        except ValueError:check(True,'研究设计负例被拒绝：'+label)
        else:raise ValueError('invalid research trail accepted: '+label)


def validate_journey(c, b):
    contracts = {'staff_coverage':'schedule','equipment_availability':'maintenance',
                 'traversal':'building','clinical_readiness':'clinical','queue_ticket':'queue',
                 'need_service':'facilities','incident_state':'incident','discharge_round':'schedule','supply_stock':'supplies'}
    for row in indexed(c['journey_reason_cards']).values():
        fields={'id','name','source','target_panel','evidence'}
        if row['source'] == 'traversal':
            fields.add('blocker_panel_overrides')
            require(row.get('blocker_panel_overrides') == {'dirt_patch':'cleaning'}, 'dirty extension suggests rebuilding instead of real cleanup')
        require(set(row) == fields, 'journey card cannot change rating or outcome')
        require(row['source'] in contracts and row['target_panel'] == contracts[row['source']]
                and row['evidence'], 'journey card has wrong fact owner or action')
    rule = b['journey_review']
    require(rule == {'details_per_visit':32,'closed_receipts':100,'cause_sample_seconds':10,
                     'examples_per_metric':3,'outcome_visibility':'settled_only'}, 'unsafe journey history policy')


def check_journey_examples(c, b, check):
    check(len(c['journey_reason_cards']) == 9, '九种就诊原因均映射原事实所有者和对应页面')
    for mutate,label in [
        (lambda x,y:x['journey_reason_cards'][0].update(target_panel='dismiss_staff'), '原因卡自动辞退'),
        (lambda x,y:x['journey_reason_cards'][0].update(rating_bonus=5), '小票另加评分'),
        (lambda x,y:y['journey_review'].update(outcome_visibility='committed_future'), '显示未揭晓治疗结果')]:
        cc,bb=copy.deepcopy(c),copy.deepcopy(b);mutate(cc,bb)
        try:validate_journey(cc,bb)
        except ValueError:check(True,'就诊历史设计负例被拒绝：'+label)
        else:raise ValueError('invalid journey data accepted: '+label)


def validate_memory_book(c, b):
    fields = {'first_disease_cure':{'resident','disease','plan'},
              'land_purchased':{'location','completed_day'},'new_floor_completed':{'location','completed_day'},
              'remodel_applied':{'room','old_location','new_location'},
              'research_completed':{'research'},'staff_growth':{'staff','growth_tags'},
              'activity_completed':{'activity','participant_count','core_residents','variation'},
              'relationship_reconciled':{'resident_pair','context'},
              'gift_received':{'gift','resident','credited_staff'},
              'story_completed':{'objective','reward_state'},'milestone_completed':{'objective','reward_state'}}
    seen = set()
    for row in indexed(c['history_templates']).values():
        require(set(row) == {'id','name','source_kinds','detail_fields','caption','source_captions'}, 'history template cannot change world facts')
        require(row['source_kinds'] and len(row['source_kinds']) == len(set(row['source_kinds']))
                and set(row['source_kinds']) <= set(fields), 'unknown history source')
        require(not seen.intersection(row['source_kinds']), 'history source assigned twice')
        seen.update(row['source_kinds'])
        allowed = set().union(*(fields[key] for key in row['source_kinds']))
        require(set(row['detail_fields']) <= allowed and row['caption']
                and '{' not in row['caption'] and '}' not in row['caption'], 'history invents unavailable detail')
        require(set(row['source_captions']) == set(row['source_kinds']), 'history lacks source-specific caption')
        for kind, caption in row['source_captions'].items():
            require(isinstance(caption,str) and caption.strip(), 'empty history caption')
            for _, token, spec, conversion in Formatter().parse(caption):
                if token is not None:
                    require(token in fields[kind] and token in row['detail_fields']
                            and not spec and conversion is None, 'history caption uses another source or expression')
    rule = b['memory_book']
    require(b['limits']['history_entries'] == 500 and rule == {'pinned_entries':50,'daily_summaries':30,
            'caption_characters':80,'photo_max_edge_pixels':4096,'photo_limit':None,
            'photos_in_hospital_backup':False,'automatic_capture':False}, 'unsafe memory book storage policy')


def check_memory_examples(c, b, check):
    check(len(c['history_templates']) == 8, '八类叙事模板只引用真实来源和可用细节')
    for mutate,label in [
        (lambda x,y:x['history_templates'][4].update(source_kinds=['activity_planned']), '计划冒充完成回忆'),
        (lambda x,y:x['history_templates'][3]['source_captions'].update(research_completed='{staff}完成研究。'), '研究卡冒用员工成长字段'),
        (lambda x,y:x['history_templates'][1]['source_captions'].pop('new_floor_completed'), '新层完成缺独立短句'),
        (lambda x,y:x['history_templates'][0].update(caption='{resident}已经康复。'), '缺细节退路仍要求姓名'),
        (lambda x,y:x['history_templates'][0]['source_captions'].update(first_disease_cure='{resident.name}'), '短句执行属性表达式'),
        (lambda x,y:x['history_templates'][0]['detail_fields'].append('future_result'), '院史虚构结果'),
        (lambda x,y:y['memory_book'].update(photos_in_hospital_backup=True), '绕过原医院备份白名单')]:
        cc,bb=copy.deepcopy(c),copy.deepcopy(b);mutate(cc,bb)
        try:validate_memory_book(cc,bb)
        except ValueError:check(True,'纪念册设计负例被拒绝：'+label)
        else:raise ValueError('invalid history template accepted: '+label)
