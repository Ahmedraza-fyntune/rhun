;; a module that asks for more memory at the start than the cap allows does not run
(module
  (memory (export "memory") 5000)
  (func (export "_start")))
