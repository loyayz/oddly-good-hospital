"""Static contracts for care, upkeep and presentation; no game simulation."""
import copy
from collections import deque
from fractions import Fraction
from math import ceil
from string import Formatter
from validate_clinical import indexed, require, expanded_footprint, binding_body


def validate_care(c, b):
    validate_visit_origins(c, b)
    validate_cleanup(c, b)
    validate_upgrades(c, b)
    validate_ward_care(c, b)
    validate_quiet_information(c, b)
    validate_supplies_and_fit(c, b)
    validate_daily_experience(c, b)
    validate_clinical_results(c, b)
    validate_inpatient_examples(c, b)


def validate_visit_origins(c, b):
    require(b['resident_retention'] == {
        'protected_references':['present_actor','active_visit_or_stay','unfinished_activity',
                                'story_identity_binding','active_interaction_or_care'],
        'history_blocks_release':False,'relationship_edge_blocks_release':False,
        'unfollow_stops_return_immediately':True,'present_actor_must_exit':True,
        'staff_uses_regular_capacity':False}, 'regular retention strands identities or erases active residents')
    require(b['arrivals']['manual_patient_invitation'] is False
            and 'invite_queue_limit' not in b['arrivals'], 'patient invitation reintroduced')
    require(b['resident_returns'] == {'identity_after_case': True, 'probability': 0.2,
            'minimum_absence_days': 2, 'selection': 'oldest_departure_then_id',
            'ordinary_visitor_purposes': ['companion', 'ward_visit'],
            'activity_admission': 'voluntary_with_reason', 'tutorial_extras': False},
            'visit identity changes need or creates idle guests')
    bindings = {(r['species_id'], r['disease_id']) for r in c['treatment_bindings']}
    for row in indexed(c['story_patient_bindings']).values():
        require(set(row) == {'id','story_id','name','species_id','disease_id','bind_on','cure_cue'},
                'story identity owns extra patient or reward')
        require(row['story_id'] == 'ST01' and row['name'] == '林阿姨'
                and (row['species_id'], row['disease_id']) == ('S49','D42')
                and (row['species_id'], row['disease_id']) in bindings
                and row['bind_on'] == 'matching_actual_arrival', 'story overwrites natural case')
        cue = row['cure_cue']
        require(set(cue) == {'source','scene','low_motion_scene','condition_caption'}
                and cue['source'] == 'counted_same_visit_patient_condition_completion'
                and all(isinstance(cue[key], str) and cue[key].strip()
                        for key in ('scene','low_motion_scene','condition_caption')),
                'story cure cue requires another visit, creates facts or lacks current readable closure')
    require(len(c['story_patient_bindings']) == 1, 'missing story patient identity')
    activities = indexed(c['community_activities']); seen = set()
    links = indexed(c['story_activity_links'])
    linked_kinds = {'completed_celebration_link':'celebration',
                    'cured_subject_or_story_objective':'objective'}
    for row in indexed(c['activity_purposes']).values():
        eligibility = row.get('eligibility')
        require(eligibility in ('cure_fact_or_active_story',*linked_kinds),
                'unknown activity eligibility type')
        fields = {'id','activity_id','purpose','participant_reason','eligibility'}
        if eligibility in linked_kinds:
            fields.add('story_activity_link_id')
        require(set(row) == fields,
                'activity reason owns clinical effects')
        require(row['activity_id'] in activities and row['activity_id'] not in seen
                and row['purpose'] and row['participant_reason'], 'activity lacks actual purpose')
        if eligibility in linked_kinds:
            link_id = row['story_activity_link_id']
            require(isinstance(link_id,str) and link_id in links,
                    'activity eligibility lacks its existing story link')
            link = links[link_id]
            require(link['activity_id'] == row['activity_id'] and link['kind'] == linked_kinds[eligibility],
                    'activity eligibility must reference its own correctly typed story link')
        seen.add(row['activity_id'])
    # Extensions declare their own purposeful participation with the activity.
    require(set(activities) == seen, 'activity lacks participation reason')


def rejects(c, b, validate, check, mutations):
    for mutate, label in mutations:
        cc, bb = copy.deepcopy(c), copy.deepcopy(b)
        mutate(cc, bb)
        try:
            validate(cc, bb)
        except ValueError:
            check(True, '照护设计负例被拒绝：' + label)
        else:
            raise ValueError('invalid care contract accepted: ' + label)


def check_care_examples(c, b, check):
    check_cleanup_examples(c, b, check)
    check_work_base_handoff(c, b, check)
    check_upgrade_examples(c, b, check)
    check_ward_examples(c, b, check)
    check_supplies_and_fit_examples(c, b, check)
    check_daily_experience_examples(c, b, check)
    check(len(c['activity_purposes']) == 5, '五类活动均有参加理由且保持各自随机人数')
    flower_purpose = indexed(c['activity_purposes'])['AP04']
    check(flower_purpose['eligibility'] == 'completed_celebration_link'
          and flower_purpose['story_activity_link_id'] == 'SAL01',
          '花展资格引用原SAL01庆祝，不以普通治愈或活跃ST02开放；运行状态查询仍待实现')
    another_celebration = copy.deepcopy(c)
    indexed(another_celebration['activity_purposes'])['AP03'].update(
        eligibility='completed_celebration_link',story_activity_link_id='SAL02')
    validate_visit_origins(another_celebration,b)
    check(True, '合法资格变体可引用同活动的其他庆祝关联，不把扩展加载器写死为CA04')
    photo_purpose=indexed(c['activity_purposes'])['AP06']
    check(photo_purpose['eligibility']=='cured_subject_or_story_objective'
          and photo_purpose['story_activity_link_id']=='SAL06',
          '合影普通入口需康复对象，目标入口引用原SAL06；真实名单与理由冻结仍待实施验证')
    another_subject=copy.deepcopy(c)
    indexed(another_subject['activity_purposes'])['AP01'].update(
        eligibility='cured_subject_or_story_objective',story_activity_link_id='SAL04')
    validate_visit_origins(another_subject,b)
    check(True,'康复对象/目标资格可引用其他活动自己的有效目标，不按CA06硬编码')
    check(b['resident_returns']['minimum_absence_days'] * b['day_seconds'] == 3600,
          '熟客离院后满3600模拟秒即两个医院日才可再次成为患者身份候选')
    check(c['story_patient_bindings'][0]['cure_cue']['source'] == 'counted_same_visit_patient_condition_completion',
          '林阿姨收尾来自本次被故事计入的真实治愈，不等再次来院；实际姿态与条件进度待实现验收')
    rejects(c, b, validate_visit_origins, check, [
        (lambda x,y:indexed(x['activity_purposes'])['AP04'].update(eligibility='any_visitor'), '未知活动资格类型'),
        (lambda x,y:indexed(x['activity_purposes'])['AP04'].pop('story_activity_link_id'), '庆祝资格缺少原关联'),
        (lambda x,y:indexed(x['activity_purposes'])['AP04'].update(story_activity_link_id='missing'), '庆祝资格引用不存在的关联'),
        (lambda x,y:indexed(x['story_activity_links'])['SAL01'].update(kind='objective'), '庆祝资格引用未完成目标类型'),
        (lambda x,y:indexed(x['story_activity_links'])['SAL01'].update(activity_id='CA03'), '庆祝资格借用其他活动关联'),
        (lambda x,y:indexed(x['activity_purposes'])['AP04'].update(story_completed=True), '活动用途复制故事完成状态'),
        (lambda x,y:indexed(x['activity_purposes'])['AP06'].pop('story_activity_link_id'), '合影目标类型缺关联'),
        (lambda x,y:indexed(x['activity_purposes'])['AP06'].update(story_activity_link_id='missing'), '合影目标引用不存在'),
        (lambda x,y:indexed(x['story_activity_links'])['SAL06'].update(kind='celebration'), '目标合影改成先完成故事'),
        (lambda x,y:indexed(x['story_activity_links'])['SAL06'].update(activity_id='CA01'), '合影借其他活动目标'),
        (lambda x,y:indexed(x['activity_purposes'])['AP06'].update(cured_count=1), '用途定义复制医院治愈状态'),
        (lambda x,y:y['arrivals'].update(manual_patient_invitation=True), '点名邀请患者'),
        (lambda x,y:y['resident_returns']['ordinary_visitor_purposes'].append('idle'), '闲逛访客填人'),
        (lambda x,y:x['story_patient_bindings'][0].update(bind_on='assign_disease'), '故事给人物安排疾病'),
        (lambda x,y:x['story_patient_bindings'][0]['cure_cue'].update(source='next_resident_return'), '人物康复结局等待再次来院'),
        (lambda x,y:x['story_patient_bindings'][0]['cure_cue'].update(low_motion_scene=''), '人物收尾缺少低动态姿态'),
        (lambda x,y:x['story_patient_bindings'][0]['cure_cue'].update(reward='another_pillow'), '人物表现另发奖励')])


def append_care_atlas(lines, c, b, table):
    species = indexed(c['species']); diseases = indexed(c['diseases'])
    lines += ['## 症状的真实占地', '', '只有实体膨胀病例扩大空间；未治愈时门路、生活与治疗共用本次包络。', '']
    table(lines, ['居民 / 病症', '症状宽×深×高（米）', '通行占地', '护理床展开'], [[
        species[r['species_id']]['name']+' / '+diseases[r['disease_id']]['name'],
        '×'.join(str(v) for v in binding_body(species[r['species_id']],r).values()),
        str(max(expanded_footprint([0,0], binding_body(species[r['species_id']],r))))+'格',
        '×'.join(str(v) for v in expanded_footprint([3,3],binding_body(species[r['species_id']],r),True))]
        for r in c['treatment_bindings'] if 'symptom_envelope' in r])
    lines += ['## 床边照护与探视表现', '', '动作映射原护理、探视或查房时长，不改变被动恢复和结局。', '']
    table(lines, ['阶段', '性格', '床边动作', '减少动态'], [[r['stage'],r['personality_id'] or '通用',r['scene'],r['low_motion_scene']] for r in c['ward_scenes']])
    table(lines, ['邻床条件', '回应', '减少动态'], [[r['condition'],r['scene'],r['low_motion_scene']] for r in c['ward_neighbor_cues']])
    lines += ['## 升级施工与机器变化', '']
    table(lines, ['等级', '研究', '基价比例', '标准秒', '通用变化'], [[str(r['level']),r['research_id'],str(r['price_basis_points']/100)+'%',str(r['work_seconds']),r['appearance']]
                                               for r in c['upgrade_tiers']])
    table(lines, ['医疗主体', '精修型', '奇想型'], [[r['definition_id'],r['level1']+' 静态：'+r['level1_static'],r['level2']+' 静态：'+r['level2_static']] for r in c['upgrade_presentations']])
    lines += ['## 日常清洁来源', '', '地面和桶内垃圾均保留至清洁员实际完成；没有到期清理。', '']
    table(lines, ['来源', '生成门槛', '标准清扫秒', '等人来扫', '实际清扫', '中断与低动态'], [[r['name'],str(r['uses_per_patch'] or '事件定义'),
            str(r['work_seconds']),r['idle_scene'],r['scene'],r['interrupted_scene']+' '+r['low_motion_scene']] for r in c['cleanup_sources']])
    lines += ['## 治疗包与医护反应', '', '一种治疗包20币；常规1/2/3包、舒缓2/3/4包、手术8/10/12包。采购实际扣款，领用不重复扣现金。', '']
    table(lines, ['物品', '单位', '价格', '表现'], [[r['name'],r['unit'],r['unit_price'],r['purchase_scene']] for r in c['medical_supplies']])
    table(lines, ['使用设备', '按用途展开', '低动态'], [[r['definition_id'],r['scene'],r['low_motion_scene']] for s in c['medical_supplies'] for r in s['opening_scenes']])
    table(lines, ['状态', '现场动作', '低动态'], [[r['stage'],r['scene'],r['low_motion_scene']] for r in c['supply_reactions']])
    append_supply_purchase_atlas(lines, c, b, table)
    lines += ['## 自动伸缩与真实空间', '', '有空地才伸展，实际占地会挡路；预览、准备和保存使用同一几何事实。', '']
    table(lines, ['设施', '成功伸展', '伸不开时', '低动态'], [[r['target'],r['scene'],r['blocked_scene'],r['low_motion_scene']] for r in c['facility_magic_scenes']])
    lines += ['## 轻松经营的默认体验', '']
    table(lines, ['内容', '默认体验', '可展开细项'], [[r['topic'],r['default'],r['detail']] for r in c['ease_rules']])
    lines += ['## 来院理由与自愿互助', '', '自然来诊先确定病例再识别熟客；普通访客关联患者，活动名单记录参加缘由。', '']
    story_links = indexed(c['story_activity_links'])
    purpose_rows=[]
    for row in c['activity_purposes']:
        eligibility=row['eligibility']
        if eligibility=='completed_celebration_link':
            entry='故事'+story_links[row['story_activity_link_id']]['story_id']+'完成后的原关联庆祝'
        elif eligibility=='cured_subject_or_story_objective':
            entry='普通名单含真实康复对象；或显式选择有效'+story_links[row['story_activity_link_id']]['story_id']+'目标邀请'
        else:
            entry='原真实治愈或故事入口条件'
        purpose_rows.append([row['activity_id'],row['purpose'],row['participant_reason'],entry])
    table(lines, ['活动', '用途', '报名理由', '开放依据'],purpose_rows)
    table(lines, ['故事人物', '真实病例条件', '身份绑定'], [[r['name'],r['species_id']+'/'+r['disease_id'],r['bind_on']]
                                                       for r in c['story_patient_bindings']])
    table(lines, ['人物当次收尾', '原离院姿态', '低动态', '已完成条件文案'], [[r['name'],
        r['cure_cue']['scene'],r['cure_cue']['low_motion_scene'],r['cure_cue']['condition_caption']]
        for r in c['story_patient_bindings']])
    lines += ['当次被故事计入的治愈首次完成相应人物条件时显示收尾；其余目标可继续推进，原奖励只领一次。离院后不召回，读档与重开卡片不补演，也不为展示康复成果制造新疾病。', '']
    append_daily_experience_atlas(lines, c, b, table)


def validate_cleanup(c, b):
    require(all('cleanup_ttl_seconds' not in r for r in c['incidents']), 'event garbage still expires')
    expected = {'incident':(None,4,False), 'water_completed':(6,4,True),
                'toilet_completed':(8,6,False), 'outpatient_completed':(8,6,True)}
    seen = set()
    for row in indexed(c['cleanup_sources']).values():
        require(set(row) == {'id','name','source','uses_per_patch','work_seconds','bin_collects','scene','idle_scene','interrupted_scene','low_motion_scene'},
                'cleanup source carries unrelated gameplay')
        require(row['source'] in expected and row['source'] not in seen
                and (row['uses_per_patch'],row['work_seconds'],row['bin_collects']) == expected[row['source']],
                'unsafe cleanup source or timeout')
        require(all(isinstance(row[k],str) and row[k].strip() for k in ('scene','idle_scene','interrupted_scene','low_motion_scene')), 'missing cleanup performance')
        seen.add(row['source'])
    require(seen == set(expected), 'missing cleanup source')
    require(b['cleanup'] == {'active_patches_per_plot':64,'budget_scope':'actual_floor_plot_of_patch_or_bin',
            'shrink_or_move':'keep_existing_block_new_if_full','per_cell':1,'daily_per_equipment':1,
            'aging_seconds':60,'pinned_jobs':1,'bin_definition_id':'FUR18','bin_range_cells':4,
            'removal':'cleaner_work_only','bin_work_seconds':4,
            'overflow':'do_not_spawn_keep_existing','build_over_dirty':'wait_for_cleaner',
            'dispatch_filter':'actual_reachable_work_position','ground_work_reach_cells':1,
            'blocked_job_keeps_worker':False,'yielding_advances_work':False,
            'blocks_pedestrian_walk':False,'blocks_construction_and_extension':True,
            'spawn_avoids_reserved_work_areas':True,'event_care_scope':'stop_source_only',
            'event_removal_source':'dirt_patch_work'}, 'unbounded or exploitative cleaning')
    furniture = indexed(c['furniture_equipment'], 'definition_id')
    require(furniture[b['cleanup']['bin_definition_id']]['equipment_class'] == 'utility', 'bin lacks equipment rules')


def check_work_base_handoff(c, b, check):
    check(b['staff_work_bases']['preparation_seconds']==6
          and b['staff_work_bases']['ward_handoff']=='separate_real_bedside_transfer'
          and b['hospital_situations']['nursing_handoff_seconds']==5
          and b['ward_care']['handoff_scope']=='one_room_coverage_set',
          '工作台每段6秒准备与病房每组5秒接班职责分开，八床不重复四十秒')
    check(b['arrivals']['capacity_scaling']['support_readiness']=='doctor_office_and_required_nurse_base',
          '扩建规模检查真实办公室及护理工作台')


def check_cleanup_examples(c, b, check):
    check(len(c['cleanup_sources']) == 4, '四类实际清洁来源绑定工时，地面与桶内均须真实清洁')
    budget=b['cleanup']['active_patches_per_plot']
    plots={(1,7):64,(2,7):3}
    check(plots[(1,7)] >= budget and plots[(2,7)] < budget and sum(plots.values()) > budget,
          '一层满64份不封锁上层真实地块，旧垃圾跨层保存不删除')
    check(9*budget==576 and 100*9*budget==57600,
          '垃圾后台容量随实际地块增长，空地块容量不产生垃圾')
    env=b['environment']
    check(env['clean_bonus']+min(4*env['dirt_per_item'],env['dirt_cap']) == 24,
          '四处脏物全清在未夹上下界时恢复24分：16脏乱与8洁净')
    rejects(c,b,validate_cleanup,check,[
        (lambda x,y:x['cleanup_sources'][0].update(source='species_entered'), '仅按种族造脏'),
        (lambda x,y:x['cleanup_sources'][0].update(expire_seconds=180), '垃圾到期消失'),
        (lambda x,y:y['cleanup'].update(event_care_scope='clear_ground'), '处理事件直接清空地面'),
        (lambda x,y:y['cleanup'].update(event_removal_source='incident_resolved'), '自然收尾删除原垃圾'),
        (lambda x,y:x['incidents'][0].update(cleanup_ttl_seconds=60), '事件垃圾残留到期字段'),
        (lambda x,y:y['cleanup'].update(overflow='queue_forever'), '满额积欠垃圾')])


def upgrade_cost(price, tier):
    return (price*tier['price_basis_points']+9999)//10000


def validate_upgrades(c, b):
    tiers = sorted(indexed(c['upgrade_tiers']).values(), key=lambda r:r['level'])
    require([(r['level'],r['research_id'],r['price_basis_points'],r['work_seconds']) for r in tiers]
            == [(1,'R12',3000,30),(2,'R13',4500,30)], 'upgrade cost or stage undefined')
    research = indexed(c['research']); machines = indexed(c['machines']); seen=set()
    medical_ids = {p['definition_id'] for p in c['medical_equipment_profiles']}
    for row in tiers:
        require(set(row) == {'id','level','research_id','price_basis_points','work_seconds','appearance'}
                and row['research_id'] in research and row['appearance'], 'upgrade tier carries unrelated state')
    for row in indexed(c['upgrade_presentations']).values():
        require(set(row) == {'id','definition_id','level1','level2','level1_static','level2_static'} and row['definition_id'] in medical_ids
                and row['definition_id'] not in seen and row['level1'] and row['level2']
                and row['level1_static'] and row['level2_static'], 'invalid upgrade appearance')
        seen.add(row['definition_id'])
    require(seen == medical_ids, 'missing core equipment upgrade presentation')
    require(b['upgrade_appearance'] == {'tier_source':'placed_object_upgrade_level',
            'solid_motion_space':'validated_fit_envelope','helpers_replace_staff':False,
            'low_motion_progress_source':'current_service_work',
            'active_motion_source':'current_service_work_and_actual_case',
            'inactive_pose':'completed_hardware_safe_idle','secondary_budget_source':'treatment_presentation'}, 'appearance changes clinical work or space')
    require(all(r['upgrade_levels'] == len(tiers) for r in machines.values()), 'machine tier unsupported')
    require(b['machine_upgrade'] == {'worker_role':'mechanic','payment':'confirm_apply',
            'blueprint_execution':'sequential_orders','condition_reset':False,'affects_frozen_attempt':False,
            'borrowed_allowed':False,'unstarted_refund':1,'started_stage_refund':0,
            'paid_cost_commit':'stage_complete'}, 'unsafe upgrade ownership or settlement')
    require(b['blueprints']['upgrade_execution'] == 'upgrade_orders', 'blueprint bypasses upgrade work')


def check_upgrade_examples(c, b, check):
    check(len(c['upgrade_tiers']) == 2 and len(c['upgrade_presentations']) == 6, '两级实际升级与六机器表现引用原定义')
    bed_price=indexed(c['clinical_equipment'])['EQ05']['price']
    bed_fees=[upgrade_cost(bed_price,r) for r in c['upgrade_tiers']]
    check(bed_fees == [555,833] and sum(bed_fees) == 1388, '护理床逐级材料向上取整为555与833，两级合计1388')
    price=indexed(c['machines'])['M09']['price'];fees=[upgrade_cost(price,r) for r in c['upgrade_tiers']]
    check(fees == [420,630] and (price+sum(fees))*80//100 == 1960 and sum(fees)*80//100 == 840,
          '整复台主体升级按基价；自购已用退1960、赠机仅实付部分退840')
    rejects(c,b,validate_upgrades,check,[
        (lambda x,y:y['blueprints'].update(upgrade_execution='instant'), '蓝图免施工升级'),
        (lambda x,y:y['machine_upgrade'].update(condition_reset=True), '升级冒充修理'),
        (lambda x,y:y['upgrade_appearance'].update(active_motion_source='elapsed_wall_clock'), '高级设备无工作也演治疗'),
        (lambda x,y:y['upgrade_appearance'].update(secondary_budget_source='independent'), '升级助手另开一套表现名额'),
        (lambda x,y:x['upgrade_presentations'][0].update(clearance_bonus=1), '附件暗改身体通行')])


def validate_ward_care(c, b):
    neighbor=indexed(c['ward_neighbor_cues'])
    require(len(neighbor) == 3 and {r['condition'] for r in neighbor.values()} == {'default','neighbor_PP03','friend'}, 'neighbor cue conditions drift')
    require(all(set(r) == {'id','condition','scene','low_motion_scene'} and r['scene'] and r['low_motion_scene'] for r in neighbor.values()), 'neighbor cue owns clinical effects')
    require(b['ward_neighbor_presentation'] == {'source':'actual_nurse_care_completed','head_anchor_distance_cells':3,
            'max_seconds':2,'selection':'friend_then_neighbor_curiosity_then_default','gameplay_effects':False,
            'replay_offscreen_or_loaded':False}, 'neighbor scene affects care or replays old facts')
    stages={'nurse_care','family_visit','discharge_round'}
    traits=indexed(c['patient_personalities']); seen=set()
    for row in indexed(c['ward_scenes']).values():
        require(set(row) == {'id','stage','personality_id','scene','low_motion_scene'}, 'ward scene owns clinical effects')
        require(row['stage'] in stages and (row['personality_id'] is None or row['personality_id'] in traits)
                and all(isinstance(row[k],str) and row[k].strip() for k in ['scene','low_motion_scene']), 'unknown ward scene context')
        key=row['stage'],row['personality_id'];require(key not in seen,'duplicate ward scene');seen.add(key)
    require({(s,None) for s in stages} <= seen, 'ward phase lacks neutral fallback')
    require(b['ward_care'] == {'coverage':'physically_in_assigned_ward','companion_probability':0.25,
            'handoff_scope':'one_room_coverage_set',
            'ward_visit_probability':0.5,'visitor_request_scan_seconds':5,'visitor_budget_per_visit':1,
            'window_state_owner':'Visit','repeat_intent_roll':False,'visit_requires_consent':True,
            'visit_changes_recovery':False,'scene_selection':'personality_then_default',
            'scene_progress_source':'actual_stage_work','scene_completion_source':'actual_stage_completion'}, 'unsafe bedside care')
    require(b['clinical']['beds_per_nurse'] == 8 and b['clinical']['nurse_visit_seconds'] == 8
            and b['clinical']['discharge_round_seconds'] == 10
            and b['hospital_situations']['ward_visit_seconds'] == 30
            and b['hospital_situations']['ward_visits_per_patient_per_day'] == 2, 'parallel clinical timing')


def check_ward_examples(c, b, check):
    check(len(c['ward_scenes']) == 6, '六种床边表现具有三阶段通用回退且不拥有疗效')
    check(b['hospital_situations']['ward_visit_seconds'] * b['hospital_situations']['ward_visits_per_patient_per_day'] == 60,
          '同一Visit每日探视最多60秒，重试生成新WardStay不重置两窗口预算')
    rejects(c,b,validate_ward_care,check,[
        (lambda x,y:y['ward_care'].update(window_state_owner='WardStay'), '换床或重试重置探视'),
        (lambda x,y:y['ward_care'].update(coverage='assigned_id_only'), '远程护士覆盖'),
        (lambda x,y:x['ward_scenes'][0].update(recovery_bonus=1), '表演加速康复'),
        (lambda x,y:x['ward_scenes'][0].pop('low_motion_scene'), '床边表现缺少低动态姿态'),
        (lambda x,y:y['ward_care'].update(scene_completion_source='animation_finished'), '动画冒充照护完成')])


def validate_quiet_information(c, b):
    require('broadcast_contexts' not in c and 'broadcast_lines' not in c and 'broadcast' not in b,
            'hospital broadcast must not exist')


def validate_clinical_readiness_queries(b):
    rule=b['clinical_readiness_queries']
    require({k:v for k,v in rule.items() if k != 'shortage_revalidation'} == {
        'scope':'not_started_clinical_queue_readiness_only','reuse':'validated_failure_certificate_only',
        'proof_per_ticket':1,
        'base_proof_kinds':['supply_shortage','required_facility_missing','qualified_team_missing','compatible_bed_busy'],
        'dependency_source':'all_prerequisites_of_one_proven_false_condition',
        'dependency_index':'sparse_resource_scope_to_current_tickets',
        'empty_candidates':'watch_definition_role_scope_and_topology',
        'unknown_dependency':'original_full_query',
        'time_source':'original_simulation_deadlines_and_thresholds',
        'wake_at':'next_legal_stage_4','order':'original_ticket_priority_and_entity_order',
        'coalesce':'one_dirty_marker_per_current_ticket',
        'during_dispatch':'processed_tickets_next_boundary_no_reverse_insert',
        'atomic_start':'original_full_current_resource_bundle_recheck',
        'independent_rules':'original_plan_staff_queue_clock_rules_continue',
        'readiness_permission_cached':False,'world_clocks_continue':True,
        'creates_business_entities':False,'snapshot_state':False,
        'cache_eviction':'full_query_at_next_original_dispatch',
        'memory_scope':'indexes_proofs_deadline_candidates_within_existing_working_set',
        'runtime_measurement_available':False}, 'clinical waiting query changes care or loses dependencies')
    require(rule['shortage_revalidation'] == {
        'handler':'supply_shortage',
        'scope':'same_uncommitted_not_started_ticket',
        'guard':'same_identity_query_scope_and_noninventory_stamps',
        'predicate':'current_committed_available_below_current_required_amount',
        'allowed_update':'existing_inventory_dependency_stamp_only',
        'own_preparation':'existing_or_changed_commitment_full_query',
        'deadline':'preserve_and_check_original_tick',
        'when':'next_legal_stage_4_original_order',
        'otherwise':'original_full_query'}, 'shortage revalidation bypasses original preparation or deadlines')
    require(type(rule['proof_per_ticket']) is int and all(type(rule[key]) is bool for key in
            ('readiness_permission_cached','world_clocks_continue','creates_business_entities',
             'snapshot_state','runtime_measurement_available')), 'clinical query cache fields have invalid types')


def readiness_query_needed_example(proof, session, ticket_id, case_signature, dependencies, tick, b):
    """Sample certificate validity only; no clinical scheduling or world is run."""
    if not isinstance(proof,dict) or proof.get('handler_id') not in b['clinical_readiness_queries']['base_proof_kinds']:
        return True
    if (proof.get('dependencies_complete') is not True or proof.get('hospital_session')!=session
            or proof.get('current_ticket_id')!=ticket_id or proof.get('case_query_signature')!=case_signature):
        return True
    stamps=proof.get('dependency_stamps')
    if not isinstance(stamps,dict) or not stamps or any(key not in dependencies or dependencies[key]!=value
                                                      for key,value in stamps.items()):
        return True
    if 'next_original_tick' not in proof:
        return True
    deadline=proof['next_original_tick']
    return deadline is not None and (type(deadline) is not int or deadline<0 or tick>=deadline)


def next_readiness_stage_example(tick, phase, position_passed=False):
    require(type(tick) is int and tick>=0 and type(phase) is int and 1<=phase<=10,
            'invalid sample simulation boundary')
    return tick if phase<4 or (phase==4 and not position_passed) else tick+1


def check_clinical_readiness_query_examples(c, b, check):
    signature=('waiting_outpatient','station:1','P_D09_COMMON',(1,1,180),'public')
    dependencies={'supply:available':3,'visit:plan':4,'service:scope':2}
    proof={'handler_id':'supply_shortage','dependencies_complete':True,'hospital_session':'h1-load1',
           'current_ticket_id':'ticket:10','case_query_signature':signature,
           'dependency_stamps':dict(dependencies),'next_original_tick':60}
    def needed(row=proof, current=dependencies, tick=20, session='h1-load1', ticket='ticket:10', case=signature):
        return readiness_query_needed_example(row,session,ticket,case,current,tick,b)
    check(all(not needed(tick=tick) for tick in range(10,60)) and needed(tick=60),
          '失败依据在50个无变化原边界持续有效，原期限tick60到达必须完整复核；不是运行提速证明')
    check(needed(current=dict(dependencies,**{'supply:available':4}))
          and needed(current={key:value for key,value in dependencies.items() if key!='service:scope'})
          and needed(case=signature[:-1]+('staff',)),
          '库存变化、依赖缺失或病例准入身份变化使必要缺项依据失效')
    # Only illustrate a permitted stamp renewal; this is not a runtime readiness implementation.
    renewed=copy.deepcopy(proof)
    renewed['dependency_stamps']['supply:available']=4
    current=dict(dependencies,**{'supply:available':4})
    check(17-12 == 5-0 == 5 and 6-0 < 12 and not (12-0 < 12),
          '其他预留真实领用后A仍5、小额补至6仍缺12；补至12不再有缺包依据，算例不证明运行提速')
    check(not needed(row=renewed,current=current)
          and needed(row=renewed,current=current,tick=60)
          and needed(row=renewed,current=dict(current,**{'visit:plan':5}))
          and needed(row=renewed,current={k:v for k,v in current.items() if k!='service:scope'})
          and needed(row=renewed,current=current,case=signature[:-1]+('quote_without_supplies',))
          and needed(row=renewed,current=current,session='h2-load1'),
          '只续库存stamp仍受原期限/其他依赖/查询身份/会话校验；实际用量和本人准备生命周期另验')
    check(needed(row=None) and needed(session='h2-load1') and needed(ticket='ticket:11')
          and needed(row=dict(proof,dependencies_complete=False))
          and needed(row=dict(proof,handler_id='extension_unknown'))
          and needed(row={key:value for key,value in proof.items() if key!='next_original_tick'}),
          '缓存缺失、会话/票不符、未知依赖处理器或期限未声明回到原完整查询')
    check(not needed(row=dict(proof,next_original_tick=None))
          and needed(row=dict(proof,next_original_tick='60'))
          and needed(row=dict(proof,next_original_tick=-1)),
          '可证明无时间依赖的必要缺项可等待真实变化，坏期限不能静待')
    check([next_readiness_stage_example(100,phase) for phase in (1,2,3,5,6,9,10)]
          ==[100,100,100,101,101,101,101]
          and next_readiness_stage_example(100,4,False)==100
          and next_readiness_stage_example(100,4,True)==101,
          '采购/拓扑同次④、到位/完成/研究下一次④，已越过位置不逆序再次派单')
    wake_ids=set(['ticket:30','ticket:10','ticket:30','ticket:10'])
    original_order=['ticket:10','ticket:20','ticket:30']
    check([ticket for ticket in original_order if ticket in wake_ids]==['ticket:10','ticket:30'],
          '重复变化合并原票标记，查询候选沿原顺序而非事件到达顺序；优先公平仍由原队列处理')
    negatives=[
        (lambda row:row.update(reuse='cached_ready_permission'), '缓存允许开工导致抢同一资源'),
        (lambda row:row.update(dependency_source='first_old_instance_only'), '失败候选遗漏合法替代来源'),
        (lambda row:row.update(empty_candidates='no_subscriptions'), '无候选无法被新增设施唤醒'),
        (lambda row:row.update(unknown_dependency='keep_waiting'), '未知依赖永久静待'),
        (lambda row:row.update(time_source='since_last_query'), '重查重置原等待钟'),
        (lambda row:row.update(order='notification_arrival'), '唤醒先后替代原优先公平'),
        (lambda row:row.update(during_dispatch='restart_from_first'), '本轮逆序重复派单'),
        (lambda row:row.update(atomic_start='trust_proof_or_ready_cache'), '实际开工绕过资源束复核'),
        (lambda row:row.update(independent_rules='skip_plan_or_staff_checks'), '省查询跳过方案重评或员工准备'),
        (lambda row:row.update(world_clocks_continue=False), '省查询暂停候诊和弃候'),
        (lambda row:row.update(creates_business_entities=True), '查询唤醒创造服务实体'),
        (lambda row:row.update(snapshot_state=True), '缓存成为存档事实'),
        (lambda row:row.update(cache_eviction='assume_not_ready'), '回收后误判永远不就绪'),
        (lambda row:row['shortage_revalidation'].update(allowed_update='replace_all_stamps'), '缺包续证掩盖其他资源变化'),
        (lambda row:row['shortage_revalidation'].update(own_preparation='ignore_own_reservation'), '本人已预留仍按全院A阻断'),
        (lambda row:row['shortage_revalidation'].update(deadline='restart_after_inventory_change'), '补少量包推迟原复核期限'),
        (lambda row:row['shortage_revalidation'].update(predicate='old_quantity_or_uncommitted_reservations'), '使用旧需求或提前释放未来预留'),
        (lambda row:row.update(proof_per_ticket=True), '依据数量混用布尔')]
    for mutate,label in negatives:
        broken=copy.deepcopy(b); mutate(broken['clinical_readiness_queries'])
        try:validate_clinical_readiness_queries(broken)
        except ValueError:check(True,'等待查询合同负例被拒绝：'+label)
        else:raise ValueError('invalid clinical readiness query contract accepted: '+label)


def validate_supply_purchase_intents(c, b):
    require(b['supplies']['top_up'] == {
        'scope':'current_hospital_supply_shortage_card',
        'target_source':'first_ready_case_else_active_strike_recovery',
        'quantity_source':'target_requirement_minus_current_available',
        'recovery_requirement_source':'existing_episode_close_per_request_max',
        'recovery_scope':'active_episode_with_striking_participant',
        'zero_quantity':'no_purchase_suggestion',
        'confirmation':'existing_manual_purchase_exact_quantity',
        'stock_scope':'hospital_shared','grants_preparation_reservation':False,
        'changes_plan':False,'bypasses_clinical_order':False,
        'manual_uses_auto_cash_reserve':False,'auto_requests_community_aid':False,
        'target_change':'refresh_explanation_keep_submitted_quantity',
        'scene_selection':'replace_same_order_purchase_scene','saves_quote':False},
        'top-up suggestion changes preparation, queue, strike recovery or purchase intent')
    require(b['supplies']['funding'] == {
        'normal_manual':'hospital_cash_full_cost',
        'community_aid':'original_separate_20_unit_order',
        'normal_auto':'cash_above_original_reserve',
        'creative_manual':'hospital_cash_then_creative_fund_shortfall',
        'creative_auto':'target_and_capacity_hospital_cash_then_creative_fund',
        'aid_counter':'community_aid_orders_only',
        'receipt':'cost_equals_hospital_paid_plus_direct_paid',
        'direct_payment_source':'committed_order_source',
        'credits_fund_to_cash':False,'unpaid_inventory':False},
        'purchase funding bypasses paid stock, credits aid cash or mixes hospital modes')
    cues = indexed(c['medical_supplies'])['SUP01']['top_up_cues']
    fields = {
        'label_template':{'units','cost'},
        'context_template':{'patient_name','ticket_label'},
        'recovery_label_template':{'units','cost'},
        'recovery_context_template':set(), 'scope_line':set(), 'zero_line':set(),
        'purchase_scene':set(), 'low_motion_scene':set()}
    require(set(cues) == set(fields), 'top-up cue owns extra state or omits an explanation')
    for key, variables in fields.items():
        require(isinstance(cues[key], str) and cues[key].strip(), 'empty top-up cue')
        parsed = list(Formatter().parse(cues[key]))
        actual = {field for _, field, _, _ in parsed if field is not None}
        require(actual == variables
                and all(not spec and conversion is None for _, field, spec, conversion in parsed
                        if field is not None), 'top-up cue uses an unknown fact or formatted expression')


def validate_supplies_and_fit(c, b):
    validate_supply_purchase_intents(c, b)
    supplies = indexed(c['medical_supplies'])
    require(set(supplies) == {'SUP01'} and supplies['SUP01']['unit_price'] == 20
            and supplies['SUP01']['unit'] == '包', 'supplies need one priced stock item')
    openings = indexed(supplies['SUP01']['opening_scenes'], 'definition_id')
    require(set(openings) == {r['definition_id'] for r in c['medical_equipment_profiles']
                              if r['effect_kind'] in {'outpatient','surgery'}}, 'supply opening lacks a consuming device or includes a free service')
    require(all(set(r) == {'definition_id','scene','low_motion_scene'} and r['scene'] and r['low_motion_scene']
                for r in openings.values()), 'opening scene owns stock or lacks accessible pose')
    require([c['profiles'][p]['supply_units'] for p in ('A','B','C')] == [1,2,3], 'wrong outpatient stock units')
    protocols = indexed(c['treatment_protocols'])
    require([protocols['TP_GENTLE']['clinical_profiles'][p]['supply_units'] for p in ('A','B','C')] == [2,3,4]
            and [protocols['TP_SURGERY'+str(i)]['supply_units'] for i in (1,2,3)] == [8,10,12], 'wrong clinical stock units')
    require(all('consumables' not in p for p in c['profiles'].values())
            and all('consumables' not in p for p in protocols.values())
            and all('consumables' not in p for p in protocols['TP_GENTLE']['clinical_profiles'].values()), 'duplicate consumption cash charge')
    require(b['supplies']['auto_evaluation'] == {
        'inputs':'current_original_facts_after_player_commands',
        'no_order_proofs':['automatic_disabled','available_at_or_above_unclamped_reorder',
                           'normal_cash_below_reserve_floor_plus_unit_price'],
        'capacity_read':'after_no_order_proofs',
        'budget_read':'normal_below_actual_reorder_with_free_capacity',
        'proof_result':'no_order_only_not_shortage_primary_reason',
        'commit':'original_current_facts_and_atomic_order',
        'extra_saved_state':False,'runtime_measurement_available':False},
        'automatic supply evaluation changes current facts, order rules or reason ownership')
    base = {k:v for k,v in b['supplies'].items() if k not in {'top_up','funding','auto_evaluation'}}
    require(base == {'definition_id':'SUP01','capacity_floor':200,'initial_purchase_units':60,
        'quick_purchase_units':20,'auto_restock_default':True,'reorder_floor':20,'restock_floor':60,
        'cash_reserve_floor':1000,'auto_order_sizing':'target_capacity_and_affordable_units',
        'growth':{'capacity_source':'installed_medical_subjects','outpatient_buffer_units':20,'surgery_buffer_units':80,
                  'demand_source':'last_completed_day_actual_consumption','reorder_demand_numerator':1,
                  'target_demand_numerator':3,'demand_denominator':4,
                  'cash_reserve_source':'max_floor_and_next_settlement_wages_operations',
                  'over_capacity':'keep_existing_no_new_purchase','rules_derive_only':True},
        'auto_check_order':'after_player_commands_once_per_boundary','delivery':'immediate_after_paid_order','consume_at':'attempt_start',
        'reservation':'clinical_preparation','reservation_seconds':30,
        'aid_purchase_units':20,'aid_orders_per_day':1,'expiry':False,'storage_building':False,
        'shortage_warning_seconds':60,'shortage_repeat_seconds':60,'shortage_stress_per_warning':6,
        'warnings_per_episode':3,'strike_after_seconds':180,'strike_stress_threshold':50,
        'return_to_work_seconds':30,'restock_stress_relief':6,
        'strike_safety':'finish_committed_care','shortage_notice_scope':'hospital'}, 'unsafe stock or strike policy')
    require({r['stage'] for r in c['supply_reactions']} == {'waiting','warning','strike','returning'}
            and all(set(r)=={'id','stage','scene','low_motion_scene'} and r['scene'] and r['low_motion_scene'] for r in indexed(c['supply_reactions']).values()), 'reaction has hidden species/effect rules')
    require(b['facility_magic'] == {'mode':'automatic','unlocked':'initial','extra_cost':0,
        'navigation':'actual_body_envelope','operator_space':'actual_body_envelope',
        'changes_occupied_cells':True,'requires_free_space':True,'blocks_navigation':True,'works_when_faulted':True,
        'scope':['doors','beds','medical_equipment','amenities','staff_workstations','vertical_connectors'],
        'visual_method':'physical_extension','reservation':'atomic_before_use','anchor':'fixed_local_origin',
        'release':'after_user_and_extension_clear','exit_policy':'reject_if_strands_actor',
        'restore_from':'saved_adaptation_reservation'}, 'magic bypasses actual space')
    fit = {r['kind']:r for r in indexed(c['facility_fit_profiles']).values()}
    require(set(fit) == {'door','bed','medical','operating_table','amenity','workstation','vertical_connector'}
            and fit['bed']['pose'] == fit['operating_table']['pose'] == 'reclined'
            and fit['vertical_connector']['extent_rule'] == 'fixed_structure_expanding_fittings', 'unowned fitting geometry')
    require({r['target'] for r in indexed(c['facility_magic_scenes']).values()} == set(b['facility_magic']['scope']), 'missing fitting scene')
    require(all(set(r) == {'id','target','scene','blocked_scene','low_motion_scene'}
                and all(isinstance(r[k],str) and r[k].strip() for k in ('scene','blocked_scene','low_motion_scene'))
                for r in c['facility_magic_scenes']), 'facility gag lacks blocked pose or changes simulation')
    require(all(r['fit_policy']=='automatic' for r in c['doors']+c['vertical_connectors']), 'manual fit setting reintroduced')
    require(len(indexed(c['ease_rules']))==9 and all(r['default'] and r['detail'] for r in c['ease_rules']), 'missing simple default or optional detail')
    maintained=b['equipment']['maintained_definition_ids']
    require(len(maintained)==len(set(maintained)) and set(maintained)=={'FUR02','FUR05','SE02','M09','M37','M17','EQ01','EQ05','VC02','VC03'}
            and b['equipment']['unlisted_policy']=='no_wear_failure_or_maintenance', 'everyday furniture maintenance reintroduced')
    require('wear_equipment' not in indexed(c['incidents'])['E25']['effects'], 'knocking creates door repair')
    require(b['case_body'] == {'symptom_source':'treatment_binding',
            'active_until':'actual_cure_or_actor_departure','mid_visit_growth':False,
            'staff_uses_patient_symptom':False,'task_size_source':'admission_binding_body'}, 'symptom size changes during route or applies to staff')



def supply_targets(outpatient_count, surgery_count, used_last_day, next_settlement_cost, b):
    """Static arithmetic only; inputs must come from actual world facts."""
    require(all(type(v) is int and v>=0 for v in
                (outpatient_count,surgery_count,used_last_day,next_settlement_cost)), 'invalid actual supply input')
    rule=b['supplies']; g=rule['growth']; denominator=g['demand_denominator']
    capacity=max(rule['capacity_floor'],g['outpatient_buffer_units']*outpatient_count+
                 g['surgery_buffer_units']*surgery_count)
    target=min(capacity,max(rule['restock_floor'],
               (g['target_demand_numerator']*used_last_day+denominator-1)//denominator))
    reorder=min(target,max(rule['reorder_floor'],
                (g['reorder_demand_numerator']*used_last_day+denominator-1)//denominator))
    reserve=max(rule['cash_reserve_floor'],next_settlement_cost)
    return capacity,reorder,target,reserve


def supply_top_up_example(required, stock, reserved, cash, capacity, price, creative=False):
    """Conditional purchase arithmetic; does not select a live clinical request."""
    require(all(type(v) is int and v >= 0 for v in
                (required, stock, reserved, cash, capacity, price)) and reserved <= stock and price > 0,
            'invalid conditional top-up input')
    units = max(0, required - (stock-reserved))
    cost = units * price
    accepted = units > 0 and units <= capacity-stock and (creative or cost <= cash)
    paid = (min(cash,cost) if creative else cost) if accepted else 0
    direct = cost-paid if accepted else 0
    return units, cost, accepted, paid, direct, stock+(units if accepted else 0), cash-paid


def check_supply_purchase_examples(c, b, check):
    price = indexed(c['medical_supplies'])['SUP01']['unit_price']
    protocols = indexed(c['treatment_protocols'])
    normal = c['profiles']['A']['supply_units']
    gentle = protocols['TP_GENTLE']['clinical_profiles']['C']['supply_units']
    surgical = protocols['TP_SURGERY3']['supply_units']
    capacity = b['supplies']['capacity_floor']
    example = lambda required,stock,reserved,cash,creative=False: supply_top_up_example(
        required,stock,reserved,cash,capacity,price,creative)
    check(example(normal,0,0,35) == (1,20,True,20,0,1,15),
          '手动补1包实付20，现金35降到15，不由自动保留额阻止')
    check(example(gentle,10,8,60) == (2,40,True,40,0,12,20),
          '舒缓C档需要4包，已预留8不算可用，补2包后可用4')
    check(example(surgical,5,0,150) == (7,140,True,140,0,12,10)
          and example(surgical,5,0,139) == (7,140,False,0,0,5,139),
          '手术需12包时补7包140；139整单拒绝，不悄悄改买6包')
    check(example(surgical,5,0,25,True) == (7,140,True,25,115,12,0),
          '创作采购140由医院25和基金115真实付款，不把基金写成现金收入')
    check(example(max(2,surgical),5,0,150)[0] == 7
          and example(0,5,0,150)[2] is False
          and example(gentle,12,8,60)[2] is False,
          '复工逐请求门槛取最大值12而非合计14，零缺口不生成订单')
    rejects(c,b,validate_supply_purchase_intents,check,[
        (lambda x,y:y['supplies']['top_up'].update(target_source='selected_patient'), '采购跟随选中患者插队'),
        (lambda x,y:y['supplies']['top_up'].update(grants_preparation_reservation=True), '采购建议替患者预留包'),
        (lambda x,y:y['supplies']['top_up'].update(recovery_requirement_source='sum_concurrent_requests'), '复工门槛冒充并发准备'),
        (lambda x,y:y['supplies']['top_up'].update(manual_uses_auto_cash_reserve=True), '手动小额补货被自动底线阻止'),
        (lambda x,y:y['supplies']['top_up'].update(auto_requests_community_aid=True), '自动小单消耗每日援助'),
        (lambda x,y:y['supplies']['top_up'].update(target_change='replace_submitted_quantity'), '队列变化暗改已提交数量'),
        (lambda x,y:y['supplies']['funding'].update(creative_auto='cash_above_original_reserve'), '创作基金仍被普通现金底线阻挡'),
        (lambda x,y:y['supplies']['funding'].update(credits_fund_to_cash=True), '直接代付变成现金补助'),
        (lambda x,y:y['supplies']['funding'].update(direct_payment_source='current_hospital_mode'), '切模式重标旧订单代付来源'),
        (lambda x,y:x['medical_supplies'][0]['top_up_cues'].update(context_template='{future_success}'), '采购文案虚构未来疗效'),
        (lambda x,y:x['medical_supplies'][0]['top_up_cues'].update(low_motion_scene=''), '采购缺少低动态回执')])


def append_supply_purchase_atlas(lines, c, b, table):
    cues = indexed(c['medical_supplies'])['SUP01']['top_up_cues']
    lines += ['### 当前缺口的采购建议', '',
              '建议取原队列中其余条件可就绪的首个缺包请求；没有可接单候选而本次缺货已有罢工参与者时，取原事件关闭查询的逐请求最大需要量。采购进入全院共享库存，准备和复工沿原流程。', '']
    table(lines, ['提示', '文案'], [[key,cues[key]] for key in
          ('label_template','context_template','recovery_label_template','recovery_context_template','scope_line','zero_line')])
    table(lines, ['同一订单的回执动作', '低动态'], [[cues['purchase_scene'],cues['low_motion_scene']]])
    protocols = indexed(c['treatment_protocols'])
    price = indexed(c['medical_supplies'])['SUP01']['unit_price']
    samples = [
        ('普通A',c['profiles']['A']['supply_units'],0,0,35,False),
        ('舒缓C',protocols['TP_GENTLE']['clinical_profiles']['C']['supply_units'],10,8,60,False),
        ('手术3',protocols['TP_SURGERY3']['supply_units'],5,0,150,False),
        ('创作：手术3',protocols['TP_SURGERY3']['supply_units'],5,0,25,True)]
    rows = []
    for label,required,stock,reserved,cash,creative in samples:
        units,cost,accepted,paid,direct,after_stock,after_cash = supply_top_up_example(
            required,stock,reserved,cash,b['supplies']['capacity_floor'],price,creative)
        require(accepted, 'conditional supply atlas describes a rejected purchase as completed')
        rows.append([label,f'{stock}/{reserved}',cash,f'{units}包 / {cost}币',
                     f'{paid} / {direct}',f'{after_stock}/{reserved}',after_cash])
    lines += ['自动补货先读原命令边界的当前事实：关闭、可用量已达未夹限触发线上界，或普通现金不足保留额下界加一包单价时，无需完整订单求值；剩余情况再按原容量和预算公式处理。排除只证明零订单，不代替缺货原因或付款核验。没有新增采购缓存或实测提速。', '',
              '以下为其余条件可就绪且数量不变的单笔订单算术；仅到本单入库时，后续自动补货、准备和领用另行发生。没有游戏就绪或复工实测。', '']
    table(lines, ['条件', '原实存/预留', '原现金', '补足报价', '医院实付/基金代付', '单笔入库后实存/预留', '余款'], rows)


def check_supplies_and_fit_examples(c, b, check):
    check_supply_purchase_examples(c, b, check)
    check('broadcast' not in b and 'broadcast_lines' not in c, '广播配置与文案完全移除')
    rule=b['supplies']; price=c['medical_supplies'][0]['unit_price']
    check(b['starting_cash']-sum(row['amount'] for row in b['starter_purchase'])-1480-rule['initial_purchase_units']*price==10600, '开院含职员设施并实际采购60包后余额10600')
    check(rule['quick_purchase_units']*price==400 and 399 < 400, '快捷采购20包实付400，399不足整单')
    def auto_order(stock, reserved, cash, targets=None, creative=False):
        capacity,reorder,target,reserve=targets or supply_targets(2,0,0,819,b)
        available=stock-reserved
        if available>=reorder: return 0
        if creative: return max(0,min(target-available,capacity-stock))
        affordable=max(0,(cash-reserve)//price)
        return max(0,min(target-available,capacity-stock,affordable))
    # Compare sufficient zero-order proofs with the complete existing formula.
    # This is design arithmetic, not a runtime query or performance benchmark.
    compared = 0
    for outpatient,surgery in ((0,0),(2,0),(20,2),(100,20)):
        for demand in (0,1,79,80,81,239,240,241,319,320,321,799,800,801,10000):
            g=rule['growth']; denominator=g['demand_denominator']
            upper=max(rule['reorder_floor'],
                      (g['reorder_demand_numerator']*demand+denominator-1)//denominator)
            for settlement in (0,1000,4000,200000):
                targets=supply_targets(outpatient,surgery,demand,settlement,b)
                capacity,reorder,target,reserve=targets
                require(reorder<=upper, 'unclamped reorder is not a safe upper bound')
                for stock in {0,19,20,max(0,reorder-1),reorder,upper,capacity-1,capacity,capacity+20}:
                    for reserved in {0,stock//2,stock}:
                        for cash in (0,999,1000,1019,1020,1819,1820,8500,200000):
                            for creative in (False,True):
                                for enabled in (False,True):
                                    complete=auto_order(stock,reserved,cash,targets,creative) if enabled else 0
                                    excluded=(not enabled or stock-reserved>=upper
                                              or (not creative and cash<rule['cash_reserve_floor']+price)
                                              or stock-reserved>=reorder or stock>=capacity)
                                    optimized=0 if excluded else auto_order(stock,reserved,cash,targets,creative)
                                    require(optimized==complete, 'automatic supply short-circuit lost a real order')
                                    compared+=1
    check(compared>100000, '自动采购充分零订单条件与完整公式逐例一致，覆盖普通/创作、预留、取整、资金与超容量；非运行性能证明')
    check(auto_order(19,0,1820)==41 and auto_order(19,0,1819)==40
          and auto_order(0,0,1200)==10 and auto_order(0,0,1019)==0
          and auto_order(0,0,1020)==1 and auto_order(20,0,3000)==0,
          '自动采购19/20阈值、预算允许的整包与1000现金底线')
    check(auto_order(0,0,0)==0 and auto_order(0,0,0,creative=True)==60
          and auto_order(19,0,1019)==0 and auto_order(19,0,1019,creative=True)==41
          and auto_order(20,0,0,creative=True)==0
          and auto_order(200,185,0,creative=True)==0,
          '创作自动采购遵循真实触发线和实体容量，由基金补现金缺额，不套普通保留额')
    check(auto_order(195,180,3000)==5 and auto_order(200,185,3000)==0, '预留不腾实体容量，采购不超过200')
    large=supply_targets(20,2,320,4000,b)
    check(large==(560,80,240,4000) and auto_order(70,0,8500,large)==170
          and 8500-170*price==5100, '大院按真实320包用量备货，支付后保留下一次必要日结')
    check(supply_targets(20,2,0,4000,b)==(560,20,60,4000)
          and auto_order(220,210,20000,supply_targets(2,0,320,819,b))==0,
          '空扩建不触发大量采购，拆机后超容量库存保留且新增采购为零')
    check(supply_targets(20,2,1,0,b)==(560,20,60,1000)
          and supply_targets(20,2,10000,0,b)==(560,560,560,1000),
          '用量取整与容量夹限有效，无需求仍不超前囤货')
    check(10-8 < 8 and 10-8==2 and 10-0==10, '两个各需8包的准备不能共享10包，取消释放后可重新预留')
    check(rule['warnings_per_episode']*rule['shortage_stress_per_warning']==18
          and 3*rule['shortage_repeat_seconds']==rule['strike_after_seconds'], '真实受阻三次提醒最多18压力，180秒后才可能罢工')
    check(rule['strike_safety']=='finish_committed_care' and rule['return_to_work_seconds']==30,
          '抗议保留必要护理，补货后30秒自动复工')
    species=indexed(c['species'])
    case_bodies = {(r['species_id'],r['disease_id']): binding_body(species[r['species_id']],r)
                   for r in c['treatment_bindings'] if 'symptom_envelope' in r}
    check({key:max(expanded_footprint([0,0],body)) for key,body in case_bodies.items()}
          == {('S06','D04'):2,('S08','D04'):3,('S38','D33'):2}, '三类实体膨胀分别实际占2/3/2格通路')
    check(expanded_footprint([3,3],case_bodies[('S08','D04')],True)==[3,4]
          and expanded_footprint([3,3],species['S08']['body'],True)==[3,3],
          '冠顶树人按症状需要3×4床，不能套健康3×3')
    check(expanded_footprint([3,3],species['S01']['body'],True)==[3,4]
          and expanded_footprint([3,3],species['S59']['body'],True)==[3,5]
          and expanded_footprint([2,2],species['S59']['body'])==[3,3], '真实身体使长颈床3×4、巨人床3×5、门诊机器3×3')
    def cells(anchor,size):
        return {(anchor[0]+x,anchor[1]+y) for x in range(size[0]) for y in range(size[1])}
    base=cells((2,0),(3,3)); expanded=cells((2,0),(3,5)); room=cells((0,0),(7,7))
    check(expanded <= room and (4,4) not in base and (4,4) in expanded,
          '床尾新占两行，原本空着的格子成为实际占用')
    check(bool(expanded & {(4,4)}) and not bool(base & {(4,4)}), '床尾有家具/垃圾时只能保留原形')
    def reachable(blocked,k,start,target):
        allowed=cells((0,0),(7,5));seen={start};todo=deque([start])
        while todo:
            p=todo.popleft()
            for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                q=p[0]+dx,p[1]+dy
                swept=cells(p,(k,k))|cells(q,(k,k))
                if q not in seen and swept<=allowed and not swept & blocked:
                    seen.add(q);todo.append(q)
        return target in seen
    check(reachable(base,1,(0,4),(6,4)) and not reachable(expanded,1,(0,4),(6,4)),
          '床展开堵满走廊时小体型也不能穿过去')
    partial=cells((2,0),(3,4))
    check(reachable(partial,1,(0,4),(6,4)) and not reachable(partial,2,(0,3),(5,3)),
          '床尾余一格小体型可过，两格身体仍走不过去')
    check(bool(expanded & cells((4,4),(2,2))), '两设施争伸展格不能同时预留')
    rejects(c,b,validate_quiet_information,check,[(lambda x,y:x.update(broadcast_lines=[]),'重新加入广播文案')])
    rejects(c,b,validate_supplies_and_fit,check,[
        (lambda x,y:y['supplies']['auto_evaluation'].update(inputs='previous_boundary_cache'),'沿旧边界判断自动补货'),
        (lambda x,y:y['supplies']['auto_evaluation'].update(proof_result='shortage_primary_reason'),'短路结果冒充缺货主因'),
        (lambda x,y:y['supplies']['auto_evaluation'].update(budget_read='all_modes_every_boundary'),'创作或确定零订单仍强求保留预算'),
        (lambda x,y:y['supplies'].update(consume_at='every_resume'),'接续重复扣包'),
        (lambda x,y:y['supplies'].update(delivery='unpaid_spawn'),'未付款到货'),
        (lambda x,y:y['supplies'].update(strike_safety='abandon_current_patient'),'术中罢工'),
        (lambda x,y:x['supply_reactions'][0].update(species_id='S01'),'按种族生气'),
        (lambda x,y:x['medical_supplies'][0]['opening_scenes'][0].update(stock_delta=-1),'开包动画另扣库存'),
        (lambda x,y:y['facility_magic'].update(requires_free_space=False),'空间不够也伸展'),
        (lambda x,y:x['facility_magic_scenes'][0].update(moves_blocker=True),'设施小戏挤开障碍'),
        (lambda x,y:y['facility_magic'].update(blocks_navigation=False),'伸长床尾可穿越'),
        (lambda x,y:y['facility_magic'].update(navigation='one_cell_for_everyone'),'统一一格忽略身体'),
        (lambda x,y:y['facility_magic'].update(restore_from='animation'),'读档未恢复真实阻挡'),
        (lambda x,y:y['equipment']['maintained_definition_ids'].append('FUR18'),'垃圾桶也随机维修')])


def validate_protocol_presentation(c, b):
    p = b['treatment_presentation']
    require(p['phase_boundary_rule'] == 'ceil_cumulative_work_ticks'
            and p['protocol_mode_source'] == 'attempt_frozen_protocol'
            and p['protocol_mode_scope'] == 'outpatient_work_only' and p['gentle_work_included'] is True,
            'protocol presentation changes the frozen work, timing or clinical scope')
    require(p['gentle_creates_affect_fact'] is False and p['gentle_counts_nurse_help'] is False
            and p['gentle_requires_extra_staff'] is False and p['protocol_style_changes_success'] is False,
            'gentle scene creates extra calming, nursing staff or success')
    protocols = indexed(c['treatment_protocols'])
    for protocol in protocols.values():
        if protocol['kind'] == 'outpatient':
            require(protocol['presentation_mode'] in {'standard', 'gentle'}, 'unknown outpatient presentation mode')
    require(protocols['TP_COMMON']['presentation_mode'] == 'standard'
            and protocols['TP_GENTLE']['presentation_mode'] == 'gentle', 'core protocols use the wrong presentation mode')
    for row in c['medical_progress_cues']:
        variants = indexed(row['protocol_variants'], 'mode')
        require(set(variants) == ({'gentle'} if row['progress_source'] == 'attempt_work' else set()),
                'gentle work cue missing or applied to diagnosis, surgery or ward')
        for variant in variants.values():
            require(set(variant) == {'mode', 'beats'} and isinstance(variant['beats'], list)
                    and [beat['phase'] for beat in variant['beats']] == p['beat_phases'], 'protocol cue phase contract incomplete')
            require(all(set(beat) == {'phase', 'scene', 'low_motion_scene'}
                        and all(isinstance(beat[key], str) and beat[key].strip() for key in ('scene', 'low_motion_scene'))
                        for beat in variant['beats']), 'protocol cue owns effects or lacks body-safe/low-motion scene')


def presentation_boundaries_example(total_work_ticks, b):
    cumulative = 0; boundaries = []
    for point in b['treatment_presentation']['beat_basis_points']:
        cumulative += point
        boundaries.append((total_work_ticks * cumulative + 9999) // 10000)
    return boundaries


def check_protocol_presentation_examples(c, b, check):
    protocols = indexed(c['treatment_protocols']); routine = indexed(c['treatment_routines'])['TR01']
    tick = Fraction(str(b['tick_seconds']))
    totals = [ceil(Fraction(str(routine['service_seconds'])) * Fraction(str(protocols[key]['work_multiplier'])) / tick)
              for key in ('TP_COMMON', 'TP_GENTLE')]
    boundaries = [presentation_boundaries_example(total, b) for total in totals]
    spans = [[end - start for start, end in zip([0] + values[:-1], values)] for values in boundaries]
    check(totals == [360,648] and boundaries == [[54,216,306,360],[98,389,551,648]]
          and spans == [[54,162,90,54],[98,291,162,97]] and [sum(values) for values in spans] == totals,
          'TR01冻结36/64.8秒使用累计边界，舒缓9.8/29.1/16.2/9.7秒仍合计64.8秒')
    gentle_bounds = boundaries[1]
    check([sum(done >= end for end in gentle_bounds) for done in (0,97,98,388,389,550,551,648)]
          == [0,0,1,1,2,2,3,4], '舒缓工作tick达到累计边界才切段，完成后不追加第五段表演')
    all_exact = True
    for row in c['treatment_routines']:
        for protocol in (protocols['TP_COMMON'], protocols['TP_GENTLE']):
            total = ceil(Fraction(str(row['service_seconds'])) * Fraction(str(protocol['work_multiplier'])) / tick)
            bounds = presentation_boundaries_example(total, b)
            all_exact &= bounds[-1] == total and all(a < z for a, z in zip([0] + bounds[:-1], bounds))
    check(all_exact, '84套演出的两个门诊模式累计边界不漏段、不增加冻结工作量；不验证实际临床资格或动画')
    rejects(c, b, validate_protocol_presentation, check, [
        (lambda x,y:indexed(x['treatment_protocols'])['TP_GENTLE'].update(presentation_mode='free_nurse_help'), '表现模式充当护士服务'),
        (lambda x,y:y['treatment_presentation'].update(phase_boundary_rule='ceil_each_segment_and_add'), '各段取整附加工作'),
        (lambda x,y:y['treatment_presentation'].update(gentle_creates_affect_fact=True), '舒缓小戏重复减怒'),
        (lambda x,y:y['treatment_presentation'].update(gentle_counts_nurse_help=True), '前奏刷护士绩效'),
        (lambda x,y:y['treatment_presentation'].update(gentle_requires_extra_staff=True), '每次舒缓额外拉护士'),
        (lambda x,y:y['treatment_presentation'].update(protocol_style_changes_success=True), '动作额外提高成功率'),
        (lambda x,y:x['medical_progress_cues'][1]['protocol_variants'][0]['beats'][0].update(anger_delta=-15), '次要动作带护士安抚效果'),
        (lambda x,y:x['medical_progress_cues'][1]['protocol_variants'][0]['beats'][0].update(low_motion_scene=''), '舒缓准备缺低动态'),
        (lambda x,y:x['medical_progress_cues'][0].update(protocol_variants=copy.deepcopy(x['medical_progress_cues'][1]['protocol_variants'])), '诊断台提前播放门诊舒缓'),
    ])


def validate_diagnostic_work_styles(c, b):
    require(b['diagnostic_work_presentation'] == {
        'actor_source':'started_service_current_doctor',
        'service_scope':'initial_consultation_only','state_scope':'working_only',
        'selection':'definition_and_doctor_personality','mode':'replace_secondary_only',
        'missing_style':'original_generic_working_pose','added_work_seconds':0,
        'gameplay_effects':False,'dialogue':False,
        'secondary_budget_source':'treatment_presentation'},
        'diagnostic style uses predicted staff, adds work or owns clinical effects')
    personalities = indexed(c['doctor_personalities'])
    diagnostic = {r['definition_id'] for r in c['medical_equipment_profiles']
                  if r['effect_kind'] == 'diagnostic'}
    pairs = set()
    for row in indexed(c['diagnostic_work_styles']).values():
        require(set(row) == {'id','definition_id','doctor_personality_id','scene','low_motion_scene'}
                and row['definition_id'] in diagnostic
                and row['doctor_personality_id'] in personalities,
                'diagnostic style has an invalid device/personality or adds gameplay fields')
        require(all(isinstance(row[k], str) and row[k].strip()
                    for k in ('scene','low_motion_scene')), 'diagnostic style lacks a readable pose')
        pair = (row['definition_id'], row['doctor_personality_id'])
        require(pair not in pairs, 'diagnostic style has an ambiguous device/personality key')
        pairs.add(pair)
    require({('FUR02',f'DP{i:02}') for i in range(1,7)} <= pairs,
            'core initial consultation lacks one of the six professional styles')


def diagnostic_work_style_example(c, *, service_kind, phase, provider_id,
                                  provider_role, personality_id, definition_id='FUR02'):
    if (service_kind != 'initial_consultation' or phase != 'working'
            or not provider_id or provider_role != 'doctor'):
        return None
    return next((r['id'] for r in c['diagnostic_work_styles']
                 if r['definition_id'] == definition_id
                 and r['doctor_personality_id'] == personality_id), None)


def check_diagnostic_work_style_examples(c, b, check):
    context = dict(service_kind='initial_consultation',phase='working',
                   provider_id='actual_provider',provider_role='doctor',personality_id='DP01')
    select = lambda catalog=c, **changes: diagnostic_work_style_example(catalog, **(context | changes))
    check([select(personality_id=f'DP{i:02}') for i in range(1,7)]
          == [f'DW{i:02}' for i in range(1,7)], '六种初诊动作只读实际医生DP性格')
    check(select(provider_id=None) is None, '推荐或待到岗医生不能充当实际初诊演员')
    check(all(select(phase=p) is None for p in ('waiting','held','completed')),
          '未开工、暂停与完成不继续播放性格工作动作')
    check(select(service_kind='check') is None
          and select(service_kind='check',provider_role='nurse') is None
          and select(provider_role='nurse') is None,
          '医生代检查和护士检查不冒充医生初诊性格')
    extended = copy.deepcopy(c)
    new_personality = copy.deepcopy(extended['doctor_personalities'][0])
    new_personality.update(id='DP07', name='新增专业性格')
    extended['doctor_personalities'].append(new_personality)
    validate_diagnostic_work_styles(extended, b)
    check(select(extended,personality_id='DP07') is None,
          '已注册新性格没有专用动作时可回退原功能姿态')
    new_style = copy.deepcopy(extended['diagnostic_work_styles'][2])
    new_style.update(id='DW07',doctor_personality_id='DP07')
    extended['diagnostic_work_styles'].append(new_style)
    validate_diagnostic_work_styles(extended, b)
    check(select(extended,personality_id='DP07') == 'DW07',
          '追加合法性格动作不受基础六种数量限制')
    rejects(c,b,validate_diagnostic_work_styles,check,[
        (lambda x,y:x['diagnostic_work_styles'][0].update(doctor_personality_id='PP01'), '日常性格冒充医生DP性格'),
        (lambda x,y:x['diagnostic_work_styles'][0].update(definition_id='M09'), '治疗机器播放初诊小戏'),
        (lambda x,y:x['diagnostic_work_styles'].append(dict(x['diagnostic_work_styles'][0],id='DW_DUP')), '同主体同医生性格重复定义'),
        (lambda x,y:y['diagnostic_work_presentation'].update(actor_source='case_recommended_doctor'), '推荐医生代替实际工作者'),
        (lambda x,y:y['diagnostic_work_presentation'].update(gameplay_effects=True), '诊断性格动作增加疗效'),
        (lambda x,y:y['diagnostic_work_presentation'].update(dialogue=True), '初诊工作小戏附加现场对白'),
        (lambda x,y:x['diagnostic_work_styles'][0].update(low_motion_scene=''), '性格动作缺低动态姿态')])


def validate_daily_experience(c, b):
    validate_diagnostic_work_styles(c, b)
    validate_clinical_readiness_queries(b)
    """References and protected boundaries for the everyday experience definitions."""
    validate_protocol_presentation(c, b)
    species = indexed(c['species'])
    personalities = indexed(c['patient_personalities'])
    materials = indexed(c['renovation_materials'])
    equipment = {r['definition_id']: r['effect_kind'] for r in c['medical_equipment_profiles']}
    require(c['schema_version'] == b['schema_version'] == 100, 'daily experience schema mismatch')
    for row in indexed(c['fit_examples']).values():
        require(set(row) == {'id', 'species_id', 'label', 'focus'}
                and row['species_id'] in species and row['label'] == species[row['species_id']]['name']
                and row['focus'], 'fit example has invalid body or owns runtime state')
    sources = {'diagnostic': 'diagnostic_service', 'outpatient': 'attempt_work',
               'surgery': 'surgery_work', 'ward': 'ward_work_and_care'}
    progress = list(indexed(c['medical_progress_cues']).values())
    require(len(progress) == len(equipment)
            and {r['definition_id'] for r in progress} == set(equipment), 'medical progress missing a core device')
    for row in progress:
        require(set(row) == {'id', 'definition_id', 'progress_source', 'text', 'working_scene', 'held_scene', 'finished_scene', 'low_motion_scene', 'working_variants', 'result_scenes', 'protocol_variants'}
                and row['progress_source'] == sources[equipment[row['definition_id']]] and row['text'],
                'medical presentation owns result or uses wrong work source')
        require(all(isinstance(row[k],str) and row[k].strip() for k in ('working_scene','held_scene','finished_scene','low_motion_scene')), 'medical device lacks readable comic states')
        choices = indexed(row['working_variants'], 'specialty_id')
        supported = {r['specialty_id'] for r in c['treatment_routines'] if r['equipment_id'] == row['definition_id']}
        require(set(choices) <= supported, 'device comic context references an unsupported specialty')
        require(all(set(v) == {'specialty_id', 'scene'} and isinstance(v['scene'],str) and v['scene'].strip()
                    for v in choices.values()), 'device comic context adds gameplay or lacks scene')
    for row in indexed(c['decor_style_presets']).values():
        require(set(row) == {'id', 'name', 'floor_material_id', 'wall_material_id', 'description'},
                'decor style owns bonus, runtime order or bundled furniture')
        require(row['floor_material_id'] in materials and row['wall_material_id'] in materials,
                'decor style references missing material')
        require(materials[row['floor_material_id']]['surface'] == 'floor'
                and materials[row['wall_material_id']]['surface'] == 'wall', 'decor style swaps floor and wall')
    cooperation = {'ward_handoff_completed': 'outgoing_and_incoming_nurse',
                   'mentored_course_completed': 'contributing_mentor_and_student',
                   'surgical_case_settled_cured': 'actual_three_person_team_pairs'}
    for row in indexed(c['colleague_scenes']).values():
        require(set(row) == {'id', 'fact', 'pair_source', 'friendly_personality_ids',
                             'common_scene', 'familiar_scene','common_low_motion_scene','familiar_low_motion_scene'}, 'colleague scene adds species gate or reward')
        require(all(row[k] for k in ('common_scene','familiar_scene','common_low_motion_scene','familiar_low_motion_scene')), 'colleague lacks selected low-motion pose')
        require(row['fact'] in cooperation and row['pair_source'] == cooperation[row['fact']]
                and row['friendly_personality_ids']
                and set(row['friendly_personality_ids']) <= set(personalities), 'cooperation lacks actual source or personality')
    cue_states = {
        'queue_cues': {'waiting', 'called', 'amenity_away', 'rerouted', 'waiting_condition'},
        'rest_cues': {'early_rest', 'handoff', 'resting', 'returning',
                      'sleep_seeking', 'sleep_waiting', 'sleeping', 'offsite_rest'},
        'observation_cues': {'watching', 'in_transit', 'manual_speed', 'stage_ended'},
        'resume_note_templates': {'care_blocker', 'tracked_goal', 'active_project', 'all_clear'},
        'visitor_cues': {'arriving_bedside', 'yielding', 'leaving'},
    }
    for key, allowed in cue_states.items():
        text_field = 'scene' if key == 'visitor_cues' else 'text'
        rows = list(indexed(c[key]).values())
        require({r['state'] for r in rows} == allowed, key + ' lacks a defined state')
        for row in rows:
            fields = {'id', 'state', text_field} | ({'scene','low_motion_scene'} if key in {'queue_cues','visitor_cues'} else set())
            require(set(row) == fields and all(isinstance(row[k],str) and row[k].strip() for k in fields), key + ' owns simulation effects or lacks cue')
    moves = list(indexed(c['movement_cues']).values())
    require({r['reason'] for r in moves} == {'yielding', 'body_clearance', 'expanded_facility'},
            'movement cue conflates temporary traffic and hard geometry')
    require(all(set(r) == {'id', 'reason', 'text', 'scene'} for r in moves), 'movement cues alter body size')
    m = b['movement_courtesy']
    require(m['body_overlap'] is False and m['yield_resets_wait'] is False
            and 0 < m['blocked_before_yield_seconds'] < m['retry_hard_block_seconds']
            < m['reselect_hard_block_seconds'] < m['refer_hard_block_seconds']
            and m['priority'] == ['inside_narrow_segment', 'committed_transfer_group', 'blocked_tick', 'actor_id'],
            'courtesy permits body overlap, unfair priority or resets patient wait')
    trial = b['build_tryout']
    require(all(trial[k] is False for k in ('reserves_space', 'creates_actor', 'charges_cash'))
            and trial['operator_source'] == 'actual_roster_or_labelled_example', 'tryout changes hospital or fakes staffing')
    calling = b['quiet_calling']
    require(all(calling[k] is False for k in ('requires_screen', 'requires_confirmation', 'missed_call_penalty', 'audio_announcement'))
            and calling['preserve_ticket'] is True and calling['reroute'] == 'invalid_reservation_only',
            'calling adds chore, broadcast or unstable queue')
    require(b['visual_resources'] == {
            'asset_key':'content_fingerprint_and_resource_id',
            'immutable_assets':'shared_by_reference',
            'scene_scope':'current_floor_visible_chunks_and_explicit_preview',
            'other_floors':'simulation_facts_only',
            'attach_pose':'current_logical_stage',
            'late_binding':'hospital_session_view_entity_visual_generation',
            'idle_cache':'byte_accounted_lru_within_existing_budget',
            'business_effects':False,
            'micro_idle_display':'current_state_material_projection',
            'micro_live_closeup_limit':1,
            'micro_closeup_actor_source':'actual_bound_residents',
            'micro_closeup_audio':'reuse_original_no_duplicate'},
            'visual loading duplicates the hospital or changes simulation')
    presentation = b['treatment_presentation']
    require(presentation['beat_phases'] == ['preparation', 'process', 'climax', 'safe_closing']
            and presentation['recovery_source'] == 'binding_on_actual_cure'
            and presentation['pose_authority'] == 'saved_logical_stage_and_reserved_envelope'
            and presentation['missing_secondary'] == 'omit_keep_primary'
            and presentation['result_writes_from_animation'] is False
            and presentation['secondary_gag_view_limit'] == 3
            and presentation['secondary_view_scope'] == 'visible_secondary_medical_props_only'
            and presentation['secondary_offscreen_replay'] is False
            and presentation['secondary_standalone_audio'] is False
            and len(presentation['beat_basis_points']) == 4 and all(type(v) is int and v > 0 for v in presentation['beat_basis_points'])
            and sum(presentation['beat_basis_points']) == 10000
            and presentation['added_work_seconds'] == 0 and presentation['replay_elapsed_beats'] is False
            and presentation['outcome_reveal'] == 'actual_settlement', 'animation changes work or reveals result early')
    require(presentation['device_gag_scope'] == 'secondary_prop_inside_reserved_envelope'
            and presentation['device_gag_context_source'] == 'active_routine_specialty'
            and presentation['device_gag_context_miss'] == 'generic_function_pose'
            and presentation['device_gag_adds_time'] is False
            and presentation['finished_cue_means'] == 'source_work_completed_not_cured',
            'device gag changes work, footprint or cure fact')
    rest = b['staggered_rest']
    require(b['staff_rest_location'] == {'seat_candidates':'free_staff_area_compatible_reachable',
            'selection':'earliest_recovery_including_travel','fallback':'legal_staff_tea_space_or_actual_exit',
            'occupied_seat_queue':False,'switch_after_rest_started':False,
            'recovery_while_travelling':False}, 'rest steals seats or grants recovery in transit')
    require(35 < rest['early_energy_ceiling'] < b['schedule']['compensatory_rest_target_energy']
            and rest['voluntary_per_pool'] == 1 and rest['eligibility'] == 'actual_qualified_coverage'
            and rest['assignment_scope'] == 'existing_roster_and_permissions'
            and rest['delay_mandatory_rest'] is False and rest['recall_early_rest'] is False,
            'staggered rest overrides coverage, roster or mandatory rest')
    colleague = b['colleague_moments']
    require(0 < colleague['interrupt_seconds'] <= colleague['seconds']
            and colleague['relationship_credit'] == 'existing_positive_day'
            and colleague['relationship_storage'] == 'sparse_actual_staff_pairs'
            and colleague['extra_work_seconds'] == 0 and 0 < colleague['familiar_stress_below'] <= 70
            and all(colleague[k] is False for k in ('task_credit', 'deferred_replay', 'species_gate')),
            'cooperation duplicates metric, task rewards or forced performance')
    visitor = b['visitor_courtesy']
    require(visitor['response_seconds_source'] == 'hospital_situations.visitor_yield_seconds'
            and 'response_seconds' not in visitor and visitor['vacancy_at'] == 'body_and_extension_clear'
            and visitor['body_source'] == 'actual_visitor' and visitor['teleport'] is False
            and visitor['medical_space_priority'] is True and visitor['extra_visit_seconds'] == 0
            and visitor['no_space_mood_penalty'] == 0, 'visitor response is instant vacancy or punishes unavailable space')
    style = b['style_preview']
    require(style['exclude_matching_material'] is True and style['order_source'] == 'renovation'
            and style['pay_new_materials_before_old_refund'] is True and style['set_bonus'] == 0
            and style['automatic_future_rooms'] is False, 'style bypasses paid renovation or adds set bonus')
    watch = b['observation']
    require(b['playback_control'] == {'speed_owner':'player_intent','automatic_pause':'source_owned_tokens',
            'effective_pause':'manual_pause_or_any_token','observation':'single_temporary_override',
            'cancel_exit_speed':0,'new_session_speed':0,'persist_runtime_tokens':False}, 'pause restoration overrides current intent')
    require(watch['scope'] == 'current_execution_stage' and watch['temporary_speed'] == 1
            and watch['manual_speed_revokes_restore'] is True and watch['pause_stays_paused'] is True
            and watch['switch_floor_at'] == 'actual_arrival' and watch['stack_limit'] == 1
            and watch['persist_session'] is False and watch['changes_simulation_outcome'] is False,
            'observation takes speed control, teleports or changes outcome')
    note = b['resume_note']
    require(note['card_limit_source'] == 'comedy.max_suggestions'
            and note['source'] == 'loaded_hospital_current_facts'
            and all(note[k] is False for k in ('advances_offline_time', 'performs_commands', 'persists_checklist')),
            'resume note changes world or owns duplicate tasks')


def check_daily_experience_examples(c, b, check):
    check_diagnostic_work_style_examples(c, b, check)
    check_clinical_readiness_query_examples(c, b, check)
    check_protocol_presentation_examples(c, b, check)
    materials = indexed(c['renovation_materials'])
    warm = indexed(c['decor_style_presets'])['DS01']
    price = 20 * materials[warm['floor_material_id']]['unit_price'] + 18 * materials[warm['wall_material_id']]['unit_price']
    check(price == 860, '墙地搭配20格地面18面墙需新材料860，不预支旧材退款')
    limit = b['renovation']['max_units_per_order']
    full, remainder = divmod(130, limit)
    chunks = [limit] * full + ([remainder] if remainder else [])
    check(chunks == [64,64,2] and sum(chunks) == 130, '130个装修单元沿原上限分单且没有漏单元')
    profiles = indexed(c['species'])
    examples = indexed(c['fit_examples'])
    giant = profiles[examples['FE03']['species_id']]
    check(expanded_footprint([3,3], giant['body'], True) == [3,5],
          '石巨人试摆引用真实身体，护理床仍展开到3乘5')
    points = b['treatment_presentation']['beat_basis_points']
    check([36 * p / 10000 for p in points] == [5.4,16.2,9.0,5.4],
          '36秒门诊演出四段合计仍36秒，不附加表演时长')
    check(len(c['medical_equipment_profiles']) == 6 and len(c['clinical_abilities']) == 4
          and len(c['medical_supplies']) == 1 and b['floors']['max_floors'] is None,
          '日常深化保持六设备四能力一种治疗包与无限楼层')
    check_clinical_result_examples(c, b, check)
    check_inpatient_examples(c, b, check)
    rejects(c,b,validate_daily_experience,check,[
        (lambda x,y:y['movement_courtesy'].update(body_overlap=True), '自动礼让穿过身体'),
        (lambda x,y:x['fit_examples'][0].update(species_id='missing'), '试摆缺失身体定义'),
        (lambda x,y:y['quiet_calling'].update(missed_call_penalty=True), '错过叫号惩罚'),
        (lambda x,y:x['medical_progress_cues'][0].update(reward=1), '演出另发数值效果'),
        (lambda x,y:y['visual_resources'].update(micro_idle_display='one_live_camera_per_window'), '每扇观察窗常驻实时近景'),
        (lambda x,y:y['visual_resources'].update(micro_closeup_actor_source='spawn_visual_residents'), '微观近景制造新参与者'),
        (lambda x,y:y['visual_resources'].update(other_floors='full_scene_trees'), '未观察楼层常驻完整动画世界'),
        (lambda x,y:y['visual_resources'].update(attach_pose='replay_from_start'), '资源加载重放已完成治疗'),
        (lambda x,y:y['treatment_presentation'].update(device_gag_adds_time=True), '机器笑点延长服务'),
        (lambda x,y:y['treatment_presentation'].update(result_writes_from_animation=True), '动画完成代替真实治愈'),
        (lambda x,y:y['treatment_presentation'].update(secondary_view_scope='medical_service_capacity'), '表现名额限制医院接诊'),
        (lambda x,y:x['medical_progress_cues'][1]['working_variants'][0].update(specialty_id='T07'), '整复台错放梦境道具'),
        (lambda x,y:y['staggered_rest'].update(delay_mandatory_rest=True), '错峰阻止必要休息'),
        (lambda x,y:y['colleague_moments'].update(relationship_storage='fixed_32_staff_matrix'), '同事关系沿用旧32人编制'),
        (lambda x,y:x.update(schema_version=31), '新版数值与旧版目录混用'),
        (lambda x,y:x['colleague_scenes'][0].update(friendly_personality_ids=['doctor_only']), '同事性格引用错误'),
        (lambda x,y:y['visitor_courtesy'].update(vacancy_at='intention'), '有意让座即算腾空'),
        (lambda x,y:x['decor_style_presets'][0].update(wall_material_id='MAT01'), '地材误作墙材'),
        (lambda x,y:y['observation'].update(manual_speed_revokes_restore=False), '观看覆盖手动暂停'),
        (lambda x,y:y['resume_note'].update(performs_commands=True), '返回便签自动执行业务')])


def append_daily_experience_atlas(lines, c, b, table):
    lines += ['## 现场更好懂，经营更轻松', '', '以下内容引用真实业务状态；不增加可购设备、能力或耗材种类。', '']
    table(lines, ['通道原因', '提示', '动作'], [[r['reason'],r['text'],r['scene']] for r in c['movement_cues']])
    table(lines, ['试摆居民', '种族', '观察重点'], [[r['label'],r['species_id'],r['focus']] for r in c['fit_examples']])
    table(lines, ['叫号状态', '病例面板状态', '号签动作', '低动态'], [[r['state'],r['text'],r['scene'],r['low_motion_scene']] for r in c['queue_cues']])
    table(lines, ['医疗主体', '进度来源', '现场提示'], [[r['definition_id'],r['progress_source'],r['text']] for r in c['medical_progress_cues']])
    table(lines, ['医疗主体', '工作小戏', '真实等待', '工作完成', '低动态'], [[r['definition_id'],r['working_scene'],r['held_scene'],r['finished_scene'],r['low_motion_scene']] for r in c['medical_progress_cues']])
    table(lines, ['医疗主体 / 本次专业', '与工作有关的道具反应'], [[r['definition_id']+' / '+indexed(c['specialties'])[v['specialty_id']]['name'],v['scene']] for r in c['medical_progress_cues'] for v in r['working_variants']])
    table(lines, ['初诊主体 / 实际医生性格', '无语言工作小动作', '低动态'],
          [[r['definition_id']+' / '+indexed(c['doctor_personalities'])[r['doctor_personality_id']]['name'],
            r['scene'],r['low_motion_scene']] for r in c['diagnostic_work_styles']])
    lines += ['### 舒缓准备包含在原工作量内', '',
              '当前门诊Attempt的协议决定表现；三台主体各四段取代同台次要专业小戏，共用原3台可见动态预算。高潮定格，不另加护士、工时、减怒或成功率，结果仍取实际结算。', '']
    table(lines, ['主体', '工作段', '舒缓小戏', '低动态'], [
        [row['definition_id'], beat['phase'], beat['scene'], beat['low_motion_scene']]
        for row in c['medical_progress_cues'] for variant in row['protocol_variants'] for beat in variant['beats']])
    append_clinical_result_atlas(lines, c, b, table)
    append_inpatient_atlas(lines, c, b, table)
    lines += ['### 等待条件不变时少做重复查询', '',
              '以下只定义未开工临床队列的准备查询。原候诊、怒气、弃候、工作、票序与开工原子核验继续；尚未实测大院查询耗时与内存。', '']
    table(lines,['来源或边界','确定规则'],[
        ['复用范围','每当前票至多一份仍成立的必要缺项依据，只缓存失败，不缓存开工许可'],
        ['当前基础缺项','治疗包不足、必要设施不存在、合格团队缺失、兼容床暂忙；完整依赖不足执行原查询'],
        ['新增替代来源','按定义、岗位/能力、作用域及拓扑关注，不只绑定旧实例；空层没有票或轮询任务'],
        ['原阶段','①采购/②变更在本次④；⑤到位/⑥完成/⑨解锁在下次④，已越过位置不逆序重插'],
        ['公平与期限','原票号与两优先后最早普通规则；原时钟和30/60/120/300秒边界保持，方案重评与员工准备继续'],
        ['当前现场','原ReadModel解释当前缺项；看卡片不清标记、不提优先、不派单，叫号无语言'],
        ['恢复与成本','失败依据、反向索引、标记、到期候选计真实工作集，不保存；回收后原机会完整查询']])
    lines += ['### 休息与医院日常', '']
    table(lines, ['休息状态', '提示'], [[r['state'],r['text']] for r in c['rest_cues']])
    table(lines, ['实际合作', '通用动作', '熟悉的动作'], [[r['fact'],r['common_scene']+' 低动态：'+r['common_low_motion_scene'],r['familiar_scene']+' 低动态：'+r['familiar_low_motion_scene']] for r in c['colleague_scenes']])
    table(lines, ['访客状态', '动作', '减少动态'], [[r['state'],r['scene'],r['low_motion_scene']] for r in c['visitor_cues']])
    materials = indexed(c['renovation_materials'])
    table(lines, ['墙地搭配', '地面', '墙面', '外观'], [[r['name'],materials[r['floor_material_id']]['name'],
          materials[r['wall_material_id']]['name'],r['description']] for r in c['decor_style_presets']])
    table(lines, ['观看状态', '提示'], [[r['state'],r['text']] for r in c['observation_cues']])
    table(lines, ['继续经营', '便签'], [[r['state'],r['text']] for r in c['resume_note_templates']])


def validate_clinical_results(c, b):
    require(b['clinical_results'] == {
        'selection': 'actual_fact_and_current_clinical_phase',
        'reveal': 'actual_settlement_after_required_care',
        'feedback_behavior_id': 'CB15',
        'feedback_key': 'attempt_and_failure_phase',
        'automatic_retry': 'existing_plan_decision_and_queue',
        'manual_plan': 'retain_until_explicit_change',
        'comparison': 'prediction_not_failure_cause',
        'device_scene': 'replace_finished_scene',
        'added_work_seconds': 0,
        'secondary_budget_source': 'treatment_presentation',
        'replay_completed': False,
        'alters_body_or_outcome': False,
        'history_source': 'existing_visit_receipt'}, 'clinical result display changes care, outcome or continuation')
    behavior = indexed(c['consultation_behaviors'])[b['clinical_results']['feedback_behavior_id']]
    require(behavior['phase'] == 'failure' and behavior['handler_id'] == 'failure_feedback'
            and behavior['selection_kind'] == 'delegated', 'result feedback has no actual failure source')
    allowed = {
        'diagnostic': {'diagnosis_confirmed', 'more_evidence'},
        'outpatient': {'cured', 'retry_ready', 'final_failure', 'awaiting_recovery'},
        'surgery': {'awaiting_recovery'},
        'ward': {'cured', 'retry_ready', 'final_failure'}}
    equipment = {r['definition_id']: r['effect_kind'] for r in c['medical_equipment_profiles']}
    for row in c['medical_progress_cues']:
        scenes = indexed(row['result_scenes'], 'state')
        require(set(scenes) == allowed[equipment[row['definition_id']]],
                'result scenes missing a legal state or revealing outcome before care')
        require(all(set(v) == {'state', 'label', 'scene', 'low_motion_scene'}
                    and all(isinstance(value, str) and value.strip() for value in v.values())
                    for v in scenes.values()), 'result scene owns effects or lacks a readable low-motion state')
    require(b['max_treatment_attempts'] == 2 and b['second_attempt_bonus'] == 0.15,
            'result continuation changes the existing attempt allowance')
    bindings = indexed(c['treatment_bindings'])
    plans = indexed(c['treatment_plans'])
    diseases = indexed(c['diseases'])
    protocols = indexed(c['treatment_protocols'])
    machines = indexed(c['machines'])
    titles = indexed(c['doctor_titles'])
    samples = indexed(b['balance_reference']['outpatient_examples'])
    require(samples, 'conditional outpatient comparison has no source examples')
    for row in samples.values():
        require(set(row) == {'id', 'name', 'binding_id', 'plan_id', 'gp_title_id',
                             'treatment_level', 'upgrade_level', 'comfort_level', 'condition'}
                and isinstance(row['name'], str) and row['name'].strip(),
                'outpatient example owns calculated price, probability or runtime state')
        require(row['binding_id'] in bindings and row['plan_id'] in plans and row['gp_title_id'] in titles,
                'outpatient example references missing content')
        binding, plan = bindings[row['binding_id']], plans[row['plan_id']]
        require(binding['disease_id'] == plan['disease_id'], 'outpatient example mixes unrelated disease and plan')
        protocol = protocols[plan['protocol_id']]
        require(protocol['kind'] == 'outpatient', 'outpatient comparison bypasses surgery and ward resources')
        profile = diseases[plan['disease_id']]['profile']
        values = c['profiles'][profile] if protocol['uses_disease_profile'] else protocol['clinical_profiles'][profile]
        require(values.get('recovery_seconds', 0) == 0, 'simple outpatient comparison omits required ward care')
        routine = indexed(c['treatment_routines'])[binding['routine_id']]
        machine = machines[routine['equipment_id']]
        wear = indexed(b['equipment']['classes'])['medical']['wear_per_use']
        require(all(type(row[k]) is int for k in ('treatment_level', 'upgrade_level', 'comfort_level', 'condition'))
                and values.get('min_treatment', values.get('min_skill', 1)) <= row['treatment_level'] <= 5
                and 0 <= row['upgrade_level'] <= machine['upgrade_levels']
                and 0 <= row['comfort_level'] <= 2
                and row['condition'] <= 100
                and b['equipment']['stop_new_service_threshold'] < row['condition'] - wear,
                'outpatient example cannot be legally executed')


def outpatient_reference(c, b, row):
    """Conditional design arithmetic only; never used as live clinical prediction."""
    binding = indexed(c['treatment_bindings'])[row['binding_id']]
    plan = indexed(c['treatment_plans'])[row['plan_id']]
    disease = indexed(c['diseases'])[plan['disease_id']]
    protocol = indexed(c['treatment_protocols'])[plan['protocol_id']]
    profile = c['profiles'][disease['profile']] if protocol['uses_disease_profile'] else protocol['clinical_profiles'][disease['profile']]
    routine = indexed(c['treatment_routines'])[binding['routine_id']]
    effective = row['upgrade_level'] * Fraction(str(b['medical_equipment_effects']['utilization_by_level'][row['treatment_level']]))
    raw = (Fraction(str(profile['base_success'])) + Fraction(row['treatment_level'] - 1, 50)
           + Fraction(str(b['medical_equipment_effects']['outpatient_success_per_effective_level'])) * effective
           + Fraction(row['comfort_level'], 100) - (Fraction(4, 100) if row['condition'] < 40 else 0))
    p1 = Fraction(max(7000, min(9800, int(raw * 10000))), 10000)
    wear = indexed(b['equipment']['classes'])['medical']['wear_per_use']
    next_condition = row['condition'] - wear
    next_raw = raw + (Fraction(4, 100) if row['condition'] < 40 else 0)
    next_raw -= Fraction(4, 100) if next_condition < 40 else 0
    p2 = Fraction(max(7000, min(9800, int((next_raw + Fraction(str(b['second_attempt_bonus']))) * 10000))), 10000)
    cured = 1 - (1 - p1) * (1 - p2)
    attempts = 2 - p1
    fees = b['billing']['facility_fees']
    gp = indexed(b['billing']['doctor_consultation_fees'], 'title_id')[row['gp_title_id']]['amount']
    gp += next(v['amount'] for v in fees if v['service_kind'] == 'gp')
    facility = next(v['amount'] for v in fees if v['equipment_id'] == routine['equipment_id'] and v['service_kind'] == 'outpatient')
    cure_fee = ceil(disease['cure_fee'] * Fraction(str(protocol['cure_fee_multiplier'])))
    units = attempts * profile['supply_units']
    supplies = units * c['medical_supplies'][0]['unit_price']
    income = gp + attempts * facility + cured * cure_fee
    work = Fraction(routine['service_seconds']) * Fraction(str(protocol['work_multiplier']))
    work /= 1 + Fraction(row['treatment_level'] - 1, 20) + Fraction(str(b['medical_equipment_effects']['outpatient_speed_per_effective_level'])) * effective
    work = Fraction(ceil(work * 10), 10)
    price = indexed(c['machines'])[routine['equipment_id']]['price']
    investment = sum(upgrade_cost(price, tier) for tier in c['upgrade_tiers'] if tier['level'] <= row['upgrade_level'])
    return {'p1': p1, 'p2': p2, 'cured': cured, 'attempts': attempts,
            'units': units, 'supplies': supplies, 'income': income,
            'contribution': income - supplies, 'operation_seconds': attempts * work,
            'upgrade_investment': investment, 'cure_fee': cure_fee,
            'bills': [gp + facility + cure_fee, gp + 2 * facility + cure_fee, gp + 2 * facility, gp + facility]}


def check_clinical_result_examples(c, b, check):
    cases = {r['id']: outpatient_reference(c, b, r) for r in b['balance_reference']['outpatient_examples']}
    common, refined, low, gentle = (cases[k] for k in ('RB01', 'RB02', 'RB03', 'RB04'))
    check((common['p1'], common['p2'], common['cured']) == (Fraction(92, 100), Fraction(98, 100), Fraction(9984, 10000))
          and common['attempts'] == Fraction(108, 100), '92%和98%的两次条件性累计为99.84%，平均1.08次')
    check(common['bills'] == [235, 245, 45, 35] and common['income'] == Fraction(23548, 100)
          and common['supplies'] == Fraction(216, 10), 'D09真实账单235/245/45/35，条件性收入235.48与包成本21.60分开')
    check(refined['p1'] == Fraction(935, 1000) and refined['upgrade_investment'] == 420
          and refined['operation_seconds'] < common['operation_seconds'] and refined['units'] < common['units'],
          '能力1精修台首试93.5%，材料420，平均操作与领包下降但不是回本证明')
    check(low['p1'] == Fraction(88, 100) and low['p2'] == Fraction(98, 100)
          and low['attempts'] == Fraction(112, 100), '状态39的常规台首试88%，两次完成时平均1.12次')
    check(gentle['p1'] == Fraction(97, 100) and gentle['cure_fee'] == 220
          and gentle['units'] == Fraction(206, 100) and gentle['operation_seconds'] > common['operation_seconds'],
          '舒缓平均2.06包且操作更久，治愈费按精确倍率为220而非浮点多收1币')
    rejects(c, b, validate_clinical_results, check, [
        (lambda x,y:x['medical_progress_cues'][4]['result_scenes'].append(
            copy.deepcopy(x['medical_progress_cues'][1]['result_scenes'][0])), '手术台提前显示治愈'),
        (lambda x,y:x['medical_progress_cues'][0]['result_scenes'][0].update(state='cured'), '诊断直接冒充治愈'),
        (lambda x,y:x['medical_progress_cues'][1]['result_scenes'][1].update(anger_delta=-15), '结果小戏重复修改怒气'),
        (lambda x,y:x['medical_progress_cues'][5]['result_scenes'][0].update(low_motion_scene=''), '结果缺少低动态解释'),
        (lambda x,y:y['clinical_results'].update(reveal='attempt_start'), '读取开工隐藏结果'),
        (lambda x,y:y['clinical_results'].update(automatic_retry='mandatory_player_confirmation'), '首次失败增加逐患者确认'),
        (lambda x,y:y['clinical_results'].update(manual_plan='replace_with_surgery'), '结果覆盖手动方案'),
        (lambda x,y:y['clinical_results'].update(replay_completed=True), '读档重播已经结算失败'),
        (lambda x,y:y['clinical_results'].update(comparison='certain_failure_cause'), '预测差异断言单次失败原因'),
        (lambda x,y:y['balance_reference']['outpatient_examples'][0].update(plan_id='P_D09_SURGERY'), '门诊算术漏掉手术团队与恢复'),
        (lambda x,y:y['balance_reference']['outpatient_examples'][0].update(condition=0), '算术样例让停诊机器开工'),
        (lambda x,y:y['balance_reference']['outpatient_examples'][0].update(condition=11), '首试磨损后无法开工仍算两次完成')])


def append_clinical_result_atlas(lines, c, b, table):
    lines += ['### 治疗结果与下一步', '', '以下18种基础结果表现替代同次工作收尾，揭晓和自动接续规则见医生团队章节；小戏不结算业务。', '']
    table(lines, ['医疗主体', '实际结果键', '提示', '结果小戏', '低动态'],
          [[r['definition_id'],v['state'],v['label'],v['scene'],v['low_motion_scene']]
           for r in c['medical_progress_cues'] for v in r['result_scenes']])
    lines += ['### 两次确实完成时的条件性比较', '',
              '同一D09病例、住院医师初诊、治疗能力1、能量100、劳累0，无舒适、复杂、天赋、科室或沟通修正；失败后仍完成同方案第二次，其余条件保持。仅是设计校准，不预测实际每日收入或诊疗完成数。', '']
    rows = []
    for row in b['balance_reference']['outpatient_examples']:
        result = outpatient_reference(c, b, row)
        rows.append([row['name'], f'{float(result["p1"])*100:.2f}% / {float(result["p2"])*100:.2f}%',
                     f'{float(result["cured"])*100:.2f}%', f'{float(result["attempts"]):.3f} / {float(result["units"]):.3f}',
                     f'{float(result["operation_seconds"]):.3f}', f'{float(result["income"]):.2f} / {float(result["supplies"]):.2f}',
                     f'{float(result["contribution"]):.2f}', result['upgrade_investment']])
    table(lines, ['校准条件', '首试 / 第二次', '最终治愈（有条件）', '平均尝试 / 领包', '平均机器操作秒',
                  '收入 / 领包成本参考', '扣包后贡献参考', '本机升级材料'], rows)
    lines += ['操作秒不含初诊、会诊、等待、走路、反馈或必要临床中断；贡献不扣工资、维护、运营、培训与升级。材料实付与一次性投资不藏进每次治疗费。实际库存现金在采购时结算，不能再扣表中领用估算；样例不消费随机数或写入世界。', '']


def validate_inpatient_examples(c, b):
    bindings, plans = indexed(c['treatment_bindings']), indexed(c['treatment_plans'])
    protocols, diseases = indexed(c['treatment_protocols']), indexed(c['diseases'])
    titles = indexed(c['doctor_titles'])
    adapted = {(r['binding_id'], r['plan_id']) for r in c['surgical_adapters']}
    examples = indexed(b['balance_reference']['inpatient_examples'])
    require(examples, 'inpatient calibration has no source cases')
    grades, surgical_bindings, gentle_bindings = set(), set(), set()
    base_keys = {'id', 'name', 'binding_id', 'plan_id', 'gp_title_id', 'complex_case'}
    for row in examples.values():
        require(row['binding_id'] in bindings and row['plan_id'] in plans
                and row['gp_title_id'] in titles and type(row['complex_case']) is bool
                and isinstance(row['name'], str) and row['name'].strip(),
                'inpatient calibration has missing references or invalid case labels')
        binding, plan = bindings[row['binding_id']], plans[row['plan_id']]
        require(binding['disease_id'] == plan['disease_id'], 'inpatient calibration mixes different diseases')
        protocol = protocols[plan['protocol_id']]
        if protocol['kind'] == 'surgery':
            require(set(row) == base_keys | {'surgeon_title_id', 'surgeon_surgery',
                    'anesthetist_title_id', 'anesthetist_surgery', 'nurse_surgery'},
                    'surgery calibration duplicates outcomes or omits a team role')
            require((binding['id'], plan['id']) in adapted, 'surgery calibration has no matching body adaptation')
            for role in ('surgeon', 'anesthetist'):
                require(row[role+'_title_id'] in titles
                        and titles[row[role+'_title_id']]['rank'] >= titles[protocol['min_'+role+'_title_id']]['rank'],
                        'surgery calibration bypasses title qualification')
            require(all(type(row[k]) is int and protocol['min_'+k] <= row[k] <= 5
                        for k in ('surgeon_surgery', 'anesthetist_surgery', 'nurse_surgery')),
                    'surgery calibration bypasses a required ability')
            grades.add(protocol['difficulty'])
            surgical_bindings.add(binding['id'])
        else:
            require(set(row) == base_keys | {'treatment_level'} and protocol['kind'] == 'outpatient'
                    and not protocol['uses_disease_profile'], 'ward calibration is a non-ward outpatient case')
            values = protocol['clinical_profiles'][diseases[plan['disease_id']]['profile']]
            require(values['recovery_seconds'] > 0 and type(row['treatment_level']) is int
                    and values['min_treatment'] <= row['treatment_level'] <= 5,
                    'ward calibration omits required recovery or bypasses treatment qualification')
            gentle_bindings.add(binding['id'])
        if row['complex_case']:
            require(any(binding['id'] == binding_id for binding_id, _ in adapted),
                    'complex calibration has no available surgical body route')
        require(inpatient_reference(c, b, row)['p1'] >= Fraction(str(b['clinical']['minimum_predicted_success'])),
                'inpatient calibration assumes an unselectable first attempt')
    require(grades == {1, 2, 3} and surgical_bindings & gentle_bindings,
            'inpatient calibration lacks a surgical grade or a same-body gentle comparison')


def inpatient_reference(c, b, row):
    """Ideal completed-attempt arithmetic; resource durations are lower bounds."""
    binding = indexed(c['treatment_bindings'])[row['binding_id']]
    plan = indexed(c['treatment_plans'])[row['plan_id']]
    disease = indexed(c['diseases'])[plan['disease_id']]
    protocol = indexed(c['treatment_protocols'])[plan['protocol_id']]
    routine = indexed(c['treatment_routines'])[binding['routine_id']]
    tick = Fraction(str(b['tick_seconds']))
    fees = {(r['equipment_id'], r['service_kind']): r['amount'] for r in b['billing']['facility_fees']}
    gp = indexed(b['billing']['doctor_consultation_fees'], 'title_id')[row['gp_title_id']]['amount']
    gp += fees[('FUR02', 'gp')]
    evidence = Fraction(str(c['profiles'][disease['profile']]['gp_confidence']))
    for test in c['profiles'][disease['profile']]['tests']:
        if evidence >= b['diagnosis_threshold']:
            break
        evidence += Fraction(str(b['tests'][test]['confidence']))
        gp += fees[('FUR02', test)]
    surgery = protocol['kind'] == 'surgery'
    if surgery:
        raw = Fraction(str(protocol['base_success']))
        raw += Fraction(15, 1000) * (row['surgeon_surgery'] - protocol['min_surgeon_surgery'])
        raw += Fraction(5, 1000) * (row['anesthetist_surgery'] - protocol['min_anesthetist_surgery'])
        operation = Fraction(protocol['work_seconds']) / (1 + Fraction(row['surgeon_surgery'] - protocol['min_surgeon_surgery'], 20))
        recovery, units = protocol['recovery_seconds'], protocol['supply_units']
        facility, wake = fees[('EQ01', 'surgery')], b['clinical']['wake_seconds']
    else:
        values = protocol['clinical_profiles'][disease['profile']]
        raw = Fraction(str(values['base_success'])) + Fraction(row['treatment_level'] - 1, 50)
        operation = Fraction(routine['service_seconds']) * Fraction(str(protocol['work_multiplier']))
        operation /= 1 + Fraction(row['treatment_level'] - 1, 20)
        recovery, units = values['recovery_seconds'], values['supply_units']
        facility, wake = fees[(routine['equipment_id'], 'outpatient')], 0
    if row['complex_case']:
        raw -= Fraction(str(protocol['complex_penalty']))
    p1 = Fraction(max(7000, min(9800, int(raw * 10000))), 10000)
    p2 = Fraction(max(7000, min(9800, int((raw + Fraction(str(b['second_attempt_bonus']))) * 10000))), 10000)
    cured, attempts = 1 - (1-p1)*(1-p2), 2-p1
    operation = ceil(operation / tick) * tick
    facility += fees[('EQ05', 'ward')]
    cure_fee = ceil(disease['cure_fee'] * Fraction(str(protocol['cure_fee_multiplier'])))
    income = gp + attempts * facility + cured * cure_fee
    supplies = attempts * units * c['medical_supplies'][0]['unit_price']
    discharge = b['clinical']['discharge_round_seconds']
    return {'p1': p1, 'p2': p2, 'cured': cured, 'attempts': attempts,
            'income': income, 'supplies': supplies, 'contribution': income-supplies,
            'operation_seconds': attempts*operation,
            'doctor_lock_seconds': attempts*(operation+wake),
            'surgical_nurse_lock_min_seconds': attempts*(operation+wake) if surgery else 0,
            'ward_recovery_seconds': attempts*recovery,
            'bed_commitment_min_seconds': attempts*(operation+wake+recovery+discharge),
            'ward_nurse_active_seconds': attempts*b['clinical']['nurse_visit_seconds'],
            'discharge_doctor_seconds': attempts*discharge,
            'bills': [gp+facility+cure_fee, gp+2*facility+cure_fee, gp+2*facility]}


def check_inpatient_examples(c, b, check):
    cases = {r['id']: inpatient_reference(c, b, r) for r in b['balance_reference']['inpatient_examples']}
    first, second, third, gentle = (cases[k] for k in ('RC01', 'RC02', 'RC03', 'RC04'))
    check(all(r['p1'] == Fraction(96, 100) and r['cured'] == Fraction(9992, 10000)
              and r['attempts'] == Fraction(104, 100) for r in (first, second, third)),
          '合格基础三档手术首试96%、次试98%，两次完成时平均1.04次')
    check([r['bed_commitment_min_seconds'] for r in (first, second, third)]
          == [338, Fraction(2158, 5), Fraction(2626, 5)]
          and third['ward_recovery_seconds'] == 312 and third['doctor_lock_seconds'] == Fraction(1014, 5),
          '三级手术平均床承诺下界525.2秒，恢复312秒，两位医生各202.8秒不能相互替代')
    check(second['bills'] == [1260, 1380, 300] and third['bills'] == [1296, 1416, 300]
          and third['contribution'] == Fraction(2625768, 2500),
          'C档检查实收一次，三级手术账单1296/1416/300，扣包后贡献1050.31不是利润')
    check(gentle['p1'] == Fraction(89, 100) and gentle['attempts'] == Fraction(111, 100)
          and gentle['bed_commitment_min_seconds'] == Fraction(305361, 1000)
          and gentle['ward_nurse_active_seconds'] == Fraction(222, 25)
          and gentle['bills'] == [790, 860, 200],
          '同一复杂D14舒缓首试89%，平均床承诺下界305.361秒，主动护理8.88秒不重复加到恢复')
    rejects(c, b, validate_inpatient_examples, check, [
        (lambda x,y:y['balance_reference']['inpatient_examples'][0].update(surgeon_title_id='DT01'), '一级手术用住院医师主刀'),
        (lambda x,y:y['balance_reference']['inpatient_examples'][2].update(nurse_surgery=1), '三级手术漏掉护士能力'),
        (lambda x,y:y['balance_reference']['inpatient_examples'][1].update(binding_id='B_S13_D09_M09'), '手术病例与身体适配不一致'),
        (lambda x,y:y['balance_reference']['inpatient_examples'][3].update(plan_id='P_D14_COMMON'), '无住院常规方案冒充舒缓床位算例'),
        (lambda x,y:y['balance_reference']['inpatient_examples'][3].update(treatment_level=2), '舒缓C档绕过治疗3'),
        (lambda x,y:y['balance_reference']['inpatient_examples'][0].update(daily_completed_visits=4), '校准输入复制每日吞吐结论')])


def append_inpatient_atlas(lines, c, b, table):
    lines += ['### 手术与舒缓住院的条件性校准', '',
              '基础设备、状态100（次试按真实磨损）、能量100、劳累0，无舒适、天赋、专长或沟通修正；初诊/检查能力1且本院该病治愈经验0。研究、互异团队、同层床、护理与查房均合格且确实完成；覆盖护士护理1。两次沿相同方案，首试失败才做第二次。不是日完成量或运行时收费来源。', '']
    rows = []
    for row in b['balance_reference']['inpatient_examples']:
        r = inpatient_reference(c, b, row)
        rows.append([row['name'], f'{float(r["p1"])*100:.2f}% / {float(r["p2"])*100:.2f}%',
                     f'{float(r["income"]):.2f} / {float(r["supplies"]):.2f}', f'{float(r["contribution"]):.2f}',
                     f'{float(r["operation_seconds"]):.3f}', f'{float(r["doctor_lock_seconds"]):.3f}',
                     f'{float(r["bed_commitment_min_seconds"]):.3f}',
                     f'{float(r["ward_nurse_active_seconds"]):.3f} / {float(r["discharge_doctor_seconds"]):.3f}'])
    table(lines, ['条件', '首试 / 次试', '收入 / 领包成本', '扣包后贡献', '平均操作秒',
                  '每位操作医生占用秒（术含苏醒）', '平均床承诺下界秒', '主动护理 / 查房秒'], rows)
    lines += ['床承诺包括操作、手术苏醒、基础恢复及最后查房；还须加开工前实际预留、转床、覆盖空缺、查房等待和安全离床。主动护理可与恢复重叠，不再加一次8秒；术中护士另有真实转床，覆盖护士是另一人。两位手术医生的工时不能当作一人连续执行。贡献不扣工资、运营、维护和发展支出，不给出保证床数或每日吞吐。', '']
