#!/bin/sh
# macOS on Apple silicon: tools/arm64.py translates the x86-64 sources to AArch64, src/mac holds
# the native parts (entry, Linux system calls on libSystem, the AppKit window)
# usage: tools/build-mac.sh [release|test]
set -e
cd "$(dirname "$0")/.."
mkdir -p build/obj build/a64
tools/gen-assets.sh > build/assets.s.new
cmp -s build/assets.s.new build/assets.s || { mv build/assets.s.new build/assets.s; rm -f build/obj/build_assets.o; }
MINOS=12.0
ASFLAGS="-arch arm64 -mmacosx-version-min=$MINOS"

# stale(obj, deps...): obj is missing or older than a dependency
stale() {
    [ -f "$1" ] || return 0
    o=$1; shift
    for d in "$@"; do [ "$d" -nt "$o" ] && return 0; done
    return 1
}
name() { echo "$1" | sed 's|/|_|g; s|\.s$||'; }

# translated sources: everything but the Linux entry and display servers
x86=$(find src -name '*.s' ! -path 'src/mac/*' ! -path 'src/win/*' ! -path src/start.s ! -path src/plat/wayland.s ! -path src/plat/x11.s ! -path src/plat/appearance.s | LC_ALL=C sort)
[ "$1" = test ] && x86="$x86 $(ls tests/*.s)"
todo=
objs=
for s in $x86 build/assets.s; do
    o=build/obj/$(name "$s").o
    if stale "$o" "$s" src/rhun.inc tools/arm64.py ||
        { case "$s" in src/app/catalogretire.s|src/app/catalogregistry*.s|tests/catalog*_test.s) catalog_stale=0; for h in src/app/catalogretire.inc src/app/catalogregistry.inc src/app/catalogregistrywork.inc src/app/catalogregistrymap.inc src/app/extprepare.inc src/app/extprepareretire.inc src/app/extvalidate.inc; do [ "$h" -nt "$o" ] && catalog_stale=1; done; [ "$catalog_stale" = 1 ];; *) false;; esac; } ||
        { [ "$s" = src/app/extproto.s ] && [ src/app/extwatchproto.inc -nt "$o" ]; } ||
        { [ "$s" = src/app/extproto.s ] && [ src/app/extprotoevents.inc -nt "$o" ]; } ||
        { [ "$s" = src/app/ext.s ] && [ src/app/extvalidateparse.inc -nt "$o" ]; } ||
        { [ "$s" = src/app/extvalidatemanifest.s ] && [ src/app/extvalidatemanifest.inc -nt "$o" ]; } ||
        { [ "$s" = src/app/extvalidatetree.s ] && [ src/app/extvalidatetree.inc -nt "$o" ]; } ||
        { case "$s" in src/app/extprepare*.s|src/app/extlaunchscratch.s|src/app/extvalidate*.s|src/app/ext.s|src/app/syntax.s|src/app/theme.s|tests/*.s|tests/faults/*.s) [ src/app/extprepare.inc -nt "$o" ] || [ src/app/extpreparelegacy.inc -nt "$o" ] || [ src/app/extprepareretire.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extsettingsworker*.s|tests/ext_settings_worker_test.s) [ src/app/extsettingsworker.inc -nt "$o" ] || [ src/app/extsettingswire.inc -nt "$o" ] || [ src/app/extchoices.inc -nt "$o" ] || [ src/app/extchoicesdisk.inc -nt "$o" ] || [ src/app/extstore.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extsettingsservice*.s|src/app/extsettingsadoption*.s|src/app/extsettingsrequest*.s|tests/ext_settings_service*.s|tests/ext_settings_adoption*.s|tests/ext_settings_request*.s) service_stale=0; for h in src/app/extsettingsadoption.inc src/app/extsettingsservice.inc src/app/extprepare.inc src/app/extprepareretire.inc src/app/extvalidate.inc src/app/extsettingsrequest.inc src/app/extsettingscatalog.inc src/app/extsettingsview.inc src/app/extsettingsini.inc src/app/extsettingsjob.inc src/app/extsettingssnapshot.inc src/app/extsettingsqueue.inc src/app/extsettingsframe.inc src/app/extsettingswire.inc src/app/extsettingsmemory.inc src/app/extchoices.inc; do if [ "$h" -nt "$o" ]; then service_stale=1; fi; done; [ "$service_stale" = 1 ];; *) false;; esac; } ||
        { case "$s" in src/app/exthost*.s|src/app/extmetadata.s|src/app/extvisibility.s|src/app/extoutputslot.s|src/app/extactivation*.s|tests/ext_host*.s|tests/ext_metadata_borrowers_test.s|tests/ext_activation_owner_test.s|tests/extension_lifecycle_test.s) metadata_stale=0; for h in src/app/exthostidentity.inc src/app/extprepare.inc src/app/extprepareretire.inc src/app/extactivation.inc src/app/taskauth.inc src/app/taskproc.inc src/app/extvalidate.inc; do [ "$h" -nt "$o" ] && metadata_stale=1; done; [ "$metadata_stale" = 1 ];; *) false;; esac; } ||
        { case "$s" in src/app/extactivation*.s|tests/ext_activation_owner_test.s|tests/extension_lifecycle_test.s) [ src/app/extactivation.inc -nt "$o" ] || [ src/app/taskauth.inc -nt "$o" ] || [ src/app/extprepare.inc -nt "$o" ] || [ src/app/extprepareretire.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ] || [ tests/ext_activation_lifecycle_helpers.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/commandgeneration*.s|tests/command_generation*.s) [ src/app/commandgeneration.inc -nt "$o" ] || [ src/app/keylinesnapshot.inc -nt "$o" ] || [ src/app/extprepare.inc -nt "$o" ] || [ src/app/extprepareretire.inc -nt "$o" ] || [ src/app/extruntime.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ] || [ src/app/keycombo.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/keyline*.s) [ src/app/keylinesnapshot.inc -nt "$o" ] || [ src/app/commandgeneration.inc -nt "$o" ] || [ src/app/extprepare.inc -nt "$o" ] || [ src/app/extprepareretire.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ] || [ src/app/keycombo.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/keycombo.s|tests/keycombo_test.s) [ src/app/keycombo.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extsettingsview*.s|src/app/extsettingsmodel*.s|src/app/extsettingscatalog*.s|src/app/extsettingsprovider*.s|src/app/extsettingseditor.s|src/app/extsettingsactive.s|src/app/extsettingscanonical.s|src/app/extsettingseffective.s|src/app/extsettingsflags.s|tests/ext_settings_view_test.s) [ src/app/extsettingsview.inc -nt "$o" ] || [ src/app/extsettingscatalog.inc -nt "$o" ] || [ src/app/extprepare.inc -nt "$o" ] || [ src/app/extsettingsqueue.inc -nt "$o" ] || [ src/app/extsettingsini.inc -nt "$o" ] || [ src/app/extsettingssnapshot.inc -nt "$o" ] || [ src/app/extsettingsframe.inc -nt "$o" ] || [ src/app/extsettingswire.inc -nt "$o" ] || [ src/app/extsettingsmemory.inc -nt "$o" ] || [ src/app/extchoices.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extsettingssnapshot.s|src/app/extsettingsini.s|tests/ext_settings_snapshot_test.s|tests/ext_settings_release_test.s) [ src/app/extsettingssnapshot.inc -nt "$o" ] || [ src/app/extsettingsini.inc -nt "$o" ] || [ src/app/extsettingsframe.inc -nt "$o" ] || [ src/app/extsettingsmemory.inc -nt "$o" ] || [ src/app/extsettingswire.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/themecapture*.s|src/app/themeintent*.s|src/win/themecapture*.s|src/app/extsettingsnative.s|tests/theme_capture*.s|tests/theme_intent*.s) theme_stale=0; for h in src/app/themecapture*.inc src/app/themeintent*.inc src/app/extsettingsnative.inc src/app/extstorejob.inc src/app/extstorejoblegacy.inc src/app/extvalidate.inc; do [ "$h" -nt "$o" ] && theme_stale=1; done; [ "$theme_stale" = 1 ];; *) false;; esac; } ||
        { case "$s" in src/app/extsettingsjob*.s|src/app/extsettingsmemory.s|src/app/extsettingsframe.s|tests/ext_settings_job*.s|tests/ext_settings_memory_test.s|tests/ext_settings_receipts_test.s|tests/ext_settings_release_test.s|tests/ext_settings_retire_test.s) [ src/app/extsettingsjob.inc -nt "$o" ] || [ src/app/extsettingsmemory.inc -nt "$o" ] || [ src/app/extsettingsframe.inc -nt "$o" ] || [ src/app/extsettingswire.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extruntimeservice.s|src/app/extruntimesession.s|src/app/extruntimespan.s|src/app/extruntimepromptrevoke.s|src/app/extruntimechannel.s|src/app/extruntimeticket*.s|src/app/extruntimeadmit.s|src/app/extruntimecredit.s|src/app/extruntimeterminal.s|src/app/extruntimereply*.s|src/app/extruntimeoperation.s|src/app/extruntimechannelquiet.s|src/app/extruntimesessionclock.s|src/app/extruntimeremove.s|src/app/extruntimerow.s|src/app/extruntimerevoke.s|src/app/extruntimedebt.s|src/app/extruntimedebtscan.s) runtime_stale=0; for h in src/app/extruntimeservice.inc src/app/extruntimeticket.inc src/app/extruntimeadmit.inc src/app/extruntimereply.inc src/app/extruntimesessionclock.inc src/app/extruntimeremove.inc src/app/extruntimedebtscan.inc src/app/extruntime.inc src/app/extprepare.inc src/app/extprepareretire.inc src/app/extactivation.inc src/app/exthostidentity.inc src/app/taskauth.inc; do [ "$h" -nt "$o" ] && runtime_stale=1; done; [ "$runtime_stale" = 1 ];; *) false;; esac; } ||
        { case "$s" in src/app/extruntime.s|tests/ext_runtime_owner_test.s) [ src/app/extruntime.inc -nt "$o" ] || [ src/app/extprepare.inc -nt "$o" ] || [ src/app/extprepareretire.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extpending.s|src/app/extpendingdispatch.s|tests/ext_pending_owner_test.s) [ src/app/extpending.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extsettingsqueue*.s|tests/ext_settingsqueue_test.s|tests/ext_settings_release_test.s) [ src/app/extsettingsqueue.inc -nt "$o" ] || [ src/app/extsettingsmemory.inc -nt "$o" ] || [ src/app/extchoices.inc -nt "$o" ];; src/app/extsettingswire.s|tests/ext_settingswire_test.s) [ src/app/extsettingswire.inc -nt "$o" ] || [ src/app/extchoices.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extdiscoverygp*.s) [ src/app/extdiscoverygp.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extdiscoverygpexport.s|src/app/extdiscoverygpemit.s|src/app/extdiscoverygpimport.s|src/app/extdiscoverygprelocate.s) [ src/app/extdiscoverygpxfer.inc -nt "$o" ] || [ src/app/extdiscoveryalloc.inc -nt "$o" ] || [ src/app/extprepare.inc -nt "$o" ] || [ src/app/extprepareretire.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extdiscoveryalloc*.s|src/app/extdiscoveryenroll.s|tests/faults/discovery_alloc.s) [ src/app/extdiscoveryalloc.inc -nt "$o" ] || [ src/app/extprepare.inc -nt "$o" ] || [ src/app/extprepareretire.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extdiscovery*.s|tests/ext_discovery*.s) [ src/app/extdiscovery.inc -nt "$o" ] || [ src/app/extstore.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extsettingsnative*.s|src/app/extstorejobposix.s|src/win/extstorejob.s|src/win/extsettingsnative.s|tests/ext_settings_native*.s) [ src/app/extsettingsnative.inc -nt "$o" ] || [ src/app/extstorejob.inc -nt "$o" ] || [ src/app/extchoicesdisk.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extstorejob*.s|src/win/extstorejob*.s|tests/ext_store_job*.s) [ src/app/extstorejob.inc -nt "$o" ] || [ src/app/extstorejoblegacy.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extchoices.s|tests/ext_choices_test.s) [ src/app/extchoices.inc -nt "$o" ];; src/app/extvalidate*.s|src/mac/extvalidatepath.s|src/win/extvalidate*.s|tests/ext_validate*.s|tests/ext_root_test.s) [ src/app/extvalidate.inc -nt "$o" ];; src/app/extstore*.s|tests/ext_store*.s) [ src/app/extstore.inc -nt "$o" ];; src/app/task*.s|tests/task*.s|tests/extension_lifecycle_test.s) [ src/app/taskproc.inc -nt "$o" ] || [ src/app/taskauth.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extchoices*.s|tests/ext_choices*.s) [ src/app/extchoicesdisk.inc -nt "$o" ] || [ src/app/extchoices.inc -nt "$o" ] || [ src/app/extstore.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/syntax.s|src/app/theme.s|src/app/extprepare*.s|tests/ext_prepare_owner_test.s|tests/grammar_prepare_test.s|tests/theme_prepare_test.s) [ src/app/extprepare.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/taskcore.s|src/app/taskview.s|tests/task_core_test.s|tests/task_view_test.s) [ src/app/taskcore.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/taskview.s|tests/task_view_test.s) [ src/app/taskview.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extprepare*.s|src/app/ext.s|src/app/extvalidate.s|src/app/extvalidateexec.s|src/app/extvalidatemanifest.s|src/app/extvalidatetree.s|tests/ext_prepare*.s) [ src/app/extprepare.inc -nt "$o" ] || [ src/app/extvalidate.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extvalidatewire.s|tests/ext_validate_wire_test.s) [ src/app/extvalidatewire.inc -nt "$o" ];; *) false;; esac; } ||
        { case "$s" in src/app/extpreparebegin.s|src/app/extpreparelaunch.s|tests/ext_prepare_manifest_test.s) [ src/app/extvalidatemanifest.inc -nt "$o" ];; *) false;; esac; } ||
        { [ "$s" = build/assets.s ] && [ -n "$(find runtime assets/fonts -newer "$o" -print -quit)" ]; }; then
        todo="$todo $s"
    fi
    case $s in tests/*) ;; *) objs="$objs $o" ;; esac
done
if [ -n "$todo" ]; then
    printf '%s\n' $todo | xargs -P "$(sysctl -n hw.ncpu)" -n 1 sh -c '
        n=$(echo "$1" | sed "s|/|_|g; s|\.s$||")
        python3 tools/arm64.py -I src -D MACOS "$1" "build/a64/$n.s" &&
        as '"$ASFLAGS"' -o "build/obj/$n.o" "build/a64/$n.s"' sh
fi
for s in src/mac/*.s; do
    o=build/obj/$(name "$s").o
    stale "$o" "$s" src/mac/mac.inc && as $ASFLAGS -I src/mac -o "$o" "$s"
    objs="$objs $o"
done

LIBS="-framework AppKit -framework QuartzCore -framework IOSurface -framework CoreServices -framework Carbon"
link() { # out objs...
    out=$1; shift
    clang -arch arm64 -mmacosx-version-min=$MINOS -o "$out" "$@" $LIBS
}
link build/rhun $objs
[ "$1" = release ] && strip -x build/rhun

# build/rhun.app, signed ad hoc for this machine (tools/package-mac.sh signs for distribution)
app=build/rhun.app/Contents
mkdir -p $app/MacOS $app/Resources
# a new file, not rewritten in place: a running rhun keeps its code pages
cp build/rhun $app/MacOS/rhun.new && mv -f $app/MacOS/rhun.new $app/MacOS/rhun
[ -f assets/icons/rhun.icns ] && cp assets/icons/rhun.icns $app/Resources/rhun.icns
# the bundle versions are numbers only: a prerelease suffix (-rc1) is left out
sed "s/@VERSION@/$(sed "s/-.*//" VERSION)/" assets/mac/Info.plist > $app/Info.plist
codesign -s - -f build/rhun.app 2>/dev/null
if [ "$1" = test ]; then
    lib=$(echo $objs | tr ' ' '\n' | grep -v 'src_main.o')
    for t in tests/*.s; do
        n=$(basename "$t" .s)
        link "build/$n" build/obj/tests_$n.o $lib
    done
    for t in tests/mac/*.s; do
        [ -f "$t" ] || continue
        n=mac_$(basename "$t" .s)
        o=build/obj/tests_$n.o
        as $ASFLAGS -I src/mac -o "$o" "$t"
        helper="${t%_test.s}_helper.m"
        if [ -f "$helper" ]; then
            h=build/obj/tests_${n}_helper.o
            clang $ASFLAGS -fobjc-arc -Wall -Wextra -Werror -c "$helper" -o "$h"
            link "build/$n" "$o" "$h" $lib
        else
            link "build/$n" "$o" $lib
        fi
    done
fi
