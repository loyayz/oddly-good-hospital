"""Static product contracts for everyday operation; no game runtime is exercised."""
import copy
from validate_clinical import indexed, require


def validate_operations(c, b):
    validate_save_growth(b)
    validate_audio_resources(b)
    validate_dialogue_presentation(b)
    require(b['audio_presentation']=={
        'facility_voices':6,'actor_reaction_voices':6,'ui_voices':2,'music_voices':2,
        'scope':'current_floor_camera_audible_sources','priority':'observed_then_relevant_event_then_distance_then_id',
        'late_oneshots':'omit_without_replay','game_speed_changes_pitch':False,
        'audio_changes_environment':False,'necessary_information':'independent_visual_state'},
        'audio budget adds hidden simulation limits or replays past events')
    require(b['ui_lists'] == {
        'materialization':'visible_rows_with_bounded_overscan','overscan_viewports_each_side':1,
        'portrait_mode':'shared_static_thumbnail','updates':'coalesced_domain_changes',
        'command_target':'captured_entity_id_revalidated','reorder_during_input':False,
        'late_results':'discard_wrong_hospital_panel_or_query_generation','world_effects':False},
        'list virtualization changes selection or eagerly creates full scenes')
    require(b['operating_notices'] == {'ongoing_reason':'update_existing_card','toasts_per_reason_episode':2,
            'second_toast':'first_material_escalation','replay_loaded_problems':False,
            'deferred_queue':'current_highest_still_valid_only','critical_error_uses_ordinary_quota':False}, 'notices replay or hide actionable errors')
    require(b['ui_input'] == {'text_focus_suppresses_scene_shortcuts':True,'ime_confirmation_passes_through':False,
            'grid_step_cells':1,'grid_fast_step_cells':5,'held_key_repeats_purchase':False,
            'return_focus':'invoker_or_parent','clear_held_keys_on_session_change':True}, 'input causes accidental world commands')
    views = indexed(c['finance_views'])
    require(b['operating_settlement'] == {
        'owner':'EconomyState.daily_accumulators.operating_numerator',
        'accrual':'current_rate_per_simulation_tick',
        'settlement':'floor_daily_carry_remainder',
        'commit':'original_daily_settlement_transaction',
        'payer_affects_accrual':False}
        and b['operating_settlement']['payer_affects_accrual'] is False,
        'operating costs lose exact accrual, carry or original settlement ownership')
    expected = {
        'clinical': {'gp', 'facility', 'cure'},
        'operation': {'wages', 'operations', 'consumables', 'maintenance'},
        'development': {'construction', 'land', 'recruitment', 'training', 'research',
                        'search', 'upgrade', 'department_focus', 'renovation'},
        'grant': {'subsidy', 'task_reward'}, 'refund': {'refund'},
        'direct_support': {'community_aid', 'creative_fund'}}
    require({r['group'] for r in views.values()} == set(expected), 'missing finance view')
    require(len(views) == len(expected), 'duplicate finance group')
    for row in views.values():
        require(set(row) == {'id', 'name', 'group', 'sources', 'description'}, 'finance view cannot own money')
        require(set(row['sources']) == expected[row['group']]
                and len(row['sources']) == len(set(row['sources'])), 'finance source counted in wrong group')
    require({k:v for k,v in b['finance_review'].items() if k != 'forecast_query'} == {'closing_days': 3, 'reference_settled_days': 3,
            'saving_notes': 1, 'note_characters': 40, 'reserve_cash': False,
            'forecast_income': 'known_grants_only'}, 'unsafe finance forecast')
    require(b['finance_review']['forecast_query'] == {
        'scope':'visible_three_closing_days',
        'invalidation':'relevant_financial_changes_and_day_boundary',
        'same_day_fixed_costs':'reuse_only_proven_unchanged_per_owner_settlement',
        'source':'original_current_owners_and_exact_per_employee_rounding',
        'hidden':'cancel_projection_queries_only',
        'publication':'existing_hospital_panel_query_generation',
        'unknown_dependencies':'original_complete_visible_query',
        'world_effects':False}, 'finance projection freezes actual accounting or loses dependencies')
    validate_task_guides(c, b)
    validate_staff_practice(c, b)
    validate_amenities(c, b)
    validate_onboarding(c, b)



def validate_dialogue_presentation(b):
    require(b['dialogue_presentation'] == {
        'medium':'text_only_no_voice_or_speech_like_audio',
        'clinical_source':'actual_started_medical_communication_of_focused_case',
        'placement':'current_case_inspection_panel','default_on':True,
        'visible_cards':1,'max_lines':2,'minimum_read_real_seconds':4,
        'world_bubbles':False,'nonclinical_lines':False,
        'decorative_language':'pictograms','calling_lines':False,
        'focus_change':'discard_old_card_and_query_current',
        'late_lines':'omit_no_backlog','writes_world_state':False,
        'blocks_work_or_input':False},
        'dialogue creates voices, calling language, crowd text or extra medical work')
    require(b['quiet_calling']['audio_announcement'] is False
            and b['quiet_calling']['requires_confirmation'] is False,
            'text presentation reintroduces spoken or manually acknowledged calling')


def validate_save_growth(b):
    s=b['save']; fmt=s['backup_format']; budget=s['resource_budget']
    require(s['sqlite']=={
        'version':'3.54.0','scope':'independent_database_per_hospital','file':'hospital.sqlite3',
        'application_id':0x4F474853,'database_schema_version':1,'world_schema_version':1,
        'journal_mode':'DELETE','synchronous':'EXTRA','foreign_keys':True,
        'world_chunk_bytes':32768,'page_cache_kib':4096,'write_mode':'single_background_transaction',
        'simulation_reads':'in_memory_world_only','commit':'validate_seal_commit_reopen',
        'legacy_import':'validated_complete_json_commits_transactional_source_preserved',
        'cleanup':'separate_transaction_after_success_no_daily_vacuum'},
        'SQLite storage loses hospital isolation, exact world DTOs or atomic recovery')
    require(s['user_directory_guard']=={
        'scope':'persistent_profile_in_actual_user_directory',
        'primitive':'windows_exclusive_noninheritable_file_handle',
        'path':'user://.session.guard',
        'acquire_before':'profile_load_cleanup_and_writes',
        'lifetime':'app_root_until_all_profile_io_stopped',
        'busy':'startup_manual_retry_or_exit',
        'authority':'live_handle_not_marker_or_pid',
        'logging':'engine_file_logging_disabled_product_logs_after_acquire',
        'engine_cache':'separate_rebuildable_data_not_ownership',
        'uninstall':'same_guard_delete_content_keep_empty_guard_and_root',
        'snapshot_state':False},
        'profile ownership permits concurrent writes or unlocks before all IO stops')
    require(s['hospital_switch']=={
        'scope':'switch_to_another_hospital',
        'source_retention':'paused_world_and_draft_until_target_activation',
        'target_ready':'full_world_validation_required_indexes_occupancy_and_initial_view',
        'candidate_simulation':'inactive_no_ticks_commands_or_random_draws',
        'publication':'same_main_thread_boundary_world_session_input_and_view',
        'operation_guard':'original_current_leave_operation_and_source_session',
        'failure_or_cancel':'discard_candidate_keep_source_paused',
        'resource_accounting':'all_live_source_candidate_save_and_display_allocations',
        'source_release':'after_successful_swap_and_actual_unbinding'},
        'hospital switch destroys the source before validated target publication')
    require(s['browser']=={'summary_fields':['display_name','mode','present_actor_count'],
        'summary_source':'same_frozen_world_dto','list_reads':'sqlite_sealed_manifest_index',
        'world_reads':'selected_snapshot_full_validation','cache':'rebuildable_hospital_snapshot_sequence',
        'thumbnail_max_dimensions':[640,360],'thumbnail_optional':True},
        'hospital browser loads all worlds or trusts decorative thumbnails')
    require(s['size_policy']=='available_resources_no_fixed_world_size_cap'
            and 'max_snapshot_bytes' not in s and 'max_backup_bytes' not in s,
            'save size blocks hospital growth')
    require(fmt=={'entries':['manifest.json','hospital.sqlite3','thumbnail.png'],
            'optional_entry':'thumbnail.png','manifest_max_bytes':65536,'thumbnail_max_bytes':262144,
            'max_entries':3,'max_expansion_ratio':200,'json_max_depth':64,'json_max_string_bytes':65536,
            'read_mode':'stream_to_private_staging','export_compression':'store_if_ratio_exceeds_guard',
            'database_manifest_fields':['database_bytes','database_sha256']},
            'large backup loses bounded metadata or path guards')
    require(budget=={'world_memory_factor':4,'memory_headroom_bytes':67108864,
            'free_memory_fraction':0.5,'staging_disk_world_factor':3,'disk_headroom_bytes':67108864,
            'enforcement':'before_and_during','on_shortage':'keep_current_and_previous_commits'},
            'large backup skips actual resource checks')


def save_growth_budget(world_bytes, b):
    require(type(world_bytes) is int and world_bytes>=0, 'invalid snapshot byte count')
    p=b['save']['resource_budget']
    return (p['world_memory_factor']*world_bytes+p['memory_headroom_bytes'],
            p['staging_disk_world_factor']*world_bytes+p['disk_headroom_bytes'])


def validate_audio_resources(b):
    expected={
        'budget_source':'audio_presentation',
        'count_source':'actual_parallel_playbacks_including_substreams_fading_and_pending_stop',
        'player_scope':'bounded_original_audio_pools_not_per_entity_or_floor',
        'scene_slot_polyphony':1,
        'facility_layers':'offline_premixed_current_stage_clip_one_actual_stream_per_slot',
        'hidden_parallel_substreams':False,'crossfade':'all_old_and_new_playbacks_count_before_admission',
        'release_accounting':'after_actual_playback_stop_pending_resources_still_accounted',
        'release':'explicit_stop_and_unbind_not_wait_for_finished',
        'scene_slot_key':['hospital_session','view_id','view_generation','floor_id','pool_kind','slot_index',
                          'slot_generation','source_entity_id','source_binding_key','clip_resource','content_fingerprint'],
        'late_clip':'oneshot_omit_loop_requery_current_original_stage_after_binding_check',
        'slot_reuse':'stop_old_actual_playback_then_unbind_before_current_attach',
        'muted_scene_categories':'stop_decoder_and_admission_no_oneshot_backlog',
        'unmute_scene':'current_legal_loops_only_no_missed_state_replay',
        'micro_preview':'reuse_original_scene_audio_no_second_pool',
        'clip_assets':'immutable_shared_by_content_fingerprint_and_resource_id',
        'playback_state':'private_slot_cursor_parameters_and_decode_buffers',
        'memory_scope':'original_working_set_encoded_decode_buffers_idle_loading_and_pending_release',
        'graphics_memory_includes_audio_pcm':False,
        'codec_validation':'actual_imported_format_and_runtime_decode_cost_not_file_size_only',
        'scene_nodes_per_actor':False,'snapshot_state':False,'business_writes_from_audio':False,
        'business_random_used':False,'runtime_measurement_available':False}
    row=b['audio_resources']
    require(set(row)==set(expected) and all(type(row[key]) is type(value) and row[key]==value
            for key,value in expected.items()), 'audio resource contract hides real streams or writes gameplay')


def audio_stream_counts_example(rows, b):
    # Declared static playback/substream counts only, never queries AudioServer or decodes a clip.
    counts={key:0 for key in ('facility_voices','actor_reaction_voices','ui_voices','music_voices')}
    seen=set()
    for row in rows:
        require(row['kind'] in counts and row['state'] in ('playing','fading','pending_stop','stopped')
                and type(row['parallel_streams']) is int and row['parallel_streams']>0
                and type(row['playback_id']) is str and row['playback_id'] and row['playback_id'] not in seen,
                'invalid or duplicate declared audio playback')
        seen.add(row['playback_id'])
        if row['state']!='stopped':counts[row['kind']]+=row['parallel_streams']
    fits=all(counts[key]<=b['audio_presentation'][key] for key in counts)
    return counts,fits


def audio_slot_matches_example(first, second, b):
    keys=b['audio_resources']['scene_slot_key']
    return (isinstance(first,dict) and isinstance(second,dict) and all(key in first and key in second for key in keys)
            and all(first[key]==second[key] for key in keys))


def check_audio_resources_examples(b, check):
    rows=[{'kind':'facility_voices','state':'playing','parallel_streams':1,'playback_id':f'facility:{i}'} for i in range(6)]
    counts,fits=audio_stream_counts_example(rows,b)
    check(counts['facility_voices']==6 and fits, '原6设施实际单流符合预算，不把六台业务机器当接诊上限')
    layered=copy.deepcopy(rows)
    for row in layered:row['parallel_streams']=3
    counts,fits=audio_stream_counts_example(layered,b)
    check(counts['facility_voices']==18 and not fits, '六逻辑源各三子流实际18，不用六节点隐藏解码')
    fading=copy.deepcopy(rows); fading[-1]['state']='fading'
    fading.append({'kind':'facility_voices','state':'playing','parallel_streams':1,'playback_id':'facility:new'})
    counts,fits=audio_stream_counts_example(fading,b)
    check(counts['facility_voices']==7 and not fits, '5当前加1淡出加1新流为7，过渡也计原设施预算')
    pending=copy.deepcopy(fading); pending[-2]['state']='pending_stop'
    stopped=copy.deepcopy(pending); stopped[-2]['state']='stopped'
    check(not audio_stream_counts_example(pending,b)[1] and audio_stream_counts_example(stopped,b)[1],
          '发stop但未实际停止仍计流，停止后名额释放；未释放字节另计不在算例中伪测')
    music=[{'kind':'music_voices','state':'fading' if i==0 else 'playing','parallel_streams':1,'playback_id':f'music:{i}'} for i in range(2)]
    check(audio_stream_counts_example(music,b)[1]
          and not audio_stream_counts_example(music+[{'kind':'music_voices','state':'pending_stop','parallel_streams':1,'playback_id':'music:old'}],b)[1],
          '原音乐双轨交叉淡入已占2，第三条待停仍超预算')
    binding={'hospital_session':'hospital:1','view_id':'main','view_generation':3,'floor_id':'floor:1',
        'pool_kind':'facility_voices','slot_index':2,'slot_generation':8,'source_entity_id':'machine:7',
        'source_binding_key':('service:19','working'),'clip_resource':'machine:loop','content_fingerprint':'core:1'}
    check(audio_slot_matches_example(binding,copy.deepcopy(binding),b), '同当前场景槽完整身份可绑定，静态守卫未播放声音')
    for key in b['audio_resources']['scene_slot_key']:
        changed=copy.deepcopy(binding); changed[key]=('different',key)
        check(not audio_slot_matches_example(binding,changed,b), '音频旧结果不能跨错误槽/源身份：'+key)
    check(not audio_slot_matches_example(binding,None,b) and not audio_slot_matches_example(binding,{},b),
          '缺场景绑定不能收到迟到声音或完成回调')
    check(44100*1*1*2==88200 and 48000*2*6*2==1152000,
          'PCM16声明原始88200/1152000字节仅算术，非Ogg解码/真实驻留证明')
    for row,label in [({'kind':'facility_voices','state':'playing','parallel_streams':0,'playback_id':'bad'},'零子流'),
                      ({'kind':'facility_voices','state':'playing','parallel_streams':True,'playback_id':'bad'},'布尔子流'),
                      ({'kind':'speech','state':'playing','parallel_streams':1,'playback_id':'bad'},'虚构对白池')]:
        try:audio_stream_counts_example([row],b)
        except ValueError:check(True,'非法音频声明被拒绝：'+label)
        else:raise ValueError('invalid audio stream declaration accepted '+label)
    try:audio_stream_counts_example(rows+[copy.deepcopy(rows[0])],b)
    except ValueError:check(True,'同一声明playback重复计账被拒绝')
    else:raise ValueError('duplicate audio playback accepted')
    for mutate,label in [
        (lambda row:row.update(count_source='logical_node_count'),'节点数掩盖复音'),
        (lambda row:row.update(player_scope='one_player_per_actor_per_floor'),'全院播放器'),
        (lambda row:row.update(scene_slot_polyphony=8),'场景槽藏8路'),
        (lambda row:row.update(hidden_parallel_substreams=True),'复合子流不计账'),
        (lambda row:row.update(release_accounting='free_on_stop_request'),'待停流提前免费'),
        (lambda row:row.update(release='wait_for_finished_only'),'stop不回调泄露名额'),
        (lambda row:row.update(late_clip='replay_loaded_oneshots'),'补播旧高潮'),
        (lambda row:row.update(muted_scene_categories='gain_zero_keep_decoding'),'静音仍全解码'),
        (lambda row:row.update(micro_preview='second_audio_pool'),'微观重复现场声'),
        (lambda row:row.update(clip_assets='mutable_shared_cursor'),'串改共享片段'),
        (lambda row:row.update(graphics_memory_includes_audio_pcm=True),'PCM重复加GPU预算'),
        (lambda row:row.update(snapshot_state=True),'声音游标写世界'),
        (lambda row:row.update(business_writes_from_audio=True),'声音结束结算医疗'),
        (lambda row:row.update(business_random_used=True),'声源选择抽业务随机'),
        (lambda row:row.update(runtime_measurement_available=True),'纸面名额冒充实际解码')]:
        invalid=copy.deepcopy(b); mutate(invalid['audio_resources'])
        try:validate_audio_resources(invalid)
        except ValueError:check(True,'音频资源合同负例被拒绝：'+label)
        else:raise ValueError('invalid audio resource contract accepted '+label)


def check_operations_examples(c, b, check):
    check_audio_resources_examples(b,check)
    check_task_examples(c, b, check)
    check_staff_examples(c, b, check)
    check_amenity_examples(c, b, check)
    check_onboarding_examples(c, b, check)
    mib=1024*1024
    check(save_growth_budget(64*mib,b)==(320*mib,256*mib)
          and save_growth_budget(128*mib,b)==(576*mib,448*mib),
          '64和128MiB世界按实际资源预算检查，不受旧32MiB门槛拦截')
    check(320*mib<=2*1024*mib*b['save']['resource_budget']['free_memory_fraction']
          and 576*mib>1024*mib*b['save']['resource_budget']['free_memory_fraction'],
          '相同规则按实际可用内存允许或拒绝，未冒充运行时内存测量')
    check(len(c['finance_views']) == 6, '六张财务账页覆盖实际账目且展示不拥有余额')
    check(len(c['doctor_responses']) == 6 and b['dialogue_presentation']['visible_cards'] == 1
          and b['dialogue_presentation']['max_lines'] == 2,
          '六种专业文字共用一张聚焦病例卡，实际背景沟通不变成全院字幕')
    medical=indexed(c['diseases'])
    check(medical['D136']['name'] == '重启招呼症'
          and medical['D148']['name'] == '关节客服灯牌'
          and medical['D136']['profile'] == 'B' and medical['D136']['cure_fee'] == 320
          and medical['D148']['profile'] == 'A' and medical['D148']['cure_fee'] == 220
          and len([row for row in c['treatment_bindings'] if row['routine_id'] in {'TR75','TR76','TR81','TR82'}]) == 32,
          '八类共32条病例适配保留真实数量，招呼/客服换图符而不改变档位收费')
    cost = 740 + 200
    check(cost - min(100, cost) == 840 and max(0, 100 + 1400 - cost) == 560,
          '资助与补助顺序样例：100现金需840直接资助；先入1400补助则余560')
    # Fixed-period arithmetic only; live invalidation and UI costs need runtime evidence.
    day_ticks = round(b['day_seconds'] / b['tick_seconds'])
    rates = {p['wage_day'] for p in b['doctor_pay']}
    rates.update(role['wage_day'] for role in b['staff'] if 'wage_day' in role)
    check(all((numerator + elapsed*rate) + (remaining-elapsed)*rate == numerator + remaining*rate
              for rate in rates for numerator in (0, 1, day_ticks-1, day_ticks+49)
              for remaining in (1, 2, day_ticks//3, day_ticks)
              for elapsed in {0, remaining//2, remaining-1}),
          '同日名单及费率不变时逐人工资期末分子与纯tick无关；不是UI或帧率实测')
    fractional_wages=(day_ticks-100, day_ticks-100)
    check(sum(value//day_ticks for value in fractional_wages) == 0
          and sum(fractional_wages)//day_ticks == 1,
          '两份不足一币的工资必须逐人舍入，先合并分子会虚增一币')
    for mutate, label in [
        (lambda x,y:y['audio_presentation'].update(audio_changes_environment=True), '静音改变医院环境分'),
        (lambda x,y:y['audio_presentation'].update(late_oneshots='queued_for_next_view'), '切层补播旧治疗声音'),
        (lambda x,y:y['dialogue_presentation'].update(medium='text_and_voices'), '对白录音替代文字'),
        (lambda x,y:y['dialogue_presentation'].update(world_bubbles=True), '全院角色头顶铺对话'),
        (lambda x,y:y['dialogue_presentation'].update(nonclinical_lines=True), '日常笑点自动显示对白句'),
        (lambda x,y:y['dialogue_presentation'].update(calling_lines=True), '叫号生成语言句子'),
        (lambda x,y:y['dialogue_presentation'].update(blocks_work_or_input=True), '读文字阻挡临床或玩家操作'),
        (lambda x,y:y['dialogue_presentation'].update(late_lines='queue_all_unseen_lines'), '离屏对白堆积补播'),
        (lambda x,y:y['ui_lists'].update(command_target='current_row_index'), '列表重排把命令交给另一人'),
        (lambda x,y:y['ui_lists'].update(portrait_mode='one_live_3d_viewport_per_row'), '列表为全部居民创建实时场景'),
        (lambda x,y:x['finance_views'][0]['sources'].append('community_aid'), '援助冒充诊疗收入'),
        (lambda x,y:y['operating_settlement'].update(settlement='floor_daily_discard_remainder'), '运营日结丢失小数成本'),
        (lambda x,y:y['operating_settlement'].update(settlement='ceil_every_day'), '运营每日零头提前多收'),
        (lambda x,y:y['operating_settlement'].update(payer_affects_accrual=True), '资助来源改变费用累计'),
        (lambda x,y:y['finance_review'].update(reserve_cash=True), '便签暗中圈存资金'),
        (lambda x,y:y['finance_review'].update(forecast_income='future_cures'), '未发生治愈进入预算'),
        (lambda x,y:y['finance_review']['forecast_query'].update(invalidation='any_world_change'), '全世界变化无差别重求展望'),
        (lambda x,y:y['finance_review']['forecast_query'].update(source='round_summed_payroll_numerators'), '先合并工资再舍入'),
        (lambda x,y:y['finance_review']['forecast_query'].update(hidden='pause_payroll_and_procurement'), '关财务页停止真实结算'),
        (lambda x,y:y['finance_review']['forecast_query'].update(unknown_dependencies='reuse_unchecked'), '未知财务依赖返回旧预测'),
        (lambda x,y:y['save']['browser'].update(list_reads='load_every_world'), '医院列表解析全部世界'),
        (lambda x,y:y['save']['user_directory_guard'].update(acquire_before='first_save'), '载入和清理后才取得资料库'),
        (lambda x,y:y['save']['user_directory_guard'].update(authority='existing_file_or_pid'), '把遗留空文件当成占用凭据'),
        (lambda x,y:y['save']['user_directory_guard'].update(lifetime='until_world_closed'), '写盘未停便随旧世界释放句柄'),
        (lambda x,y:y['save']['user_directory_guard'].update(logging='engine_default_shared_log'), '占用检查前轮换共同日志'),
        (lambda x,y:y['save']['user_directory_guard'].update(uninstall='unlock_then_delete_root'), '先交出目录再递归删除资料'),
        (lambda x,y:y['save']['browser'].update(world_reads='trust_manifest_summary'), '正式载入只信卡片摘要'),
        (lambda x,y:y['save']['hospital_switch'].update(source_retention='close_after_source_checkpoint'), '目标尚未就绪便关闭原医院'),
        (lambda x,y:y['save']['hospital_switch'].update(target_ready='manifest_valid'), '只凭清单通过便切换世界'),
        (lambda x,y:y['save']['hospital_switch'].update(candidate_simulation='advance_during_loading'), '候选加载期间偷跑模拟'),
        (lambda x,y:y['save']['hospital_switch'].update(resource_accounting='candidate_only'), '切换峰值漏计原世界'),
        (lambda x,y:y['save'].update(max_snapshot_bytes=33554432), '恢复固定32MiB世界上限'),
        (lambda x,y:y['save']['backup_format'].update(read_mode='extract_paths'), '使用包内路径解压'),
        (lambda x,y:y['save']['resource_budget'].update(enforcement='declared_only'), '仅读自报大小不查真实资源'),
        (lambda x,y:x['finance_views'][0]['sources'].append('care'), '护理床再叠加旧照护收入')]:
        cc, bb = copy.deepcopy(c), copy.deepcopy(b)
        mutate(cc, bb)
        try:
            validate_operations(cc, bb)
        except ValueError:
            check(True, '经营设计负例被拒绝：' + label)
        else:
            raise ValueError('invalid operation contract accepted: ' + label)


def append_operations_atlas(lines, c, b, table):
    lines += ['## 真实音流与解码资源', '',
              '以下为声明并发、绑定守卫及PCM16原始字节算例，没有运行音频后端、解码或本机性能。全部音效保持非语言，叫号无声音语言。', '']
    table(lines,['来源或边界','确定规则'],[
        ['原预算','设施6/角色非语言反应6/UI2/音乐2仍取audio_presentation；实际子流/淡出/待停计名额'],
        ['音层与真数量','六源各三流为18；5当前+1淡出+1新为7。设备阶段层离线预混，场景槽复音1，无隐藏子流'],
        ['槽与回收','、'.join(b['audio_resources']['scene_slot_key'])+'；显式stop/解绑不等finished，未实际停仍计播放'],
        ['当前阶段','迟到短音省略，合法当前循环匹配后重读原源；现场静音停解码，恢复不补播，微观无第二池'],
        ['共享与字节','只读编码资源共享，playback/游标/缓冲私有；PCM16原始88200/1152000字节不是实际Ogg驻留'],
        ['原世界','实际编码/解码/缓存/临时/退场计工作集，无全院音节点；声音不结算、改噪声/怒气/随机或保存游标']])
    dialogue=b['dialogue_presentation']
    lines += ['## 文字与动作的分工', '',
              '对话没有语音、TTS或拟语声。医患文字来自已真正开始的沟通；日常喜剧用动作、表情与图符，叫号沿原无语言视觉规则。', '']
    table(lines, ['范围', '显示方式', '边界'], [
        ['医患沟通', '当前病例详情的一张文字卡',
         str(dialogue['visible_cards'])+'张 / '+str(dialogue['max_lines'])+'行；通常'+str(dialogue['minimum_read_real_seconds'])+'现实秒，不阻挡工作或输入'],
        ['互动 / 回访 / 活动', '原动作、插画和图符', '不显示对白句、不增加人物/工时/收益'],
        ['病症道具', '原身体与道具槽中的图符', '招呼、字幕、客服保留原病例，图符不成为业务完成事实'],
        ['叫号', '原号签、头像、站点指示', '没有播报、叫号句或确认，原队列自动衔接'],
        ['必要信息', '名称、票号、数量、楼号、真实原因', '不由医患文字开关隐藏，重要提示优先']])
    lines += ['## 开院引导与情境帮助', '', '学习顺序不锁功能；帮助重播不重置患者、奖励或随机结果。', '']
    table(lines, ['步骤', '完成依据', '入口', '说明'], [[str(r['order'])+'. '+r['name'],r['evidence'],r['target_panel'],r['help_text']]
                                        for r in c['onboarding_steps']])
    table(lines, ['情境', '真实触发', '入口', '说明'], [[r['name'],r['trigger'],r['target_panel'],r['help_text']]
                                        for r in c['context_lessons']])
    lines += ['## 候诊生活服务与表现', '']
    table(lines, ['用途', '普通伸缩设施', '宽敞造型备选', '随身用品', '低动态'], [[r['name'], r['ordinary_facility_id'], r['universal_facility_id'], r['fallback_scene'], r['fallback_low_motion_scene']]
                                             for r in c['amenity_services']])
    table(lines, ['表现', '用途', '性格', '动作', '低动态'], [[r['name'], r['purpose'], r['personality_id'] or '通用', r['scene'], r['low_motion_scene']]
                                    for r in c['amenity_scenes']])
    lines += ['## 六岗位实践与第一件工作', '', '经验只来自本人真实工作，医生课程和护士证书各守原门槛。', '']
    table(lines, ['岗位', '完成来源', '计数单位', '首次工作表现', '低动态'], [[r['name'], '、'.join(r['sources']), r['unit'], r['first_job_scene'], r['low_motion_first_job_scene']]
                                                   for r in c['staff_practice_profiles']])
    lines += ['## 任务引导', '', '引导投影原目标，不接单、不生成演员、不代付或代领奖励。', '']
    table(lines, ['方向', '目标指标', '下一步', '完成依据'], [[r['name'], '；'.join(v['text']+'（'+v['unit']+'）' for v in r['metric_labels'].values()), r['next_step'], r['evidence']]
                                              for r in c['task_guides']])
    lines += ['## 经营账页', '', '账页只解释原始账目；展望与存钱便签不圈存资金。', '']
    table(lines, ['账页', '来源', '说明'], [[r['name'], '、'.join(r['sources']), r['description']]
                                        for r in c['finance_views']])


def validate_task_guides(c, b):
    metrics = {r['metric'] for r in c['tasks']}
    seen = set()
    for row in indexed(c['task_guides']).values():
        require(set(row) == {'id','name','metrics','target_panel','next_step','evidence','metric_labels'}, 'task guide owns reward or progress')
        require(row['metrics'] and len(set(row['metrics'])) == len(row['metrics'])
                and set(row['metrics']) <= metrics and not seen.intersection(row['metrics']), 'unknown or repeated guide metric')
        require(row['target_panel'] in {'admissions','maintenance','staff','facilities','residents','growth','finance','cleaning'}, 'unknown task guide destination')
        require(set(row['metric_labels']) == set(row['metrics']), 'task labels differ from counted metrics')
        require(all(set(v) == {'text','unit'} and isinstance(v['text'],str) and v['text'].strip()
                    and v['unit'] in {'次','种','单','名','对','条','项','块','日'}
                    for v in row['metric_labels'].values()), 'invalid player-facing task label')
        seen.update(row['metrics'])
    require(seen == metrics, 'task metric lacks actionable guide')
    require(b['task_board_flow'] == {'first_offer_day':1,'offer_selection':'least_recent_then_id',
            'fill_mid_period':False,'paused_counts':False,'paused_uses_commission_slot':True,
            'pending_reward_uses_slot':False,'resume_backfill':False}, 'unsafe task board flow')


def check_task_examples(c, b, check):
    check(len(c['task_guides']) == 8, '八类任务指引覆盖28任务的全部指标且无重复事实所有者')
    check(1 + b['tasks']['board_refresh_days'] == 3 and 5 + b['tasks']['template_cooldown_days'] == 8,
          '换单第1/3日；第5日完成模板最早第8日且仍需已经领取')
    for mutate,label in [
        (lambda x,y:x['task_guides'][0]['metrics'].append('invented_reward'), '未知计数来源'),
        (lambda x,y:y['task_board_flow'].update(resume_backfill=True), '暂停事实回填'),
        (lambda x,y:x['task_guides'][0]['metric_labels'].pop('cured_visits'), '目标缺中文计数说明'),
        (lambda x,y:x['task_guides'][0]['metric_labels']['cured_visits'].update(unit='分钟'), '目标单位不符计数'),
        (lambda x,y:x['task_guides'][0].update(reward_cash=999), '指引复制奖励')]:
        cc,bb=copy.deepcopy(c),copy.deepcopy(b);mutate(cc,bb)
        try:validate_task_guides(cc,bb)
        except ValueError:check(True,'任务指引负例被拒绝：'+label)
        else:raise ValueError('invalid task guide accepted: '+label)


def validate_staff_practice(c, b):
    expected = {
        'receptionist': {'registration_completed'},
        'nurse': {'test_completed','guidance_corrected','incident_care_completed','ward_visit_completed','bed_transfer_completed','or_assistance_completed'},
        'cleaner': {'cleanup_completed'}, 'mechanic': {'maintenance_order_completed','machine_upgrade_completed'},
        'researcher': {'active_research_ticks'}, 'decorator': {'surface_unit_completed','floor_module_completed'}}
    rows = indexed(c['staff_practice_profiles'])
    require(len(rows) == len(expected) and {r['role'] for r in rows.values()} == set(expected), 'missing non-doctor practice role')
    for row in rows.values():
        require(set(row) == {'id','name','role','sources','unit','first_job_scene','low_motion_first_job_scene','growth_owner'}, 'practice profile duplicates pay or credentials')
        require(row['first_job_scene'] and row['low_motion_first_job_scene'], 'first work lacks actual or low-motion scene')
        require(set(row['sources']) == expected[row['role']] and len(row['sources']) == len(set(row['sources'])), 'invalid practice completion source')
        require(row['unit'] == ('active_time' if row['role'] == 'researcher' else
                'track_completed_work' if row['role'] == 'nurse' else 'completed_work'), 'wrong practice unit')
        require(row['growth_owner'] == ('clinical_ability' if row['role']=='nurse' else 'job_skill'), 'duplicate nurse growth owner')
    require(b['staff_practice'] == {'units_per_level':20,'research_active_seconds':120,
            'max_level':5,'advanced_research_id':'R11','speed_per_extra_level':0.05,
            'handoff_credit':'largest_contributor_then_id','first_job_scope':'once_per_staff'}, 'unsafe staff practice policy')
    require(b['staff_practice']['advanced_research_id'] in indexed(c['research']), 'practice research unavailable')


def check_staff_examples(c, b, check):
    check(len(c['staff_practice_profiles']) == 6, '五岗位技能与护士能力分别消费真实工作，护士不存重复通用等级')
    check(divmod(55, b['staff_practice']['units_per_level']) == (2,15)
          and divmod(75+70,b['staff_practice']['research_active_seconds']) == (1,25),
          '55次解锁后从1到3级余15；75秒加70秒研究为1次实践余25秒')
    for mutate,label in [
        (lambda x,y:x['staff_practice_profiles'][1]['sources'].append('ward_idle'), '护士空占床位刷经验'),
        (lambda x,y:x['staff_practice_profiles'][0].update(wage_day=0), '成长表覆盖工资'),
        (lambda x,y:y['staff_practice'].update(handoff_credit='every_worker'), '交接重复实践')]:
        cc,bb=copy.deepcopy(c),copy.deepcopy(b);mutate(cc,bb)
        try:validate_staff_practice(cc,bb)
        except ValueError:check(True,'岗位实践负例被拒绝：'+label)
        else:raise ValueError('invalid staff practice accepted: '+label)


def validate_amenities(c, b):
    equipment = indexed(c['accessibility_equipment'])
    furniture = {r['definition_id'] for r in c['furniture_equipment']}
    services = indexed(c['amenity_services'])
    require(len(services) == 2 and {r['purpose'] for r in services.values()} == {'water','toilet'}, 'missing basic amenity')
    for row in services.values():
        require(set(row) == {'id','name','purpose','ordinary_facility_id','ordinary_seconds','body_fit','universal_facility_id','fallback_scene','fallback_low_motion_scene'}, 'amenity definition duplicates live service')
        require(row['ordinary_facility_id'] in furniture and row['ordinary_seconds'] == 8
                and row['body_fit'] == 'automatic' and row['fallback_scene']
                and row['fallback_low_motion_scene'], 'invalid ordinary facility profile')
        universal = equipment.get(row['universal_facility_id'])
        require(universal and row['purpose'] in universal['purposes'] and universal['max_clearance_cells'] == 3, 'wrong full-body amenity')
    personalities = indexed(c['patient_personalities']); seen = set()
    for row in indexed(c['amenity_scenes']).values():
        require(set(row) == {'id','name','purpose','personality_id','scene','low_motion_scene'}, 'amenity performance cannot produce rewards')
        require(row['purpose'] in {'water','toilet'} and (row['personality_id'] is None or row['personality_id'] in personalities), 'invalid amenity context')
        require(bool(row['scene']) and bool(row['low_motion_scene']), 'missing amenity scene')
        key=(row['purpose'],row['personality_id']);require(key not in seen,'ambiguous amenity scene');seen.add(key)
    require({('water',None),('toilet',None)} <= seen, 'amenity scene needs neutral fallback')
    require(b['amenity_flow'] == {'first_need_seconds':180,'cooldown_seconds':180,'seek_seconds':45,
            'fallback_seconds':8,'fallback_anger':5,'active_needs_per_visit':1,
            'clinical_wait_paused':True,'release_seat':True,'scene_selection':'personality_then_default'}, 'unsafe amenity flow')


def check_amenity_examples(c, b, check):
    check(len(c['amenity_services']) == 2 and len(c['amenity_scenes']) == 6, '两类生活服务引用真实设施，六表现有用途与性格边界')
    check(b['amenity_flow']['first_need_seconds'] + b['amenity_flow']['fallback_seconds'] + b['amenity_flow']['cooldown_seconds'] == 368,
          '180秒即用8秒兜底后，下次需求最早368秒，不能连续惩罚')
    for mutate,label in [
        (lambda x,y:x['amenity_services'][0].update(universal_facility_id='AE01'), '软垫冒充生活设施'),
        (lambda x,y:x['amenity_scenes'][0].update(low_motion_scene=''), '生活表现缺低动态'),
        (lambda x,y:x['amenity_services'][0].update(fallback_low_motion_scene=''), '随身用品缺低动态'),
        (lambda x,y:x['amenity_scenes'][0].update(reward_cash=1), '生活动作送奖励'),
        (lambda x,y:y['amenity_flow'].update(release_seat=False), '离座继续占椅')]:
        cc,bb=copy.deepcopy(c),copy.deepcopy(b);mutate(cc,bb)
        try:validate_amenities(cc,bb)
        except ValueError:check(True,'生活服务负例被拒绝：'+label)
        else:raise ValueError('invalid amenity accepted: '+label)


def validate_onboarding(c, b):
    steps = list(indexed(c['onboarding_steps']).values())
    require([r['order'] for r in steps] == list(range(1,11)), 'onboarding order missing or repeated')
    evidence = {'hospital_created','patient_selected','human_case_cured','zombie_case_cured','seat_fit_reviewed_or_layout_committed',
                'interaction_finished','research_evidence_received','finance_view_opened','milestone_reward_claimed','manual_save_and_hospital_list'}
    require({r['evidence'] for r in steps} == evidence, 'onboarding uses intent instead of fact')
    seeds = []
    seed_by_evidence = {'human_case_cured':('S49','D37'), 'zombie_case_cured':('S13','D09')}
    bindings = {(r['species_id'],r['disease_id']) for r in c['treatment_bindings']}
    for row in steps:
        require(set(row) == {'id','name','order','evidence','target_panel','help_text','patient_seed'}, 'onboarding creates parallel progress or reward')
        seed = row['patient_seed']
        require(bool(seed) == (row['evidence'] in seed_by_evidence), 'tutorial seed attached to wrong lesson')
        if seed:
            require(set(seed) == {'species_id','disease_id'} and (seed['species_id'],seed['disease_id']) in bindings, 'tutorial patient lacks real binding')
            require((seed['species_id'],seed['disease_id']) == seed_by_evidence[row['evidence']], 'tutorial seed does not match observed case')
            seeds.append((seed['species_id'],seed['disease_id']))
    require(seeds == [('S49','D37'),('S13','D09')] and len(seeds) == b['arrivals']['tutorial_fixed_slots'], 'teaching changes original visits')
    triggers = {'body_route_blocked','land_preview_opened','equipment_failed','shift_coverage_missing',
                'clinical_resource_missing','remodel_waiting','amenity_fallback_active','direct_support_recorded','actor_frozen'}
    lessons = list(indexed(c['context_lessons']).values())
    require(len(lessons) == len(triggers) and {r['trigger'] for r in lessons} == triggers, 'missing or invented context lesson')
    for row in lessons:
        require(set(row) == {'id','name','trigger','priority','target_panel','help_text'} and 1 <= row['priority'] <= 9, 'unsafe context lesson')
    require(b['onboarding'] == {'active_bubbles':1,'bubble_cooldown_seconds':60,'defer_days':1,
            'replay_changes_world':False,'locks_features':False,'protected_visits_per_seed':1,
            'cross_hospital_progress':False}, 'unsafe onboarding persistence')


def check_onboarding_examples(c, b, check):
    check(len(c['onboarding_steps']) == 10 and len(c['context_lessons']) == 9, '十项开院与九种情境引导只认真实完成依据')
    check(sum(r['patient_seed'] is not None for r in c['onboarding_steps']) == b['arrivals']['tutorial_fixed_slots'],
          '仅两条教学病例请求，消耗原到访机会而不增加配额')
    for mutate,label in [
        (lambda x,y:y['onboarding'].update(replay_changes_world=True), '重看帮助重放世界'),
        (lambda x,y:x['onboarding_steps'][9].update(evidence='save_requested'), '提交保存冒充成功'),
        (lambda x,y:y['onboarding'].update(locks_features=True), '引导锁住完整系统')]:
        cc,bb=copy.deepcopy(c),copy.deepcopy(b);mutate(cc,bb)
        try:validate_onboarding(cc,bb)
        except ValueError:check(True,'教学设计负例被拒绝：'+label)
        else:raise ValueError('invalid onboarding accepted: '+label)
