//! The Rust SDK's protocol 1.1 commands in rhun (tests/ext-sdk-commands.py): the same program as
//! ../go/main.go, line for line in its log (standard error).

use rhun_ext::{run, CallRequest, Error, Ext, Feature, Handler, Invocation, StatusItem};

struct Sample;

fn code<T>(r: &Result<T, Error>) -> String {
    match r {
        Ok(_) => "ok".into(),
        Err(e) => e.code.clone(),
    }
}

impl Handler for Sample {
    fn ready(&mut self, ext: &Ext, _project: Option<&str>) {
        let r = ext.set_status_item(&StatusItem {
            name: "go".into(),
            align: "left".into(),
            priority: 9,
            text: "$(play) Sample".into(),
            tooltip: "Run the sample".into(),
            command: "say".into(),
            args: b"from the status bar".to_vec(),
            ..Default::default()
        });
        eprintln!("status {}", code(&r));
        eprintln!("context {}", code(&ext.set_context("mode", "ready")));
    }

    fn invoke(&mut self, ext: &Ext, inv: &Invocation) {
        let mut line = format!("invoke {} doc={} from={}", inv.name, inv.doc, inv.from);
        match inv.target() {
            Some((t, args)) => line += &format!(
                " target={} path={} args={}",
                t.kind,
                t.path().unwrap_or(""),
                String::from_utf8_lossy(args)
            ),
            None => line += &format!(" body={}", String::from_utf8_lossy(&inv.body)),
        }
        eprintln!("{line}");
        match inv.name.as_str() {
            "jump" => eprintln!("goto_line {}", code(&ext.run_command("goto_line", b"2"))),
            "ask_other" => {
                let r = ext.run_command("bob/other.answer", b"question");
                let res = r.as_ref().map(|b| String::from_utf8_lossy(b).into_owned()).unwrap_or_default();
                eprintln!("call result={res} {}", code(&r));
            }
            "mode" => {
                let v = String::from_utf8_lossy(&inv.body).into_owned();
                eprintln!("mode {v} {}", code(&ext.set_context("mode", &v)));
            }
            _ => {}
        }
    }

    fn call(&mut self, _ext: &Ext, req: &CallRequest) -> Result<Vec<u8>, Error> {
        eprintln!("call {} from {} args={}", req.name, req.caller, String::from_utf8_lossy(&req.args));
        Ok([&b"answer to "[..], &req.args].concat())
    }
}

fn main() {
    run(&[Feature::CommandArgs, Feature::ContextKeys, Feature::StatusItems], Sample).unwrap();
}
