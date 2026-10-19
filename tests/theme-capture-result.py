#!/usr/bin/env python3
"""Refcounted result borrows survive staged request cleanup and end at wire consumption."""
import argparse,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--exe',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt';exe=a.exe or ROOT/('build/windows/theme_capture_result_test.exe'if win else'build/theme_capture_result_test')
 r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
 assert r.returncode==0 and not r.stdout and not r.stderr,r
 print('ok theme-capture-result/owned-request-wire-capacity-and-borrowed-views',flush=True)
if __name__=='__main__':main()
