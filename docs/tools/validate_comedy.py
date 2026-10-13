"""Validate community design contracts and examples; this does not run the game."""
import copy
import math
import re
from pathlib import Path
from fractions import Fraction
from validate_clinical import require, indexed


PRODUCERS = {'queue_claim', 'social_offer', 'idle_prop', 'prop_contact',
             'treatment_result', 'wait_threshold'}
SOURCES = {'incident_resolved': 'incidents',
           'interaction_completed': 'interactions',
           'communication_completed': 'consultation_behaviors'}


def cells(anchor, size):
    return {(anchor[0]+x, anchor[1]+y)
            for x in range(size[0]) for y in range(size[1])}


def minimum_activity_size(activity, fixed_families, required_families):
    """Count distinct required residents plus families they do not yet cover."""
    return max(activity['participants']['min'],
               len(fixed_families) + len(set(required_families)-set(fixed_families)))


def connection_work_ticks_example(connector, b, prefix_ticks, prefix_end_floor, legs, descent_only=False):
    """Conditional route-work arithmetic; no actors, tickets or runtime queue."""
    if not legs:
        return 0
    tick = Fraction(str(b['tick_seconds']))
    def ticks(seconds):
        return math.ceil(Fraction(str(seconds))/tick)
    layer = (b['floors']['emergency_travel_seconds_per_floor'] if descent_only
             else connector['travel_seconds_per_floor'])
    loaded = sum(ticks(connector['boarding_seconds'])+ticks(abs(origin-target)*layer)
                 +ticks(connector['alighting_seconds']) for origin,target in legs)
    if connector['kind'] == 'stairs':
        return prefix_ticks+loaded
    origins = [origin for origin,_ in legs]; targets = [target for _,target in legs]
    first_gap = max(abs(prefix_end_floor-min(origins)),abs(prefix_end_floor-max(origins)))
    later_gap = max(abs(max(targets)-min(origins)),abs(min(targets)-max(origins)))
    return prefix_ticks+loaded+ticks(first_gap*layer)+(len(legs)-1)*ticks(later_gap*layer)


def gather_budget_ticks_example(quoted_ticks, walking_ticks, connection_work_ticks, b):
    """One frozen deadline offset over already valid finite route projections."""
    rule=b['community_activity'];tick=Fraction(str(b['tick_seconds']))
    entry=math.ceil(Fraction(str(rule['entry_interval_seconds']))*(len(quoted_ticks)-1)/tick)
    slack=math.ceil(Fraction(str(rule['gather_slack_seconds']))/tick)
    return max(sum(quoted_ticks),sum(walking_ticks)+sum(connection_work_ticks))+entry+slack


def validate_community_activities(c, b):
    activities = indexed(c['community_activities'])
    cast = indexed(c['community_cast'])
    links = indexed(c['story_activity_links'])
    species = indexed(c['species'])
    families = indexed(c['families'])
    traits = indexed(c['patient_personalities'])
    research = indexed(c['research'])
    furniture = indexed(c['furniture_equipment'], 'definition_id')
    # Stories remain authored in the existing chapter; the links do not own rewards.
    story_text = (Path(__file__).resolve().parents[1]/'design/02-content.md').read_text(encoding='utf-8')
    stories = set(re.findall(r'^\| (ST\d+)\s', story_text, re.M))
    rules = b['community_activity']
    require(rules['venue_policy'] == 'dedicated_nonclinical_area'
            and rules['excluded_space_roles'] == ['clinical_waiting','clinical_work','staff_rest','staff_work','circulation','maintenance_access']
            and rules['seat_use'] == 'activity_only_while_venue_designated'
            and rules['shrink_roster_to_yield'] is False, 'activity occupies clinical seating or circulation')
    require(rules['max_active'] == 1 and rules['admission'] == 'reserve_whole_roster'
            and rules['participant_role'] == 'visitor', 'unsafe community admission')
    require(rules['rng_stream'] == 'community_activity', 'activity random stream not isolated')
    require(rules['entry_interval_seconds'] > 0 and rules['gather_slack_seconds'] > 0
            and 0 < rules['interrupt_seconds'] <= 1, 'invalid activity timing')
    require(rules['gather_deadline'] == {
        'budget':'max_current_quotes_and_roster_work',
        'prefix':'complete_current_connection_work',
        'empty_travel':'endpoint_extrema_per_connection',
        'freeze':'whole_roster_reservation'},
        'gather deadline omits roster transport, uses a partial prefix or keeps extending')
    require(rules['opening_seconds'] > 0 and rules['closing_seconds'] > 0, 'missing activity beats')
    require(rules['effects'] == ['play_gag', 'designated_pair_positive_day', 'story_activity_completed'],
            'activity has undefined rewards or effects')
    require(b['hospital_growth']['ordinary_visitors'] == 'one_per_active_visit_and_real_waiting_position'
            and 'total_actors' not in b['limits'] and 'ordinary_visitors' not in b['limits'],
            'ordinary visitor or actor count wrongly limits growth')

    for person in cast.values():
        require(person['species_id'] in species and person['social_personality_id'] in traits,
                'unknown story resident body or personality')
        require(person['profession_id'] in {'resident', 'priest', 'mage', 'gardener', 'merchant', 'performer'},
                'unknown story resident profession')
        if person['profession_id'] in {'priest', 'mage', 'merchant'}:
            require(species[person['species_id']]['rig'] == 'biped', 'story profession lacks body adapter')
        require(bool(person['name']), 'unnamed story resident')

    indexed([variant for a in activities.values() for variant in a['variations']])
    for activity in activities.values():
        bounds = activity['participants']
        require(set(bounds) == {'min', 'max'}
                and all(type(v) is int for v in bounds.values())
                and 1 <= bounds['min'] <= bounds['max'],
                'invalid activity population range')
        require(set(activity['requires_research']) <= set(research), 'unknown activity unlock')
        selector = activity['participant_filter']
        require(set(selector) <= {'family_id'} and selector.get('family_id') in (None, *families),
                'unknown activity participant filter')
        eligible = [s for s in species.values() if not selector or s['family_id'] == selector['family_id']]
        require(bool(eligible), 'activity has no eligible species')
        require(activity['seating'] in {'standing', 'compatible_activity', 'micro_berth'}, 'unknown activity seating')
        if activity['seating'] == 'micro_berth':
            require(all(s['rig'] == 'micro' for s in eligible) and 'FUR11' in furniture,
                    'nonmicro resident assigned a culture berth')
        for group in activity['required_objects']:
            require(bool(group['any_of']) and len(set(group['any_of'])) == len(group['any_of'])
                    and set(group['any_of']) <= set(furniture), 'unknown or repeated activity facility')
            require(type(group['count']) is int and group['count'] > 0, 'invalid activity facility count')
        duration = activity['duration_seconds']
        require(type(duration) is int and duration > rules['opening_seconds']+rules['closing_seconds'],
                'activity has no middle beat')
        require(len(activity['beats']) == 3 and all(activity['beats']), 'activity lacks complete generic scene')
        require(activity['relationship_credit'] in {'none', 'designated_pair'}, 'unknown activity relationship credit')
        for variation in activity['variations']:
            conditions = variation['conditions']
            require(bool(conditions) and set(conditions) <= {'designated_pair_relationship', 'personality_all'},
                    'unregistered activity condition')
            if 'personality_all' in conditions:
                required_traits = conditions['personality_all']
                require(bool(required_traits) and len(set(required_traits)) == len(required_traits)
                        and set(required_traits) <= set(traits) and len(required_traits) <= bounds['max'],
                        'unknown or impossible activity personality cast')
            if 'designated_pair_relationship' in conditions:
                require(conditions['designated_pair_relationship'] in {'friend', 'rival', 'reconciled'}
                        and activity['relationship_credit'] == 'designated_pair' and bounds['min'] >= 2,
                        'relationship variation has no designated pair')
            require(bool(variation['scene']), 'empty activity variation')

    for link in links.values():
        require(set(link) == {'id', 'story_id', 'activity_id', 'kind', 'required_cast_ids',
                             'required_family_ids', 'designated_pair_cast_ids', 'required_completions',
                             'intro_relationship'}, 'story activity link duplicates unrelated facts')
        require(link['story_id'] in stories and link['activity_id'] in activities, 'unknown story or activity link')
        activity = activities[link['activity_id']]
        for key, definitions in [('required_cast_ids', cast), ('required_family_ids', families)]:
            require(len(link[key]) == len(set(link[key])) and set(link[key]) <= set(definitions),
                    'unknown or repeated required story participant')
        fixed_families = [species[cast[r]['species_id']]['family_id'] for r in link['required_cast_ids']]
        minimum = minimum_activity_size(activity, fixed_families, link['required_family_ids'])
        require(minimum <= activity['participants']['max'], 'story requirements exceed activity maximum')
        family_filter = activity['participant_filter'].get('family_id')
        require(family_filter is None or set(fixed_families+link['required_family_ids']) <= {family_filter},
                'story participant excluded by activity filter')
        pair = link['designated_pair_cast_ids']
        require(not pair or (len(pair) == 2 and len(set(pair)) == 2
                            and set(pair) <= set(link['required_cast_ids'])
                            and activity['relationship_credit'] == 'designated_pair'),
                'story pair is not two required residents')
        require(link['kind'] in {'objective', 'celebration'} and type(link['required_completions']) is int,
                'invalid story activity goal')
        require((link['kind'] == 'objective' and link['required_completions'] > 0)
                or (link['kind'] == 'celebration' and link['required_completions'] == 0),
                'celebration incorrectly gates original reward')
        intro = link['intro_relationship']
        if intro is not None:
            require(len(pair) == 2 and intro['state'] == 'rival' and intro['only_if_absent'] is True
                    and bool(intro['context']), 'story intro overwrites a relationship or lacks context')


def response_variant(row, actor_traits, relationship):
    variants = row.get('response_variants', [])
    specific = [v for v in variants if v['condition'] == 'actor_personality'
                and actor_traits.get(v['actor_role']) == v['personality_id']]
    familiar = [v for v in variants if v['condition'] == 'familiar_relationship'
                and relationship in {'friend','reconciled'}]
    matches = specific or familiar
    return min(matches, key=lambda v:v['id'])['id'] if matches else None


def validate_comedy(c, b):
    validate_community_activities(c, b)
    require(b['comedy']['required_object_walk_distance_cells'] == 3
            and b['comedy']['required_object_scope'] == 'same_floor_connected_public_area'
            and b['comedy']['required_object_sessions'] == 1
            and b['comedy']['gag_spawns_residents'] is False,
            'casual props must be local, exclusive and use existing actors')
    require(b['comedy']['candidate_query'] == {
        'catalog_lookup':'compiled_selector_index',
        'spatial_scope':'same_floor_intersecting_neighbor_buckets',
        'pair_order':'circular_actor_id_then_partner_id',
        'materialization':'one_anchor_neighbors_and_one_pair_scenes',
        'stop_when':'original_start_or_active_budget_full',
        'index_persistence':'rebuild_from_world_and_content'},
        'casual candidate query changes ordering, omits neighbors or materializes the hospital pair matrix')
    interactions = indexed(c['interactions'])
    ref_sets = {'furniture_equipment':set(indexed(c['furniture_equipment'],'definition_id')),
                'accessibility_equipment':set(indexed(c['accessibility_equipment']))}
    for guide in indexed(c['comedy_corner_guides']).values():
        require(set(guide) == {'id','name','object_refs','interaction_ids','layout_hint','ordinary_use'}
                and all(guide[k] for k in ('name','layout_hint','ordinary_use')), 'corner creates bonus or live state')
        object_ids = set()
        for ref in guide['object_refs']:
            require(set(ref) == {'collection','definition_id'} and ref['collection'] in ref_sets
                    and ref['definition_id'] in ref_sets[ref['collection']], 'corner references absent furniture')
            require(ref['definition_id'] not in object_ids, 'duplicate corner object')
            object_ids.add(ref['definition_id'])
        require(guide['interaction_ids'] and len(guide['interaction_ids']) == len(set(guide['interaction_ids']))
                and set(guide['interaction_ids']) <= set(interactions), 'corner references absent or repeated gag')
        require(all(interactions[i]['conditions'].get('required_object_id') in object_ids | {None}
                    for i in guide['interaction_ids']), 'corner omits gag prerequisite')
    traits = indexed(c['patient_personalities'])
    require(b['comedy']['response_variant_policy'] == 'bound_actor_personality_then_familiar_then_base'
            and b['comedy']['response_variant_rng'] is False, 'response variation adds random opportunity')
    variant_ids = set()
    for row in c['interactions']:
        conditions = set()
        for variant in row.get('response_variants', []):
            kind = variant['condition']
            required = {'id','condition','scene','low_motion_scene'}
            if kind == 'actor_personality':
                required |= {'actor_role','personality_id'}
                require(variant.get('actor_role') in {'actor_a','actor_b'}
                        and variant.get('personality_id') in traits, 'response uses wrong actor or trait')
            require(kind in {'actor_personality','familiar_relationship'} and set(variant) == required
                    and all(isinstance(variant.get(k),str) and variant[k].strip()
                            for k in ('scene','low_motion_scene')),
                    'response variant adds effects, unsupported conditions or lacks a readable pose')
            condition = (kind,variant.get('actor_role'),variant.get('personality_id'))
            require(condition not in conditions and variant['id'] not in variant_ids, 'duplicate response condition or id')
            conditions.add(condition);variant_ids.add(variant['id'])
        require(set(row.get('preferred_personality_ids', [])) <= set(traits),
                'unknown comedy personality')
    for row in c['incident_contexts']:
        require(row.get('producer_id') in PRODUCERS, 'context lacks registered producer')

    equipment = indexed(c['accessibility_equipment'])
    for row in equipment.values():
        require(isinstance(row['price'], int) and row['price'] > 0,
                'unpriced accessibility equipment')
        require(row['equipment_class'] in {'comfort', 'utility'}, 'invalid access failure class')
        require(len(row['footprint']) == 2 and all(isinstance(n, int) and 1 <= n <= 4
                                                  for n in row['footprint']), 'invalid access footprint')
        require(row['capacity'] == 1 and 1 <= row['max_clearance_cells'] <= 3
                and math.isfinite(row['max_height_m']) and 0 < row['max_height_m'] <= 7,
                'invalid access capacity')
        require(bool(row['purposes']) and set(row['purposes']) <= {'waiting', 'staff_rest', 'water', 'toilet'},
                'invalid access purpose')
        require(row['initially_available'] is True, 'basic access locked behind research')
        if set(row['purposes']) & {'water', 'toilet'}:
            require(row['service_seconds'] == 8, 'undefined life service time')
        footprint = cells([0, 0], row['footprint'])
        for k in range(1, row['max_clearance_cells']+1):
            operation = cells(row['operation_anchor'], [k, k])
            repair = cells(row['repair_anchor'], [k, k])
            require(not operation & footprint and not repair & footprint,
                    'access operation or repair overlaps device')
            require(not operation & repair, 'access approach and repair overlap')
            if row['support_anchor'] is not None:
                require(cells(row['support_anchor'], [k, k]) <= footprint,
                        'support body exceeds device')
    for species in c['species']:
        k = math.ceil(max(species['body']['width_m'], species['body']['depth_m'])/1.5)
        supported = set()
        for row in equipment.values():
            if k <= row['max_clearance_cells'] and species['body']['height_m'] <= row['max_height_m']:
                supported.update(row['purposes'])
        require(supported == {'waiting', 'staff_rest', 'water', 'toilet'},
                'species lacks compatible life facility')

    responses = indexed(c['doctor_responses'])
    for row in indexed(c['memory_callbacks']).values():
        source = row['source']
        require(source['kind'] in SOURCES, 'unknown memory source kind')
        require(source['definition_id'] in indexed(c[SOURCES[source['kind']]]),
                'missing memory source definition')
        require(set(source['required_response_ids']) <= set(responses), 'unknown memory response')
        require(not source['required_response_ids'] or source['kind'] == 'communication_completed',
                'responses required on noncommunication fact')
        require(source['required_relationship'] in (None, 'reconciled'), 'invalid memory relationship')
        require(row['owner_role'] == 'actor_a' and row['counterpart_kind'] in {'staff', 'resident'},
                'invalid memory identity owner')
        expected_roles = {'staff': {'last_treating_staff', 'responding_doctor'}, 'resident': {'actor_b'}}
        require(row['counterpart_role'] in expected_roles[row['counterpart_kind']], 'memory counterpart type mismatch')
        require(row['min_return_days'] >= 1 and row['next_visit_required']
                and row['public_only'] and row['idle_only'] and row['consume_on_start'],
                'memory can replay without return or consume')
        require(4 <= row['duration_seconds'] <= 8 and 0 < row['interrupt_seconds'] <= 1,
                'callback blocks clinical service')
        require(row['effects'] == ['play_gag'] and bool(row['scene'])
                and bool(row.get('low_motion_scene')), 'callback grants resources or lacks scene')
        if row['counterpart_kind'] == 'staff':
            expected_role = {'incident_resolved':'last_treating_staff',
                             'communication_completed':'responding_doctor'}.get(source['kind'])
            require(row['counterpart_role'] == expected_role, 'callback staff differs from source role')
            if source['kind'] == 'incident_resolved':
                require(indexed(c['incidents'])[source['definition_id']]['conditions'].get('target')
                        == 'last_treating_staff', 'callback incident has no clinical staff target')

    pace = b['comedy']
    require(pace['followup_extra_actor_search'] is False and pace['followup_moves_furniture'] is False
            and pace['followup_added_work_seconds'] == 0, 'incident followup creates another service or actor search')
    require(pace['memory_counterpart_binding'] == 'committed_source_fact', 'memory changes counterpart on return')
    require(0 < pace['max_new_casual_per_scan'] <= b['casual_interaction']['max_active'],
            'invalid casual starts budget')
    require(pace['scene_history_seconds'] > pace['same_scene_zone_cooldown_seconds'],
            'recent-scene preference expires before cooldown ends')
    required_records = math.ceil(pace['scene_history_seconds'] /
                                 b['casual_interaction']['scan_seconds']) * pace['max_new_casual_per_scan']
    require(required_records <= pace['recent_scene_start_limit'] <= 144, 'insufficient or unbounded scene history')
    require(0 < pace['recent_weight'] < pace['seen_weight'] < pace['unseen_weight'], 'no novelty preference')
    require(pace['preferred_personality_weight_multiplier'] > 0, 'invalid personality scene weight')
    require(set(pace['major_window_caps']) == set(b['event_settings'])
            and 0 < pace['major_window_caps']['quiet'] <= pace['major_window_caps']['lively']
            <= pace['major_window_caps']['wild'] <= 7, 'invalid rolling event budgets')
    require(pace['major_window_seconds'] == b['day_seconds'] and pace['major_per_stay_limit'] == 1,
            'invalid major visit budget')
    require(1 <= pace['memories_per_regular'] <= 3 and pace['callback_min_return_days'] >= 1,
            'unbounded or immediate memories')
    require(pace['max_suggestions'] == 3 and pace['schedule_proposal_horizon_seconds'] == b['day_seconds'],
            'invalid management proposal limits')
    require(b['environment']['upgraded_range_cells'] == b['environment']['range_cells']+1
            and b['environment']['upgraded_range_scope'] == 'positive_coverage',
            'environment upgrade range differs')


def check_comedy_examples(c, b, check):
    require(b['comedy']['candidate_query'] == {
        'catalog_lookup':'compiled_selector_index',
        'spatial_scope':'same_floor_intersecting_neighbor_buckets',
        'pair_order':'circular_actor_id_then_partner_id',
        'materialization':'one_anchor_neighbors_and_one_pair_scenes',
        'stop_when':'original_start_or_active_budget_full',
        'index_persistence':'rebuild_from_world_and_content'},
        'casual candidate query changes ordering, omits neighbors or materializes the hospital pair matrix')
    interactions = indexed(c['interactions'])
    check(len(c['comedy_corner_guides']) == 4, '四种生活角落引用已有家具与真实互动条件，无隐藏收益')
    portrait = interactions['I50']
    check(response_variant(portrait, {'actor_a':'PP04','actor_b':'PP10'}, 'friend') == 'I50_P'
          and response_variant(portrait, {'actor_a':'PP01','actor_b':'PP04'}, 'friend') == 'I50_F'
          and response_variant(portrait, {'actor_a':'PP01','actor_b':'PP10'}, 'neutral') is None,
          '合影回应按真正吸血鬼的害羞性格、实际朋友关系与普通结尾依次选择')
    check(interactions['I13']['actor_a']=={'species_any':['S32']}
          and interactions['I13']['actor_b']=={'species_any':['S35']}
          and interactions['I23']['actor_a']=={'species_any':['S57']}
          and interactions['I23']['actor_b']=={'species_any':['S41']},
          '圆杯角色A茶壶/B雪人与宝箱角色A宝箱/B布偶固定，文字顺序不替换绑定')
    check(interactions['I12']['actor_a']=={'species_any':['S18']}
          and interactions['I12']['actor_b']=={'species_any':['S31']}
          and interactions['I70']['actor_a']=={'species_any':['S36']}
          and interactions['I70']['actor_b']=={'species_any':['S71']}
          and interactions['I70']['conditions']=={'required_object_id':'FUR42'},
          '柔光A星星/B台灯与倒影A水滴/B镜子精固定，保留真实FUR42候选条件')
    response_cases = [('I03','actor_b','PP07',8),('I09','actor_b','PP03',8),
                      ('I17','actor_a','PP09',6),('I34','actor_b','PP02',6),
                      ('I44','actor_b','PP04',6),('I48','actor_a','PP07',8),
                      ('I05','actor_a','PP02',6),('I11','actor_a','PP04',6),
                      ('I13','actor_a','PP07',6),('I23','actor_b','PP04',6),
                      ('I12','actor_b','PP03',8),('I70','actor_a','PP10',6)]
    for scene_id,role,trait,seconds in response_cases:
        row = interactions[scene_id]
        actual = {'actor_a':'PP01','actor_b':'PP01'};actual[role] = trait
        wrong = {'actor_a':'PP01','actor_b':'PP01'}
        wrong['actor_b' if role == 'actor_a' else 'actor_a'] = trait
        check(response_variant(row,actual,'friend') == scene_id+'_P'
              and response_variant(row,wrong,'friend') == scene_id+'_F'
              and response_variant(row,wrong,'reconciled') == scene_id+'_F'
              and response_variant(row,wrong,'neutral') is None
              and response_variant(row,wrong,'rival') is None
              and row['duration_seconds'] == seconds,
              scene_id+'回应只取绑定本人的性格，朋友/和解其次，保留原'+str(seconds)+'秒')
    check(sum(len(row.get('response_variants',[])) for row in c['interactions']) == 36,
          '基础包十八场共36种回应均有静态定义，目录记录数量不是扩展上限')
    check(True, '全体型生活设备覆盖所有基础种族的候诊/休息/饮水/如厕容量；未验证实时寻路')
    check(True, '三设备1/2/3格操作与维修区不重叠本体，承托区容纳身体')
    check(b['limits']['regulars']*b['comedy']['memories_per_regular'] == 600, '熟客记忆上界600条')
    check({x['producer_id'] for x in c['incident_contexts']} == PRODUCERS, '24情境均有注册生产者，共6类')
    # Formula examples exercise the documented order; engine parity is future V54.
    base = 36*1.8/(1+.05*(3-1)+.1)*1.21*.95
    actual = math.ceil(max(.8*base, base-4)*10)/10
    check(actual == 58.1, '劳累70、科室3级、升级1、专长与沟通-4的舒缓样例为58.1秒')
    surgery = math.ceil(180/(1+.05)*1.21*.95*10)/10
    check(surgery == 197.1, '主刀高所需外科一级、劳累70与专长的180秒手术为197.1秒')
    check(sum(x['price'] for x in c['accessibility_equipment']) == 1430, '三件生活设备单件组合购置费1430，未计房间装修')
    connectors=indexed(c['vertical_connectors']);lift=connectors['VC02'];stairs=connectors['VC01']
    work100=connection_work_ticks_example(lift,b,0,1,[(1,100)]*4)
    check(work100==7050
          and gather_budget_ticks_example([1420]*4,[400]*4,[work100],b)==9610
          and sum([1420]*4)+60+900==6640,
          '四位100F来宾载客与空返705秒，期限961秒；漏空返的664秒仍不足')
    check(connection_work_ticks_example(lift,b,200,3,[(1,2),(2,4)])==340,
          '完整前缀20秒后从3F接人，异起终层空返用极值，连接负荷34秒')
    check(connection_work_ticks_example(stairs,b,30,1,[(1,2),(2,1)])==80
          and connection_work_ticks_example(lift,b,0,1,[(3,1),(3,1)],descent_only=True)==380,
          '楼梯只计前缀及实际通行，缓降空返和载客均用4秒每层')
    check(gather_budget_ticks_example([80,120,100],[80,120,100],[],b)==1240
          and gather_budget_ticks_example([1000,1000],[10,10],[100],b)==2920,
          '同层无虚构连接工作，原报价更长时仍保留较大预算及原间隔/余量')
    work10000=connection_work_ticks_example(lift,b,0,1,[(1,10000)]*4)
    check(work10000==700050
          and gather_budget_ticks_example([100420]*4,[400]*4,[work10000],b)==702610,
          '万层样例只计算四段层差，期限70261秒；不代表运行时已实现或到场保证')
    activities, links = indexed(c['community_activities']), indexed(c['story_activity_links'])
    photo = activities['CA06']
    families = links['SAL06']['required_family_ids']
    low = minimum_activity_size(photo, [], families)
    check((low, min(photo['participants']['max'], 10)) == (4,10)
          and low == min(photo['participants']['max'], 4)
          and low > min(photo['participants']['max'], 3),
          '合影场地10/4/3位分别得到4…10、仅4与不可提交；只是容量算术')
    check(minimum_activity_size(photo, ['F13','F13','F13'], families) == 6,
          '三位必需人类仍需另补植物、亡灵、微观，最低六人')
    check(all(a['participants']['min'] < a['participants']['max'] for a in activities.values())
          and any(a['participants']['max'] > b['performance_reference']['ordinary_visitors'] for a in activities.values()),
          '五类活动均有随机区间，活动最大值不受八人性能样本截断')
    check(set(activities) == {'CA01','CA02','CA03','CA04','CA06'}
          and {r['id'] for r in c['community_cast']} == {f'CR{i:02}' for i in range(1,9)}
          and {r['id'] for r in c['story_activity_links']} == {'SAL01','SAL02','SAL03','SAL04','SAL06'}
          and {r['id'] for r in c['activity_purposes']} == {'AP01','AP02','AP03','AP04','AP06'}
          and all(r['story_id'] != 'ST09' for r in c['story_activity_links']),
          '基础活动保留稳定ID，病例成果故事无展会用途、庆祝或专属来宾入口')
    check(sum(len(a['variations']) for a in activities.values()) == 15
          and all(len(a['variations']) == 3 for a in activities.values()), '五类活动各三变体，总15种')
    check(104+32+8+16 == b['performance_reference']['total_actors']
          and b['performance_reference']['purpose'] == 'benchmark_not_gameplay_limit',
          '160人只作性能样本，活動整组保留真实独立配位'.replace('活動','活动'))
    species = indexed(c['species'])
    check(species['S09']['family_id'] not in families and species['S13']['family_id'] in families,
          '吸血鬼不能替代ST12的亡灵家族，僵尸可覆盖')
    check(links['SAL03']['required_completions'] == 3 and links['SAL04']['required_completions'] == 1
          and links['SAL06']['required_completions'] == 1
          and links['SAL04']['intro_relationship'] is None,
          '共同园艺、康复交流与四家族合影保留原门槛，ST07不预设旧怨；实际关系结算另验')
    check('CR01' in links['SAL01']['required_cast_ids'] and 'CR01' in links['SAL04']['required_cast_ids']
          and 'CR03' in links['SAL01']['required_cast_ids'] and 'CR03' in links['SAL03']['required_cast_ids'],
          '萨米、向阳跨故事引用相同身份定义；运行时绑定仍待实测')
    cast = indexed(c['community_cast'])
    choir_traits = {cast[r]['social_personality_id'] for r in links['SAL02']['required_cast_ids']}
    choir_variants = {v['id'] for v in activities['CA03']['variations']
                      if set(v['conditions'].get('personality_all', [])) <= choir_traits}
    check(choir_variants == {'CA03_V1','CA03_V2'}, '固定四位合唱成员至少有两种真实匹配变体可选')
    extension = copy.deepcopy(c)
    expanded_activity = copy.deepcopy(photo)
    expanded_activity.update(id='garden:group_portrait', participants={'min': 5, 'max': 20})
    for ordinal, variation in enumerate(expanded_activity['variations']):
        variation['id'] = f'garden:portrait_variant_{ordinal}'
    extension['community_activities'].append(expanded_activity)
    validate_community_activities(extension, b)
    check(True, '20人扩展活动可通过定义校验，不把基础8/16写成活动人数枚举；实际配位另验')
    broken_cases = [
        (lambda x,y:x['memory_callbacks'][0]['source'].update(definition_id='E999'), '回访缺前情定义'),
        (lambda x,y:x['comedy_corner_guides'][0].update(spawns_patients=True), '角落布置凭空召来病人'),
        (lambda x,y:x['comedy_corner_guides'][2]['object_refs'][0].update(definition_id='FUR19'), '观察站缺显微观察窗'),
        (lambda x,y:x['memory_callbacks'][0].update(counterpart_role='responding_doctor'), '道歉回访错绑下一位回应医生'),
        (lambda x,y:x['memory_callbacks'][0].update(low_motion_scene=''), '回访缺低动态表现'),
        (lambda x,y:y['comedy'].update(memory_counterpart_binding='current_visit'), '下次就诊改写前情对方'),
        (lambda x,y:x['memory_callbacks'][0].update(effects=['grant_cash']), '回访暗发经济奖励'),
        (lambda x,y:x['memory_callbacks'][0].update(consume_on_start=False), '回访允许重复开始'),
        (lambda x,y:x['memory_callbacks'][0].update(min_return_days=0), '回访当场递归'),
        (lambda x,y:x['incident_contexts'][0].update(producer_id='parse_prose'), '情境由文案执行'),
        (lambda x,y:x['accessibility_equipment'][0].update(max_clearance_cells=2), '巨型员工没有休息设备'),
        (lambda x,y:x['accessibility_equipment'][1].update(operation_anchor=[0,0]), '操作位重叠设备'),
        (lambda x,y:y['comedy'].update(recent_scene_start_limit=1), '冷却记录过早淘汰'),
        (lambda x,y:y['comedy'].update(scene_history_seconds=120), '最近场景权重永远被冷却覆盖'),
        (lambda x,y:y['comedy']['candidate_query'].update(spatial_scope='current_view_bucket_only'), '视角或分桶边界漏掉真实近邻'),
        (lambda x,y:y['comedy']['candidate_query'].update(materialization='all_hospital_pairs'), '全院居民对矩阵随规模膨胀'),
        (lambda x,y:y['comedy'].update(followup_extra_actor_search=True), '收尾重新召集看客'),
        (lambda x,y:y['comedy'].update(followup_moves_furniture=True), '收尾搬动真实家具'),
        (lambda x,y:y['comedy'].update(followup_added_work_seconds=4), '收尾追加医疗等待'),
        (lambda x,y:y['comedy']['major_window_caps'].update(wild=100), '主要事件预算越界'),
        (lambda x,y:x['interactions'][-1].update(preferred_personality_ids=['PP99']), '场景性格引用未知'),
        (lambda x,y:x['interactions'][-1]['response_variants'][0].update(reward=3), '回应变体另发奖励'),
        (lambda x,y:indexed(x['interactions'])['I03']['response_variants'][0].pop('low_motion_scene'), '互助回应缺少静态定义'),
        (lambda x,y:indexed(x['interactions'])['I50']['response_variants'][0].update(low_motion_scene=''), '已有回应静态为空'),
        (lambda x,y:indexed(x['interactions'])['I09']['response_variants'][0].update(duration_seconds=12), '结尾另加四秒'),
        (lambda x,y:indexed(x['interactions'])['I44']['response_variants'][0].update(personality_id='PP99'), '回应引用未知性格'),
    ]
    for mutate,label in broken_cases:
        broken, other = copy.deepcopy(c), copy.deepcopy(b)
        mutate(broken,other)
        try:
            validate_comedy(broken,other)
        except ValueError:
            check(True, '拒绝喜剧合同负例：'+label)
        else:
            check(False, '未拒绝喜剧合同负例：'+label)
    activity_negatives = [
        (lambda x,y:x['community_activities'][0]['participants'].update(min=9, max=6), '人数区间倒置'),
        (lambda x,y:y['community_activity'].update(venue_policy='clinical_waiting'), '活动占用候诊区域'),
        (lambda x,y:x['community_activities'][1]['required_objects'][0].update(any_of=['FUR99']), '缺必要设施'),
        (lambda x,y:x['community_activities'][0]['variations'][0].update(conditions={'species_conflict': True}), '按种族必然冲突'),
        (lambda x,y:x['community_activities'][0]['variations'][1].update(conditions={'personality_all': ['PP99']}), '未知活动性格'),
        (lambda x,y:x['community_activities'][2].update(participant_filter={'family_id':'F13'}), '人类占培养皿泊位'),
        (lambda x,y:x['community_cast'][0].update(species_id='missing'), '故事角色缺身体'),
        (lambda x,y:x['story_activity_links'][0].update(required_cast_ids=['CR99']), '故事缺固定成员'),
        (lambda x,y:x['story_activity_links'][1].update(required_cast_ids=['CR02']), '牧师误入微观限定合唱'),
        (lambda x,y:x['story_activity_links'][2].update(designated_pair_cast_ids=['CR03','CR03']), '自己与自己和解'),
        (lambda x,y:x['story_activity_links'][2]['intro_relationship'].update(only_if_absent=False), '前情覆盖已有朋友'),
        (lambda x,y:x['story_activity_links'][0].update(required_completions=1), '庆祝追加领奖门槛'),
        (lambda x,y:x['story_activity_links'][0].update(reward_cash=100), '活动复制故事奖励'),
        (lambda x,y:y['community_activity'].update(effects=['grant_cash']), '活动刷钱'),
        (lambda x,y:y['community_activity']['gather_deadline'].update(budget='individual_quotes_only'), '集合遗漏本场空返'),
        (lambda x,y:y['community_activity']['gather_deadline'].update(prefix='first_request_prefix'), '集合截短现有队列'),
        (lambda x,y:y['community_activity']['gather_deadline'].update(empty_travel='none'), '名单空返用零代替'),
        (lambda x,y:y['community_activity']['gather_deadline'].update(freeze='every_progress_tick'), '集合进展无限续期'),
    ]
    for mutate, label in activity_negatives:
        broken, other = copy.deepcopy(c), copy.deepcopy(b)
        mutate(broken, other)
        try:
            validate_community_activities(broken, other)
        except ValueError:
            check(True, '拒绝活动合同负例：'+label)
        else:
            check(False, '未拒绝活动合同负例：'+label)


def append_comedy_atlas(lines, c, b, table):
    lines += ['## 四种生活角落搭配卡', '', '物件价格、研究与使用条件读取原定义；点击只打开建造预览。', '']
    table(lines,['搭配卡','已有物件','可能遇到的互动','空间要点','日常也有用途'],[
        [r['id']+' '+r['name'],'、'.join(v['definition_id'] for v in r['object_refs']),
         '、'.join(r['interaction_ids']),r['layout_hint'],r['ordinary_use']] for r in c['comedy_corner_guides']])
    lines += ['## 同一笑点的不同接法' , '', '性格先看绑定角色，熟悉版本须真实朋友或和解；未匹配时使用原场景。变体共享原时长、场景冷却和结算。', '']
    traits = indexed(c['patient_personalities'])
    table(lines,['互动 / 回应','回应条件','同次画面','低动态'],[
        [r['id']+' '+r['name']+' / '+v['id'],
         (('A（第一位）' if v['actor_role']=='actor_a' else 'B（第二位）')+' / '+traits[v['personality_id']]['name'])
         if v['condition']=='actor_personality' else '双方朋友或已和解',
         v['scene'],v['low_motion_scene']] for r in c['interactions'] for v in r.get('response_variants',[])])

    lines += ['## 六种熟客回访','', '只依据真实已发生来源，公共区空闲、下一医院日及下一次到访，开始即消费；无钱或物件奖励。','']
    table(lines,['回访','来源','同一对方','表现','低动态'],[
        [x['id']+' '+x['name'],x['source']['kind']+' / '+x['source']['definition_id'],x['counterpart_role'],x['scene'],x['low_motion_scene']]
        for x in c['memory_callbacks']])
    lines += ['## 全体型生活设施','']
    table(lines,['设备','占地 / 购置费','用途 / 故障类','容量'],[
        [x['id']+' '+x['name'],'×'.join(map(str,x['footprint']))+' / '+str(x['price']),
         ','.join(x['purposes'])+' / 免维护',f"{x['capacity']}人 / {x['max_clearance_cells']}格 / {x['max_height_m']}米"]
        for x in c['accessibility_equipment']])
    lines += ['设备从开局可买，仍需合法路径和真实展开/操作区；免维护，不加入默认建设报价。',
              '', '场景每对机会25%，同场景同分桶120秒冷却；每次5秒扫描最多新开2组，所有日常共享6组并发。主要事件滚动1800模拟秒（一医院日）预算安静2、热闹4、闹腾7，单次到访最多参与1起。','']
    lines += ['## 五类社区活动','',
              '人数按类型与真实场地随机；完整名单受独立休闲区实际配位约束，不受全院160人或普通访客8人限制。预览不抽签，确认后冻结名单。各活动开场/收尾各4秒，中段占剩余时间；无报名费、门票或独立现金奖励。','']
    seating = {'standing':'兼容公共站位', 'compatible_activity':'独立休闲区每人一处兼容座位', 'micro_berth':'每人一处培养皿泊位FUR11'}
    table(lines,['活动 / 随机人数','开放 / 场地','时长 / 关系','三段演出'],[
        [a['id']+' '+a['name']+f" / {a['participants']['min']}…{a['participants']['max']}人",
         ('、'.join(a['requires_research']) or '开局可安排')+'；'+seating[a['seating']]+'；'+
         ('、'.join('或'.join(g['any_of'])+'×'+str(g['count']) for g in a['required_objects']) or '无需额外物件'),
         str(a['duration_seconds'])+'秒；'+('指定一对，每日最多一次积极关系' if a['relationship_credit']=='designated_pair' else '不增加关系计数'),
         ' → '.join(a['beats'])] for a in c['community_activities']])
    names = {x['id']:x['name'] for x in c['patient_personalities']}
    relationships = {'friend':'朋友', 'rival':'冤家', 'reconciled':'和解'}
    def condition_label(conditions):
        parts = []
        if 'designated_pair_relationship' in conditions:
            parts.append('指定双方为'+relationships[conditions['designated_pair_relationship']])
        if 'personality_all' in conditions:
            parts.append('来宾中包含'+'及'.join(names[p] for p in conditions['personality_all']))
        return '且'.join(parts)
    lines += ['## 十五种活动变体','', '先筛实际条件；匹配指定关系的变体优先，否则在匹配的性格变体中等权选择。未命中时仍有完整通用演出，选定后保存，变体不改变奖励和时长。','']
    table(lines,['变体','真实条件','表现'],[
        [v['id'],condition_label(v['conditions']),v['scene']]
        for a in c['community_activities'] for v in a['variations']])
    species = indexed(c['species'])
    cast = indexed(c['community_cast'])
    professions = {'resident':'居民','gardener':'园艺师','priest':'牧师','mage':'法师','merchant':'商贩','performer':'表演者'}
    lines += ['## 八位活动关联故事居民','', '稳定绑定到同一居民；首次需要时登记，计入200熟客预算，实际入院前不登记到访事实。','']
    table(lines,['身份','种族','职业 / 性格'],[
        [x['id']+' '+x['name'],species[x['species_id']]['name'],professions[x['profession_id']]+' / '+names[x['social_personality_id']]]
        for x in c['community_cast']])
    families = indexed(c['families'])
    lines += ['## 五条故事活动关联','', '故事原有研究、治疗、座位使用、纪念物和领奖规则仍由内容章拥有。这里只定义活动怎样满足对应步骤或开启具名庆祝。','']
    table(lines,['故事 / 活动','关联用途','必需成员或类别','关系对象 / 前情'],[
        [x['story_id']+' / '+x['activity_id'],
         ('接取后完成'+str(x['required_completions'])+'次' if x['kind']=='objective' else '故事完成后的可重复庆祝'),
         '、'.join(cast[r]['name'] for r in x['required_cast_ids']) or '、'.join(families[f]['name'] for f in x['required_family_ids'])+'各至少一位',
         ('与'.join(cast[r]['name'] for r in x['designated_pair_cast_ids']) or '无指定关系对象')+
         ('；仅双方尚无关系记录时采用此前情：'+x['intro_relationship']['context'] if x['intro_relationship'] else '')]
        for x in c['story_activity_links']])
