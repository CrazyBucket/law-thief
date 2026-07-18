#!/usr/bin/env bash

# Test-suite membership and changed-file routing live here so selection can be
# inspected without starting Godot. Keep manual probes out of automatic suites.

FAST_TESTS=(
  balance_config_test
  combat_transaction_test
  battle_architecture_test
  battle_overlay_presenter_test
  adventure_map_copy_presenter_test
  board_overlay_api_test
  battle_query_cache_test
  persistence_isolation_test
  encounter_content_diagnostics_test
  battle_presentation_planner_test
  battle_event_player_cluster_test
  presentation_state_applier_test
  battle_renderer_timing_test
  testkit_snapshot_test
  gem_semantic_contract_test
  full_run_contract_test
  intent_consistency_contract_test
  room_effect_executor_test
  economy_service_test
  event_service_test
  adventure_rule_registry_test
  shop_service_test
  explosion_test
  gem_level_context_test
  status_test
  prop_entity_test
  stone_bow_guard_test
  split_shot_test
  gravity_test
  bomb_rat_test
  tile_overlay_reaction_test
  overlay_render_contract_test
  ui_overlay_contract_test
  ui_visual_regression_contract_test
  transition_manager_test
  law_worm_test
  gem_insert_replace_test
  fission_slime_test
  gem_transfer_test
)

CORE_TESTS=(
  balance_config_test
  encounter_load_test
  ai_test
  combat_transaction_test
  battle_architecture_test
  battle_overlay_presenter_test
  adventure_map_copy_presenter_test
  board_overlay_api_test
  battle_query_cache_test
  persistence_isolation_test
  encounter_content_diagnostics_test
  presentation_state_applier_test
  smoke_test
  economy_service_test
  event_service_test
  adventure_rule_registry_test
  shop_service_test
  explosion_test
  status_test
  prop_entity_test
  stone_bow_guard_test
  split_shot_test
  bomb_rat_test
  tile_overlay_reaction_test
  overlay_render_contract_test
  ui_overlay_contract_test
  ui_visual_regression_contract_test
  transition_manager_test
  law_worm_test
  gem_insert_replace_test
  fission_slime_test
  gem_transfer_test
)

GEM_TESTS=(
  balance_config_test
  combat_transaction_test
  battle_architecture_test
  gem_semantic_contract_test
  intent_consistency_contract_test
  explosion_test
  gem_level_context_test
  status_test
  prop_entity_test
  stone_bow_guard_test
  split_shot_test
  gravity_test
  bomb_rat_test
  tile_overlay_reaction_test
  law_worm_test
  gem_insert_replace_test
  fission_slime_test
  gem_transfer_test
)

BATTLE_TESTS=(
  encounter_load_test
  ai_test
  combat_transaction_test
  battle_architecture_test
  battle_query_cache_test
  battle_presentation_planner_test
  battle_event_player_cluster_test
  presentation_state_applier_test
  battle_renderer_timing_test
  smoke_test
  intent_consistency_contract_test
  explosion_test
  status_test
  prop_entity_test
  stone_bow_guard_test
  split_shot_test
  bomb_rat_test
  fission_slime_test
)

ADVENTURE_TESTS=(
  balance_config_test
  adventure_chapter_transition_test
  encounter_content_diagnostics_test
  full_run_contract_test
  game_service_continue_route_test
  run_recovery_route_test
  room_effect_executor_test
  economy_service_test
  event_service_test
  adventure_rule_registry_test
  shop_service_test
)

PERSISTENCE_TESTS=(
  persistence_isolation_test
  run_history_service_test
  run_recovery_route_test
  run_save_compat_test
  run_save_corruption_recovery_test
  run_state_round_trip_test
  save_service_atomic_test
  game_service_continue_route_test
)

UI_TESTS=(
  battle_overlay_presenter_test
  adventure_map_copy_presenter_test
  board_overlay_api_test
  presentation_state_applier_test
  overlay_render_contract_test
  ui_overlay_contract_test
  ui_visual_regression_contract_test
  transition_manager_test
  ui_compile_test
)

LOCALIZATION_TESTS=(
  adventure_map_copy_presenter_test
  event_service_test
  ui_compile_test
)

ALL_TESTS=()
MANUAL_TESTS=()
TESTS=()
VERIFY_CHANGED_FILES=""

append_tests() {
  TESTS+=("$@")
}

dedupe_selected_tests() {
  local test_name
  local deduped=()
  while IFS= read -r test_name; do
    [[ -n "$test_name" ]] && deduped+=("$test_name")
  done < <(printf '%s\n' "${TESTS[@]}" | awk 'NF && !seen[$0]++')
  TESTS=("${deduped[@]}")
}

collect_all_tests() {
  local root="$1"
  local file
  ALL_TESTS=()
  while IFS= read -r file; do
    ALL_TESTS+=("$(basename "$file" .gd)")
  done < <(find "$root/scripts/tests" -maxdepth 1 -name '*_test.gd' | sort)

  MANUAL_TESTS=()
  while IFS= read -r file; do
    MANUAL_TESTS+=("manual/$(basename "$file" .gd)")
  done < <(find "$root/scripts/tests/manual" -maxdepth 1 -name '*_test.gd' 2>/dev/null | sort)
}

collect_changed_files() {
  local root="$1"
  {
    # Windows checkouts are invoked through WSL by verify.cmd. WSL Git can see
    # every CRLF file as modified when its config differs from Windows Git, so
    # use numstat after whitespace filtering instead of trusting --name-only.
    git -C "$root" diff --no-renames --ignore-space-at-eol --numstat HEAD | cut -f3-
    git -C "$root" ls-files --others --exclude-standard
  } | awk 'NF && !seen[$0]++'
}

select_changed_tests() {
  local root="$1"
  local changed="$2"
  local path
  TESTS=()

  # A changed executable test is always the narrowest useful evidence. Manual
  # probes remain opt-in even when their source changes.
  while IFS= read -r path; do
    if [[ "$path" =~ ^scripts/tests/[^/]+_test\.gd$ && -f "$root/$path" ]]; then
      append_tests "$(basename "$path" .gd)"
    fi
  done <<<"$changed"

  if grep -Eq '^tests/contracts/gem_semantics\.json$|^scripts/rules/(gem_effects|gem_tag_resolver|attack_pipeline)\.gd$|^scripts/core/combat_config\.gd$|^resources/gems/' <<<"$changed"; then
    append_tests "${GEM_TESTS[@]}"
  fi

  if grep -Eq '^scripts/(rules|battle)/|^resources/combat/|^resources/units/unit_defs\.json$|^resources/relics/' <<<"$changed"; then
    append_tests "${BATTLE_TESTS[@]}"
  fi

  # Shared state shapes can affect battle, adventure, and persistence together.
  if grep -Eq '^scripts/data/' <<<"$changed"; then
    append_tests "${CORE_TESTS[@]}" "${PERSISTENCE_TESTS[@]}"
  fi

  if grep -Eq '^resources/adventure/|^scripts/services/(adventure_config_validator|adventure_rule_registry|adventure_service|balance_config_validator|data_registry|economy_config_validator|economy_service|event_service|game_service|numeric_text_resolver|room_effect_executor|room_flow_service|shop_service)\.gd$' <<<"$changed"; then
    append_tests "${ADVENTURE_TESTS[@]}"
  fi

  if grep -Eq '^scripts/services/(persistence_path_policy|run_history_service|save_manager|save_service|settings_service)\.gd$' <<<"$changed"; then
    append_tests "${PERSISTENCE_TESTS[@]}"
  fi

  if grep -Eq '^scripts/ui/|^scenes/(ui|adventure|battle)/|^assets/ui/' <<<"$changed"; then
    append_tests "${UI_TESTS[@]}"
  fi

  if grep -Eq '^localization/strings\.csv$|^scripts/tools/build_localization_translations\.gd$' <<<"$changed"; then
    append_tests "${LOCALIZATION_TESTS[@]}"
  fi

  if grep -Eq '^scripts/testkit/|^scripts/tools/|^tools/' <<<"$changed"; then
    append_tests testkit_snapshot_test
  fi

  if grep -Eq '^project\.godot$' <<<"$changed"; then
    append_tests smoke_test ui_compile_test
  fi

  # Unknown runtime files still receive a small compile/load safety net. Docs,
  # workflow metadata, and copy-only changes intentionally start no Godot test.
  if (( ${#TESTS[@]} == 0 )) && grep -Eq '\.(gd|tscn|tres|gdshader|json|csv)$' <<<"$changed"; then
    append_tests encounter_load_test ui_compile_test
  fi

  dedupe_selected_tests
}

select_verify_tests() {
  local mode="$1"
  local root="$2"
  local test_name
  shift 2
  collect_all_tests "$root"
  TESTS=()
  VERIFY_CHANGED_FILES=""

  case "$mode" in
    test)
      if (( $# == 0 )); then
        return 2
      fi
      for test_name in "$@"; do
        if [[ ! "$test_name" =~ ^[A-Za-z0-9_]+_test$ || ! -f "$root/scripts/tests/${test_name}.gd" ]]; then
          echo "VERIFY_UNKNOWN_TEST $test_name" >&2
          return 2
        fi
        TESTS+=("$test_name")
      done
      dedupe_selected_tests
      ;;
    fast)
      TESTS=("${FAST_TESTS[@]}")
      ;;
    changed)
      VERIFY_CHANGED_FILES="$(collect_changed_files "$root")"
      select_changed_tests "$root" "$VERIFY_CHANGED_FILES"
      ;;
    all)
      TESTS=("${ALL_TESTS[@]}")
      ;;
    manual)
      TESTS=("${MANUAL_TESTS[@]}")
      ;;
    *)
      return 2
      ;;
  esac
}
