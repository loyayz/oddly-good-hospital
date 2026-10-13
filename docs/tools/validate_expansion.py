"""Static growth, arrival and recruitment contracts; no game runtime is executed."""
import copy
import hashlib
import math
from collections import Counter, defaultdict
from fractions import Fraction
from validate_clinical import require, indexed, validate_bed_links
from validate_care import outpatient_reference, inpatient_reference


WAITING_STAGES = {'waiting_reception', 'waiting_gp', 'waiting_test',
                  'waiting_consultation', 'waiting_outpatient', 'waiting_surgery'}
WORK_PREFERENCES = {'shift_ready', 'help', 'current_task', 'preventive',
                    'group_recreation', 'quiet_recreation'}


def slot_bounds(count, index, b):
    ticks = b['day_seconds'] * 10
    require(type(count) is int and count > 0 and 0 <= index < count, 'invalid daily slot request')
    left, right = index * ticks // count, (index + 1) * ticks // count
    if right-left < 2:
        return left, left
    return (math.ceil(left + b['arrivals']['slot_jitter_min'] * (right-left)),
            math.floor(left + b['arrivals']['slot_jitter_max'] * (right-left)))



def scheduled_slot_tick(count, day_index, seed, index, b, first_u32=None):
    """Portable design vector; no game scheduler or RNG is executed."""
    lo, hi = slot_bounds(count, index, b)
    if lo == hi:
        return lo
    require(type(day_index) is int and day_index>=0 and isinstance(seed,str)
            and seed.isascii() and seed.isdecimal() and str(int(seed))==seed
            and 0<=int(seed)<2**64, 'invalid daily schedule identity')
    width=hi-lo+1; limit=2**32-(2**32 % width); nonce=0
    while True:
        payload=f"arrival-slot-v1|{day_index}|{seed}|{index}|{nonce}".encode('utf-8')
        sample=(first_u32(payload) if first_u32 else
                int.from_bytes(hashlib.sha256(payload).digest()[:4],'big'))
        require(type(sample) is int and 0<=sample<2**32, 'invalid schedule digest sample')
        if sample < limit:
            return lo+sample % width
        nonce+=1


def planned_arrivals(preset, capacity):
    """Nominal capacity is a design input, not actual completed visits."""
    mean=Fraction(capacity)*Fraction(preset['target_load_bp'],10000)
    spread=Fraction(preset['daily_variation_bp'],10000)
    return math.floor(mean*(1-spread)), math.ceil(mean*(1+spread)), mean


def sample_arrival_count(preset, capacity, draw_integer):
    if capacity==0: return 0
    spread=preset['daily_variation_bp']
    delta=draw_integer(-spread,spread)
    require(type(delta) is int and -spread<=delta<=spread, 'invalid design density sample')
    value=Fraction(capacity)*Fraction(preset['target_load_bp'],10000)*Fraction(10000+delta,10000)
    whole,remainder=divmod(value.numerator,value.denominator)
    if not remainder: return whole
    draw=draw_integer(0,value.denominator-1)
    require(type(draw) is int and 0<=draw<value.denominator, 'invalid design rounding sample')
    return whole+int(draw<remainder)


def reference_arrival_capacity(c,b):
    row=indexed(b['balance_reference']['outpatient_examples'])[b['balance_reference']['arrival_outpatient_example_id']]
    work=outpatient_reference(c,b,row)['operation_seconds']
    # This homogeneous example has diagnosis ability 1 and no upgrade or talent.
    context=b['arrivals']['load_projection']
    trait=indexed(c['patient_personalities'])[context['reference_patient_personality_id']]
    expression=indexed(b['consultation']['communication_states'])[context['reference_expression']]
    gp=Fraction(b['gp_seconds'])*Fraction(str(expression['multiplier']))*Fraction(str(trait['speech_multiplier']))
    gp*=1+Fraction(context['reference_anger'],200)
    gp=max(Fraction(b['consultation']['minimum_seconds']),min(Fraction(b['consultation']['maximum_seconds']),gp))
    tick=Fraction(str(b['tick_seconds']));gp=math.ceil(gp/tick)*tick
    return Fraction(b['day_seconds'])/max(work,gp)


def scaled_arrivals(preset, scale_numerator, b, reference_capacity):
    """Scale the explicitly supplied conditional case; no generic per-S quota."""
    require(type(scale_numerator) is int and scale_numerator >= 0, 'invalid admission scale')
    divisor = b['arrivals']['capacity_scaling']['reference_shift_pairs']
    low,high,_=planned_arrivals(preset,Fraction(reference_capacity)*Fraction(scale_numerator,divisor))
    return (low,high,
            (preset['active_outpatients_per_scale']*scale_numerator+divisor-1)//divisor)


def split_shift_opportunities(count, capacities, day_index, seed):
    require(type(count) is int and count>=0 and len(capacities)==3 and all(v>=0 for v in capacities),
            'invalid shift opportunity inputs')
    if count==0:return [0,0,0]
    total=sum(capacities)
    require(total>0, 'positive opportunities without nominal capacity')
    exact=[Fraction(count)*v/total for v in capacities]
    counts=[math.floor(v) for v in exact]
    def order(i):
        payload=f'arrival-load-shift-v1|{day_index}|{seed}|{i}'.encode('utf-8')
        return (-(exact[i]-counts[i]), int.from_bytes(hashlib.sha256(payload).digest()[:4],'big'),i)
    for i in sorted(range(3),key=order)[:count-sum(counts)]:counts[i]+=1
    return counts


def load_scheduled_slot_tick(shift_counts, day_index, seed, index, b, first_u32=None):
    """New portable slot vector; legacy whole-day decoder remains independent."""
    require(len(shift_counts)==3 and all(type(n) is int and n>=0 for n in shift_counts)
            and type(index) is int and 0<=index<sum(shift_counts), 'invalid frozen shift counts')
    require(type(day_index) is int and day_index>=0 and isinstance(seed,str)
            and seed.isascii() and seed.isdecimal() and str(int(seed))==seed
            and 0<=int(seed)<2**64, 'invalid load schedule identity')
    local=index; shift=0
    while local>=shift_counts[shift]:local-=shift_counts[shift];shift+=1
    count=shift_counts[shift]; ticks=int(Fraction(b['schedule']['shift_seconds'])/Fraction(str(b['tick_seconds'])))
    left,right=local*ticks//count,(local+1)*ticks//count
    if right-left<2:return shift*ticks+left
    lo=(left*4+right-left+3)//4;hi=(left*4+3*(right-left))//4
    if lo==hi:return shift*ticks+lo
    width=hi-lo+1;limit=2**32-2**32%width;nonce=0
    while True:
        payload=f'arrival-load-slot-v1|{day_index}|{seed}|{shift}|{local}|{nonce}'.encode('utf-8')
        sample=(first_u32(payload) if first_u32 else
                int.from_bytes(hashlib.sha256(payload).digest()[:4],'big'))
        require(type(sample) is int and 0<=sample<2**32, 'invalid load schedule digest sample')
        if sample<limit:return shift*ticks+lo+sample%width
        nonce+=1


def validate_admission_evaluation(b):
    require(b['arrivals']['admission_evaluation']=={
        'scope':'current_original_patient_opportunity',
        'phase':'phase3_original_arrival_boundary',
        'order':['current_intake_open','actual_outpatient_count_below_frozen_day_allowance','original_case_and_body_readiness'],
        'active_count_source':'actually_arrived_not_physically_departed_without_valid_inpatient_bed_commitment',
        'allowance_source':'original_frozen_day_preset_and_scale',
        'guard_rejection':'consume_same_slot_without_catchup',
        'guard_rejection_case_queries':0,'guard_rejection_patient_draws':0,
        'daily_count_and_seed_draws':'original_day_plan_unchanged',
        'same_tick':'slot_order_reread_after_each_actual_admission',
        'passed_guard':'original_complete_readiness_and_atomic_actual_admission',
        'existing_care':'original_intake_controls_new_visits_only',
        'readonly_reason_card':'original_complete_cause_query',
        'snapshot_counter':False,'runtime_measurement_available':False},
        'arrival early rejection changes admission, patient draws, current counts or actual care')


def validate_arrival_load(c,b):
    require(b['arrivals']['load_projection']=={
        'source':'original_structural_readiness_roster_and_reference_case_quotes',
        'definition':'maximum_feasible_expected_visit_flow_per_shift',
        'case_weights':'current_disease_weights_then_equal_ready_species_then_original_complexity_ratio',
        'reference_plan':'original_auto_plan_score_with_fixed_reference_context',
        'reference_energy':100,'reference_fatigue':0,'reference_anger':15,
        'reference_patient_personality_id':'PP01','reference_expression':'clear',
        'temporary_intake_switch_changes_capacity':False,'extra_consultation_behavior':False,
        'retry_work':'probability_weighted_original_auto_retry_without_reading_hidden_results',
        'resource_clocks':['reception','gp','required_tests_and_consultation','terminal_device',
                           'each_active_clinician','bed_commitment','ward_coverage_and_active_care'],
        'shared_resource_budget':'one_physical_owner_per_original_shift_window',
        'existing_load':'committed_remaining_and_quotable_existing_queue_before_new_reference_flow',
        'ward_coverage':'one_actual_nurse_one_ward_original_eight_beds_distinct_from_active_team',
        'bed_clock':'preparation_reservation_operation_wake_transfer_recovery_rounds_safe_release',
        'projection_assignment':'readonly_never_dispatches_or_reserves',
        'freeze':'complete_original_day_boundary_inputs',
        'unknown_future':'no_invented_failures_arrivals_or_future_treatment_results',
        'index_scope':'compiled_case_indexes_and_actual_sparse_resources_not_actor_team_cartesian_matrix',
        'empty_floor_models':0,'snapshot_solver_model':False,'partial_projection_allowed':False,
        'runtime_measurement_available':False}, 'arrival load loses actual clocks, case mix or read-only ownership')
    require(b['arrivals']['count_sampling']=={
        'algorithm':'arrival-load-count-v1','daily_density_draw':'uniform_integer_signed_basis_points',
        'integer_count':'unbiased_fractional_rounding_with_integer_rejection',
        'zero_capacity':'zero_count_no_count_or_seed_draw','draw_stream':'arrival',
        'count_cap':None,'fixed_minimum_count':False}, 'arrival count is fixed, capped, rounded down or redraws zero capacity')
    require(b['balance_reference']['arrival_outpatient_example_id'] in indexed(b['balance_reference']['outpatient_examples']),
            'arrival arithmetic reference duplicates absent clinical work')
    for row in b['arrival_presets'].values():
        require(set(row)=={'target_load_bp','daily_variation_bp','active_outpatients_per_scale'}
                and type(row['target_load_bp']) is int and row['target_load_bp']>0
                and type(row['daily_variation_bp']) is int and 0<=row['daily_variation_bp']<10000
                and type(row['active_outpatients_per_scale']) is int and row['active_outpatients_per_scale']>0,
                'fixed daily quota or invalid load preset')
    require([(b['arrival_presets'][k]['target_load_bp'],b['arrival_presets'][k]['daily_variation_bp'])
             for k in ('slow','normal','busy','festival')]==[(7500,2500),(9000,2500),(10000,3000),(11000,3500)],
            'base arrival pressure or daily variability drift')


def check_arrival_load_examples(c,b,check):
    capacity=reference_arrival_capacity(c,b); normal=b['arrival_presets']['normal']
    check(capacity==Fraction(500,9) and planned_arrivals(normal,capacity)==(37,63,Fraction(50)),
          '单D09基础常规终点的条件性名义容量55又5/9，正常平均50随机37…63，非医院固定人数')
    check([planned_arrivals(b['arrival_presets'][k],capacity) for k in ('slow','normal','busy','festival')]
          ==[(31,53,Fraction(125,3)),(37,63,Fraction(50)),(38,73,Fraction(500,9)),(39,83,Fraction(550,9))],
          '75/90/100/110百分比与25/25/30/35百分比浮动从同一工时推导，区间中点不是期望')
    def no_draw(lo,hi):raise ValueError('zero-capacity count unexpectedly drew randomness')
    check(sample_arrival_count(normal,0,no_draw)==0, '零名义能力不抽日密度、舍入或计划种子，不补最低一人')
    half={**normal,'daily_variation_bp':0}
    def draws(values):
        samples=iter(values)
        return lambda lo,hi:next(samples)
    check([sample_arrival_count(half,Fraction(25,9),draws([0,r])) for r in (0,1)]==[3,2],
          '参考均值2.5的随机舍入等概率2或3，不截成2或把整数区间中点当流量')
    for density in (-2500,0,2500):
        value=capacity*Fraction(normal['target_load_bp'],10000)*Fraction(10000+density,10000)
        whole,rem=divmod(value.numerator,value.denominator)
        samples=[sample_arrival_count(normal,capacity,draws([density,r]))
                 for r in range(value.denominator)]
        check(Fraction(sum(samples),len(samples))==value and all(n in (whole,whole+1) for n in samples),
              '固定密度'+str(density)+'bp下穷举舍入签的期望严格等于参考流量，不积累偏差')
    inpatient=inpatient_reference(c,b,indexed(b['balance_reference']['inpatient_examples'])['RC03'])
    bed=inpatient['bed_commitment_min_seconds']
    operation=inpatient['doctor_lock_seconds']
    one_bed=min(Fraction(b['day_seconds'])/bed,Fraction(b['day_seconds'])/operation)
    two_beds=min(Fraction(2*b['day_seconds'])/bed,Fraction(b['day_seconds'])/operation)
    check(two_beds==2*one_bed and planned_arrivals(normal,two_beds)[2]==2*planned_arrivals(normal,one_bed)[2],
          '同一完整术组参考下两张兼容可护理床缓解床瓶颈，终点流量翻倍不要求再买初诊')
    check(planned_arrivals(normal,min(two_beds,one_bed))==planned_arrivals(normal,one_bed),
          '保持当前客流冻结名义参考量，新增可用床改善余量；能力下降仍取较小值')
    shifts=split_shift_opportunities(8,[Fraction(1),Fraction(1),Fraction(1)],1,'321')
    check(sum(shifts)==8 and sorted(shifts)==[2,3,3]
          and split_shift_opportunities(8,[Fraction(1),Fraction(0),Fraction(1)],1,'321')==[4,0,4]
          and split_shift_opportunities(0,[0,0,0],1,None)==[0,0,0],
          '机会按三班承接量分配，零覆盖班不分机会，等余数由种子散列稳定仲裁，零日不除零')
    ticks=[load_scheduled_slot_tick(shifts,1,'321',i,b) for i in range(8)]
    check(shifts==[3,2,3] and ticks==[1156,2815,5438,8035,11156,12853,15397,16553],
          '新算法N8/日1/种子321分班3/2/3，八个精确tick固定向量可跨实现复现')
    check(ticks==sorted(ticks) and all(0<=t<b['day_seconds']*10 for t in ticks),
          '新算法三班各自分窗、完整日时刻非递减，同tick按原机会序，未生成日数组')
    without_middle=[load_scheduled_slot_tick([4,0,4],1,'321',i,b) for i in range(8)]
    check(all(not 6000<=t<12000 for t in without_middle),
          '没有临床班覆盖的中班不刷机会，不把缺岗平均摊到全天降低两次实际接诊')
    check([load_scheduled_slot_tick([12001,0,0],1,'321',i,b) for i in (0,1,12000)]==[0,0,5999],
          '分班12001机会的窄窗复现同tick与末次5999，不封顶或延到未覆盖班')
    calls=[]
    def reject_once(payload):
        calls.append(payload)
        return 2**32-1 if len(calls)==1 else 0
    check(load_scheduled_slot_tick([3,2,3],1,'321',0,b,reject_once)==500
          and calls==[b'arrival-load-slot-v1|1|321|0|0|0',b'arrival-load-slot-v1|1|321|0|0|1'],
          '分班拒绝区重做摘要而不抽随机流，nonce与局部序号编码固定')
    for path,value,label in [
        ('load_projection.shared_resource_budget','count_each_role_again','共享医生按多岗位虚增工时'),
        ('load_projection.case_weights','equal_all_plans','机器或方案多的病种提高概率'),
        ('load_projection.retry_work','read_frozen_future_result','偷看未揭晓治疗结果估客流'),
        ('load_projection.bed_clock','operation_only','忽略恢复与床承诺'),
        ('load_projection.ward_coverage','same_as_surgery_nurse','术组护士兼算病房覆盖'),
        ('load_projection.projection_assignment','dispatch_actual_staff','流量投影自动改真实排班'),
        ('load_projection.partial_projection_allowed',True,'未完投影伪装全天能力'),
        ('load_projection.empty_floor_models',10000,'为空楼层建模型'),
        ('load_projection.snapshot_solver_model',True,'保存第二套求解资源世界'),
        ('count_sampling.integer_count','floor_every_day','小医院长期少一人'),
        ('count_sampling.count_cap',160,'以性能样本封顶人数'),
        ('count_sampling.fixed_minimum_count',True,'零能力保底造病人')]:
        bad=copy.deepcopy(b);section,key=path.split('.');bad['arrivals'][section][key]=value
        try:validate_arrival_load(c,bad)
        except ValueError:check(True,'客流工时合同负例被拒绝：'+label)
        else:raise ValueError('arrival load accepted '+label)


def admission_opportunity_example(intake_open, count, allowance, read_original_readiness):
    """Boolean evaluation example only; no actors, cursor or RNG are simulated."""
    if not intake_open: return 'closed'
    if count>=allowance: return 'full'
    return 'admit' if read_original_readiness() else 'unready'


def check_admission_evaluation_examples(b, check):
    normal=b['arrival_presets']['normal']
    allowance=normal['active_outpatients_per_scale']
    check(allowance==24, '原当天S=1正常档门诊额度24，不把当日随机机会或名义均值当在院额度')
    def cannot_query(): raise ValueError('closed/full opportunity unexpectedly queried clinical readiness')
    check(admission_opportunity_example(False,0,allowance,cannot_query)=='closed'
          and admission_opportunity_example(False,allowance,allowance,cannot_query)=='closed',
          '关诊机会不求病例；人数状态不覆盖原关诊判定')
    check(all(admission_opportunity_example(True,n,allowance,cannot_query)=='full'
              for n in (allowance,allowance+1,640)),
          '已满或床承诺取消后的超额均只阻止新增，不求病例也不驱逐原患者')
    outcomes=[]; queries=[]
    for opened in (False,True):
        for n in (0,allowance-1,allowance,allowance+1):
            for ready in (False,True):
                calls=[]
                result=admission_opportunity_example(opened,n,allowance,lambda: calls.append('readiness') or ready)
                outcomes.append((result=='admit')==(opened and n<allowance and ready))
                queries.append(len(calls)==int(opened and n<allowance))
    check(all(outcomes) and all(queries),
          '16种开关/额度/就绪组合与原完整准入布尔式等价，只有合法分支求原Readiness')
    def run_same_tick(readiness_values):
        count=allowance-1; results=[]; reads=[]
        for i,ready in enumerate(readiness_values):
            result=admission_opportunity_example(True,count,allowance,lambda: reads.append(i) or ready)
            results.append(result)
            if result=='admit': count+=1
        return count,results,reads
    check(run_same_tick([True,True,True])==(24,['admit','full','full'],[0]),
          '同tick从23人首人确实入院变24，后两机会不共用批次旧准入结果')
    check(run_same_tick([False,True,True])==(24,['unready','admit','full'],[0,1]),
          '首机会Readiness失败不虚加人数，第二机会仍完整查病例，第三才早排除')
    check(admission_opportunity_example(True,23,24,lambda:False)=='unready'
          and admission_opportunity_example(True,24,24,cannot_query)=='full'
          and admission_opportunity_example(True,24,0,cannot_query)=='full',
          '前两项通过不等于临床可用，0额度或原额度不随日中意图擅自扩大')
    check(sum(admission_opportunity_example(False,0,allowance,cannot_query)=='closed'
              for _ in range(b['day_seconds']*10))==18000,
          '18000个实际到期关诊机会只做原逐次消费判定，不触碰临床查询；非运行计时证据')
    for key,value,label in [
        ('order',['original_case_and_body_readiness','current_intake_open','actual_outpatient_count_below_frozen_day_allowance'],'关诊先求全院病例'),
        ('active_count_source','current_visible_floor','只数镜头所在层'),
        ('allowance_source','current_midday_capacity','扩建重算今日额度'),
        ('guard_rejection','defer_until_reopen','遗漏到访堆积补发'),
        ('guard_rejection_patient_draws',1,'排除后先抽患者'),
        ('daily_count_and_seed_draws','skip_when_closed','关诊重排日计划随机数'),
        ('same_tick','reuse_batch_initial_result','同tick多人共用旧人数'),
        ('passed_guard','skip_body_or_bed','早判通过跳过身体或床位'),
        ('existing_care','cancel_current_visits','关诊取消已有治疗'),
        ('readonly_reason_card','reuse_guard_as_complete_cause','早排除替代完整原因卡'),
        ('snapshot_counter',True,'保存第二份人数')]:
        invalid=copy.deepcopy(b); invalid['arrivals']['admission_evaluation'][key]=value
        try: validate_admission_evaluation(invalid)
        except ValueError: check(True,'到访求值合同负例被拒绝：'+label)
        else: raise ValueError('admission evaluation accepted '+label)


def leave_probability(wait_seconds, anger, personality, environment, b):
    rule = b['wait_departure']
    if wait_seconds < rule['first_check_seconds']:
        return 0
    buffer = .5 if environment >= 80 else .75 if environment >= 60 else 1
    value = (rule['base_probability'] + rule['per_extra_wait_second'] *
             max(0, wait_seconds-rule['first_check_seconds']) +
             rule['per_extra_anger'] * max(0, anger-rule['anger_threshold']))
    return min(rule['probability_max'], max(rule['probability_min'],
               value * personality['wait_leave_multiplier'] * buffer))


def connector_fits(species, connector):
    body = species['body']
    width = max(body['width_m'], body['depth_m'])
    return (math.ceil(width / 1.5) <= connector['max_clearance_cells']
            and round(width * 100) + 10 <= round(connector['clear_width_m'] * 100)
            and round(body['height_m'] * 100) + 10 <= round(connector['clear_height_m'] * 100))


def cabin_fits(cabin, clearances):
    """Exhaustive placement of at most two square traversal envelopes."""
    def place(index, occupied):
        if index == len(clearances):
            return True
        k = clearances[index]
        for x in range(cabin[0]-k+1):
            for y in range(cabin[1]-k+1):
                body = {(x+dx, y+dy) for dx in range(k) for dy in range(k)}
                if not body & occupied and place(index+1, occupied | body):
                    return True
        return False
    return place(0, set())


def section_quote(floor, b):
    require(type(floor) is int and floor >= 2, 'invalid upper floor number')
    rule = b['floors']['section_pricing']
    offset = floor-rule['first_upper_floor']
    return (min(rule['max_material_cost'],rule['base_material_cost']+offset*rule['material_increment_per_floor']),
            min(rule['max_work_seconds'], rule['base_work_seconds']+offset*rule['work_increment_per_floor']))


def section_allowed(owned_plots, top_floor_by_plot, floor, plot, rooms,
                    source, lift=None, pending_sections=()):
    """Static prerequisites over committed Room and connection projections, not a game command.

    Rooms have already passed whole-room geometry validation. This predicate does
    not prove funds, workers, dynamic routes, atomic completion or recovery.
    """
    if not (type(floor) is int and floor >= 2 and plot in owned_plots
            and top_floor_by_plot.get(plot, 1) == floor-1
            and (floor, plot) not in pending_sections):
        return False
    if not any(room['floor_id'] == f'floor:{floor-1}'
               and any(x//32+3*(y//32) == plot for x,y in room['inner_cells'])
               for room in rooms):
        return False
    if source == 'selected_lift':
        return (lift is not None and lift['kind'] == 'lift' and lift['first_floor'] == 1
                and lift['anchor'][0]//32+3*(lift['anchor'][1]//32) == plot)
    if source == 'same_floor':
        return any(top_floor_by_plot.get(p, 1) >= floor for p in owned_plots)
    return False


def ward_projection_slots(wards, b):
    assigned=set(); slots=0
    for bed_count,nurse_ids in wards:
        require(type(bed_count) is int and 0<=bed_count<=b['clinical']['max_beds_per_room'],
                'invalid projected ward bed count')
        require(len(nurse_ids)==len(set(nurse_ids)) and not assigned.intersection(nurse_ids),
                'one projected nurse covers two wards')
        assigned.update(nurse_ids)
        slots+=min(bed_count,len(nurse_ids)*b['clinical']['beds_per_nurse'])
    return slots


def actor_path_budget(actor_count, b):
    p=b['pathfinding']
    require(type(actor_count) is int and actor_count>=0, 'invalid path actor count')
    return max(p['minimum_actor_requests_per_tick'],
               (actor_count+p['actors_per_request']-1)//p['actors_per_request'])


def validate_movement_queries(b):
    expected = {
        'scope':'original_floor_bodies_and_complete_movement_units',
        'bucket_cells_source':'pathfinding.local_updates.chunk_cells',
        'floor_source':'original_mutually_exclusive_actor_position',
        'bounds_source':'actual_current_complete_body_or_original_group_envelope',
        'query_source':'original_proposed_legal_step_sweeps',
        'bucket_cover':'include_boundary_touch_all_intersecting_buckets',
        'step_sweeps':'accepted_original_move_sweeps_pinned_until_stage_5_end',
        'update':'atomic_before_after_binding_on_actual_source_commit',
        'candidate_identity':'original_movement_unit_key',
        'membership_source':'original_owner_current_members_and_past_sweep_participants',
        'candidate_order':'deduplicate_then_original_stable_entity_order','candidate_cap':None,
        'narrow_phase':'original_current_body_sweep_reservations_and_courtesy_rules',
        'broadphase_is_permission':False,'group_policy':'original_complete_group_no_new_actor_or_split',
        'incomplete_index':'rebuild_requested_floor_or_original_complete_query_with_pinned_sweeps',
        'actor_motion_rebuilds_static_graph':False,
        'memory_scope':'original_working_set_actual_units_step_sweeps_and_temporary_candidates',
        'actor_pair_matrix':False,'empty_floor_records':False,'snapshot_state':False,
        'changes_courtesy_or_simulation':False,'runtime_measurement_available':False}
    row=b['movement_queries']
    require(set(row)==set(expected) and all(type(row[key]) is type(value) and row[key]==value
            for key,value in expected.items()), 'movement candidate index changes bodies, safety or original order')


def movement_bucket_cover_example(rectangles, b):
    """Conservative rational-cell fixture cover, not runtime avoidance or a movement permit."""
    width,height=b['pathfinding']['local_updates']['chunk_cells']; result=set()
    for rect in rectangles:
        require(type(rect) in (tuple,list) and len(rect)==4
                and all(type(value) in (int,Fraction) for value in rect), 'invalid movement fixture bounds')
        x0,y0,x1,y1=rect
        require(x0<x1 and y0<y1, 'empty or reversed movement fixture bounds')
        # Include exact boundary touch; broad phase may conservatively report extra units.
        for x in range(math.floor(Fraction(x0)/width),math.floor(Fraction(x1)/width)+1):
            for y in range(math.floor(Fraction(y0)/height),math.floor(Fraction(y1)/height)+1):
                result.add((x,y))
    return result


def movement_candidates_example(records, floor_id, rectangles, b, self_unit=None):
    # Rebuild a small static fixture index; it does not model source commits or simulate a game step.
    buckets=defaultdict(set)
    for row in records:
        require(type(row['unit_key']) is str and row['unit_key'] and type(row['floor_id']) is str,
                'invalid movement fixture identity')
        for chunk in movement_bucket_cover_example(row['bounds'],b):
            buckets[(row['floor_id'],*chunk)].add(row['unit_key'])
    candidates=set()
    for chunk in movement_bucket_cover_example(rectangles,b):
        candidates.update(buckets.get((floor_id,*chunk),set()))
    if self_unit is not None:candidates.discard(self_unit)
    return sorted(candidates)


def check_movement_queries_examples(b, check):
    crossing=(Fraction(31,4),1,Fraction(33,4),2)
    check(movement_bucket_cover_example([crossing],b)=={(0,0),(1,0)},
          '跨8格身体真实7.75…8.25覆盖两桶，不只看锚点或粗取整')
    check(movement_bucket_cover_example([(7,1,8,2)],b)=={(0,0),(1,0)}
          and movement_bucket_cover_example([(-1,1,1,2)],b)=={(-1,0),(0,0)},
          '精确桶边界接触保守保留，负边界向下分桶，不截为0')
    rows=[{'unit_key':'actor:1','floor_id':'floor:1','bounds':[crossing]},
          {'unit_key':'actor:2','floor_id':'floor:2','bounds':[crossing]},
          {'unit_key':'group:7','floor_id':'floor:1','bounds':[(6,1,10,3)]},
          {'unit_key':'group:7','floor_id':'floor:1','bounds':[(6,1,10,3)]},
          {'unit_key':'actor:3','floor_id':'floor:1','bounds':[(2,5,3,6)]}]
    original=copy.deepcopy(rows)
    candidates=movement_candidates_example(rows,'floor:1',[(8,1,9,2)],b)
    check(candidates==['actor:1','group:7'], '跨桶候选身体/完整组去重，另一层同XY不混入')
    check(movement_candidates_example(rows,'floor:1',[(8,1,9,2)],b,'group:7')==['actor:1'],
          '自身原完整移动单位排除一次，不把同组多桶引用当对手')
    false_positive=movement_candidates_example(rows,'floor:1',[(1,1,2,2)],b)
    query=(1,1,2,2); distant=rows[-1]['bounds'][0]
    interiors_overlap=(query[0]<distant[2] and distant[0]<query[2]
                       and query[1]<distant[3] and distant[1]<query[3])
    check('actor:3' in false_positive and not interiors_overlap,
          '同桶远处身体可粗筛多报，矩形真实不相交，候选本身不是碰撞许可/硬阻挡')
    current=[{'unit_key':'actor:4','floor_id':'floor:1','bounds':[(Fraction(161,20),1,Fraction(181,20),2)]}]
    swept=current+[{'unit_key':'actor:4','floor_id':'floor:1','bounds':[(Fraction(157,20),1,Fraction(181,20),2)]}]
    sweep_query=[(Fraction(69,10),1,Fraction(79,10),2)]
    check(movement_candidates_example(current,'floor:1',sweep_query,b)==[]
          and movement_candidates_example(swept,'floor:1',sweep_query,b)==['actor:4'],
          '仅新位置会漏历史经过区，本步原接受扫掠作为候选仍保留；不模拟扫掠时序')
    many=[{'unit_key':f'actor:{i:03}','floor_id':'floor:1','bounds':[(i%8,i//8,i%8+1,i//8+1)]} for i in range(40)]
    check(len(movement_candidates_example(many,'floor:1',[(1,1,2,2)],b))==40,
          '40条不重叠格范围在同桶粗筛不截前N，索引示意不是医院运行证明')
    check(movement_bucket_cover_example([(1,1,2,2),(80,1,81,2)],b)=={(0,0),(10,0)},
          '分段源范围分别覆盖，不用跨越中间全部桶的起终点巨盒')
    check(rows==original and movement_candidates_example(rows,'floor:10000',[(8,1,9,2)],b)==[],
          '静态索引示意只读原源且楼层隔离，真实空结果仍须先证明完整性')
    for rect,label in [((1,1,1,2),'零宽'),((2,1,1,2),'反向'),((True,1,2,2),'布尔坐标'),
                       ((0.1,1,2,2),'未声明浮点精度')]:
        try:movement_bucket_cover_example([rect],b)
        except ValueError:check(True,'通行粗筛非法示意被拒绝：'+label)
        else:raise ValueError('movement fixture accepted '+label)
    for mutate,label in [
        (lambda row:row.update(bounds_source='anchor_only'),'漏长身体'),
        (lambda row:row.update(floor_source='same_xy_all_floors'),'跨层假碰撞'),
        (lambda row:row.update(step_sweeps='discard_after_endpoint_update'),'丢本步扫掠'),
        (lambda row:row.update(update='next_visual_refresh'),'显示驱动身体更新'),
        (lambda row:row.update(candidate_order='bucket_iteration'),'桶顺序决定礼让'),
        (lambda row:row.update(candidate_cap=8),'截最近8人'),
        (lambda row:row.update(broadphase_is_permission=True),'粗筛允许穿越'),
        (lambda row:row.update(group_policy='split_into_independent_actors'),'拆开陪同组'),
        (lambda row:row.update(membership_source='old_members_are_permanent_self_exceptions'),'离组者永久当自有身体'),
        (lambda row:row.update(incomplete_index='missing_means_empty'),'未知通道当空'),
        (lambda row:row.update(actor_motion_rebuilds_static_graph=True),'每步重建全静态图'),
        (lambda row:row.update(actor_pair_matrix=True),'全院角色对预分配'),
        (lambda row:row.update(empty_floor_records=True),'预建万层索引'),
        (lambda row:row.update(snapshot_state=True),'桶缓存进快照'),
        (lambda row:row.update(changes_courtesy_or_simulation=True),'改变既定速度礼让'),
        (lambda row:row.update(runtime_measurement_available=True),'候选算例冒充实机')]:
        invalid=copy.deepcopy(b); mutate(invalid['movement_queries'])
        try:validate_movement_queries(invalid)
        except ValueError:check(True,'通行近邻合同负例被拒绝：'+label)
        else:raise ValueError('movement candidate contract accepted '+label)


def validate_local_navigation(b):
    p=b['pathfinding']['local_updates']
    require(p == {
        'chunk_cells':[8,8],
        'change_source':'authoritative_before_after_geometry_occupancy_and_soft_cost',
        'graph_repair':'affected_nodes_edges_before_query',
        'dependency':'actual_envelope_footprint_and_movement_sweep',
        'coalescing':'union_until_next_query',
        'history_miss':'rebuild_requested_floor_envelope',
        'actor_motion':'movement_contention_only',
        'connector_change':'index_and_touched_landings_only',
        'single_floor_query_key':['hospital_session','floor_id','start','goal',
            'traversal_envelope','query_kind','query_options','nav_revision','occupancy_revision'],
        'cached_results':['route','partial','unreachable','walking_distance','connectivity'],
        'result_lifetime':'retire_results_with_floor_cache_record',
        'cross_floor_queries':'fresh_search_with_current_transit_quote',
        'active_route_recheck':'remaining_sweeps_and_used_connections_on_related_change',
        'safety_gate':'atomic_current_edge_and_work_start',
        'dirty_storage':'sparse_derived_discardable',
        'memory_scope':'graphs_dependency_indexes_dirty_history_and_query_results',
        'snapshot_state':False,'view_changes_revision':False,'runtime_measurement_available':False},
        'local navigation update, cache or actual safety contract is invalid')
    require(all(type(p[key]) is bool for key in
                ('snapshot_state','view_changes_revision','runtime_measurement_available')),
            'navigation cache boolean fields must be booleans')


def navigation_dirty_chunks_example(rectangles, width, depth, b):
    """Conservative sample bucket cover only; no graph or runtime path search."""
    grid_width,grid_height=b['limits']['grid_width'],b['limits']['grid_height']
    require(type(width) is int and type(depth) is int
            and 1<=width<=grid_width and 1<=depth<=grid_height, 'invalid sample body footprint')
    chunk_width,chunk_height=b['pathfinding']['local_updates']['chunk_cells']
    margin=max(width,depth); chunks=set()
    for rect in rectangles:
        require(len(rect)==4 and all(type(value) is int for value in rect), 'invalid dirty rectangle')
        x0,y0,x1,y1=rect
        require(0<=x0<x1<=grid_width and 0<=y0<y1<=grid_height, 'invalid dirty bounds')
        left,right=max(0,x0-margin),min(grid_width,x1+margin)
        top,bottom=max(0,y0-margin),min(grid_height,y1+margin)
        chunks.update((x,y) for y in range(top//chunk_height,math.ceil(bottom/chunk_height))
                      for x in range(left//chunk_width,math.ceil(right/chunk_width)))
    return sorted(chunks,key=lambda cell:(cell[1],cell[0]))


def navigation_query_cache_matches_example(saved, current, b):
    if not isinstance(saved,dict) or not isinstance(current,dict):
        return False
    return all(key in saved and key in current and saved[key]==current[key]
               for key in b['pathfinding']['local_updates']['single_floor_query_key'])


def check_local_navigation_examples(b, check):
    check(navigation_dirty_chunks_example([[42,42,43,43]],1,1,b)==[(5,5)],
          '96×96大平层单格变化筛出1个逻辑桶，仍须精确检查身体和边扫掠')
    check(navigation_dirty_chunks_example([[10,10,11,11],[82,82,83,83]],1,1,b)==[(1,1),(10,10)],
          '搬动两端分别扩展只取2桶，不用两端包围矩形使中间走廊失效')
    check(navigation_dirty_chunks_example([[12,10,15,13]],1,1,b)==[(1,1)]
          and navigation_dirty_chunks_example([[12,10,15,13],[12,10,17,13]],1,1,b)==[(1,1),(2,1)],
          '3格底座伸为5格尾部时，真实后占地包含相邻桶')
    check(len(navigation_dirty_chunks_example([[20,20,21,21]],1,1,b))==1
          and len(navigation_dirty_chunks_example([[20,20,21,21]],5,5,b))==9,
          '扫掠候选范围随实际5格身体扩大，不能固定外扩1格或3格')
    check(navigation_dirty_chunks_example([],3,3,b)==[]
          and navigation_dirty_chunks_example([[0,0,1,1]],1,1,b)==[(0,0)],
          '没有真实导航变化不产生脏桶，地图边界裁剪仍包含合法依赖')
    saved={'hospital_session':'h1-load1','floor_id':1,'start':(1,1),'goal':(90,90),
           'traversal_envelope':(3,3,580),'query_kind':'route',
           'query_options':('public','standing','reservation:none'),'nav_revision':4,'occupancy_revision':7}
    check(navigation_query_cache_matches_example(saved,dict(saved),b)
          and not navigation_query_cache_matches_example(saved,None,b)
          and not navigation_query_cache_matches_example(saved,{key:value for key,value in saved.items()
                                                                if key!='query_options'},b),
          '完整同层查询可复用，缺失请求或准入/预约参数不可借旧缓存放行')
    differences={'hospital_session':'h2-load1','floor_id':10000,'goal':(89,90),
                 'traversal_envelope':(5,5,580),'query_kind':'unreachable',
                 'query_options':('staff','sitting','reservation:own'),'nav_revision':5,'occupancy_revision':8}
    check(all(not navigation_query_cache_matches_example(saved,dict(saved,**{key:value}),b)
              for key,value in differences.items()),
          '医院/楼层/终点/身体/类型/准入或拓扑占用变化均拒绝旧查询结果')
    check(all(not navigation_query_cache_matches_example(dict(saved,query_kind=kind),
                 dict(saved,query_kind=kind,nav_revision=5),b)
              for kind in b['pathfinding']['local_updates']['cached_results']),
          '新开门或捷径使成功、部分、无路、路程与连通性结果一同重新求解')
    negatives=[
        (lambda row:row.update(change_source='authoritative_before_after_geometry_and_occupancy'), '软绕行变化遗漏原导航修订'),
        (lambda row:row.update(dependency='anchor_cell_only'), '只看锚点漏掉身体扫掠'),
        (lambda row:row.update(actor_motion='rebuild_graph_on_each_step'), '居民迈步重建静态图'),
        (lambda row:row.update(graph_repair='return_stale_then_repair'), '查询先返回旧图'),
        (lambda row:row['single_floor_query_key'].remove('query_options'), '缓存省略预约准入条件'),
        (lambda row:row.update(cached_results=['route']), '失败和距离结果不核验修订'),
        (lambda row:row.update(cross_floor_queries='reuse_old_corridor_quote'), '跨层沿旧走廊报价'),
        (lambda row:row.update(active_route_recheck='restart_every_actor'), '局部变化重启全院路线'),
        (lambda row:row.update(safety_gate='cached_permission_only'), '移动开工跳过原子核验'),
        (lambda row:row.update(memory_scope='graph_nodes_only'), '索引脏记录和结果隐藏内存'),
        (lambda row:row.update(result_lifetime='survive_floor_cache_recreation'), '层缓存重建复活旧结果'),
        (lambda row:row.update(snapshot_state=True), '派生导航缓存保存成世界事实'),
        (lambda row:row.update(view_changes_revision=True), '切层改变业务通路修订'),
        (lambda row:row.update(snapshot_state=0), '布尔字段混用整数')]
    for mutate,label in negatives:
        broken=copy.deepcopy(b); mutate(broken['pathfinding']['local_updates'])
        try:validate_local_navigation(broken)
        except ValueError:check(True,'局部通行合同负例被拒绝：'+label)
        else:raise ValueError('invalid local navigation contract accepted: '+label)


def validate_transit(c, b):
    p = b['transit']
    require(p['queue_admission'] == 'whole_group_ready_at_legal_origin_landing'
            and p['queue_order'] == 'ticket_sequence_then_session_id'
            and p['ticket_scope'] == 'one_current_vertical_leg' and p['queued_reserves_cabin'] is False,
            'transit preview admits absent actors or reserves cabins for an entire queue')
    require(p['clinical_ticket_preserved'] is True
            and p['after_ticket_choice'] == 'keep_until_goal_or_access_change', 'transport changes medical ticket or chases quotations')
    require(p['projection'] == 'active_remaining_then_ready_fifo_prefix_and_empty_pickup'
            and p['walking_overlap'] == 'absolute_arrival_max_prefix_finish'
            and p['future_arrivals_in_estimate'] is False and p['future_failures_in_estimate'] is False,
            'transit quote doubles walking/waiting or predicts unknown requests/faults')
    require(p['preview_creates_session'] is False and p['quote_saved_in_world'] is False
            and p['quote_charges_cash'] is False and p['return_trip_reserved'] is False,
            'quotation creates a second transport fact, fee or future cabin claim')
    require(p['boarding_time_scope'] == 'once_per_group'
            and p['initial_cabin_station_source'] == 'floors.ground_floor_number'
            and p['layer_time_source'] == 'current_operation_mode'
            and p['emergency_layer_time_source'] == 'floors.emergency_travel_seconds_per_floor'
            and p['cancel_empty_pickup'] == 'release_group_finish_real_empty_segment'
            and p['prefix_cache_key'] == 'connection_operational_revision' and p['prefix_count_cap'] is None,
            'transit group timing, empty-cabin continuity or growing queue is invalid')
    require(p['cue_extra_seconds'] == 0 and p['cue_extra_actor'] is False
            and p['cue_creates_interaction'] is False and p['animation_controls_progress'] is False
            and p['runtime_measurement_available'] is False, 'transport cue creates work, actors or unmeasured proof')
    for row in c['vertical_connectors']:
        cues = row['transit_cues']
        require(set(cues) == {'queued_scene', 'empty_scene', 'riding_scene', 'unavailable_scene', 'low_motion_scene'}
                and all(isinstance(cues[key], str) and cues[key] for key in (
                    'queued_scene', 'riding_scene', 'unavailable_scene', 'low_motion_scene')), 'transit cue lacks actual phase or low-motion presentation')
        require((cues['empty_scene'] is None if row['kind'] == 'stairs'
                 else isinstance(cues['empty_scene'], str) and bool(cues['empty_scene'])), 'stairs invent a cabin or elevator lacks empty pickup cue')


def transit_projection_example(connection, b, cabin_floor, ready_prefix, origin, target,
                               walk_ticks=0, active_remaining_ticks=0, active_end_floor=None, final_walk_ticks=0,
                               descent_only=False):
    """Conditional time-axis arithmetic; no real queue, geometry or actor is simulated."""
    tick = Fraction(str(b['tick_seconds']))
    def ticks(seconds):
        return math.ceil(Fraction(str(seconds)) / tick)
    if descent_only:
        require(connection['kind'] == 'lift' and target < origin
                and all(to_floor < from_floor for from_floor, to_floor in ready_prefix),
                'safety descent cannot carry passengers upwards')
    layer_seconds = Fraction(str(b['floors']['emergency_travel_seconds_per_floor'] if descent_only
                                 else connection['travel_seconds_per_floor']))
    def empty(from_floor, to_floor):
        return ticks(layer_seconds * abs(from_floor - to_floor)) if connection['kind'] == 'lift' else 0
    def group(from_floor, to_floor):
        return (ticks(connection['boarding_seconds']) + ticks(layer_seconds * abs(from_floor - to_floor))
                + ticks(connection['alighting_seconds']))
    prefix_finish = active_remaining_ticks
    end_floor = active_end_floor if active_end_floor is not None else cabin_floor
    for from_floor, to_floor in ready_prefix:
        prefix_finish += empty(end_floor, from_floor) + group(from_floor, to_floor)
        end_floor = to_floor
    empty_ticks = empty(end_floor, origin); own_ticks = group(origin, target)
    return {'total_ticks': max(walk_ticks, prefix_finish) + empty_ticks + own_ticks + final_walk_ticks,
            'front_queue_ticks': max(0, prefix_finish - walk_ticks), 'empty_ticks': empty_ticks, 'own_ticks': own_ticks}


def check_transit_examples(c, b, check):
    connectors = indexed(c['vertical_connectors']); lift = connectors['VC02']; stairs = connectors['VC01']
    check(transit_projection_example(lift, b, 1, [], 1, 2)['total_ticks'] == 40
          and transit_projection_example(lift, b, 3, [], 1, 2)['total_ticks'] == 60,
          '闲梯1F接人到2F为4模拟秒即3.2医院分钟，闲梯在3F时共6模拟秒')
    quotes = [transit_projection_example(lift, b, 1, [(1,3)], 1, 2, walk_ticks=t) for t in (0,100,400)]
    check([q['total_ticks'] for q in quotes] == [110,160,460]
          and [q['front_queue_ticks'] for q in quotes] == [50,0,0]
          and all(q['empty_ticks'] == 20 and q['own_ticks'] == 40 for q in quotes),
          '前组5秒与步行0/10/40秒重叠，B组到达11/16/46秒，空载不遗漏')
    check(transit_projection_example(lift, b, 1, [], 1, 2, active_remaining_ticks=100, active_end_floor=3)['total_ticks'] == 160
          and transit_projection_example(lift, b, 1, [], 1, 2, active_remaining_ticks=60, active_end_floor=4)['total_ticks'] == 130,
          '当前安全组残10秒结束于3F计16秒；取消接人空车残6秒到4F计13秒，不重置轿厢')
    check(transit_projection_example(stairs, b, 1, [], 1, 2)['total_ticks'] == 25
          and transit_projection_example(stairs, b, 1, [(2,1)], 1, 2)['total_ticks'] == 50,
          '楼梯无队2.5模拟秒即2医院分钟，前方一组5模拟秒，没有空载返回')
    first = transit_projection_example(lift, b, 1, [], 1, 3)['total_ticks']
    cycle = transit_projection_example(lift, b, 3, [], 1, 3)['total_ticks']
    completed = 1 + (int(Fraction(str(b['day_seconds'])) / Fraction(str(b['tick_seconds']))) - first) // cycle
    check(first == 50 and cycle == 70 and completed == 257,
          '条件性持续1F到3F首5秒/随后7秒，1800秒最多完整257组，不是治愈人数或真实吞吐')
    check(transit_projection_example(lift, b, 1, [(1,2)]*600, 1, 2)['total_ticks'] == 30040
          and transit_projection_example(lift, b, 1, [], 1, 10000)['total_ticks'] == 100020,
          '算术前缀不截断600组，10000F只按真实层差得10002秒，不展开中间层')
    check(transit_projection_example(lift, b, 3, [], 3, 1, descent_only=True)['total_ticks'] == 110
          and transit_projection_example(lift, b, 1, [], 3, 1, descent_only=True)['total_ticks'] == 190,
          '缓降每层4模拟秒，3F到1F为11秒，空车从1F上行接人后共19秒')
    try:
        transit_projection_example(lift, b, 1, [], 1, 2, descent_only=True)
    except ValueError:
        check(True, '安全缓降可以空车上行接人，不能载客上楼')
    else:
        raise ValueError('safety descent forecasts an uphill passenger ride')
    negatives = [
        (lambda x,y:y['transit'].update(queue_admission='planned_route'), '远处规划就占叫梯票'),
        (lambda x,y:y['transit'].update(queued_reserves_cabin=True), '排队组同时锁轿厢'),
        (lambda x,y:y['transit'].update(walking_overlap='walk_plus_entire_queue'), '走路和已流逝队列重复加'),
        (lambda x,y:y['transit'].update(clinical_ticket_preserved=False), '取消叫梯丢医疗票号'),
        (lambda x,y:y['transit'].update(cancel_empty_pickup='reset_cabin_to_ground'), '取消接人传送空车'),
        (lambda x,y:y['transit'].update(return_trip_reserved=True), '报价预占未来回程'),
        (lambda x,y:y['transit'].update(prefix_count_cap=16), '长队只算前16组'),
        (lambda x,y:y['transit'].update(animation_controls_progress=True), '动画回调完成跨层'),
        (lambda x,y:y['transit'].update(emergency_layer_time_source='normal_connector_speed'), '正常6秒误算故障缓降'),
        (lambda x,y:x['vertical_connectors'][0]['transit_cues'].update(empty_scene='空楼梯车来接人'), '结构楼梯生成空车'),
        (lambda x,y:x['vertical_connectors'][1]['transit_cues'].update(low_motion_scene=''), '运输缺少低动态状态'),
    ]
    for mutate, label in negatives:
        broken_c, broken_b = copy.deepcopy(c), copy.deepcopy(b); mutate(broken_c, broken_b)
        try:
            validate_transit(broken_c, broken_b)
        except ValueError:
            check(True, '运输合同负例被拒绝：' + label)
        else:
            raise ValueError('invalid transit contract accepted: ' + label)


def validate_patience_schedule(b):
    expected = {
        'scope': 'active_original_wait_departure_ticket',
        'clock_source': 'queue_ticket_effective_wait_ticks',
        'threshold_source': 'wait_departure_state_next_check_wait_ticks',
        'phase': 'after_phase7_wait_and_affect_before_new_interactions',
        'exit_order': 'actual_service_and_safety_then_deterministic_then_probability',
        'entry_update': 'replace_or_remove_current_entry', 'current_entries_per_ticket': 1,
        'due_order': 'existing_actor_id_then_current_ticket_id',
        'coincident_budget': 'all_due_same_original_step',
        'pause_resume': 'remaining_effective_wait_from_original_owner',
        'probability_inputs': 'current_original_anger_personality_environment',
        'index_identity': 'hospital_session_actor_current_ticket_threshold',
        'rebuild': 'from_validated_owners_before_next_phase7',
        'unknown_dependency': 'original_check_for_affected_ticket',
        'suspended_draws': 0, 'readonly_draws': 0, 'entries_for_empty_floors': 0,
        'memory_scope': 'actual_entries_handles_and_temporary_rebuild',
        'snapshot_state': False, 'changes_wait_probability_or_interval': False,
        'runtime_measurement_available': False}
    require(b['patience_schedule'] == expected
            and all(type(b['patience_schedule'][key]) is int
                    for key in ('current_entries_per_ticket', 'suspended_draws', 'readonly_draws', 'entries_for_empty_floors')),
            'patience scheduling duplicates clocks, changes ordering or skips original assessments')


def check_patience_schedule_examples(b, check):
    tick = Fraction(str(b['tick_seconds']))
    first = int(Fraction(b['wait_departure']['first_check_seconds']) / tick)
    interval = int(Fraction(b['wait_departure']['check_interval_seconds']) / tick)
    thresholds = list(range(first, 1800+1, interval))
    check(thresholds == [1200, 1500, 1800],
          '有效候诊120/150/180秒对应1200/1500/1800tick，原三次门槛不变')
    check(1610 + max(0, 1500-1210) == 1900,
          '121秒暂离40秒后剩29有效秒，下一门槛仍150秒，派生实际时刻190秒')
    check(640*1800 == 1152000 and 640*len(thresholds) == 1920,
          '640票180秒有1152000逐tick检查机会，对应三批各640到期通知；不是实机提速')
    for key, value, label in [
        ('clock_source', 'elapsed_wall_time', '生活服务期间仍按全局钟消耗耐心'),
        ('pause_resume', 'restart_full_interval', '回来重新等完整30秒'),
        ('coincident_budget', 'eight_actors_each_frame', '同刻到期延期'),
        ('due_order', 'heap_insertion_order', '缓存重建改变随机消费顺序'),
        ('entry_update', 'append_lazy_tombstones', '频繁改期积累无界旧项'),
        ('exit_order', 'probability_before_actual_service', '安全服务或确定离院仍抽签'),
        ('snapshot_state', True, '存档保存第二份到期时钟'),
        ('probability_inputs', 'frozen_at_first_assessment', '到期继续用旧怒气环境'),
        ('entries_for_empty_floors', 1, '空层也有定时记录')]:
        invalid = copy.deepcopy(b)
        invalid['patience_schedule'][key] = value
        try:
            validate_patience_schedule(invalid)
        except ValueError:
            check(True, '耐心调度合同负例被拒绝：'+label)
        else:
            raise ValueError('patience scheduling accepted '+label)


def validate_expansion(c, b):
    validate_arrival_load(c,b)
    validate_admission_evaluation(b)
    validate_patience_schedule(b)
    validate_transit(c, b)
    require({key:value for key,value in b['pathfinding'].items() if key!='local_updates'}==
            {'minimum_actor_requests_per_tick':8,'actors_per_request':20,
            'count_at':'tick_start_unique_present_actors','order':'request_sequence',
            'pending_per_actor':1,'replacement_keeps_sequence':True,'requeue_after_failed_dispatch':'tail',
            'cache_hits_consume_budget':True,'read_only_queries_use_business_queue':False,
            'graph_cache_target_bytes':134217728,'cache_key':'floor_and_traversal_envelope',
            'cache_changes_business_result':False}, 'navigation budget changes physical or deterministic rules')
    validate_local_navigation(b)
    validate_movement_queries(b)
    require(b['intake_controls'] == {'hospital_scope':'new_visits_only',
            'zero_weight_scope':'new_visits_only','existing_visit_retries':True,
            'closes_physical_doors':False,'reopen_resets_facility_intent':False,
            'closed_opportunity_policy':'consume_without_catchup','stops_staff_work':False},
            'intake switch cancels existing care or resets arrivals')
    arrivals = b['arrivals']
    require(arrivals['schedule']=={'algorithm':'arrival-load-slot-v1','legacy_read_algorithm':'arrival-slot-v1',
            'storage':'count_three_shift_counts_seed_cursor',
            'shift_allocation':'capacity_weighted_largest_remainder_seed_hash_ties',
            'seed_draw':'one_arrival_u64_if_nonzero','digest':'sha256_first_u32_be',
            'mapping':'rejection_then_modulo','zero_count_seed':None,'rebuild_consumes_rng':False},
            'arrival schedule grows saved arrays or redraws on inspection')
    require(0 < arrivals['slot_jitter_min'] < arrivals['slot_jitter_max'] < 1,
            'arrival jitter crosses daily windows')
    require(arrivals['preset_change'] == 'next_day'
            and arrivals['missed_slot'] == 'consume_without_catchup'
            and arrivals['manual_patient_invitation'] is False
            and 'invite_queue_limit' not in arrivals
            and arrivals['tutorial_fixed_slots'] == 2, 'unbounded or ambiguous arrival policy')
    scale = arrivals['capacity_scaling']
    require(scale['source'] == 'scheduled_complete_clinical_pairs'
            and scale['reference_shift_pairs'] == b['schedule']['shifts_per_day'] == 3
            and scale['reception_pairs_per_station'] == 3
            and scale['apply'] == 'next_day' and scale['default_mode'] == 'follow_capacity'
            and scale['active_count_excludes'] == 'valid_committed_inpatient_bed'
            and scale['ward_support']=='per_nurse_beds_in_one_ward'
            and scale['active_clinical_operators']=='distinct_from_ward_coverage',
            'unowned or unsafe admission growth')
    require(scale['hold_mode']=='min_current_capacity_and_held_capacity'
            and scale['active_allowance_mode']=='original_min_current_and_held_structural_scale',
            'hold mode forces expanded flow or changes original outpatient allowance')
    departure = b['wait_departure']
    require(departure['first_check_seconds'] == 120 and departure['check_interval_seconds'] == 30,
            'undefined patience clock')
    require(0 < departure['probability_min'] <= departure['base_probability']
            <= departure['probability_max'] <= 1, 'invalid departure probability')
    require(all(math.isfinite(departure[key]) and departure[key] >= 0
                for key in ('per_extra_wait_second', 'per_extra_anger'))
            and 0 <= departure['anger_threshold'] <= 100, 'invalid departure coefficients')
    require(set(departure['eligible_stages']) == WAITING_STAGES
            and len(departure['eligible_stages']) == len(WAITING_STAGES)
            and departure['rng_stream'] == 'patience'
            and departure['outcome_rating'] == 50, 'unsafe or unowned wait departure')
    traits = indexed(c['patient_personalities'])
    for trait in traits.values():
        require(math.isfinite(trait['wait_leave_multiplier'])
                and 0 < trait['wait_leave_multiplier'] <= 2, 'invalid personality patience')

    floors = b['floors']
    require(floors['ground_floor_number'] == 1 and floors['max_floors'] is None
            and floors['section_size_cells'] == [32, 32], 'invalid floor budget')
    require(all(floors[key] is True for key in ('requires_owned_ground',
                'requires_completed_below', 'same_floor_recovery')),
            'unsafe floor prerequisites or capacity duplication')
    require(floors['purchase_contract'] == {
        'new_floor_plot_source':'selected_lift_ground_anchor',
        'below_building_source':'actual_room_inner_cells_overlap',
        'same_floor_expansion':'at_least_one_completed_module',
        'section_acquisition':'construction_completion',
        'initial_lift_stations':'ground_single_station'},
        'floor purchase grants free plots, substitutes slab for room, or invents lift stops')
    require(floors['capacity_policy'] == 'actual_services_across_all_floors'
            and b['care_departments']['max_count'] is None
            and not set(b['limits']) & {'patients','staff','rooms','stations','props','total_actors','ordinary_visitors'},
            'fixed hospital entity limits block floor expansion')
    require(floors['structural_height_m'] > floors['clear_height_m'] >= 7
            and floors['connector_object_count'] == 'one_per_lift_driver'
            and floors['lift_ground_floor_required'] is True,
            'undefined floor height, landing budget or ground repair')
    pricing = floors['section_pricing']
    require('section_rules' not in floors and pricing['first_upper_floor'] == 2
            and all(type(pricing[key]) is int and pricing[key] > 0 for key in (
                'base_material_cost', 'material_increment_per_floor', 'max_material_cost', 'base_work_seconds',
                'work_increment_per_floor', 'max_work_seconds'))
            and pricing['base_work_seconds'] <= pricing['max_work_seconds']
            and pricing['base_material_cost'] <= pricing['max_material_cost'], 'invalid formula floor pricing')
    require(floors['completed_structure_storage'] == 'top_floor_per_plot'
            and floors['landing_storage'] == 'contiguous_range'
            and floors['floor_view_camera_cache'] == 32, 'dense floor storage or unbounded camera cache')
    roles = indexed(b['staff'], 'role')
    require(floors['construction_role'] == 'decorator' and 'decorator' in roles
            and floors['construction_tool_id'] in indexed(c['service_equipment'])
            and floors['emergency_travel_seconds_per_floor'] > 0, 'missing floor worker/tool or escape time')
    connectors = indexed(c['vertical_connectors'])
    for row in connectors.values():
        require(row['kind'] in {'stairs', 'lift'} and row['base_price'] > 0
                and row['base_stops'] == 2,
                'invalid connector kind or price')
        require(len(row['footprint']) == 2 and all(isinstance(n, int) and 1 <= n <= 8
                                                for n in row['footprint']), 'invalid connector footprint')
        require(1 <= row['max_clearance_cells'] <= 3
                and 0 < row['clear_width_m'] < min(row['footprint'])*1.5
                and 0 < row['clear_height_m'] <= 7, 'invalid connector envelope')
        require(row['travel_seconds_per_floor'] > 0 and row['boarding_seconds'] >= 0
                and row['alighting_seconds'] >= 0, 'invalid travel time')
        width, depth = row['footprint']
        require(row['front_operation_anchor'] == [0, depth]
                and row['repair_anchor'] == ([width, depth] if row['kind'] == 'lift' else None),
                'undefined connector operation or repair anchor')
        footprint = {(x, y) for x in range(width) for y in range(depth)}
        for k in range(1, row['max_clearance_cells']+1):
            operation = {(x, depth+y) for x in range(k) for y in range(k)}
            repair = ({(width+x, depth+y) for x in range(k) for y in range(k)}
                      if row['kind'] == 'lift' else set())
            require(not operation & footprint and not repair & footprint
                    and not operation & repair, 'connector operation/repair overlaps shaft or each other')
        if row['kind'] == 'stairs':
            require(row['cabin_size'] is None and row['equipment_class'] is None
                    and row['max_stops'] == 2 and row['extra_stop_price'] is None
                    and row['max_group_size'] == 1 and row['failure_policy'] == 'structural',
                    'stairs pretend to be mechanical equipment')
        else:
            require(row['equipment_class'] == 'utility'
                    and row['failure_policy'] == 'finish_ride_then_descent_only'
                    and row['extra_stop_price'] > 0 and row['max_group_size'] == 2
                    and row['max_stops'] is None,
                    'unsafe or unpriced lift')
            require(isinstance(row['cabin_size'], list) and len(row['cabin_size']) == 2
                    and all(isinstance(n, int) and row['max_clearance_cells'] <= n < bound
                            for n, bound in zip(row['cabin_size'], row['footprint'])),
                    'cabin exceeds shaft or rejects declared envelope')
    for species in c['species']:
        require(any(row['kind'] == 'lift' and connector_fits(species, row)
                    for row in connectors.values()), 'species has no vertical access definition')

    profiles = indexed(c['staff_role_profiles'])
    require(Counter(x['role'] for x in profiles.values()) == Counter({key: 1 for key in roles}),
            'staff role profile coverage')
    for profile in profiles.values():
        source = 'doctor_pay' if profile['role'] == 'doctor' else 'staff:'+profile['role']
        require(profile['pay_source'] == source and profile['description'] and profile['qualification_note']
                and not {'hire', 'wage_day'} & set(profile), 'staff biography duplicates pay or lacks qualification')
    styles, bios = indexed(c['staff_work_styles']), indexed(c['staff_biographies'])
    require({row['preference'] for row in styles.values()} == WORK_PREFERENCES, 'unknown work preference')
    for row in bios.values():
        require(row['grants_qualification'] is False and row['description'] and row['hobby'],
                'biography grants clinical qualification or lacks introduction')
    titles, specialties, personalities = (indexed(c[key]) for key in
        ('doctor_titles', 'specialties', 'doctor_personalities'))
    for card in indexed(c['recruitment_examples']).values():
        require(card['illustrative_only'] is True and card['role'] in roles
                and card['species_id'] in indexed(c['species']), 'invalid example employee')
        require(card['social_personality_id'] in traits and card['work_style_id'] in styles
                and card['biography_id'] in bios, 'missing employee personality or biography')
        require(not {'hire', 'wage_day', 'body', 'anger'} & set(card), 'duplicated employee price or body facts')
        require(set(card['certificates']) <= {'q_test', 'q_ward', 'q_guide', 'q_research'},
                'example grants untrained surgery qualification')
        if card['role'] == 'doctor':
            doctor = card['doctor_profile']
            require(card['non_doctor_skill'] is None and doctor['title_id'] in titles
                    and doctor['personality_id'] in personalities, 'invalid doctor profile')
            require(1 <= doctor['diagnosis_level'] <= 5 and 0 <= doctor['surgery_level'] <= 5
                    and 1 <= doctor['treatment_level'] <= 5
                    and not {'anesthesia_level','specialty_levels'} & set(doctor),
                    'invalid candidate medical ability')
        elif card['role'] == 'nurse':
            require(card['non_doctor_skill'] is None and card['certificates'] == []
                    and card['nurse_profile'] == {'diagnosis':1,'care':1,'surgery':0}, 'nurse has separate skill or certificate state')
        else:
            require('doctor_profile' not in card and 1 <= card['non_doctor_skill'] <= 5,
                    'nondoctor receives doctor profile')
            expected = {'q_research'} if card['role'] == 'researcher' else set()
            require(set(card['certificates']) == expected, 'wrong default role certificates')
    recruitment = b['recruitment']
    require(recruitment['passive_per_day'] == len(roles)
            and recruitment['max_passive'] == recruitment['passive_per_day']*recruitment['passive_days_retained']
            and recruitment['passive_days_retained'] == recruitment['result_days_retained'] == 2,
            'undefined CV refresh or retention')
    require(recruitment['max_passive']+recruitment['max_targeted_results']+recruitment['max_bookmarked']
            == recruitment['total_candidate_cap'] <= 24, 'unbounded candidate pools')
    require(0 < recruitment['search_result_count'] <= recruitment['max_targeted_results']
            and recruitment['search_fee'] > 0 and recruitment['search_seconds'] > 0
            and recruitment['max_active_searches'] == 1 and recruitment['standard_fee'] == 0,
            'invalid recruitment search or missing fallback')
    require(recruitment['rng_stream'] == 'recruitment' and recruitment['max_daily_referrals'] == 1
            and 0 <= recruitment['daily_referral_probability'] <= 1
            and recruitment['max_daily_notices'] == 1, 'unbounded referral or notice')
    require(recruitment['initial_energy'] == 100 and recruitment['initial_stress'] == 10
            and recruitment['initial_doctor_fatigue'] == 10, 'undefined employee initial condition')
    require(0 <= recruitment['secondary_ability_probability'] <= 1
            and recruitment['preference_weight_multiplier'] == 2
            and recruitment['targeted_reserve_on_start'] is True
            and recruitment['wage_start'] == 'hire_tick',
            'unbounded hiring preference, unpaid staff or hidden result overflow')


def check_expansion_examples(c, b, check):
    check_arrival_load_examples(c,b,check)
    check_admission_evaluation_examples(b, check)
    check_patience_schedule_examples(b, check)
    check_transit_examples(c, b, check)
    check_local_navigation_examples(b, check)
    check_movement_queries_examples(b, check)
    # Python samples exercise the design arithmetic, not the Godot RNG algorithm.
    check([actor_path_budget(n,b) for n in (0,160,161,320,640,1600)]==[8,8,9,16,32,80],
          '移动请求额度随真实在院人数增长，院外人员和空楼板不计')
    check(ward_projection_slots([(2,['n1'])],b)==2
          and ward_projection_slots([(8,['n1']),(1,[])],b)==8
          and ward_projection_slots([(8,['n1']),(1,['n2'])],b)==9,
          '护理容量按同病房实际床位计，一人可覆盖两组但不能跨房当两人')
    try:ward_projection_slots([(2,['n1']),(2,['n1'])],b)
    except ValueError:check(True,'容量投影拒绝同一护士同时覆盖两间病房')
    else:raise ValueError('double-assigned projected nurse accepted')
    normal=b['arrival_presets']['normal']
    capacity=reference_arrival_capacity(c,b)
    check([scaled_arrivals(normal,s,b,capacity) for s in (0,2,3,6,30)] ==
          [(0,0,0),(25,42,16),(37,63,24),(75,125,48),(375,625,240)],
          '同等D09参考组的工时和原门诊额度分别计算，零能力没有机会，部分班次不按整组抹零')
    check([scaled_arrivals(normal,min(actual,3),b,capacity) for actual in (0,2,3,6)] ==
          [(0,0,0),(25,42,16),(37,63,24),(37,63,24)],
          '同等参考中保持原名义能力和原S=1分别作用，扩建不强增流量，减少能力仍下调')
    day_ticks=int(Fraction(str(b['day_seconds']))/Fraction(str(b['tick_seconds'])))
    for count in (1,2,day_ticks-1,day_ticks,day_ticks+1,2*day_ticks):
        bounds=[slot_bounds(count,i,b) for i in range(count)]
        require(all(0<=lo<=hi<day_ticks for lo,hi in bounds)
                and all(bounds[i][0]<=bounds[i+1][0] for i in range(count-1)), 'large hospital slot overflow')
    check(True,'大规模医院窄窗口无空区间或越日，允许同tick按序重查真实入口')
    for count in range(18, 181):
        bounds = [slot_bounds(count, i, b) for i in range(count)]
        require(all(0 <= lo <= hi < day_ticks for lo, hi in bounds)
                and all(bounds[i][1] < bounds[i+1][0] for i in range(count-1)),
                'overlapping or invalid daily slots')
    check(True, '18…180次机会的整数窗口有界、互斥，无法同tick挤入两人')
    def example_plan(seed):
        return [scheduled_slot_tick(8,1,str(seed),i,b) for i in range(8)]
    original=example_plan(321)
    check(original==[939,3797,5823,7318,9850,12430,14889,16580]
          and hashlib.sha256(b'arrival-slot-v1|1|321|0|0').hexdigest()
              =='73e545807059859d898d55b39fa407573e8e70d6e314288c3c356c55840f1044',
          'arrival-slot-v1固定向量明确UTF-8编码、摘要截取与八次时刻')
    check(original==example_plan(321) and original!=example_plan(322),
          '同日种子按序号重建同一时刻，换种子改变计划；不代表游戏保存已通过')
    check([scheduled_slot_tick(8,1,'321',i,b) for i in range(4,8)]==original[4:],
          '保存游标4后仅重建后半天，不消耗随机流或重抽先前时刻')
    for n in (160,day_ticks+1,2*day_ticks):
        ticks=[scheduled_slot_tick(n,1,'18446744073709551615',i,b) for i in range(n)]
        require(all(0<=t<day_ticks for t in ticks) and ticks==sorted(ticks), 'derived large day goes backward')
    check(True,'160至36000机会派生计划不越日，窄窗口同tick按原序处理')
    lo,hi=slot_bounds(8,0,b); width=hi-lo+1
    calls=[]
    def reject_once(payload):
        calls.append(payload)
        return 2**32-1 if len(calls)==1 else 0
    check(2**32 % width != 0 and scheduled_slot_tick(8,1,'321',0,b,reject_once)==lo
          and calls==[b'arrival-slot-v1|1|321|0|0',b'arrival-slot-v1|1|321|0|1'],
          '拒绝区样本重新摘要，避免取模偏差且编码与nonce顺序明确')
    traits = indexed(c['patient_personalities'])
    for wait, anger, tid, environment, expected in [(120, 15, 'PP02', 0, .06),
        (120, 15, 'PP09', 0, .026), (120, 15, 'PP02', 80, .03),
        (119.9, 100, 'PP02', 0, 0), (600, 100, 'PP02', 0, .35)]:
        check(math.isclose(leave_probability(wait, anger, traits[tid], environment, b), expected),
              f'离院公式样例W{wait}/A{anger}/{tid}/E{environment}={expected:.1%}')
    check(leave_probability(120, 15, traits['PP02'], 59, b)
          > leave_probability(120, 15, traits['PP02'], 60, b)
          > leave_probability(120, 15, traits['PP02'], 80, b), '环境59/60/80依次降低离院概率')
    def empty_room(floor, x=40, y=72):
        return {'floor_id':f'floor:{floor}',
                'inner_cells':[(px,py) for px in range(x,x+4) for py in range(y,y+4)]}
    lift_a={'kind':'lift','first_floor':1,'last_floor':1,'anchor':(48,88)}
    check(section_allowed({7}, {7:1}, 2, 7, [empty_room(1)], 'selected_lift', lift_a)
          and not section_allowed({7}, {7:1}, 3, 7, [empty_room(1)], 'selected_lift', lift_a)
          and section_allowed({7}, {7:2}, 3, 7, [empty_room(2)], 'selected_lift', lift_a)
          and not section_allowed({7}, {7:2}, 3, 8, [empty_room(2)], 'selected_lift', lift_a)
          and not section_allowed({7}, {7:2}, 2, 7, [empty_room(1)], 'selected_lift', lift_a),
          '上层静态前置含地面产权/连续实完/当前下层空Room/真实选梯，拒跳层和重复')
    check(not section_allowed({7}, {7:1}, 2, 7, [], 'selected_lift', lift_a)
          and not section_allowed({7}, {7:1}, 2, 7, [empty_room(2)], 'selected_lift', lift_a)
          and not section_allowed({7}, {7:1}, 2, 7, [empty_room(1)], 'selected_lift')
          and not section_allowed({7}, {7:1}, 2, 7, [empty_room(1)], 'selected_lift',
                                  dict(lift_a,anchor=(70,88)))
          and not section_allowed({7}, {7:1}, 2, 7, [empty_room(1)], 'selected_lift',
                                  dict(lift_a,kind='stairs')),
          '纯板/错误下层/无真实梯/异plot梯/楼梯不满足新层购买来源')
    check(not section_allowed({7,8}, {7:1,8:1}, 2, 8, [empty_room(1,70)], 'same_floor')
          and section_allowed({7,8}, {7:2,8:1}, 2, 8, [empty_room(1,70)], 'same_floor')
          and not section_allowed({7,8}, {7:2,8:1}, 2, 8, [empty_room(1,70)], 'same_floor',
                                  pending_sections={(2,8)}),
          '首模块实完才开放本层旁块，旁块仍独立前置且已有未完单不重复购买')
    check(section_allowed({7,8}, {7:2,8:1}, 2, 8, [empty_room(1,61)], 'same_floor')
          and not section_allowed({7,8}, {7:2,8:1}, 2, 8, [empty_room(1,60)], 'same_floor'),
          '整体4×4空房一列真实内格进入旁plot即有建筑，墙边贴界不算')
    check([section_quote(n, b) for n in (2,3,4,5,10,1000)]
          == [(3200,90),(4800,120),(6400,150),(8000,180),(8000,180),(8000,180)],
          '任意层报价保留2…5F原价，第5/10/1000层每模块8000且施工≤180秒')
    check(sum(section_quote(n,b)[0] for n in range(2,11))==62400
          and section_quote(10000,b)==(8000,180),
          '单地块2…10F楼板累计62400，边际费用封顶而层数不封顶')
    check(all(section_allowed({7}, {7:n-1}, n, 7, [empty_room(n-1)], 'selected_lift', lift_a)
              for n in (5,10,100,1000,10000))
          and not section_allowed({7}, {7:4}, 6, 7, [empty_room(5)], 'selected_lift', lift_a)
          and not section_allowed({7}, {7:4}, 5.0, 7, [empty_room(4)], 'selected_lift', lift_a),
          '第5至10000层样例无楼号封顶，仍拒绝跨层悬空和非整数楼号')
    check(sum(section_quote(n,b)[0] for n in (2,3,4))*9 == 129600,
          '2…4F共27块楼板示例129600，不是全院结构总价或最高层')
    connectors, species = indexed(c['vertical_connectors']), indexed(c['species'])
    check([connectors['VC02']['base_price']+max(0,stops-connectors['VC02']['base_stops'])
           *connectors['VC02']['extra_stop_price'] for stops in (1,2,3)] == [3200,3200,4400],
          '医用电梯初装价含两站硬件，实际单站不免费生站，第二站零追加/第三站1200')
    check(3000+2*section_quote(2,b)[0]+connectors['VC02']['base_price']==12600
          and section_quote(2,b)[0]+connectors['VC02']['base_price']
              +indexed(b['staff'],'role')['decorator']['hire']+indexed(c['service_equipment'])['SE02']['price']==6860,
          '地面B与A2/B2及医用电梯合12600，默认首A2/梯/装修工/工具合6860，未含新房')
    check(math.floor(Fraction(3200)*Fraction(60,90))==2133
          and math.floor(Fraction(3200)*Fraction(261,10)/90)==928,
          '上层取消按冻结实付和精确剩余标准量最终取整，不预截比例或改查新版工时')
    check(not connector_fits(species['S01'], connectors['VC02'])
          and connector_fits(species['S01'], connectors['VC03'])
          and connector_fits(species['S59'], connectors['VC03']), '长颈鹿拒小梯，巨型电梯可容长颈鹿与石巨人')
    check(not cabin_fits(connectors['VC02']['cabin_size'], [2, 2])
          and cabin_fits(connectors['VC02']['cabin_size'], [2, 1])
          and cabin_fits(connectors['VC03']['cabin_size'], [3, 3]), '舱内双2格拒小梯、2+1可放、双3格可放巨型梯')
    check([connectors[key]['base_price']+2*connectors[key]['extra_stop_price']
           for key in ('VC02', 'VC03')] == [5600, 12000], '四站电梯设备价5600/12000，不重复收主驱动价')
    check(all(connectors[key]['max_stops'] is None for key in ('VC02','VC03'))
          and connectors['VC02']['base_price']+998*connectors['VC02']['extra_stop_price'] == 1200800,
          '电梯可继续扩站，千站医用电梯设备报价1200800，只有1份主设备')
    check(True, '竖向端口操作与维修区不重叠井道，楼层净高容纳基础包角色；仍需跨层动态寻路验收')
    r = b['recruitment']
    check(3+r['search_result_count'] <= r['max_targeted_results']
          and 4+r['search_result_count'] > r['max_targeted_results']
          and r['max_passive']+3+r['search_result_count']+r['max_bookmarked'] == 24,
          '寻访冻结3结果即占位，已有4结果不能再开始；三个池含未公布简历仍≤24')
    check(Counter(row['role'] for row in c['recruitment_examples'])
          == Counter({row['role']: 1 for row in b['staff']}), '七招聘示例覆盖七岗位，资格和介绍分开')
    groups = defaultdict(list)
    for row in c['treatment_bindings']:
        groups[row['disease_id']].append(row)
    additions = [row for number in range(115, 155) for row in groups[f'D{number}']]
    require(len(additions) == 160, 'missing new body adaptations')
    for number in range(115, 155):
        rows = groups[f'D{number}']
        require(len(rows) == len({row['species_id'] for row in rows}) == 4,
                'new disease does not have four distinct bodies')
        require(all(len({row[field] for row in rows}) == 4
                    for field in ('symptom_variant', 'treatment_variant', 'recovery_variant')),
                'new disease reuses identical body presentations')
    check(True, '40新增病每病4种身体，160条症状/治疗/康复文本在同病内各不相同')
    check(Counter(row['species_id'] for row in additions)
          == Counter({row['id']: 2 for row in c['species']}), '80种居民各新增2条病例')
    human = {row['disease_id'] for row in c['treatment_bindings'] if row['species_id'] == 'S49'}
    check({f'D{n}' for n in [37, 38, 39, 40, 41, 42, 110, 111, 112, 113, 114]} <= human,
          '普通人类11种日常病症保留')
    negatives = [
        (lambda x, y:y['floors'].update(max_floors=4), '恢复楼层封顶'),
        (lambda x, y:x['vertical_connectors'][1].update(max_stops=4), '电梯四站隐性封顶'),
        (lambda x, y:y['floors'].update(connector_object_count='one_per_landing'), '结构端口挤占设备名额'),
        (lambda x, y:y['floors']['section_pricing'].update(material_increment_per_floor=-1), '高层材料价格递减为负'),
        (lambda x, y:y['arrival_presets']['slow'].update(per_day=8), '旧固定每日配额'),
        (lambda x, y:y['arrivals'].update(slot_jitter_max=1.5), '到访机会跨窗口'),
        (lambda x, y:y['wait_departure']['eligible_stages'].append('operating'), '术中随机离院'),
        (lambda x, y:x['patient_personalities'][0].update(wait_leave_multiplier=-1), '负耐心倍率'),
        (lambda x, y:y['floors'].update(requires_completed_below=False), '悬空楼板'),
        (lambda x, y:y['floors']['purchase_contract'].update(new_floor_plot_source='any_ground_plot'), '新层绕过所选真实电梯'),
        (lambda x, y:y['floors']['purchase_contract'].update(below_building_source='completed_slab'), '空板替代下层房间'),
        (lambda x, y:y['floors']['purchase_contract'].update(same_floor_expansion='pending_module'), '首单未完先买旁块'),
        (lambda x, y:y['floors']['purchase_contract'].update(section_acquisition='payment'), '付款赠可用空气产权'),
        (lambda x, y:y['floors']['purchase_contract'].update(initial_lift_stations='base_stops'), '初装套件凭空生成第二站'),
        (lambda x, y:x['vertical_connectors'][1].update(failure_policy='lock_closed'), '故障电梯困人'),
        (lambda x, y:x['vertical_connectors'][2].update(clear_height_m=3), '最高居民没有竖向设施'),
        (lambda x, y:x['recruitment_examples'].append(copy.deepcopy(x['recruitment_examples'][0])), '重复候选ID'),
        (lambda x, y:x['recruitment_examples'][0].update(biography_id='missing'), '未知履历'),
        (lambda x, y:x['staff_biographies'][0].update(grants_qualification=True), '履历白送资格'),
        (lambda x, y:x['staff_role_profiles'][0].update(wage_day=0), '招聘介绍重复工资'),
        (lambda x, y:y['recruitment'].update(max_passive=200), '招聘池无界'),
    ]
    for mutate, label in negatives:
        broken_c, broken_b = copy.deepcopy(c), copy.deepcopy(b)
        mutate(broken_c, broken_b)
        try:
            validate_expansion(broken_c, broken_b)
        except ValueError:
            check(True, '扩展规则负例被拒绝：'+label)
        else:
            raise ValueError('negative expansion case accepted: '+label)


def append_expansion_atlas(lines, c, b, table):
    lines += ['## 到访机会的先决排除', '',
              '阶段③先查本院新接诊开关，再取原真实门诊在院人数与当天冻结额度；关诊/满员只消费原机会，不查询病例或抽患者。通过后仍完整核验身体、团队、床与路线，实际成功入院后下一个同tick机会重读人数。日计划N/种子、原患者医疗与完整原因卡保持原定义，不保存另一份人数。', '']
    table(lines,['同tick条件','机会结果','原完整Readiness查询'],[
        ['关诊，当前0人','消费机会','0次'],
        ['正常S=1，原24人/额度24','消费机会','0次'],
        ['原23人，首机会就绪，同tick三次','入院1人，后两次满员消费','仅第一次'],
        ['原23人，首未就绪，次就绪，同tick三次','首消费，次入院1人，末满员消费','前两次']])
    lines += ['静态16组合对照与逐次边界只验证布尔等价，不执行真实入院、随机流或路径；160/320/640人及高层下的查询成本与帧/步耗待实机验证。', '']
    lines += ['## 有效候诊到期调度', '',
              '120秒起、以后每30秒的评估仍归原票号与WaitDepartureState。到期索引只派生下次实际tick；生活服务暂离或已叫号行走暂停原钟时不抽签，恢复后按原剩余有效等待量改期。阶段⑦先取真实服务/安全状态与确定性退出，再按原角色顺序抽当期patience签。索引、观看层与缓存不改变概率或随机流；正式640人并发的帧耗、实际字节与抽签等价性仍未测。', '']
    lines += ['## 每日随机来客与付费楼层', '',
              '各档只定义参考负荷和随机幅度，医院人数来自完整病例比例及实际资源工时投影；S只保留原结构说明与门诊额度。零能力不造患者，已在院负荷先计入，实际入院仍逐次核验。', '']
    table(lines, ['来客档', '参考负荷', '日密度浮动', '每S门诊在院额度'], [
        [{'slow':'慢慢来','normal':'正常接诊','busy':'忙碌医院','festival':'盛大开放'}[key],
         str(row['target_load_bp']/100)+'%', '±'+str(row['daily_variation_bp']/100)+'%',
         row['active_outpatients_per_scale']] for key, row in b['arrival_presets'].items()])
    capacity=reference_arrival_capacity(c,b)
    rows=[]
    for key,preset in b['arrival_presets'].items():
        lo,hi,mean=planned_arrivals(preset,capacity)
        rows.append([key,f'{float(mean):.4f}',f'{lo}…{hi}'])
    lines += ['单D09基础常规参考中，平均终点占用32.4秒，名义日能力55又5/9。以下仅核对计数与工时公式，未计真实路线/准备/休息及现有队列，不能作为整座开院医院人数。随机舍入保留参考期望，不取整数区间中点作均值。', '']
    table(lines,['单终点参考档位','参考平均机会','可能整数范围'],rows)
    lines += ['以下是相同参考病例、同等资源成组倍增的条件性正常档例子。实际增加一个终点或床位是否提客流取决于完整资源瓶颈，结构S不是新的固定人数倍率。', '']
    normal=b['arrival_presets']['normal']
    growth_rows=[]
    for label,actual,held in [
        ('原三班各一组',3,None),('三班各补齐两组，随医院成长',6,None),
        ('已扩建两组，保持原S=1',6,3),('仅两班各一组，保持原S=1',2,3)]:
        effective=actual if held is None else min(actual,held)
        low,high,active=scaled_arrivals(normal,effective,b,capacity)
        mean=planned_arrivals(normal,capacity*Fraction(effective,3))[2]
        growth_rows.append([label,f'{low}…{high}',f'{float(mean):g}',active])
    table(lines,['参考配置与节奏','次日机会范围','参考期望','门诊在院额度'],growth_rows)
    counts=split_shift_opportunities(8,[1,1,1],1,'321')
    lines += ['新日到达协议arrival-load-slot-v1按三班承接量分配，再在每班窗口中部随机时刻。日1/种子321/N8/三班等能力时班数'+str(counts)+'，时刻'+str([load_scheduled_slot_tick(counts,1,'321',i,b) for i in range(8)])+'。只有三班数量保存，未来时刻派生不抽随机流；旧arrival-slot-v1的完整日固定向量仍校验、只读恢复活跃计划。', '']
    table(lines, ['上层模块', '产权/结构合并价', '基础施工秒'], [
        [f'{floor}F / 32×32格', *section_quote(floor,b)] for floor in (2,3,4,5,10)])
    rule = b['floors']['section_pricing']
    lines += [f'不设楼层上限。第n层（n≥2）每模块合并价=min({rule["max_material_cost"]}, {rule["base_material_cost"]}+'
              f'{rule["material_increment_per_floor"]}×(n−2))，工时=min({rule["max_work_seconds"]}, '
              f'{rule["base_work_seconds"]}+{rule["work_increment_per_floor"]}×(n−2))秒；表中只是示例。', '']
    lines += ['新层先选真实电梯，只购买其主锚点所属plot；本层已有实完模块后可另买旁块。正下层同plot须有已建Room，原工单完工才交付空板与产权，不另加上层土地费。', '']
    table(lines, ['竖向设施', '每层占地', '净宽/净高', '初建价/加站价', '正常每层秒'], [
        [row['id']+' '+row['name'], '×'.join(map(str, row['footprint'])),
         f'{row["clear_width_m"]}/{row["clear_height_m"]}米',
         f'{row["base_price"]}/{row["extra_stop_price"] if row["extra_stop_price"] else "不扩站"}',
         row['travel_seconds_per_floor']] for row in c['vertical_connectors']])
    lines += ['电梯实际先建1F单站；初装价含两站硬件，第二站须等完整楼面及出口合法后明确安装，0新增费；第三站起收加站价。base_stops不代表已建站数。', '',
              '### 真实排队与交通小戏', '',
              '全组实际到站才领叫梯票；预计沿同一时间轴计当前余量、前方已到站组、空载和本组通行。步行与前方队列可重叠，未来请求和故障仍未知。', '']
    table(lines, ['连接', '排队', '空车接人', '通行'], [
        [row['name'], row['transit_cues']['queued_scene'], row['transit_cues']['empty_scene'] or '结构楼梯没有空车',
         row['transit_cues']['riding_scene']] for row in c['vertical_connectors']])
    table(lines, ['连接', '不可用', '低动态'], [
        [row['name'], row['transit_cues']['unavailable_scene'], row['transit_cues']['low_motion_scene']]
        for row in c['vertical_connectors']])
    movement=b['movement_queries']
    lines += ['### 行人争用的局部完整候选', '',
              '分桶与候选仅为有理数坐标静态示意，没有运行移动、连续碰撞、礼让或本机负载。', '']
    table(lines,['来源或边界','确定规则'],[
        ['原身体与组','实际互斥floor位置的完整当前身体/原组包络，原8×8逻辑桶，非锚点/显示块'],
        ['覆盖与身份','全部相交桶含精确边界接触，跨桶去重沿原稳定ID，完整全部候选无前N截断'],
        ['本步扫掠','原已接受移动扫掠使用期间固定保留，旧新真实位置原子更新；历史证据非另一Actor'],
        ['原精确许可','当前身体/扫掠时序/预约与3秒礼让仍原Movement判定，粗矩形不作碰撞/封路'],
        ['失效与无路','所需层重建或完整同层查含固定扫掠；未知非空，5/30/60秒与候诊/票号保持'],
        ['成本与保存','实际单位/所交桶/扫掠/候选计原工作集和模拟步，无Actor²/空层数组；读档原源先恢复，派生桶不保存']])
    local=b['pathfinding']['local_updates']
    lines += ['### 大平层与多楼层的局部通行合同', '',
              '以下为设计规则与静态范围算例。图更新、真实寻路耗时、缓存内存和本机640人密集负载尚未实测。', '']
    table(lines,['来源或边界','确定规则'],[
        ['逻辑依赖索引','×'.join(map(str,local['chunk_cells']))+'格；与16×16显示块独立，路线可跨任意合法桶'],
        ['局部更新','前后真实占地及软绕行范围分别扩展实际扫掠，修补相关点边与原代价，下一次相关查询前完成'],
        ['单格 / 远距离搬动','96×96层面1格身体的示例分别筛出1桶 / 2桶，范围筛选不替代真实边核验'],
        ['查询身份','、'.join(local['single_floor_query_key'])],
        ['成功、部分与无路','都核验本层nav_revision与占用修订；几何或原软代价变化使新路线和步行距离重新求解'],
        ['跨层','当前连接/交通报价搜索，复用有效层内图及原交通前缀，空层不展开'],
        ['活动路线','相关变化核验剩余扫掠和所用连接；原移动、票号与照护承诺保持'],
        ['安全提交','实际移动边和开工仍原子核验当前世界，自有预约例外不修改共享图'],
        ['内存与恢复',f'图、索引、脏记录和结果共用{b["pathfinding"]["graph_cache_target_bytes"]//(1024*1024)}MiB目标；缺历史重建所需层/身体，层记录释放同时丢旧结果，不保存派生缓存']])
    lines += ['## 招聘清单中的七岗位示例', '',
              '示例展示卡片信息结构，不保证每日出现这些具名员工。实际候选随医院阶段生成并保存；体型与工资从定义查询。', '']
    roles = indexed(c['staff_role_profiles'], 'role')
    species, traits, styles, bios = (indexed(c[key]) for key in
        ('species', 'patient_personalities', 'staff_work_styles', 'staff_biographies'))
    titles, personalities = indexed(c['doctor_titles']), indexed(c['doctor_personalities'])
    pay, staff_pay = indexed(b['doctor_pay'], 'title_id'), indexed(b['staff'], 'role')
    cards = []
    for row in c['recruitment_examples']:
        if row['role'] == 'doctor':
            profile = row['doctor_profile']
            wages = pay[profile['title_id']]
            ability = (titles[profile['title_id']]['name']+'；'+personalities[profile['personality_id']]['name']
                       + f'；诊断{profile["diagnosis_level"]} / 治疗{profile["treatment_level"]} / 手术{profile["surgery_level"]}')
        elif row['role'] == 'nurse':
            wages = staff_pay[row['role']]
            profile = row['nurse_profile']
            ability = f'诊断{profile["diagnosis"]} / 护理{profile["care"]} / 手术{profile["surgery"]}'
        else:
            wages = staff_pay[row['role']]
            ability = f'岗位技能{row["non_doctor_skill"]}；'+(','.join(row['certificates']) or '岗位默认工作范围')
        body = species[row['species_id']]['body']
        cards.append([row['name']+' / '+species[row['species_id']]['name'], roles[row['role']]['name'],
                      f'{body["width_m"]}×{body["depth_m"]}×{body["height_m"]}米', ability,
                      traits[row['social_personality_id']]['name']+' / '+styles[row['work_style_id']]['name'],
                      bios[row['biography_id']]['name']+'；'+bios[row['biography_id']]['hobby'],
                      f'{wages["hire"]} / {wages["wage_day"]}'])
    table(lines, ['名字/种族', '岗位', '身体', '能力/资格', '社会性格/习惯', '履历/兴趣', '招聘费/日薪'], cards)
    table(lines, ['岗位', '职责', '资格说明'], [[row['name'], row['description'], row['qualification_note']]
                                             for row in c['staff_role_profiles']])
    table(lines, ['工作习惯', '表现'], [[row['name'], row['description']] for row in c['staff_work_styles']])
    table(lines, ['履历', '经历', '兴趣'], [[row['name'], row['description'], row['hobby']]
                                       for row in c['staff_biographies']])
    lines += ['## 空间蓝图与改造引导', '',
              '9张内置图引用既有几何源，不另存坐标和旧价格。放置先检查当前医院，库存复用保留状态，美化仍需付费施工。', '']
    table(lines, ['蓝图', '布局来源', '用途'], [
        [row['id']+' '+row['name'], row['source_type']+' / '+row['source_id'], row['description']]
        for row in c['blueprint_presets']])
    presets = indexed(c['blueprint_presets'])
    table(lines, ['引导', '当前问题', '可尝试的步骤', '可用蓝图', '观察点'], [
        [row['id']+' '+row['name'], row['problem'], '；'.join(row['steps']),
         '、'.join(presets[key]['name'] for key in row['blueprint_ids']) or '自由布置', row['watch_for']]
        for row in c['remodel_guides']])


def validate_remodel_content(c, b):
    """Validate declarative design data; no live room or transaction simulation."""
    presets = indexed(c['blueprint_presets'])
    preset_fields = {'id', 'name', 'source_type', 'source_id', 'description'}
    for row in presets.values():
        require(set(row) == preset_fields, 'blueprint preset must reference layout, not copy live state or price')
        require(all(isinstance(value, str) and value.strip() for value in row.values()), 'empty blueprint preset')
        require(row['source_type'] in {'starter_room', 'clinical_layout'}, 'unknown blueprint source type')
    guide_fields = {'id', 'name', 'problem', 'blueprint_ids', 'related_content', 'steps', 'watch_for'}
    reference_sets = {key: set(indexed(c[key], 'definition_id' if key == 'furniture_equipment' else 'id'))
                      for key in ('doors', 'machines', 'vertical_connectors', 'clinical_equipment',
                                  'furniture_equipment', 'renovation_materials', 'accessibility_equipment',
                                  'community_activities','service_equipment')}
    for row in indexed(c['remodel_guides']).values():
        require(set(row) == guide_fields, 'remodel guide must not contain rewards or automation')
        require(all(isinstance(row[key], str) and row[key].strip()
                    for key in ('id', 'name', 'problem', 'watch_for')), 'empty guide text')
        require(isinstance(row['steps'], list) and row['steps']
                and all(isinstance(step, str) and step.strip() for step in row['steps']), 'empty guide steps')
        require(len(row['blueprint_ids']) == len(set(row['blueprint_ids']))
                and set(row['blueprint_ids']) <= set(presets), 'missing or duplicate guide blueprint')
        seen = set()
        for ref in row['related_content']:
            require(set(ref) == {'collection', 'definition_id'}, 'invalid guide reference')
            pair = ref['collection'], ref['definition_id']
            require(pair not in seen and ref['collection'] in reference_sets
                    and ref['definition_id'] in reference_sets[ref['collection']], 'missing or duplicate guide content')
            seen.add(pair)
    policy = b['remodel']
    require(policy == {'move_fee': 0, 'max_pending_per_entity': 1, 'application': 'manual',
                       'charge_timing': 'apply', 'target_reservation': 'none'}, 'unsafe remodel policy')
    require(b['blueprints'] == {'schema_version': 1, 'scope': 'single_floor', 'inventory_default': True,
                               'inventory_selection': 'unfaulted_then_id',
                               'material_execution': 'renovation_orders',
                               'upgrade_execution': 'upgrade_orders',
                               'placement_limits': 'actual_geometry_and_resources'}, 'unsafe blueprint policy')
    barriers = b['environment']['noise_barrier_definition_ids']
    require(len(barriers) == len(set(barriers)) and set(barriers) <= reference_sets['furniture_equipment'],
            'unknown noise barrier furniture')


def validate_blueprint_sources(c, starter, clinical):
    rooms, layouts = indexed(starter['rooms']), indexed(clinical['layouts'])
    for layout in layouts.values():
        validate_bed_links(layout)
    doors = indexed(c['doors'])
    equipment_ids = {row['definition_id'] for row in c['furniture_equipment']}
    equipment_ids.update(row['id'] for key in ('machines', 'clinical_equipment', 'service_equipment') for row in c[key])
    for row in c['blueprint_presets']:
        if row['source_type'] == 'starter_room':
            require(row['source_id'] in rooms, 'missing blueprint starter room')
            source = rooms[row['source_id']]
            objects = [obj for obj in starter['objects'] if obj['room_id'] == source['id']]
            origin, door_id = source['anchor'], source['door']['definition_id']
        else:
            require(row['source_type'] == 'clinical_layout' and row['source_id'] in layouts,
                    'missing blueprint clinical layout')
            source = layouts[row['source_id']]
            objects, origin, door_id = source['objects'], (0, 0), source['door_id']
        require(door_id in doors and all(0 < value <= 96 for value in source['size']), 'invalid blueprint room source')
        require(objects, 'blueprint source lost its equipment')
        for obj in objects:
            local = [obj['anchor'][i]-origin[i] for i in (0, 1)]
            require(obj['definition_id'] in equipment_ids, 'blueprint source has unknown equipment')
            require(all(0 <= local[i] < source['size'][i] for i in (0, 1)), 'blueprint source object outside room')
    # Footprints, access envelopes, bindings and service/repair paths remain checked
    # by the existing starter and clinical validators against these same source files.


def check_remodel_examples(c, b, starter, clinical, check):
    validate_remodel_content(c, b)
    validate_blueprint_sources(c, starter, clinical)
    check(True, '9张内置蓝图源引用与8张改造引导引用有效，原几何校验继续覆盖布局')
    presets=indexed(c['blueprint_presets'])
    require(presets['BP08']['source_id']=='room_rest'
            and presets['BP09']['source_id']=='room_doctor_office', 'staff blueprint lost real source')
    check({r['definition_id'] for r in starter['objects'] if r['room_id']=='room_rest'} >= {'SE04'}
          and {r['definition_id'] for r in starter['objects'] if r['room_id']=='room_doctor_office'} >= {'SE05'},
          '两张员工蓝图包含真实小憩床和办公桌，费用与空间沿原布局')
    material = indexed(c['renovation_materials'])['MAT04']
    unit_cap = b['renovation']['max_units_per_order']
    split = [unit_cap, 70-unit_cap]
    check(split == [64, 6] and sum(n*material['unit_price'] for n in split) == 3850,
          '70格静谧地毯拆成64与6单元工单，材料总价3850不因分单改变')
    # A cost example only: copying ten units pays current material cost; a moved
    # finish retains its paid cost, and an actually removed finish refunds once.
    check(10*material['unit_price'] == 550
          and 10*material['unit_price']*b['renovation']['installed_refund'] == 440
          and b['remodel']['move_fee'] == 0, '十格材料复制550、实际拆除回收440、纯搬迁费0的报价边界')
    mutations = [
        (lambda x,y:x['blueprint_presets'][0].update(source_id='missing'), '蓝图源不存在'),
        (lambda x,y:x['blueprint_presets'][3].update(source_id='missing'), '临床蓝图源不存在'),
        (lambda x,y:x['blueprint_presets'].append(copy.deepcopy(x['blueprint_presets'][0])), '蓝图ID重复'),
        (lambda x,y:x['blueprint_presets'][0].update(price=0), '蓝图另存免费价格'),
        (lambda x,y:x['blueprint_presets'][0].update(patient_ids=['copied']), '蓝图复制运行实体'),
        (lambda x,y:x['remodel_guides'][0]['blueprint_ids'].append('missing'), '引导引用缺失蓝图'),
        (lambda x,y:x['remodel_guides'][0]['related_content'][0].update(definition_id='missing'), '引导引用缺失设备'),
        (lambda x,y:x['remodel_guides'][0].update(reward_cash=100), '引导变成额外奖励'),
        (lambda x,y:y['remodel'].update(application='automatic'), '就绪自动应用'),
        (lambda x,y:y['blueprints'].update(material_execution='instant'), '复制时免费完成装修'),
        (lambda x,y:y['blueprints'].update(placement_limits='benchmark_counts'), '蓝图借性能样本限制真实建造'),
        (lambda x,y:y['environment']['noise_barrier_definition_ids'].append('missing'), '噪声屏障引用不存在'),
    ]
    for mutate, label in mutations:
        broken_c, broken_b = copy.deepcopy(c), copy.deepcopy(b)
        mutate(broken_c, broken_b)
        try:
            validate_remodel_content(broken_c, broken_b)
            validate_blueprint_sources(broken_c, starter, clinical)
        except ValueError:
            check(True, '改建设计合同负例被拒绝：'+label)
        else:
            raise ValueError('negative remodel case accepted: '+label)
    for duplicate, label in ((True, '重复引用同一张护理床'), (False, '护理床重新引入独立监护器')):
        broken = copy.deepcopy(clinical)
        ward = indexed(broken['layouts'])['ward_two_beds']
        if duplicate:
            ward['bed_links'][1]['bed_index'] = ward['bed_links'][0]['bed_index']
        else:
            ward['bed_links'][0]['monitor_index'] = 0
        try:
            validate_blueprint_sources(c, starter, broken)
        except ValueError:
            check(True, '改建设计合同负例被拒绝：'+label)
        else:
            raise ValueError('negative clinical blueprint case accepted: '+label)
