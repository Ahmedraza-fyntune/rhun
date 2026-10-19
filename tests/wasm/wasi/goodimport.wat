;; an import WASI does not define, answering an errno: it links and answers ENOSYS (52)
(module
  (import "wasi_snapshot_preview1" "frobnicate" (func $f (param i64 f64) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
  (memory (export "memory") 1)
  (func (export "_start")
    (call $exit (call $f (i64.const 1) (f64.const 2)))))
