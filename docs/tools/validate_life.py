"""Check hospital-life content contracts and formula examples, not a game simulation."""
import copy
import math
from fractions import Fraction
from validate_clinical import require, indexed, expanded_footprint


BEHAVIOR_HANDLERS = {
    'offer_seat', 'ask_status', 'observe', 'seek_quiet_seat', 'help_neighbor',
    'request_mediation', 'request_cleaning', 'join_music', 'tell_joke',
    'accept_peace', 'thank_neighbor',
}
BEHAVIOR_CONTEXTS = {
    'seat_needed', 'wait_over_grace', 'idle_near_machine', 'crowded_waiting',
    'neighbor_dropped_ticket', 'queue_dispute', 'nearby_litter', 'music_invitation',
    'idle_near_decoration', 'receptive_neighbor', 'mediation_completed', 'help_received',
}
BEHAVIOR_SOURCES = {
    'seat_needed':'seat_occupancy','wait_over_grace':'queue_ticket',
    'idle_near_machine':'placed_equipment','crowded_waiting':'noise_and_seat_query',
    'neighbor_dropped_ticket':'idle_prop_fact','queue_dispute':'queue_claim_context',
    'nearby_litter':'dirt_patch','music_invitation':'existing_music_offer',
    'idle_near_decoration':'placed_decoration','receptive_neighbor':'accepted_social_offer',
    'mediation_completed':'mediation_completed_fact','help_received':'help_completed_fact',
}
SITUATION_HANDLERS = {
    'registration_error', 'called_while_away', 'same_display_name', 'doctor_unavailable',
    'machine_fear', 'prepare_accessory', 'slow_arrival', 'missing_compatible_seat',
    'toilet_queue', 'water_access_blocked', 'escort_arrival', 'visitor_seat_conflict',
    'lost_property', 'call_missed', 'sign_confusion', 'noise_complaint',
    'diagnosis_handoff', 'bed_race', 'ward_visit', 'quiet_hours',
    'nursing_handoff', 'rounds_wait', 'discharge_feedback', 'worksite_detour',
}
GRATITUDE_HANDLERS = {
    'cleanup_hint', 'floral_aura', 'soft_music', 'repair_hint', 'carry_materials', 'memory_projection',
}
COMMUNICATION_HANDLERS = {
    'communication', 'failure_feedback', 'incident_request', 'gratitude_receipt',
}


def finite(value, minimum, maximum):
    return isinstance(value, (int, float)) and math.isfinite(value) and minimum <= value <= maximum


SEAT_CONTEXT_SOURCES = {
    'quiet': 'actual_noise_query',
    'less_crowded': 'patient_behavior_crowd_query',
    'friendly_neighbor': 'present_idle_friend_in_public_neighbor_query',
    'calm_available': 'actual_calm_chair_and_unused_visit_claim',
    'noise_reduction': 'actual_noise_chair_and_positive_noise_anger_component',
    'clean_ground': 'actual_seat_ground_dirt_query',
    'decor_nearby': 'placed_accessible_decoration_in_environment_range',
    'casual_scene_nearby': 'actual_calm_public_casual_session_in_neighbor_query',
}
SEAT_CONTEXT_LABELS = ['安静', '不拥挤', '朋友在旁', '可用安抚', '隔开噪声', '脚下干净', '装饰可看', '小戏在旁']


def validate_seat_choice(c, b):
    p = b['seat_choice']
    require(p['scope'] == 'clinical_waiting_patient'
            and p['selection_order'] == ['physical_legality', 'travel_window', 'nearby_band', 'preference',
                                         'environment_band', 'personality_score', 'environment', 'travel', 'seat_id']
            and p['criteria'] == SEAT_CONTEXT_SOURCES, 'seat choice loses actual context or selection priority')
    require(p['automatic_travel_seconds_max'] == 30 and p['nearby_detour_seconds'] == 12
            and p['environment_tolerance'] == 10 and p['calm_minimum_anger'] == 35,
            'seat choice changes calibrated travel/environment/context bands')
    require(p['score_scale'] == 100 and p['travel_cost_unit_seconds'] == 10
            and Fraction(str(b['tick_seconds'])) == Fraction(1, 10), 'seat score fixed-point units mismatch')
    require(p['tie_randomness'] is False and p['existing_legal_seat'] == 'keep_until_original_reselection_trigger'
            and p['manual_selection'] == 'physical_legality_and_clinical_priority_only'
            and p['call_interrupt_source'] == 'patient_behavior.interrupt_seconds'
            and p['walking_counts_as_clinical_waiting'] is True, 'seat choice changes call, queue or stable occupancy')
    require(p['entry_scene_gate'] == 'any_listed_actual_context_or_empty' and p['entry_scene_extra_seconds'] == 0
            and p['entry_scene_adds_actor'] is False and p['entry_scene_creates_session'] is False
            and p['choice_changes_relationship'] is False and p['choice_changes_anger'] is False,
            'seating cue creates an extra service, neighbor, reward or delay')
    require(p['candidate_count_cap'] is None and p['runtime_measurement_available'] is False,
            'seat example imposes a count limit or claims runtime verification')
    for trait in c['patient_personalities']:
        s = trait['seating']
        require(set(s) == {'weights', 'travel_penalty_per_10_seconds', 'scene_context_ids', 'entry_scene', 'low_motion_scene'}
                and set(s['weights']) == set(SEAT_CONTEXT_SOURCES), 'personality seating contract incomplete')
        require(all(type(value) is int and 0 <= value <= 8 for value in s['weights'].values())
                and type(s['travel_penalty_per_10_seconds']) is int
                and 0 <= s['travel_penalty_per_10_seconds'] <= 20, 'invalid seating weights/travel cost')
        require(isinstance(s['scene_context_ids'], list) and len(set(s['scene_context_ids'])) == len(s['scene_context_ids'])
                and set(s['scene_context_ids']) <= set(SEAT_CONTEXT_SOURCES), 'seat scene references unknown context')
        require(all(isinstance(s[key], str) and s[key] for key in ('entry_scene', 'low_motion_scene')),
                'seating scene lacks ordinary or low-motion presentation')


def seat_score_example(seating, candidate, b):
    policy = b['seat_choice']
    weighted = sum(value for key, value in seating['weights'].items() if candidate['contexts'][key])
    travel_cost = (policy['score_scale'] * candidate['travel_ticks'] * Fraction(str(b['tick_seconds']))
                   * seating['travel_penalty_per_10_seconds'] / policy['travel_cost_unit_seconds'])
    return policy['score_scale'] * weighted - travel_cost


def seat_choice_example(seating, candidates, b):
    """Conditional arithmetic only; candidates do not establish real geometry or travel."""
    policy = b['seat_choice']; tick = Fraction(str(b['tick_seconds']))
    pool = [x for x in candidates if x['travel_ticks'] * tick <= policy['automatic_travel_seconds_max']]
    if not pool:
        return None
    nearest = min(x['travel_ticks'] for x in pool)
    pool = [x for x in pool if (x['travel_ticks'] - nearest) * tick <= policy['nearby_detour_seconds']]
    preferred = [x for x in pool if x['preference']]
    pool = preferred or pool
    best_environment = max(x['environment'] for x in pool)
    pool = [x for x in pool if x['environment'] >= best_environment - policy['environment_tolerance']]
    return min(pool, key=lambda x: (-seat_score_example(seating, x, b), -x['environment'], x['travel_ticks'], x['id']))['id']


def check_seat_choice_examples(c, b, check):
    traits = indexed(c['patient_personalities'])
    def candidate(sid, ticks, environment, contexts=(), preference=True):
        return {'id': sid, 'travel_ticks': ticks, 'environment': environment, 'preference': preference,
                'contexts': {key: key in contexts for key in SEAT_CONTEXT_SOURCES}}
    a = candidate('A', 20, 80)
    nearby = candidate('B', 80, 78, ('quiet', 'less_crowded'))
    urgent = traits['PP02']['seating']; shy = traits['PP04']['seating']
    check([seat_score_example(urgent, x, b) for x in (a, nearby)] == [-300, -1100]
          and [seat_score_example(shy, x, b) for x in (a, nearby)] == [-100, 600]
          and seat_choice_example(urgent, [a, nearby], b) == 'A'
          and seat_choice_example(shy, [a, nearby], b) == 'B', '同一2/8秒候选：急性子就近，害羞者取安静不拥挤')
    distant = candidate('C', 240, 99, ('quiet', 'less_crowded'))
    check(seat_choice_example(shy, [a, nearby, distant, candidate('D', 310, 100)], b) == 'B'
          and seat_choice_example(shy, [distant], b) == 'C'
          and seat_choice_example(shy, [candidate('D', 310, 100)], b) is None,
          '24秒高环境分不挤入2秒附近带，唯一24秒位仍可选，31秒自动池为空')
    check(seat_choice_example(shy, [candidate('A', 300, 80)], b) == 'A'
          and seat_choice_example(shy, [candidate('A', 301, 80)], b) is None
          and seat_choice_example(shy, [a, candidate('B', 140, 70, ('quiet', 'less_crowded'))], b) == 'B'
          and seat_choice_example(shy, [a, candidate('B', 80, 69, ('quiet', 'less_crowded'))], b) == 'A',
          '30秒、最近加12秒、环境差10的包含边界按定点数执行')
    check(seat_choice_example(shy, [dict(a, preference=False), nearby], b) == 'B'
          and seat_choice_example(shy, [dict(a, preference=False), dict(nearby, preference=False)], b) == 'B',
          '附近原偏好优先，没有满足者仍选合法候选')
    check(seat_choice_example(shy, [dict(a, id='B'), a], b) == 'A'
          and seat_choice_example(shy, [a, dict(a, id='B')], b) == 'A',
          '同分座位按稳定ID，候选枚举顺序不消费随机或改变结果')
    mutations = [
        (lambda x,y:x['patient_personalities'][0]['seating']['weights'].update(quiet=-1), '性格负权重反转事实'),
        (lambda x,y:x['patient_personalities'][0]['seating'].update(travel_penalty_per_10_seconds=True), '路程成本误用布尔值'),
        (lambda x,y:x['patient_personalities'][0]['seating'].update(scene_context_ids=['species_conflict']), '种族标签充当入座情境'),
        (lambda x,y:x['patient_personalities'][0]['seating'].update(low_motion_scene=''), '入座缺少低动态姿态'),
        (lambda x,y:y['seat_choice']['criteria'].update(friendly_neighbor='any_species_neighbor'), '未知居民自动成为朋友'),
        (lambda x,y:y['seat_choice'].update(existing_legal_seat='rescore_each_scan'), '坐定后不停换椅'),
        (lambda x,y:y['seat_choice'].update(walking_counts_as_clinical_waiting=False), '走向椅子清候诊等待'),
        (lambda x,y:y['seat_choice'].update(choice_changes_relationship=True), '选邻座刷关系'),
        (lambda x,y:y['seat_choice'].update(entry_scene_extra_seconds=2), '入座小戏延误叫号'),
        (lambda x,y:y['seat_choice'].update(candidate_count_cap=16), '固定候选数成为规模上限'),
    ]
    for mutate, label in mutations:
        broken, other = copy.deepcopy(c), copy.deepcopy(b); mutate(broken, other)
        try:
            validate_seat_choice(broken, other)
        except ValueError:
            check(True, '选座合同负例被拒绝：' + label)
        else:
            raise ValueError('invalid seating contract accepted: ' + label)


def validate_environment_heatmap(b):
    rule=b['environment']['heatmap_view']
    require(rule == {
        'scope':'current_floor_visible_legal_cells',
        'chunk_cells_source':'spatial_view.chunk_cells',
        'rendering':'shared_chunk_color_and_validity_mask_no_per_cell_nodes',
        'value_source':'original_environment_query_at_cell_for_subject',
        'subject_source':'environment.query_policy.heatmap_subject',
        'subject_key':'current_identity_envelope_and_access_options',
        'refresh_interval_real_ms':200,
        'refresh_scope':'hospital_view_session_across_floor_subject_and_toggle',
        'budget_sources':['spatial_view.view_build_budget_ms_per_frame','spatial_view.view_chunk_starts_per_frame'],
        'budget_additive':False,'priority':'selected_or_hovered_cell_then_visible_chunks',
        'publication':'whole_chunk_with_current_complete_query_stamp',
        'dirty_values':'mask_until_current',
        'invalidation_source':'complete_local_environment_query_dependencies_not_world_tick',
        'states':['current','updating','body_no_fit','outside_owned_floor'],
        'request_key':['hospital_session','view_id','view_generation','floor_id','chunk','subject_identity',
                       'traversal_envelope','query_options','environment_query_stamp','range_version','content_fingerprint'],
        'tooltip':'current_original_cell_query_not_texture_readback',
        'value_encoding':'color_lightness_and_pattern_with_single_legend',
        'legend_source':'existing_environment_thresholds',
        'color_bytes_per_cell':4,'status_bytes_per_cell':1,
        'staging_scope':'one_pending_payload_per_chunk_request',
        'prefetch':False,'snapshot_state':False,'writes_environment':False,'runtime_measurement_available':False},
        'environment heatmap changes world facts, loses identity or has hidden display work')
    require(all(type(rule[key]) is bool for key in
                ('budget_additive','prefetch','snapshot_state','writes_environment','runtime_measurement_available'))
            and all(type(rule[key]) is int for key in
                    ('refresh_interval_real_ms','color_bytes_per_cell','status_bytes_per_cell')),
            'environment heatmap field types are invalid')


def heatmap_raw_payload_example(b):
    width,height=b['limits']['grid_width'],b['limits']['grid_height']
    chunk_width,chunk_height=b['spatial_view']['chunk_cells']
    rule=b['environment']['heatmap_view']
    stride=rule['color_bytes_per_cell']+rule['status_bytes_per_cell']
    return (width*height,math.ceil(width/chunk_width)*math.ceil(height/chunk_height),
            chunk_width*chunk_height*stride,width*height*stride,width*height*stride*2)


def heatmap_legend_example(b):
    return sorted({0,100,b['environment']['comfort2_min_value'],
                   *[row['min_value'] for row in b['environment']['anger_buffer']]})


def heatmap_refresh_due_example(now_ms,last_ms,b):
    return last_ms is None or now_ms-last_ms>=b['environment']['heatmap_view']['refresh_interval_real_ms']


def heatmap_request_matches_example(saved,current,b):
    if not isinstance(saved,dict) or not isinstance(current,dict):
        return False
    return all(key in saved and key in current and saved[key]==current[key]
               for key in b['environment']['heatmap_view']['request_key'])


def heatmap_cell_state_example(legal_floor,body_fits,current,value):
    if not legal_floor:return ('outside_owned_floor',None)
    if not body_fits:return ('body_no_fit',None)
    if not current:return ('updating',None)
    require(type(value) in (int,float) and finite(value,0,100), 'invalid current heatmap score')
    return ('current',value)


def check_environment_heatmap_examples(b,check):
    check(heatmap_raw_payload_example(b)==(9216,36,1280,46080,92160),
          '96×96热图36块的颜色/状态原始负载46080字节，当前加暂存92160字节；不含真实容器或图形开销')
    check(heatmap_legend_example(b)==[0,60,70,80,100],
          '热图图例沿原怒气60/80与舒适70，不另造环境分数或舒适门槛')
    check(heatmap_refresh_due_example(0,None,b)
          and not heatmap_refresh_due_example(199,0,b)
          and heatmap_refresh_due_example(200,0,b)
          and [t for t in range(1000) if t%b['environment']['heatmap_view']['refresh_interval_real_ms']==0]
              ==[0,200,400,600,800],
          '显示门槛每200现实毫秒最多5Hz，切层/开关不重置本会话门槛；模拟时钟不取该值')
    check([heatmap_cell_state_example(*row) for row in
           [(True,True,True,0),(True,True,False,0),(True,False,True,0),(False,True,True,0)]]
          ==[('current',0),('updating',None),('body_no_fit',None),('outside_owned_floor',None)],
          '真实零分、未更新、身体放不下和本层不可建区四态不同，未知/非法没有数值')
    rejected=[]
    for value in (-1,101,float('nan'),float('inf'),True):
        try:heatmap_cell_state_example(True,True,True,value)
        except ValueError:rejected.append(True)
        else:raise ValueError('invalid heatmap score accepted')
    check(len(rejected)==5,'当前热图拒绝越界、非有限或布尔分数，不用零值冒充坏查询')
    saved={'hospital_session':'h1-load1','view_id':'floor-main','view_generation':2,'floor_id':1,
           'chunk':(1,1),'subject_identity':'resident:8','traversal_envelope':(3,3,580),
           'query_options':('public','reservation:none'),'environment_query_stamp':('geometry:4','noise:8','occupancy:5'),
           'range_version':1,'content_fingerprint':'core-1'}
    check(heatmap_request_matches_example(saved,dict(saved),b)
          and not heatmap_request_matches_example(saved,None,b)
          and not heatmap_request_matches_example(saved,{key:value for key,value in saved.items()
                                                         if key!='environment_query_stamp'},b),
          '完整同请求块才发布，缺当前绑定或原环境查询修订不能复用旧颜色')
    differences={'hospital_session':'h2-load1','view_id':'preview','view_generation':3,'floor_id':10000,
                 'subject_identity':'resident:9','traversal_envelope':(1,1,180),
                 'query_options':('staff','reservation:own'),'environment_query_stamp':('geometry:4','noise:9','occupancy:5'),
                 'range_version':2,'content_fingerprint':'core-2'}
    check(all(not heatmap_request_matches_example(saved,dict(saved,**{key:value}),b)
              for key,value in differences.items()),
          '医院/视图/楼层/主体身体/准入/噪声占用/范围/内容变化拒绝迟到块，不混拼成当前色场')
    negatives=[
        (lambda row:row.update(rendering='one_node_and_label_per_cell'), '每格独立节点文字'),
        (lambda row:row.update(value_source='new_visual_beauty_formula'), '热图另造美观度'),
        (lambda row:row.update(subject_key='species_id_only'), '同种族忽略实际症状和准入'),
        (lambda row:row.update(refresh_scope='reset_on_toggle'), '反复开关绕过刷新节流'),
        (lambda row:row.update(budget_additive=True), '热图另分显示预算'),
        (lambda row:row.update(publication='mixed_stale_cells'), '混拼过时单格'),
        (lambda row:row.update(dirty_values='keep_old_as_current'), '旧环境颜色冒充当前'),
        (lambda row:row.update(invalidation_source='every_world_tick'), '每步统一重建热图'),
        (lambda row:row.update(states=['current']), '非法和未知冒充零分'),
        (lambda row:row['request_key'].remove('traversal_envelope'), '绑定忽略实际身体'),
        (lambda row:row.update(tooltip='texture_color_readback'), '旧纹理代替当前单格查询'),
        (lambda row:row.update(prefetch=True), '预取圈计算额外环境场'),
        (lambda row:row.update(snapshot_state=True), '显示场保存成世界事实'),
        (lambda row:row.update(writes_environment=True), '热图写患者环境分'),
        (lambda row:row.update(status_bytes_per_cell=True), '掩码字节数混用布尔')]
    for mutate,label in negatives:
        broken=copy.deepcopy(b);mutate(broken['environment']['heatmap_view'])
        try:validate_environment_heatmap(broken)
        except ValueError:check(True,'环境热图合同负例被拒绝：'+label)
        else:raise ValueError('invalid heatmap contract accepted: '+label)


def validate_life(c, b):
    validate_seat_choice(c, b)
    validate_environment_heatmap(b)
    species = indexed(c['species'])
    traits = indexed(c['patient_personalities'])
    responses = indexed(c['doctor_responses'])
    require(set(responses) == {'listen','checklist','soothe','explain','boundary','nurse_assist'},
            'doctor response must serve professional communication')
    require(sum(p['probability_percent'] for p in traits.values()) == 100, 'social personality probability sum')
    for p in traits.values():
        require(finite(p['probability_percent'], 1, 100) and finite(p['initial_anger'], 0, 100), 'invalid social trait probability/anger')
        require(finite(p['speech_multiplier'], .5, 2), 'invalid communication pace')
        for key in ('anger_growth_multiplier', 'anger_decay_multiplier', 'conflict_initiation_multiplier',
                    'conflict_response_multiplier', 'participation_multiplier'):
            require(finite(p[key], 0, 3), 'invalid personality multiplier')
        require(set(p['response_affinities']) == set(responses), 'patient response affinity coverage')
        require(all(finite(v, .1, 3) for v in p['response_affinities'].values()), 'invalid response affinity')
    for doctor in c['doctor_personalities']:
        require(set(doctor['response_weights']) == set(responses), 'doctor response coverage')
        require(all(finite(v, .1, 3) for v in doctor['response_weights'].values()), 'invalid doctor response weight')
    for response in responses.values():
        require(finite(response['anger_delta'], -15, 0) and finite(response['work_delta_seconds'], -4, 8), 'invalid response effect')
        require(set(response) == {'id','name','anger_delta','work_delta_seconds','scene','low_motion_scene','short_line'}
                and response['scene'] and response['low_motion_scene']
                and isinstance(response['short_line'],str) and 1 <= len(response['short_line']) <= 30, 'professional response lacks body-adapted presentation')
    for behavior in indexed(c['patient_behaviors']).values():
        require(set(behavior['personality_ids']) <= set(traits) and behavior['personality_ids'], 'unknown behavior personality')
        require(behavior['handler'] in BEHAVIOR_HANDLERS and behavior['context'] in BEHAVIOR_CONTEXTS, 'unknown social handler/context')
        require(behavior.get('context_source') == BEHAVIOR_SOURCES[behavior['context']]
                and behavior.get('scene'), 'personality behavior lacks actual context producer or scene')
        require(finite(behavior['probability'], 0, 1) and 0 < behavior['duration_seconds'] <= 8
                and 0 < behavior['interrupt_seconds'] <= 1, 'unbounded social behavior')
    behavior_policy = b['patient_behavior']
    require(behavior_policy['initiator_scope'] == 'patient_or_ordinary_visitor', 'waiting-room behavior assigned to clinical staff')
    require(behavior_policy['reaction_reemits_source'] is False
            and behavior_policy['cleaning_request'] == 'reuse_existing_dirt_job'
            and behavior_policy['queue_ticket_prop_can_lose_ticket'] is False
            and behavior_policy['crowd_radius_cells'] == 3 and behavior_policy['crowded_neighbors_min'] == 4
            and behavior_policy['quiet_seat_improvement'] == 'noise_or_neighbors_without_regression',
            'personality response creates fake tasks, loses tickets or cycles equal seats')

    communication = indexed(b['consultation']['communication_states'])
    require(math.isclose(sum(x['probability'] for x in communication.values()), 1), 'communication probability sum')
    require(all(finite(x['probability'], 0, 1) and finite(x['multiplier'], .5, 3) for x in communication.values()), 'invalid communication state')
    for behavior in indexed(c['consultation_behaviors']).values():
        require(behavior['phase'] in ('gp', 'preparation', 'consult', 'failure', 'waiting', 'discharge'), 'unknown communication phase')
        require(behavior['selection_kind'] in ('sampled', 'derived', 'delegated')
                and behavior['handler_id'] in COMMUNICATION_HANDLERS, 'unknown communication handler')
        require(behavior['once_per_phase'] and finite(behavior['work_delta_seconds'], -4, 8), 'unbounded communication work')
        allowed = set(behavior['allowed_response_ids'])
        require(allowed <= set(responses), 'unknown allowed doctor response')
        if behavior['handler_id'] in ('communication', 'failure_feedback'):
            require(bool(allowed - {'nurse_assist'}), 'communication requires unavailable nurse')
        rule = behavior['eligibility_rule']
        require(len(rule) == 1 and next(iter(rule)) in ('all', 'any'), 'invalid communication rule operator')
        clauses = next(iter(rule.values()))
        require(0 < len(clauses) <= 4, 'unbounded communication rule')
        for clause in clauses:
            require(len(clause) == 1, 'ambiguous communication predicate')
            key, value = next(iter(clause.items()))
            if key == 'communication_state': require(value in communication, 'unknown communication state')
            elif key == 'social_personality_id': require(value in traits, 'unknown communication personality')
            elif key in ('anger_gte', 'anger_lte', 'doctor_fatigue_gte'): require(finite(value, 0, 100), 'invalid emotional threshold')
            elif key == 'doctor_wait_seconds_gte': require(finite(value, 0, 600), 'invalid wait threshold')
            else:
                require(key in ('regular', 'large_machine', 'accessory_obstructs', 'actual_treatment_failed', 'successful_discharge')
                        and value is True, 'unknown communication predicate')
        if behavior['handler_id'] == 'incident_request':
            require(behavior['incident_id'] in indexed(c['incidents']), 'missing delegated incident')
    situations = indexed(c['hospital_situations'])
    for scene in situations.values():
        require(scene['handler'] in SITUATION_HANDLERS and scene['once_per_visit']
                and scene['scene'] and scene['resolution'], 'unknown or unterminated hospital situation')

    require(b['hospital_situations']['accessory_scope']=='detachable_visual_props_only'
            and b['hospital_situations']['accessory_preparation_policy']=='first_real_need_choose_once_no_stacking',
            'accessory preparation removes bodies or repeats the same delay')

    require(b['hospital_situations']['lost_property_staff_role']=='receptionist'
            and b['hospital_situations']['lost_property_requires_idle_staff'] is True
            and b['hospital_situations']['lost_property_requires_existing_prop'] is True
            and b['hospital_situations']['lost_property_requires_cabinet'] is False
            and b['hospital_situations']['lost_property_creates_inventory'] is False
            and b['hospital_situations']['lost_property_interrupt_seconds']==1,
            'lost property scene invents storage, free staff or blocks clinical flow')

    contexts = indexed(c['incident_contexts'])
    for incident in c['incidents']:
        require(incident['required_context_ids'] and set(incident['required_context_ids']) <= set(contexts), 'incident lacks concrete context')
        require(incident['behavior_kind'] in ('conflict', 'mishap', 'outburst')
                and finite(incident['base_probability'], 0, 1), 'invalid incident probability')
        require(set(incident['contexts_any']) <= {'misunderstanding', 'resource_dispute', 'provocation', 'failed_treatment', 'angry_wait'}, 'unknown incident intensity')
    require(all(x['predicate'] for x in contexts.values()), 'empty incident context')

    chairs=indexed(c['chair_variants']); furniture=indexed(c['furniture_equipment'],'definition_id')
    expected={'patient_calm_once','patient_noise_anger_multiplier','staff_rest_stress_rate','staff_rest_energy_rate'}
    require({x['effect'] for x in chairs.values()}==expected
            and len({x['definition_id'] for x in chairs.values()})==len(chairs), 'chair effects missing or duplicated')
    for chair in chairs.values():
        require(chair['definition_id'] in furniture and chair['definition_id'] not in b['equipment']['maintained_definition_ids']
                and chair['fit_profile_id']=='FF05' and chair['capacity']==1 and chair['price']>0
                and chair['scene'] and chair['card'], 'chair bypasses real fit or becomes maintenance burden')
        require(set(chair) == {'id','definition_id','name','footprint','price','capacity','fit_profile_id','effect','parameters','card','scene','effect_scene','ordinary_scene','low_motion_scene'}
                and all(isinstance(chair[k],str) and chair[k].strip() for k in ('effect_scene','ordinary_scene','low_motion_scene')), 'chair presentation lacks actual-effect or ordinary state')
    require(chairs['CS01']['parameters']=={'continuous_seated_seconds':20,'anger_reduction':3}
            and chairs['CS02']['parameters']=={'multiplier':0.5}
            and b['chair_effects']['sleep_credit'] is False
            and b['chair_effects']['stacking']=='one_current_chair', 'chair removes sleep or stacks effects')
    bases=b['staff_work_bases']; facilities=indexed(c['service_equipment'])
    require(bases['preparation_frequency']=='continuous_work_block' and bases['preparation_seconds']==6
            and bases['ward_handoff']=='separate_real_bedside_transfer'
            and bases['ward_nurse_base']=='same_floor_reachable' and bases['emergency_care_preempts']
            and bases['individual_office_assignment'] is False, 'work bases burden individuals or abandon care')
    for key,use in [('doctor_equipment_id','doctor_handoff'),('nurse_equipment_id','nurse_handoff')]:
        eq=facilities[bases[key]]
        require(eq['use']==use and eq['fit_profile_id']=='FF06' and eq['capacity']==1
                and eq['id'] not in b['equipment']['maintained_definition_ids'], 'work base becomes medical device or phantom station')
    cues=list(indexed(c['staff_base_cues']).values())
    require(len(cues)==2 and {row['role'] for row in cues}=={'doctor','nurse'}, 'missing clinical base cue')
    for row in cues:
        require(set(row)=={'id','name','role','equipment_id','scene','empty_scene','low_motion_scene'}
                and row['equipment_id']==bases[row['role']+'_equipment_id']
                and all(isinstance(row[key],str) and row[key].strip()
                        for key in ('name','scene','empty_scene','low_motion_scene')),
                'base cue changes gameplay or invents empty work')
    office=indexed(c['staff_support_rooms'])['doctor_office']
    require(office['required_equipment_ids']==[bases['doctor_equipment_id']] and office['access']=='staff_only', 'doctor office lacks actual shared desk')
    sleep=b['staff_sleep']; beds=indexed(c['service_equipment'])
    require(sleep['applies_to']=='all_staff_roles' and sleep['room_type']=='rest'
            and sleep['sharing']=='automatic_no_personal_assignment'
            and 0<sleep['sleep_seconds']<sleep['early_sleep_after_seconds']<sleep['awake_limit_seconds']
            and sleep['missing_bed_fallback']=='actual_exit_paid_rest', 'staff sleep is optional tea or unsafe disappearance')
    require(sleep['early_requires_free_bed'] is True
            and sleep['early_missing_bed']=='continue_current_schedule'
            and sleep['mandatory_wait_only'] is True
            and sleep['leave_sleep_credit']=='continuous_offsite_rest_for_sleep_seconds'
            and sleep['awake_while_qualified_offsite_rest']=='zero_until_return_journey'
            and sleep['manual_wakeup']=='safe_relocation_only' and sleep['player_meter'] is False,
            'sleep creates unnecessary departure or forgets completed offsite rest')
    require(sleep['access_area']=='real_body_adjacent_to_adapted_bed'
            and bases['operator_area']=='separate_real_body_area'
            and beds['SE04']['access_anchor_policy']=='adjacent_to_adapted_footprint'
            and beds['SE05']['operator_pose']=='seated_or_rig_equivalent'
            and beds['SE06']['operator_pose']=='standing_or_rig_equivalent',
            'staff furniture loses real access or operator pose')
    bed=beds[sleep['bed_definition_id']]
    require(bed['use']=='staff_sleep' and bed['fit_profile_id']=='FF02' and bed['capacity']==1
            and bed['id'] not in b['equipment']['maintained_definition_ids']
            and bed['room_type']=='rest', 'staff sleep uses patient beds or ignores real lying body')
    classes = indexed(b['equipment']['classes'])
    for eq in [*indexed(c['service_equipment']).values(), *indexed(c['staff_recreation_equipment']).values()]:
        require(eq['equipment_class'] in classes and eq['price'] > 0, 'unpaid or unmaintained life equipment')
        require(len(eq['footprint']) == 2 and all(isinstance(v, int) and 1 <= v <= 10 for v in eq['footprint']), 'invalid life equipment footprint')
    for eq in c['staff_recreation_equipment']:
        require(bool(eq.get('scene')) and bool(eq.get('low_motion_scene')), 'recreation lacks readable scene')
        require(eq['equipment_class'] == 'comfort' and 1 <= eq['capacity'] <= 2
                and eq['max_clearance_cells'] == 3 and eq.get('fit_profile_id') == 'FF05' and finite(eq['max_height_m'], .1, 7), 'unsupported recreation capacity')
    for material in indexed(c['renovation_materials']).values():
        require(material['surface'] in ('floor', 'wall') and material['unit_price'] > 0, 'invalid paid surface')
        require(finite(material['environment_value'], 0, b['environment'][material['surface']+'_cap']), 'material exceeds environment cap')
    require(b['renovation']['tool_equipment_id'] in indexed(c['service_equipment']), 'missing renovation tool')
    roles = indexed(b['staff'], 'role')
    require('decorator' in roles and all(x['hire'] > 0 and x['wage_day'] > 0 for key, x in roles.items() if key != 'doctor'), 'unpaid staff role')
    require(0 < b['renovation']['max_units_per_order'] <= 64 and 0 < b['renovation']['max_workers_per_order'] <= 2, 'unbounded renovation')
    require(0 <= b['renovation']['installed_refund'] <= b['renovation']['unused_refund'] <= 1, 'renovation refund exploit')

    effects = indexed(c['gratitude_effects'])
    require(set(effects) <= GRATITUDE_HANDLERS, 'unregistered gratitude handler')
    require('cleanup_hint' in effects and 'tidy_patch' not in effects
            and 'max_cleanup_items' not in b['gratitude']
            and b['gratitude']['cleanup_hint_max_jobs'] == 1
            and b['gratitude']['cleanup_hint_requires_active_cleaner'] is True
            and b['gratitude']['work_help_min_remaining_ticks'] == 1,
            'gratitude deletes dirt or completes staff work')
    require(b['gratitude']['work_help_target_scope']=='current_public_position_near_active_job'
            and b['gratitude']['work_help_range_cells']==4
            and b['gratitude']['work_help_requires_active_worker'] is True
            and b['gratitude']['work_help_adds_movement'] is False
            and b['gratitude']['work_help_target_order']=='distance_then_job_id', 'gratitude invents remote work or delivery detours')
    require(b['gratitude']['area_effect_radius_cells']==4
            and b['gratitude']['area_effect_anchor']=='fixed_public_cell'
            and b['gratitude']['area_effect_propagation']=='same_floor_public_four_neighbors_walls_block'
            and b['gratitude']['area_effect_max_per_receipt']==1
            and b['gratitude']['music_recipient']=='present_patient_with_anger'
            and b['gratitude']['music_relief_stacking']=='max_once_per_anger_sample'
            and b['gratitude']['area_effect_expiry']=='simulated_remaining_ticks', 'temporary gratitude leaks scope, stacks or refreshes on load')
    gifts, abilities = indexed(c['species_gifts']), indexed(c['gratitude_abilities'])
    require(len({g['species_id'] for g in gifts.values()}) == len(gifts)
            and len({a['species_id'] for a in abilities.values()}) == len(abilities), 'duplicate species gratitude definition')
    require({g['species_id'] for g in gifts.values()} == {a['species_id'] for a in abilities.values()}, 'incomplete gratitude pair')
    for gift in gifts.values():
        require(gift['species_id'] in species and gift['sell_value'] == 0
                and gift['max_display_instances'] == 1 and gift['decoration_category'] == 'gratitude', 'invalid gratitude gift')
    for ability in abilities.values():
        require(ability['species_id'] in species and ability['effect_id'] in effects, 'unknown gratitude target/effect')
        require(4 <= ability['duration_seconds'] <= 8 and ability['scene'], 'unbounded gratitude animation')
    for weights in b['ratings']['weights'].values():
        require(sum(weights.values()) == 100 and all(finite(v, 0, 100) for v in weights.values()), 'rating weights do not sum to 100')
    require(set(b['ratings']['weights']) == {'patient','hospital','care_department','doctor','staff'}, 'missing rating owner')
    rating = b['ratings']
    require(0 < rating['minimum_samples'] <= min(rating['case_window_limit'], rating['staff_job_limit'])
            and rating['case_window_limit'] <= 100 and rating['staff_job_limit'] <= 50, 'unbounded rating window')
    require(0 < rating['clinical_prior_success'] <= rating['clinical_prior_total']
            and 0 < rating['job_prior_success'] <= rating['job_prior_total'], 'invalid rating prior')
    anger = b['anger']
    require(anger['thresholds'] == sorted(set(anger['thresholds'])) and 0 < min(anger['thresholds']) < max(anger['thresholds']) <= 100, 'invalid anger thresholds')
    for cause in indexed(anger['causes']).values():
        require(0 <= cause['grace_seconds'] <= 600 and 0 <= cause['per_update'] <= 3 and 0 <= cause['one_shot'] <= 100
                and bool(cause['per_update']) != bool(cause['one_shot']), 'ambiguous anger cause')
    require(b['environment']['query_policy'] == {
        'water_availability':'actual_body_geometry_with_service_queue_allowed',
        'water_check_shared_with_comfort':True,
        'cache_layers':'shared_coverage_then_body_specific_availability',
        'cache_invalidation':'local_relevant_revisions',
        'empty_floors':'no_precomputed_cell_field',
        'heatmap_subject':'selected_actual_body_or_labeled_example',
        'cache_changes_simulation':False}, 'environment query shares the wrong body or stale world facts')
    buffers = b['environment']['anger_buffer']
    require(b['environment']['machine_noise_definition_ids'] == ['M09','M37','M17','EQ01']
            and b['environment']['construction_noise_work_kinds'] == ['renovation_unit','floor_module','machine_upgrade']
            and b['environment']['noise_activity'] == 'effective_work_segment'
            and b['environment']['quiet_uses_all_noise_sources'] is True
            and b['environment']['audio_controls_noise'] is False, 'ambiguous or presentation-driven noise')
    require([x['min_value'] for x in buffers] == [80,60,0]
            and all(0 < x['multiplier'] <= 1 for x in buffers), 'invalid environment buffering')
    require(0 < b['gratitude']['work_help_fraction'] <= .1 and 0 < b['gratitude']['work_help_max_seconds'] <= 10
            and b['gratitude']['per_day_cap'] == 2, 'unbounded gratitude help')
    require(b['guidance']['max_wrong_registrations_per_visit'] == 1
            and 0 < b['guidance']['help_after_seconds'] < b['guidance']['self_service_after_seconds'] <= 60, 'registration loop risk')
    require(b['guidance']['wrong_destination_reason_ids'] == ['intake_scope_excludes_case','equipment_has_no_unlocked_plan']
            and b['guidance']['transient_unavailability_is_misregistration'] is False
            and b['guidance']['equivalent_destination'] == 'accept_current_without_redirection'
            and b['guidance']['recheck_at'] == 'before_correction'
            and b['guidance']['penalty_source'] == 'actual_mismatched_entry_arrival_once'
            and b['guidance']['staff_credit_source'] == 'actual_guidance_work_completed', 'equivalent or temporarily unavailable department treated as wrong destination')
    w = b['wellbeing']
    require(b['staff_relaxation'] == {'priority_stress':90,'window':'existing_rest_or_non_doctor_unassigned_idle',
            'idle_source':'original_dispatcher_no_assignable_work_or_commitment',
            'idle_return':'original_schedule_without_new_rest_target',
            'pressure_alone_stops_work':False,'energy_and_debt_rest_first':True,
            'no_slot':'ordinary_rest_or_current_schedule','quota_source':'wellbeing'},
            'high stress forces unbounded recreation or bypasses safe work')
    require(0 <= w['long_rest_end_fatigue'] < w['fatigue_leave_suggestion'] < w['fatigue_stop_new_work'] <= 100, 'invalid fatigue hysteresis')
    require(w['recreation_join_at'] == 'session_start' and w['recreation_solo_allowed'] is True
            and w['recreation_minimum_zone_cells'] is None, 'recreation adds size gate or changes active session')
    require(w['leave_day_options'] == [1,2,3] and 0 < w['recreation_seconds'] <= w['recreation_cooldown_seconds']
            and w['recreation_max_per_day'] <= 3, 'unbounded leave or recreation')


def check_life_examples(c, b, layout, check):
    check_seat_choice_examples(c, b, check)
    check_environment_heatmap_examples(b,check)
    sleep=b['staff_sleep']
    staff_bed=indexed(c['service_equipment'])['SE04']
    giant=indexed(c['species'])['S59']['body']
    footprint=expanded_footprint(staff_bed['footprint'],giant,True)
    k=math.ceil(max(giant['width_m'],giant['depth_m'])/1.5)
    def area(anchor,size):
        return {(anchor[0]+x,anchor[1]+y) for x in range(size[0]) for y in range(size[1])}
    bed_area=area((0,0),footprint)
    old_access=area(staff_bed['operation_anchor'],(k,k))
    front_access=area((0,footprint[1]),(k,k))
    side_access=area((footprint[0],0),(k,k))
    check(footprint==[3,5] and bool(old_access & bed_area)
          and not front_access & bed_area and not side_access & bed_area,
          '巨人员工床3×5时拒绝旧(0,2)上下床点，改用展开后的真实床边')
    check(not (bed_area | front_access)<=area((0,0),(4,4))
          and (bed_area | side_access)<=area((0,0),(6,6)),
          '4×4空间不能伪装放下巨人睡眠，6×6侧边示例仍须额外检查门与路线')
    chairs=indexed(c['chair_variants'])
    energy_work=90-35
    vigorous_seconds=math.ceil(energy_work/chairs['CS04']['parameters']['per_second']/b['tick_seconds']-1e-8)*b['tick_seconds']
    check(math.isclose(vigorous_seconds,45.9)
          and math.isclose(55*chairs['CS03']['parameters']['per_second'],2.2)
          and math.isclose(55*b['wellbeing']['stress_rest_per_second'],.825),
          '相同35到90能量目标下活力椅45.9秒，55秒阅览减压2.2；样例未计路程与夹限')
    check(sleep['sleep_seconds']==450 and sleep['awake_limit_seconds']==1350
          and sleep['early_sleep_after_seconds']==900
          and min(100,sleep['sleep_seconds']*sleep['energy_per_second'])==100
          and math.isclose(sleep['sleep_seconds']*sleep['doctor_fatigue_per_second'],36)
          and sleep['missing_bed_wait_seconds']<sleep['sleep_seconds'],
          '6医院小时睡眠足以恢复至100能量且最多减36劳累，早睡缺床不能误套45秒离院')
    check(sleep['early_requires_free_bed'] and sleep['mandatory_wait_only']
          and sleep['awake_while_qualified_offsite_rest']=='zero_until_return_journey',
          '提前睡等待不拉走员工，完整院外假期返程前保持清醒计时0')
    due_energy=100-sleep['awake_limit_seconds']*b['wellbeing']['energy_work_per_second']
    check(due_energy<0 and min(100,max(0,due_energy)+sleep['sleep_seconds']*sleep['energy_per_second'])==100,
          '18小时不能假设全程无短休工作：原35/45能量线先触发，睡眠与必要短休分别保留')

    require(len(layout['care_departments']) == 1, 'starter department missing')
    dept = layout['care_departments'][0]
    check(set(dept['room_ids']) <= set(indexed(layout['rooms']))
          and dept['focus_specialty_id'] in indexed(c['specialties']), '起始运营科室引用真实房间与专业')
    core_species = {s['id'] for s in c['species']}
    check({g['species_id'] for g in c['species_gifts']} == core_species
          and {a['species_id'] for a in c['gratitude_abilities']} == core_species, '基础80种族谢礼与回馈完整，扩展不强迫生成缺失礼品')
    # Independent arithmetic examples document the formula limits, not runtime execution.
    def buffered(base, environment):
        multiplier = next(x['multiplier'] for x in b['environment']['anger_buffer'] if environment >= x['min_value'])
        return min(base,b['anger']['continuous_base_cap'])*1.4*multiplier
    check(all(math.isclose(x,y) for x,y in zip([buffered(4,59),buffered(4,60),buffered(4,80)],[4.2,3.15,2.1])), '急性子多原因封顶后环境59/60/80增长4.2/3.15/2.1')
    def gp(expression, speech=1, anger=0, fatigue=0, diagnosis=1, extra=0):
        value=b['gp_seconds']*expression*speech*(1+anger/200)*(1+.003*fatigue)/(1+.05*(diagnosis-1))+extra
        return math.ceil(min(60,max(8,value))*10-1e-8)/10
    check(gp(1)==12 and gp(1.8)==21.6 and gp(2.4,1.4,100,100,1,8)==60
          and gp(1,.9,0,0,5,-4)==8, '同病不同表达工时与8/60秒上下界')
    responses=indexed(c['doctor_responses']);traits=indexed(c['patient_personalities']);doctors=indexed(c['doctor_personalities'])
    check(len(responses)==6 and len(c['consultation_behaviors'])==17
          and set(indexed(c['consultation_behaviors'])['CB08']['allowed_response_ids'])=={'listen','explain','checklist','boundary'},
          '医生六种专业回应，患者比喻由澄清接续，不含讲笑话或笑话失败惩罚')
    allowed=indexed(c['consultation_behaviors'])['CB02']['allowed_response_ids']
    def choice(did):
        return sorted(allowed,key=lambda rid:(-doctors[did]['response_weights'][rid]*traits['PP08']['response_affinities'][rid],rid))[0]
    first,second=choice('DP01'),choice('DP05')
    check(first != second and responses[first]['work_delta_seconds'] != responses[second]['work_delta_seconds'], '同一离题患者遇谨慎/效率医生选不同回应和工时')
    check(max(0,70-b['day_seconds']*b['wellbeing']['fatigue_leave_per_second'])==0,
          '劳累70休假24医院小时夹限后归0，仍按完整在职时间付薪，不产生负劳累')
    max_surgery=max(p['work_seconds'] for p in c['treatment_protocols'] if p['kind']=='surgery')
    check(max_surgery*1.3+b['clinical']['wake_seconds']+b['clinical']['surgery_guard_seconds'] <= b['schedule']['shift_seconds'],
          '最高劳累倍率下长手术加缓冲仍可被600秒完整班容纳，临近班末另查真实窗口')
    check(100*30/(30+20)==60, '只观测结果100与照护0时重新归一化得60分，不把缺项当0分')
    mat=c['renovation_materials'][0]['unit_price']
    check(10*mat-6*mat-4*mat==0 and 4*mat*.8 <= 4*mat, '十格付款完成四格退六格，安装材料回收不增币')
    mutations=[
        (lambda x,y:y['staff_relaxation'].update(window='existing_rest_window'),'娱乐资格遗漏真实待岗非医生'),
        (lambda x,y:y['staff_relaxation'].update(idle_source='empty_staff_task_only'),'空任务误作已完成岗位调度'),
        (lambda x,y:y['staff_relaxation'].update(idle_return='create_rest_until_energy_90'),'待岗娱乐凭空产生短休义务'),
        (lambda x,y:x['staff_base_cues'][0].update(empty_scene=''),'办公室无待办仍伪造病例'),
        (lambda x,y:x['staff_base_cues'][1].update(care_reward=1),'护士工作台演出完成远程护理'),
        (lambda x,y:y['environment']['query_policy'].update(cache_layers='one_value_per_cell_for_all_bodies'),'环境缓存忽略实际身体'),
        (lambda x,y:y['environment']['query_policy'].update(water_availability='currently_empty_only'),'正常饮水排队取消环境覆盖'),
        (lambda x,y:x['species_gifts'][0].update(species_id='missing'),'谢礼引用未知种族'),
        (lambda x,y:x['gratitude_abilities'][0].update(effect_id='free_repair'),'能力绕过已注册处理器'),
        (lambda x,y:y['gratitude'].update(work_help_requires_active_worker=False),'谢礼在没有现场职员时完成工作'),
        (lambda x,y:y['gratitude'].update(work_help_adds_movement=True),'谢礼另派离院居民远程送货'),
        (lambda x,y:y['gratitude'].update(area_effect_anchor='follow_source_actor'),'临时回馈跟随居民跨层漂移'),
        (lambda x,y:y['gratitude'].update(music_relief_stacking='sum_all'),'多份旋律重复安抚'),
        (lambda x,y:x['patient_personalities'][0].update(probability_percent=16),'性格概率和错误'),
        (lambda x,y:y['hospital_situations'].update(accessory_scope='all_body_attachments'),'将身体或必要载具当装饰摘除'),
        (lambda x,y:y['hospital_situations'].update(lost_property_requires_cabinet=True),'装饰柜变成必备寄存服务'),
        (lambda x,y:y['hospital_situations'].update(lost_property_creates_inventory=True),'短误会新增遗失物库存'),
        (lambda x,y:y['hospital_situations'].update(accessory_preparation_policy='stack_both'),'重复收取收纳与沟通时间'),
        (lambda x,y:y['guidance'].update(penalty_source='error_rolled'),'提前纠正仍按错误抽签惩罚'),
        (lambda x,y:y['guidance'].update(staff_credit_source='route_resolved'),'自动路线解决冒充护士绩效'),
        (lambda x,y:x['consultation_behaviors'][0]['allowed_response_ids'].append('insult'),'未定义医生回应'),
        (lambda x,y:y['patient_behavior'].update(initiator_scope='all_staff'),'把候诊性格表演派给医护'),
        (lambda x,y:x['consultation_behaviors'][0].update(allowed_response_ids=['nurse_assist']),'问诊只能等护士无兜底'),
        (lambda x,y:indexed(y['staff'],'role')['decorator'].update(wage_day=0),'装修工未付工资'),
        (lambda x,y:x['renovation_materials'][0].update(environment_value=100),'材料越过环境上限'),
        (lambda x,y:x['staff_recreation_equipment'][0].update(max_clearance_cells=4),'娱乐设备身体容量不受支持'),
        (lambda x,y:y['ratings']['weights']['patient'].update(outcome=31),'评分权重不闭合'),
        (lambda x,y:x['incidents'][0].update(required_context_ids=[]),'冲突仅凭种族无现场条件'),
    ]
    for mutate,label in mutations:
        broken,other=copy.deepcopy(c),copy.deepcopy(b);mutate(broken,other)
        try:validate_life(broken,other)
        except ValueError:check(True,'生活系统负例被拒绝：'+label)
        else:raise ValueError('invalid life contract accepted: '+label)


def append_life_atlas(lines,c,b,table):
    traits=indexed(c['patient_personalities']);responses=indexed(c['doctor_responses'])
    species=indexed(c['species']);gifts={g['species_id']:g for g in c['species_gifts']};effects=indexed(c['gratitude_effects'])
    lines += ['## 病人性格、行为与医患回应','','完整触发条件、评分、怒气与恢复见[医院日常](design/08-hospital-life.md)和[诊室互动与员工休闲](design/09-consultation-wellbeing.md)。','']
    table(lines,['性格','概率','初始怒气','增长 / 平复','冲突发起 / 回应','表达节奏'],[
        [p['name'],str(p['probability_percent'])+'%',p['initial_anger'],f"{p['anger_growth_multiplier']} / {p['anger_decay_multiplier']}",f"{p['conflict_initiation_multiplier']} / {p['conflict_response_multiplier']}",p['speech_multiplier']] for p in traits.values()])
    lines += ['### 就近候诊与十种入座姿态', '',
              '先核验实际身体/空位/路径，再取30秒窗口、最近加12秒、原偏好和环境差10范围；最后比较性格分数。已坐者保持稳定，叫号优先。下面权重只参与选择，不是心情或关系奖励。', '']
    seat_labels = dict(zip(SEAT_CONTEXT_SOURCES, SEAT_CONTEXT_LABELS))
    table(lines, ['性格', '座位偏好权重（仅列正值）', '路程成本 / 10秒'], [
        [p['name'], '、'.join(seat_labels[key] + str(value) for key, value in p['seating']['weights'].items() if value),
         p['seating']['travel_penalty_per_10_seconds']] for p in traits.values()])
    table(lines, ['性格', '当前条件（任一成立）', '入座小戏', '低动态'], [
        [p['name'], '、'.join(seat_labels[key] for key in p['seating']['scene_context_ids']) or '自身卡片与坐姿',
         p['seating']['entry_scene'], p['seating']['low_motion_scene']] for p in traits.values()])
    table(lines,['行为','适用性格','现场条件 / 来源','概率 / 时长','动作'],[
        [p['name'],'、'.join(traits[x]['name'] for x in p['personality_ids']),p['context']+' / '+p['context_source'],f"{p['probability']*100:g}% / {p['duration_seconds']}秒",p['scene']] for p in c['patient_behaviors']])
    table(lines,['医生回应','默认短句','怒气变化','沟通附加工时','实际沟通动作','低动态'],[[x['name'],x['short_line'],x['anger_delta'],str(x['work_delta_seconds'])+'秒',x['scene'],x['low_motion_scene']] for x in responses.values()])
    table(lines,['诊室互动','场景','阶段 / 基础工时','可用回应','流程解释'],[
        [x['name'],x['scene'],x['phase']+' / '+str(x['work_delta_seconds'])+'秒','、'.join(responses[k]['name'] for k in x['allowed_response_ids']) or '调用既有事件/回应/谢礼规则',x['response']] for x in c['consultation_behaviors']])
    lines += ['## 24种医院服务情境','']
    table(lines,['情境','场景','处理与终点'],[[x['name'],x['scene'],x['resolution']] for x in c['hospital_situations']])
    lines += ['## 25类事件的现场条件','','条件来自实际动作与资源事实；物种、性格和概率不能跳过它们。','']
    contexts=indexed(c['incident_contexts'])
    table(lines,['事件','所需现场事实'],[[x['id']+' '+x['name'],'；'.join(contexts[k]['predicate'] for k in x['required_context_ids'])] for x in c['incidents']])
    lines += ['## 付费装修、导诊与员工设施','',
              '员工小憩床用于七岗位真实睡眠；医生办公桌设在共享办公室，护士工作台服务同层护理。三者免维护，展开与操作位仍需真实空间。', '']
    table(lines,['员工支持房间','最小内接矩形','必要物件','使用权限'],[
        [x['name'],'×'.join(map(str,x['min_inner_size'])),'、'.join(x['required_equipment_ids']),'员工专用'] for x in c['staff_support_rooms']])
    table(lines,['上岗整理','设施','实际待办时','无待办时','低动态'],[
        [x['name'],x['equipment_id'],x['scene'],x['empty_scene'],x['low_motion_scene']] for x in c['staff_base_cues']])
    table(lines,['材料','表面','单元价格','环境贡献'],[[x['name'],x['surface'],x['unit_price'],x['environment_value']] for x in c['renovation_materials']])
    cells,chunks,chunk_bytes,raw_bytes,dual_bytes=heatmap_raw_payload_example(b)
    lines += ['### 大平层环境热图的显示合同', '',
              '热图仅读原环境查询，图例标明实际居民或参考体型；未知/非法不写成零分。以下为原始负载算术与显示合同，尚未实测图形资源或大院帧率。', '']
    table(lines,['来源或边界','确定规则'],[
        ['视野与原显示块',f'当前层视野内合法格；最大平层{cells}格/{chunks}块，逐块颜色/状态掩码，无逐格节点/文字'],
        ['原始字节',f'每块{chunk_bytes}、全平层{raw_bytes}、当前加暂存{dual_bytes}字节；容器、上传、网格及实际纹理开销另计'],
        ['刷新与工作',f'每{b["environment"]["heatmap_view"]["refresh_interval_real_ms"]}现实毫秒受理最新需求；共用原2ms/2块启动预算，开关/切层不重置门槛'],
        ['值和图例','原环境查询及身体饮水可用性；图例断点'+ '/'.join(map(str,heatmap_legend_example(b)))+'，颜色、明度与纹理共同区分'],
        ['四态','当前值 / 正在更新 / 固定几何身体放不下 / 本层不可建；只有当前值可显示0…100'],
        ['绑定与详情','当前医院/楼层/主体实际包络/准入/原查询修订匹配才发布；详情查当前单格，不读旧纹理'],
        ['原医院','患者本人采样继续，不取热图；缓存不保存、无预取色场，全部实际字节计原工作集与图形目标']])
    table(lines,['设备','占地','价格','维护','人数 / 身体表现范围'],[
        [x['name'],'×'.join(map(str,x['footprint'])),x['price'],('按'+x['equipment_class']+'维护' if x['id'] in b['equipment']['maintained_definition_ids'] else '免维护'),f"{x['capacity']}人 / {x['max_clearance_cells']}格 / {x['max_height_m']}米" if 'capacity' in x else '真实操作区校验'] for x in c['service_equipment']+c['staff_recreation_equipment']])
    table(lines,['娱乐设备','30秒内的动作','低动态表现'],[
        [x['name'],x['scene'],x['low_motion_scene']] for x in c['staff_recreation_equipment']])
    lines += ['## 四种有不同效果的椅子', '', '全部开局可购、免维护；只有真实占座者在相应状态中生效，同类速率替代而不相加。', '']
    table(lines,['椅子','收起占地 / 价格','购买卡效果','现场动作'],[
        [x['definition_id']+' '+x['name'],'×'.join(map(str,x['footprint']))+' / '+str(x['price']),x['card'],x['scene']] for x in c['chair_variants']])
    chair_details=[]
    for x in c['chair_variants']:
        p=x['parameters'];effect=x['effect']
        if effect=='patient_calm_once':
            detail=f"真实候诊连续坐满{p['continuous_seated_seconds']}秒，怒气减{p['anger_reduction']}，每次就诊一次"
        elif effect=='patient_noise_anger_multiplier':
            detail=f"只把占座患者的设备/施工噪声怒气分量乘{p['multiplier']:g}，其他原因不变"
        elif effect=='staff_rest_stress_rate':
            detail=f"员工清醒短休每秒减{p['per_second']:g}压力，替代普通短休的{b['wellbeing']['stress_rest_per_second']:g}"
        else:
            detail=f"员工清醒短休每秒恢复{p['per_second']:g}能量，不代替必要睡眠"
        chair_details.append([x['name'],detail])
    table(lines,['椅子','展开后的具体效果'],chair_details)
    table(lines,['椅子','实际生效','普通使用','低动态'],[[x['name'],x['effect_scene'],x['ordinary_scene'],x['low_motion_scene']] for x in c['chair_variants']])
    lines += ['## 五类评分权重','']
    labels={'patient':'病人本次体验','hospital':'医院','care_department':'运营科室','doctor':'医生职工评价','staff':'其他职工'}
    table(lines,['对象','分项权重'],[[labels[k],'、'.join(f'{part} {value}%' for part,value in weights.items())] for k,weights in b['ratings']['weights'].items()])
    lines += ['## 80种族的土特产与能力回馈','','每种一个纪念物和一种表现；效果有界、不能出售或代替付薪工人。','']
    table(lines,['种族','土特产','有限帮助','回馈演出'],[
        [species[x['species_id']]['name'],gifts[x['species_id']]['name'],effects[x['effect_id']]['name'],x['scene']] for x in c['gratitude_abilities']])
