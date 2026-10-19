#!/bin/sh
# builds test binaries and compares their output with tests/data/*.expected
cd "$(dirname "$0")/.."
./build.sh test || exit 1
fail=0
tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT HUP INT TERM
check() { # name cmd...
    name=$1; shift
    if "$@" > "$tmp" 2>&1 && cmp -s "$tmp" "tests/data/$name.expected"; then
        echo "ok   $name"
    else
        echo "FAIL $name"; fail=1
    fi
}
check keymap-names-us-ru build/xkb_test tests/data/keymap-names-us-ru.txt
check keymap-gnome-us build/xkb_test tests/data/keymap-gnome-us.txt
check keymap-pl-intl build/xkb_test tests/data/keymap-pl-intl.txt
check doc build/doc_test
check doc-language build/doc_language_test
check doc-language-choice build/doc_language_choice_test
check doc-selections build/doc_selections_test
check doc-multi-edit build/doc_multi_edit_test
check doc-batch build/doc_batch_test
check doc-batch-guard build/doc_batch_guard_test
check editor-multi-type build/editor_multi_type_test
check editor-multi-newline build/editor_multi_newline_test
check editor-multi-delete build/editor_multi_delete_test
check editor-multi-tab build/editor_multi_tab_test
check clipboard-write build/clipboard_write_test
check clipboard-wire build/clipboard_wire_test
check clipboard-metadata build/clipboard_metadata_test
check clipboard-context build/clipboard_context_test
check clipboard-paste-queue build/clipboard_paste_queue_test
if [ "$(uname -s)" = Darwin ]; then
    check mac-clipboard-read build/mac_clipboard_read_test
    check mac-clipboard-metadata build/mac_clipboard_metadata_test
    if python3 tests/mac-clipboard-metadata.py; then :; else fail=1; fi
fi
if [ "$(uname -s)" = Linux ]; then
    if python3 tests/clipboard-faults.py; then :; else fail=1; fi
    check x11-wire build/x11_wire_test
    check x11-paste build/x11_paste_test
    check x11-string build/x11_string_test
    check x11-send build/x11_send_test
    check x11-metadata build/x11_metadata_test
    check wayland-paste build/wayland_paste_test
    check wayland-send build/wayland_send_test
    check wayland-metadata build/wayland_metadata_test
    check clipboard-async build/clipboard_async_test
fi
check editor-clipboard build/editor_clipboard_test
check editor-paste build/editor_paste_test
check snippet build/snippet_test
check snippet-choice build/snippet_choice_test
check snippet-unicode build/snippet_unicode_test
check snippet-regex build/snippet_regex_test
check snippet-regex-state build/snippet_regex_state_test
check snippet-regex-scope build/snippet_regex_scope_test
check snippet-regex-match build/snippet_regex_match_test
check snippet-regex-limits build/snippet_regex_limits_test
check snippet-replacement build/snippet_replacement_test
check snippet-case build/snippet_case_test
check snippet-case-api build/snippet_case_api_test
check snippet-transform build/snippet_transform_test
check snippet-transform-api build/snippet_transform_api_test
check snippet-transform-indent build/snippet_transform_indent_test
check snippet-transform-payload build/snippet_transform_payload_test
check snippet-indent-capture build/snippet_indent_capture_test
check snippet-transform-leave build/snippet_transform_leave_test
check snippet-base64 build/snippet_base64_test
check config env XDG_CONFIG_HOME=tests/data/config-reload build/config_test
check ext-settings-target env XDG_CONFIG_HOME=tests/data/ext-settings-target build/ext_settings_target_test
check ext-index build/ext_index_test
check ext-send build/ext_send_test
check ext-enqueue build/ext_enqueue_test
check ext-settings-queue build/ext_settingsqueue_test
python3 tests/ext-settings-queue.py || fail=1
python3 tests/ext-settings-queue-hash.py --negative-controls || fail=1
python3 tests/ext-settings-ack.py --negative-controls || fail=1
python3 tests/ext-settings-wire.py || fail=1
python3 tests/ext-enqueue.py --faults || fail=1
python3 tests/ext-flush.py || fail=1
python3 tests/ext-events.py --negative-controls || fail=1
python3 tests/ext-pending-commands.py || fail=1
python3 tests/ext-pending-owner.py || fail=1
python3 tests/ext-runtime-owner.py --negative-controls || fail=1
python3 tests/key-combo.py --negative-controls || fail=1
python3 tests/command-generation.py || fail=1
python3 tests/command-generation-owner.py --negative-controls || fail=1
python3 tests/command-generation-build.py --negative-controls || fail=1
python3 tests/command-generation-defaults.py --negative-controls || fail=1
python3 tests/command-generation-defaults.py --limits || fail=1
python3 tests/keyline-snapshot.py --negative-controls || fail=1
python3 tests/command-key-copy.py --negative-controls || fail=1
python3 tests/file-read-limited.py || fail=1
python3 tests/file-read-try.py || fail=1
python3 tests/file-ops.py || fail=1
python3 tests/dir-scan.py || fail=1
python3 tests/ext-choices.py --faults || fail=1
python3 tests/ext-choices-disk.py || fail=1
python3 tests/ext-prepare.py --exe build/ext_prepare_owner_test --grammar-exe build/grammar_prepare_test --theme-exe build/theme_prepare_test || fail=1
python3 tests/ext-prepare-products.py --exe build/ext_prepare_test || fail=1
python3 tests/ext-prepare-retire.py --dir build || fail=1
python3 tests/custom-retire-capacity.py --negative-controls || fail=1
python3 tests/catalog-foundation-faults.py || fail=1
python3 tests/catalog-map-faults.py || fail=1
python3 tests/catalog-merge-faults.py || fail=1
python3 tests/catalog-limits.py || fail=1
python3 tests/catalog-admission-faults.py || fail=1
python3 tests/catalog-retire.py || fail=1
python3 tests/catalog-capacity.py || fail=1
python3 tests/runtime-service-table.py --all || fail=1
python3 tests/runtime-service-session.py --negative-controls || fail=1
python3 tests/runtime-channel.py --negative-controls || fail=1
python3 tests/runtime-channel-native.py --negative-controls || fail=1
python3 tests/runtime-channel-compact.py --negative-controls || fail=1
python3 tests/runtime-ticket.py --negative-controls || fail=1
python3 tests/runtime-admission.py --negative-controls || fail=1
python3 tests/runtime-reply.py --negative-controls || fail=1
python3 tests/runtime-reply-native.py --negative-controls || fail=1
python3 tests/runtime-remove.py --negative-controls || fail=1
python3 tests/runtime-debt-timer.py --negative-controls || fail=1
python3 tests/runtime-session-clock.py --negative-controls || fail=1
python3 tests/ext-activation-eo-audit.py --negative-controls || fail=1
python3 tests/ext-int31.py --negative-controls || fail=1
python3 tests/ext-activation-owner.py --dir build || fail=1
python3 tests/ext-host-native.py --dir build || fail=1
python3 tests/ext-keeper-host.py || fail=1
python3 tests/metadata-platform-gates.py || fail=1
python3 tests/ext-launch-scratch.py --negative-controls || fail=1
python3 tests/ext-launch-scratch.py --optional-environment --negative-controls || fail=1
python3 tests/ext-launch-scratch-unit.py --negative-controls || fail=1
python3 tests/ext-launch-scratch-faults.py || fail=1
python3 tests/ext-legacy-parsers.py --dir build || fail=1
python3 tests/ext-prepare-legacy.py --exe build/ext_prepare_legacy_test --probe build/ext_validate_probe_test || fail=1
python3 tests/ext-legacy-snapshot.py --producer build/ext_legacy_snapshot_test --importer build/ext_prepare_legacy_import_test --probe build/ext_validate_probe_test || fail=1
python3 tests/ext-legacy-faults.py --probe build/ext_validate_probe_test || fail=1
python3 tests/ext-legacy-early.py --exe build/rhun || fail=1
python3 tests/ext-validate-wire.py --exe build/ext_validate_wire_test --helper build/rhun || fail=1
python3 tests/ext-prepare-faults.py || fail=1
python3 tests/ext-root.py --exe build/ext_root_test || fail=1
python3 tests/ext-store.py || fail=1
python3 tests/ext-store-read.py || fail=1
python3 tests/ext-store-guards.py || fail=1
python3 tests/ext-store-write.py || fail=1
python3 tests/ext-store-cli.py || fail=1
python3 tests/ext-store-faults.py || fail=1
python3 tests/ext-store-job.py || fail=1
python3 tests/ext-store-job-faults.py || fail=1
python3 tests/ext-store-job-legacy.py || fail=1
python3 tests/ext-store-job-legacy-real.py || fail=1
python3 tests/ext-store-job-legacy-faults.py || fail=1
python3 tests/ext-store-job-legacy-native-faults.py || fail=1
python3 tests/ext-store-job-legacy-context-faults.py || fail=1
python3 tests/ext-store-job-legacy-stream-faults.py || fail=1
python3 tests/ext-settings-native.py || fail=1
python3 tests/ext-settings-native-faults.py || fail=1
python3 tests/theme-capture.py || fail=1
python3 tests/theme-capture-build.py || fail=1
python3 tests/theme-capture-candidate.py || fail=1
python3 tests/theme-capture-candidate-purity.py || fail=1
python3 tests/theme-capture-cleanup.py || fail=1
python3 tests/theme-capture-faults.py || fail=1
python3 tests/theme-capture-file-cleanup.py || fail=1
python3 tests/theme-capture-file-faults.py || fail=1
python3 tests/theme-capture-files.py || fail=1
python3 tests/theme-capture-job.py || fail=1
python3 tests/theme-capture-job-faults.py || fail=1
python3 tests/theme-capture-job-owners.py || fail=1
python3 tests/theme-capture-native.py || fail=1
python3 tests/theme-capture-native-poison.py || fail=1
python3 tests/theme-capture-omarchy.py || fail=1
python3 tests/theme-capture-omarchy-faults.py || fail=1
python3 tests/theme-capture-omarchy-files.py || fail=1
python3 tests/theme-capture-proof-faults.py || fail=1
python3 tests/theme-capture-proof-mutations.py || fail=1
python3 tests/theme-capture-result.py || fail=1
python3 tests/theme-capture-result-decode.py || fail=1
python3 tests/theme-capture-result-faults.py || fail=1
python3 tests/theme-capture-startup.py || fail=1
python3 tests/theme-capture-startup-faults.py || fail=1
python3 tests/theme-capture-timeout.py || fail=1
python3 tests/theme-capture-worker.py || fail=1
python3 tests/theme-intent.py || fail=1
python3 tests/theme-intent-faults.py || fail=1
python3 tests/theme-intent-migration.py || fail=1
python3 tests/theme-intent-migration-faults.py || fail=1
python3 tests/theme-intent-reduce.py || fail=1
python3 tests/theme-intent-reduce-faults.py || fail=1
python3 tests/theme-capture-native-poison.py --negative-control || fail=1
python3 tests/native-cleanup.py || fail=1
python3 tests/native-cleanup-launch.py || fail=1
python3 tests/native-cleanup-start.py || fail=1
python3 tests/native-cleanup-unpack-job.py || fail=1
python3 tests/ext-settings-job.py || fail=1
python3 tests/ext-settings-job.py --kind memory || fail=1
python3 tests/ext-settings-job.py --kind receipts || fail=1
python3 tests/ext-settings-job.py --faults || fail=1
python3 tests/ext-settings-retire.py --negative-controls || fail=1
python3 tests/ext-settings-snapshot.py || fail=1
python3 tests/ext-settings-request.py --negative-controls || fail=1
python3 tests/ext-settings-service.py || fail=1
python3 tests/ext-settings-service-source.py || fail=1
python3 tests/ext-settings-service-worker.py || fail=1
python3 tests/ext-settings-service-worker.py --negative-controls || fail=1
python3 tests/ext-settings-service-initial.py || fail=1
python3 tests/ext-settings-service-initial.py --negative-controls || fail=1
python3 tests/ext-settings-adoption-empty.py || fail=1
python3 tests/ext-settings-adoption-empty.py --negative-controls || fail=1
python3 tests/ext-settings-adoption-unchanged.py || fail=1
python3 tests/ext-settings-adoption-unchanged.py --negative-controls || fail=1
python3 tests/ext-settings-adoption-sparse.py || fail=1
python3 tests/ext-settings-adoption-max.py || fail=1
python3 tests/ext-settings-adoption-service.py || fail=1
python3 tests/ext-settings-adoption-service.py --negative-controls || fail=1
python3 tests/ext-settings-adoption-read.py || fail=1
python3 tests/ext-settings-adoption-read.py --negative-controls || fail=1
python3 tests/ext-settings-adoption-native.py || fail=1
python3 tests/ext-settings-adoption-native.py --negative-controls || fail=1
python3 tests/ext-settings-adoption-constructor.py || fail=1
python3 tests/ext-settings-adoption-constructor.py --negative-controls || fail=1
python3 tests/ext-settings-view.py --faults --negative-controls || fail=1
python3 tests/ext-settings-catalog.py --faults --negative-controls || fail=1
python3 tests/ext-settings-active.py --faults --negative-controls || fail=1
python3 tests/ext-settings-editor.py --real-metadata --negative-controls || fail=1
python3 tests/ext-settings-prompt.py --negative-controls || fail=1
python3 tests/ext-settings-effective.py --negative-controls || fail=1
python3 tests/ext-settings-release.py --negative-controls || fail=1
python3 tests/ext-settings-worker.py --deadlines || fail=1
python3 tests/ext-settings-worker.py --faults || fail=1
python3 tests/ext-discovery.py || fail=1
python3 tests/ext-discovery-faults.py || fail=1
python3 tests/ext-validate.py --exe build/ext_validate_test --helper build/rhun --resource || fail=1
python3 tests/ext-validate-faults.py || fail=1
python3 tests/task-core.py --faults || fail=1
python3 tests/task-keeper.py --extensions --faults --deadlines || fail=1
python3 tests/extension-keeper.py || fail=1
for keeper_driver in keeper-cleanup keeper-cleanup-live keeper-cleanup-launch keeper-cleanup-terminal keeper-cleanup-status keeper-cleanup-cancel keeper-cleanup-active keeper-cleanup-producers keeper-cleanup-lowfd; do
    python3 tests/"$keeper_driver".py || fail=1
done
python3 tests/task-view.py --faults || fail=1
python3 tests/task-clipboard.py || fail=1
check config-strings build/config_strings_test
check keys build/keys_test
check ui-clip build/ui_clip_test
check fill build/fill_test
check memmove build/memmove_test
python3 tests/sha256.py || fail=1
python3 tests/mem-try.py || fail=1
python3 tests/mem-uninit.py --negative-controls || fail=1
python3 tests/discovery-alloc.py --negative-controls || fail=1
python3 tests/discovery-gp.py --controls || fail=1
python3 tests/discovery-gp-transfer.py --controls || fail=1
python3 tests/mem-helpers.py || fail=1
check syntax build/syntax_test
check themes build/theme_test
check term build/term_test
check diff build/diff_test
check images build/image_test $(ls tests/data/images/* | LC_ALL=C sort)
python3 tests/image-fuzz.py 1 20 || fail=1
check cpu build/cpu_test
check cols build/cols_test
check textarea build/textarea_test
check strfind build/str_test tests/data/strfind.txt
check versions build/update_test tests/data/versions.txt
python3 tests/mac-package.py || fail=1
python3 tests/windows-package.py || fail=1
python3 tests/installer-unicode.py || fail=1
python3 tests/install-command.py || fail=1
check paths build/path_test tests/data/paths.txt
check urls build/url_test tests/data/urls.txt
check grammars env HOME=/nonexistent XDG_CONFIG_HOME=tests/data/config build/grammar_test tests/data/detect.txt tests/data/samples
dups=$(grep -h '^files' runtime/syntax/*.syn | sed 's/^files *= *//' | tr ' ' '\n' | grep -v '^$' | sort | uniq -d)
if [ -z "$dups" ]; then echo "ok   grammar-patterns"; else echo "FAIL grammar-patterns: $dups"; fail=1; fi
check prefix-tag build/grammar_test --try tests/data/prefix-tag.syn tests/data/prefix-tag.txt
check fileicons env HOME=/nonexistent XDG_CONFIG_HOME=tests/data/fileicons-config build/fileicon_test tests/data/fileicons.txt
if [ "$(build/rhun --version)" = "rhun $(cat VERSION)" ]; then echo "ok   version"; else echo "FAIL version"; fail=1; fi
python3 tests/palette-scroll.py || fail=1
python3 tests/commit-wrap.py || fail=1
python3 tests/git-reset.py || fail=1
python3 tests/git-untracked.py || fail=1
python3 tests/git-fsmonitor.py || fail=1
python3 tests/git-trust.py || fail=1
python3 tests/live-reload.py || fail=1
python3 tests/tooltips.py || fail=1
python3 tests/terminal-tabs.py || fail=1
python3 tests/terminal-panel.py || fail=1
python3 tests/terminal-keys.py || fail=1
python3 tests/terminal-links.py || fail=1
python3 tests/new-window.py || fail=1
python3 tests/file-launch.py || fail=1
python3 tests/readonly-save.py || fail=1
python3 tests/save.py || fail=1
python3 tests/save-actions.py || fail=1
python3 tests/reopen-tab.py || fail=1
python3 tests/focused-zoom.py || fail=1
python3 tests/agents.py || fail=1
python3 tests/opencode.py || fail=1
python3 tests/agents-refresh.py || fail=1
sh tests/files.sh || fail=1
sh tests/update.sh || fail=1
python3 tests/commit-ai.py || fail=1
sh tests/detach.sh || fail=1
sh tests/blink.sh || fail=1
python3 tests/field-blink.py || fail=1
sh tests/session.sh || fail=1
python3 tests/desktop-ux.py || fail=1
python3 tests/mac-launch.py || fail=1
python3 tests/x11-auth.py || fail=1
python3 tests/linux-clipboard.py || fail=1
python3 tests/wayland-clipboard.py || fail=1
python3 tests/explorer-delete.py || fail=1
python3 tests/explorer-create.py || fail=1
python3 tests/explorer-tabs.py || fail=1
python3 tests/settings-ui.py || fail=1
python3 tests/settings-search.py || fail=1
python3 tests/appearance.py || fail=1
python3 tests/editor-matrix.py || fail=1
python3 tests/editor-hscroll.py || fail=1
python3 tests/splitter.py || fail=1
python3 tests/scroll-sensitivity.py || fail=1
python3 tests/window-focus.py || fail=1
python3 tests/new-tab.py || fail=1
python3 tests/tab-drag.py || fail=1
python3 tests/tab-pin.py || fail=1
python3 tests/tab-view.py || fail=1
python3 tests/terminal-font.py || fail=1
python3 tests/shift-wheel.py || fail=1
python3 tests/stress.py || fail=1
python3 tests/ext-host.py || fail=1
python3 tests/ext-commands.py || fail=1
python3 tests/ext-snapshots.py || fail=1
python3 tests/snippets.py || fail=1
python3 tests/snippet-variants.py || fail=1
python3 tests/snippet-transforms.py || fail=1
python3 tests/snippet-choices.py || fail=1
python3 tests/snippet-final.py || fail=1
python3 tests/snippet-context.py || fail=1
python3 tests/ext-providers.py || fail=1
python3 tests/ext-language.py || fail=1
python3 tests/ext-scheduling.py || fail=1
python3 tests/ext-watch.py || fail=1
python3 tests/ext-watch-native.py || fail=1
python3 tests/ext-boundaries.py || fail=1
python3 tests/ext-confine.py || fail=1
python3 tests/ext-ui.py || fail=1
python3 tests/ext-fuzz.py 1 4 || fail=1
# testing: the test explorer (feature "tests")
python3 tests/testing.py || fail=1
if [ "$(uname -s)" = Darwin ] || command -v strace >/dev/null; then
    status=0
    sh tests/file-faults.sh || status=$?
    [ "$status" = 0 ] || [ "$status" = 77 ] || fail=1
fi
[ -x tests/ui.sh ] && { tests/ui.sh || fail=1; }
exit $fail
