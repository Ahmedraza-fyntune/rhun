;; an import WASI does not define, with a result no errno can be: it must not link
(module
  (import "wasi_snapshot_preview1" "frobnicate" (func $f (result funcref)))
  (memory (export "memory") 1)
  (table 1 funcref)
  (func (export "_start")
    (table.set (i32.const 0) (call $f))
    (call_indirect (i32.const 0))))
