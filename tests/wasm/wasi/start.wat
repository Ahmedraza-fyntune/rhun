;; a start section that calls WASI before the instance exists for the host: it must work
(module
  (import "wasi_snapshot_preview1" "args_sizes_get" (func $sizes (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 64) "start ok\n")
  (func $s
    (drop (call $sizes (i32.const 0) (i32.const 4)))
    (i32.store (i32.const 16) (i32.const 64))
    (i32.store (i32.const 20) (i32.const 9))
    (drop (call $write (i32.const 1) (i32.const 16) (i32.const 1) (i32.const 24))))
  (start $s)
  (func (export "_start")))
