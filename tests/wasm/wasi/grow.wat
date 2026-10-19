;; linear memory is capped at 256 MB (4096 pages): growing past it answers -1, growing within it
;; answers the old size; the exit status says both (3)
(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
  (memory (export "memory") 1)
  (func (export "_start")
    (call $exit
      (i32.add
        (i32.eq (memory.grow (i32.const 5000)) (i32.const -1))
        (i32.shl (i32.eq (memory.grow (i32.const 100)) (i32.const 1)) (i32.const 1))))))
