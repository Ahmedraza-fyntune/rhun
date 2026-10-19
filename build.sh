#!/bin/sh
# usage: ./build.sh [release|test]
set -e
cd "$(dirname "$0")"
[ "$(uname -s)" = Darwin ] && exec tools/build-mac.sh "$@"
mkdir -p build/obj
ASFLAGS="--64 -I src -I build"
[ "$1" = release ] || ASFLAGS="$ASFLAGS -g"
tools/gen-assets.sh > build/assets.s.new
cmp -s build/assets.s.new build/assets.s || { mv build/assets.s.new build/assets.s; rm -f build/obj/build_assets.o; }
objs=""
for s in $(find src -name "*.s" ! -path "src/mac/*" ! -path "src/win/*" | LC_ALL=C sort) build/assets.s; do
    o=build/obj/$(echo "$s" | sed 's|/|_|g; s|\.s$|.o|')
    stale=
    # assets.s only names the embedded files; their contents count too
    [ "$s" = build/assets.s ] && [ -f "$o" ] && [ -n "$(find runtime assets/fonts -newer "$o" -print -quit)" ] && stale=1
    [ "$s" = src/plat/x11.s ] && [ src/plat/x11.inc -nt "$o" ] && stale=1
    [ "$s" = src/plat/wayland.s ] && [ src/plat/wayland.inc -nt "$o" ] && stale=1
    [ "$s" = src/app/extproto.s ] && [ src/app/extwatchproto.inc -nt "$o" ] && stale=1
    [ "$s" = src/app/extproto.s ] && [ src/app/extprotoevents.inc -nt "$o" ] && stale=1
    [ "$s" = src/app/extproto.s ] && [ src/app/extresproto.inc -nt "$o" ] && stale=1
    [ "$s" = src/app/ext.s ] && [ src/app/extvalidateparse.inc -nt "$o" ] && stale=1
    [ "$s" = src/app/extvalidatemanifest.s ] && [ src/app/extvalidatemanifest.inc -nt "$o" ] && stale=1
    [ "$s" = src/app/extvalidatetree.s ] && [ src/app/extvalidatetree.inc -nt "$o" ] && stale=1
    case "$s" in
        src/app/catalogretire.s|src/app/catalogregistry*.s|tests/catalog*_test.s)
            for h in src/app/catalogretire.inc src/app/catalogregistry.inc src/app/catalogregistrywork.inc src/app/catalogregistrymap.inc src/app/extprepare.inc src/app/extprepareretire.inc src/app/extvalidate.inc; do
                [ "$h" -nt "$o" ] && stale=1
            done ;;
    esac
    case "$s" in
        src/app/extchoices.s|tests/ext_choices_test.s)
            [ src/app/extchoices.inc -nt "$o" ] && stale=1 ;;
        src/app/extvalidate*.s|src/mac/extvalidatepath.s|src/win/extvalidate*.s|tests/ext_validate*.s|tests/ext_root_test.s)
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1 ;;
        src/app/extstore*.s|tests/ext_store*.s)
            [ src/app/extstore.inc -nt "$o" ] && stale=1 ;;
        src/app/task*.s|tests/task*.s|tests/extension_lifecycle_test.s)
            [ src/app/taskproc.inc -nt "$o" ] && stale=1
            [ src/app/taskauth.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extprepare*.s|src/app/extlaunchscratch.s|src/app/extvalidate*.s|src/app/ext.s|src/app/syntax.s|src/app/theme.s|tests/*.s|tests/faults/*.s)
            [ src/app/extprepare.inc -nt "$o" ] && stale=1
            [ src/app/extpreparelegacy.inc -nt "$o" ] && stale=1
            [ src/app/extprepareretire.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extsettingsworker*.s|tests/ext_settings_worker_test.s)
            [ src/app/extsettingsworker.inc -nt "$o" ] && stale=1
            [ src/app/extsettingswire.inc -nt "$o" ] && stale=1
            [ src/app/extchoices.inc -nt "$o" ] && stale=1
            [ src/app/extchoicesdisk.inc -nt "$o" ] && stale=1
            [ src/app/extstore.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extsettingsservice*.s|src/app/extsettingsadoption*.s|src/app/extsettingsrequest*.s|tests/ext_settings_service*.s|tests/ext_settings_adoption*.s|tests/ext_settings_request*.s)
            for h in src/app/extsettingsadoption.inc src/app/extsettingsservice.inc src/app/extprepare.inc src/app/extprepareretire.inc src/app/extvalidate.inc src/app/extsettingsrequest.inc src/app/extsettingscatalog.inc src/app/extsettingsview.inc src/app/extsettingsini.inc src/app/extsettingsjob.inc src/app/extsettingssnapshot.inc src/app/extsettingsqueue.inc src/app/extsettingsframe.inc src/app/extsettingswire.inc src/app/extsettingsmemory.inc src/app/extchoices.inc; do
                if [ "$h" -nt "$o" ]; then stale=1; fi
            done ;;
    esac
    case "$s" in
        src/app/exthost*.s|src/app/extmetadata.s|src/app/extvisibility.s|src/app/extoutputslot.s|src/app/extactivation*.s|tests/ext_host*.s|tests/ext_metadata_borrowers_test.s|tests/ext_activation_owner_test.s|tests/extension_lifecycle_test.s)
            for h in src/app/exthostidentity.inc src/app/extprepare.inc src/app/extprepareretire.inc src/app/extactivation.inc src/app/taskauth.inc src/app/taskproc.inc src/app/extvalidate.inc; do
                [ "$h" -nt "$o" ] && stale=1
            done ;;
    esac
    case "$s" in
        src/app/extactivation*.s|tests/ext_activation_owner_test.s|tests/extension_lifecycle_test.s)
            [ src/app/extactivation.inc -nt "$o" ] && stale=1
            [ src/app/taskauth.inc -nt "$o" ] && stale=1
            [ src/app/extprepare.inc -nt "$o" ] && stale=1
            [ src/app/extprepareretire.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1
            [ tests/ext_activation_lifecycle_helpers.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/commandgeneration*.s|tests/command_generation*.s)
            [ src/app/commandgeneration.inc -nt "$o" ] && stale=1
            [ src/app/keylinesnapshot.inc -nt "$o" ] && stale=1
            [ src/app/extprepare.inc -nt "$o" ] && stale=1
            [ src/app/extprepareretire.inc -nt "$o" ] && stale=1
            [ src/app/extruntime.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1
            [ src/app/keycombo.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/keyline*.s)
            [ src/app/keylinesnapshot.inc -nt "$o" ] && stale=1
            [ src/app/commandgeneration.inc -nt "$o" ] && stale=1
            [ src/app/extprepare.inc -nt "$o" ] && stale=1
            [ src/app/extprepareretire.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1
            [ src/app/keycombo.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/keycombo.s|tests/keycombo_test.s)
            [ src/app/keycombo.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extsettingsview*.s|src/app/extsettingsmodel*.s|src/app/extsettingscatalog*.s|src/app/extsettingsprovider*.s|src/app/extsettingseditor.s|src/app/extsettingsactive.s|src/app/extsettingscanonical.s|src/app/extsettingseffective.s|src/app/extsettingsflags.s|tests/ext_settings_view_test.s)
            [ src/app/extsettingsview.inc -nt "$o" ] && stale=1
            [ src/app/extsettingscatalog.inc -nt "$o" ] && stale=1
            [ src/app/extprepare.inc -nt "$o" ] && stale=1
            [ src/app/extsettingsqueue.inc -nt "$o" ] && stale=1
            [ src/app/extsettingsini.inc -nt "$o" ] && stale=1
            [ src/app/extsettingssnapshot.inc -nt "$o" ] && stale=1
            [ src/app/extsettingsframe.inc -nt "$o" ] && stale=1
            [ src/app/extsettingswire.inc -nt "$o" ] && stale=1
            [ src/app/extsettingsmemory.inc -nt "$o" ] && stale=1
            [ src/app/extchoices.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extsettingssnapshot.s|src/app/extsettingsini.s|tests/ext_settings_snapshot_test.s|tests/ext_settings_release_test.s)
            [ src/app/extsettingssnapshot.inc -nt "$o" ] && stale=1
            [ src/app/extsettingsini.inc -nt "$o" ] && stale=1
            [ src/app/extsettingsframe.inc -nt "$o" ] && stale=1
            [ src/app/extsettingsmemory.inc -nt "$o" ] && stale=1
            [ src/app/extsettingswire.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/themecapture*.s|src/app/themeintent*.s|src/win/themecapture*.s|src/app/extsettingsnative.s|tests/theme_capture*.s|tests/theme_intent*.s)
            for h in src/app/themecapture*.inc src/app/themeintent*.inc src/app/extsettingsnative.inc src/app/extstorejob.inc src/app/extstorejoblegacy.inc src/app/extvalidate.inc; do
                [ "$h" -nt "$o" ] && stale=1
            done ;;
    esac
    case "$s" in
        src/app/extsettingsjob*.s|src/app/extsettingsmemory.s|src/app/extsettingsframe.s|tests/ext_settings_job*.s|tests/ext_settings_memory_test.s|tests/ext_settings_receipts_test.s|tests/ext_settings_release_test.s|tests/ext_settings_retire_test.s)
            [ src/app/extsettingsjob.inc -nt "$o" ] && stale=1
            [ src/app/extsettingsmemory.inc -nt "$o" ] && stale=1
            [ src/app/extsettingsframe.inc -nt "$o" ] && stale=1
            [ src/app/extsettingswire.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extruntimeservice.s|src/app/extruntimesession.s|src/app/extruntimespan.s|src/app/extruntimepromptrevoke.s|src/app/extruntimechannel.s|src/app/extruntimeticket*.s|src/app/extruntimeadmit.s|src/app/extruntimecredit.s|src/app/extruntimeterminal.s|src/app/extruntimereply*.s|src/app/extruntimeoperation.s|src/app/extruntimechannelquiet.s|src/app/extruntimesessionclock.s|src/app/extruntimeremove.s|src/app/extruntimerow.s|src/app/extruntimerevoke.s|src/app/extruntimedebt.s|src/app/extruntimedebtscan.s)
            for h in src/app/extruntimeservice.inc src/app/extruntimeticket.inc src/app/extruntimeadmit.inc src/app/extruntimereply.inc src/app/extruntimesessionclock.inc src/app/extruntimeremove.inc src/app/extruntimedebtscan.inc src/app/extruntime.inc src/app/extprepare.inc src/app/extprepareretire.inc src/app/extactivation.inc src/app/exthostidentity.inc src/app/taskauth.inc; do
                [ "$h" -nt "$o" ] && stale=1
            done ;;
    esac
    case "$s" in
        src/app/extruntime.s|tests/ext_runtime_owner_test.s)
            [ src/app/extruntime.inc -nt "$o" ] && stale=1
            [ src/app/extprepare.inc -nt "$o" ] && stale=1
            [ src/app/extprepareretire.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extpending.s|tests/ext_pending_owner_test.s)
            [ src/app/extpending.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extsettingsqueue*.s|tests/ext_settingsqueue_test.s|tests/ext_settings_release_test.s)
            [ src/app/extsettingsqueue.inc -nt "$o" ] && stale=1
            [ src/app/extsettingsmemory.inc -nt "$o" ] && stale=1
            [ src/app/extchoices.inc -nt "$o" ] && stale=1 ;;
        src/app/extsettingswire.s|tests/ext_settingswire_test.s)
            [ src/app/extsettingswire.inc -nt "$o" ] && stale=1
            [ src/app/extchoices.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extdiscoverygp*.s)
            [ src/app/extdiscoverygp.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extdiscoverygpexport.s|src/app/extdiscoverygpemit.s|src/app/extdiscoverygpimport.s|src/app/extdiscoverygprelocate.s)
            [ src/app/extdiscoverygpxfer.inc -nt "$o" ] && stale=1
            [ src/app/extdiscoveryalloc.inc -nt "$o" ] && stale=1
            [ src/app/extprepare.inc -nt "$o" ] && stale=1
            [ src/app/extprepareretire.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extdiscoveryalloc*.s|src/app/extdiscoveryenroll.s|tests/faults/discovery_alloc.s)
            [ src/app/extdiscoveryalloc.inc -nt "$o" ] && stale=1
            [ src/app/extprepare.inc -nt "$o" ] && stale=1
            [ src/app/extprepareretire.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extdiscovery*.s|tests/ext_discovery*.s)
            [ src/app/extdiscovery.inc -nt "$o" ] && stale=1
            [ src/app/extstore.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extsettingsnative*.s|src/app/extstorejobposix.s|src/win/extstorejob.s|src/win/extsettingsnative.s|tests/ext_settings_native*.s)
            [ src/app/extsettingsnative.inc -nt "$o" ] && stale=1
            [ src/app/extstorejob.inc -nt "$o" ] && stale=1
            [ src/app/extchoicesdisk.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extstorejob*.s|src/win/extstorejob*.s|tests/ext_store_job*.s)
            [ src/app/extstorejob.inc -nt "$o" ] && stale=1
            [ src/app/extstorejoblegacy.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extchoices*.s|tests/ext_choices*.s)
            [ src/app/extchoicesdisk.inc -nt "$o" ] && stale=1
            [ src/app/extchoices.inc -nt "$o" ] && stale=1
            [ src/app/extstore.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/syntax.s|src/app/theme.s|src/app/extprepare*.s|tests/ext_prepare_owner_test.s|tests/grammar_prepare_test.s|tests/theme_prepare_test.s)
            [ src/app/extprepare.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/taskcore.s|src/app/taskview.s|tests/task_core_test.s|tests/task_view_test.s)
            [ src/app/taskcore.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/taskview.s|tests/task_view_test.s)
            [ src/app/taskview.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extprepare*.s|src/app/ext.s|src/app/extvalidate.s|src/app/extvalidateexec.s|src/app/extvalidatemanifest.s|src/app/extvalidatetree.s|src/win/extprepareruntime.s|tests/ext_prepare*.s)
            [ src/app/extprepare.inc -nt "$o" ] && stale=1
            [ src/app/extvalidate.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extvalidatewire.s|tests/ext_validate_wire_test.s)
            [ src/app/extvalidatewire.inc -nt "$o" ] && stale=1 ;;
    esac
    case "$s" in
        src/app/extpreparebegin.s|src/app/extpreparelaunch.s|tests/ext_prepare_manifest_test.s)
            [ src/app/extvalidatemanifest.inc -nt "$o" ] && stale=1 ;;
    esac
    if [ -n "$stale" ] || [ ! -f "$o" ] || [ "$s" -nt "$o" ] || [ src/rhun.inc -nt "$o" ]; then
        as $ASFLAGS -o "$o" "$s"
    fi
    objs="$objs $o"
done
LDFLAGS="-static -nostdlib --no-dynamic-linker -z noexecstack"
[ "$1" = release ] && LDFLAGS="$LDFLAGS -s"
ld $LDFLAGS -o build/rhun $objs
if [ "$1" = test ]; then
    lib=$(echo $objs | tr ' ' '\n' | grep -v 'src_main.o')
    for t in tests/*.s; do
        n=$(basename "$t" .s)
        as $ASFLAGS -o "build/obj/test_$n.o" "$t"
        ld $LDFLAGS -o "build/$n" "build/obj/test_$n.o" $lib
    done
    for t in tests/linux/*.s; do
        [ -f "$t" ] || continue
        n=$(basename "$t" .s)
        as $ASFLAGS -o "build/obj/test_linux_$n.o" "$t"
        ld $LDFLAGS -o "build/$n" "build/obj/test_linux_$n.o" $lib
    done
fi
