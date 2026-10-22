//! wasmtest: a rhun extension compiled to wasm32-wasip1 (tests/wasm-host.py runs it in
//! rhun --wasm-host). Each command answers with a toast that the test reads.

use rhun_ext::{run, whole_range, Doc, Ext, Handler};
use std::fs;
use std::io::Read;

struct Test;

fn toast(ext: &Ext, text: &str) {
    let _ = ext.toast(text);
}

impl Handler for Test {
    fn command(&mut self, ext: &Ext, name: &str, doc: Doc) {
        match name {
            "hello" => toast(ext, "hello from wasm"),
            "upper" => {
                let Ok((text, version)) = ext.text(doc) else { return };
                let upper = String::from_utf8_lossy(&text).to_uppercase();
                match ext.replace(doc, version, whole_range(&text), &upper) {
                    Ok(_) => toast(ext, "upper ok"),
                    Err(e) => toast(ext, &format!("upper failed {e}")),
                }
            }
            "env" => {
                let v = std::env::var("RHUN_EXTENSION").unwrap_or_default();
                let args: Vec<String> = std::env::args().collect();
                toast(ext, &format!("env {v} args {}", args.len()));
            }
            "files" => {
                // the state folder is the extension's to write
                let state = std::env::var("RHUN_STATE").unwrap_or_default();
                let path = format!("{state}/probe.txt");
                let res = fs::write(&path, b"written by wasm\n")
                    .and_then(|_| fs::read_to_string(&path))
                    .and_then(|s| {
                        fs::create_dir_all(format!("{state}/sub/deeper"))?;
                        fs::rename(&path, format!("{state}/sub/moved.txt"))?;
                        let n = fs::read_dir(format!("{state}/sub"))?.count();
                        let len = fs::metadata(format!("{state}/sub/moved.txt"))?.len();
                        Ok(format!("{} {n} {len}", s.trim()))
                    });
                match res {
                    Ok(s) => toast(ext, &format!("files ok {s}")),
                    Err(e) => toast(ext, &format!("files failed {e}")),
                }
            }
            "project" => {
                // readable with project = read, writable only with project = write
                let proj = std::env::var("RHUN_PROJECT").unwrap_or_default();
                let read = fs::read_to_string(format!("{proj}/a.txt")).map(|s| s.len());
                let write = fs::write(format!("{proj}/from-wasm.txt"), b"x");
                toast(ext, &format!("project read={} write={}", read.is_ok(), write.is_ok()));
            }
            "escape" => {
                // outside every allowed folder: an absolute path, and climbing out with ..
                let state = std::env::var("RHUN_STATE").unwrap_or_default();
                let secret = std::env::var("WASMTEST_SECRET").unwrap_or_default();
                let a = fs::read_to_string(&secret).is_ok();
                let b = fs::File::open(format!("{state}/../../../../../../../../{}", secret.trim_start_matches('/')))
                    .map(|mut f| {
                        let mut s = String::new();
                        f.read_to_string(&mut s).is_ok()
                    })
                    .unwrap_or(false);
                toast(ext, &format!("escape absolute={a} climb={b}"));
            }
            "time" => {
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_secs())
                    .unwrap_or(0);
                let t0 = std::time::Instant::now();
                std::thread::sleep(std::time::Duration::from_millis(20));
                let slept = t0.elapsed().as_millis();
                let mut seed = [0u8; 16];
                let random = fs::File::open("/dev/urandom").is_ok();
                let h = std::collections::hash_map::RandomState::new();
                let _ = (&mut seed, h);
                toast(ext, &format!("time {} slept={} urandom={random}", now > 1_700_000_000, slept >= 20));
            }
            "spin" => {
                toast(ext, "spinning");
                let mut x: u64 = 0;
                loop {
                    x = x.wrapping_mul(6364136223846793005).wrapping_add(1);
                    if x == 42 {
                        break;
                    }
                }
            }
            "trap" => {
                let v: Vec<u8> = Vec::new();
                let i = std::env::var("NEVER").map(|s| s.len()).unwrap_or(7);
                toast(ext, &format!("{}", v[i]));
            }
            "own" => {
                // its own folder, read only: the manifest next to bin/, found from the module's path
                let module = std::env::args().next().unwrap_or_default();
                let dir = std::path::Path::new(&module).parent().and_then(|p| p.parent());
                let read = dir.map(|d| fs::read_to_string(d.join("extension.ini")).is_ok()).unwrap_or(false);
                let write = dir.map(|d| fs::write(d.join("x.txt"), b"x").is_ok()).unwrap_or(false);
                toast(ext, &format!("own read={read} write={write}"));
            }
            "exit" => std::process::exit(3),
            _ => {}
        }
    }
}

fn main() {
    if let Err(e) = run(&[], Test) {
        eprintln!("wasmtest: {e}");
    }
}
