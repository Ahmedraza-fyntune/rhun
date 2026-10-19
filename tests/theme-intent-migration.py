#!/usr/bin/env python3
"""Prepared cfg owners never alias TI/legacy bases and transfer only at checked publication."""
import argparse,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--exe',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt';exe=a.exe or ROOT/('build/windows/theme_intent_migration_test.exe'if win else'build/theme_intent_migration_test')
 for mode,name in enumerate(('abort','publish-transfer','stale-before-header','alias-bookkeeping','null-request-refusal','shared-TI-refs-and-live-pending')):
  r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),str(mode)],capture_output=True,timeout=10)
  assert r.returncode==0 and not r.stdout and not r.stderr,(name,r)
  print('ok theme-intent/migration-'+name,flush=True)
if __name__=='__main__':main()
