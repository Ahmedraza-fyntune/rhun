// wasmtest-go: a rhun extension compiled with GOOS=wasip1 GOARCH=wasm (tests/wasm-host.py runs it
// in rhun --wasm-host). Each command answers with a toast that the test reads; "tick" shows that
// goroutines keep running while the reader waits on rhun's input.
package main

import (
	"bytes"
	"crypto/rand"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/rhun-editor/extension-protocol/go/rhunext"
)

type test struct{ ticks chan int }

func (t *test) Ready(ext *rhunext.Ext, project string) {}

func (t *test) Event(ext *rhunext.Ext, ev rhunext.Event) {}

func (t *test) Run(ext *rhunext.Ext, command string, doc rhunext.Doc) {
	switch strings.TrimPrefix(command, "wasmtest-go.") {
	case "hello":
		ext.Toast("hello from wasm")
	case "upper":
		text, version, err := ext.Text(doc)
		if err != nil {
			return
		}
		if _, err := ext.Replace(doc, version, rhunext.WholeRange(text), bytes.ToUpper(text)); err != nil {
			ext.Toast("upper failed " + err.Error())
			return
		}
		ext.Toast("upper ok")
	case "env":
		ext.Toast(fmt.Sprintf("env %s args %d", os.Getenv("RHUN_EXTENSION"), len(os.Args)))
	case "files":
		state := os.Getenv("RHUN_STATE")
		p := filepath.Join(state, "probe.txt")
		err := os.WriteFile(p, []byte("written by wasm\n"), 0o644)
		var data []byte
		if err == nil {
			data, err = os.ReadFile(p)
		}
		if err == nil {
			err = os.MkdirAll(filepath.Join(state, "sub", "deeper"), 0o755)
		}
		if err == nil {
			err = os.Rename(p, filepath.Join(state, "sub", "moved.txt"))
		}
		n := 0
		var size int64
		if err == nil {
			var entries []os.DirEntry
			entries, err = os.ReadDir(filepath.Join(state, "sub"))
			n = len(entries)
		}
		if err == nil {
			var fi os.FileInfo
			fi, err = os.Stat(filepath.Join(state, "sub", "moved.txt"))
			if fi != nil {
				size = fi.Size()
			}
		}
		if err != nil {
			ext.Toast("files failed " + err.Error())
			return
		}
		ext.Toast(fmt.Sprintf("files ok %s %d %d", strings.TrimSpace(string(data)), n, size))
	case "project":
		proj := os.Getenv("RHUN_PROJECT")
		_, rerr := os.ReadFile(filepath.Join(proj, "a.txt"))
		werr := os.WriteFile(filepath.Join(proj, "from-wasm.txt"), []byte("x"), 0o644)
		ext.Toast(fmt.Sprintf("project read=%v write=%v", rerr == nil, werr == nil))
	case "escape":
		state := os.Getenv("RHUN_STATE")
		secret := os.Getenv("WASMTEST_SECRET")
		_, a := os.ReadFile(secret)
		_, b := os.ReadFile(state + "/../../../../../../../../" + strings.TrimPrefix(secret, "/"))
		ext.Toast(fmt.Sprintf("escape absolute=%v climb=%v", a == nil, b == nil))
	case "time":
		t0 := time.Now()
		time.Sleep(20 * time.Millisecond)
		var buf [8]byte
		_, rerr := rand.Read(buf[:])
		ext.Toast(fmt.Sprintf("time %v slept=%v urandom=false random=%v", t0.Unix() > 1700000000,
			time.Since(t0) >= 20*time.Millisecond, rerr == nil))
	case "tick":
		// a goroutine counts while this handler waits on a timer: the scheduler is not held by the
		// reader blocked on standard input
		go func() {
			for i := 1; i <= 5; i++ {
				time.Sleep(5 * time.Millisecond)
				t.ticks <- i
			}
		}()
		last := 0
		for i := 0; i < 5; i++ {
			last = <-t.ticks
		}
		ext.Toast(fmt.Sprintf("ticks %d", last))
	case "spin":
		ext.Toast("spinning")
		x := uint64(0)
		for {
			x = x*6364136223846793005 + 1
			if x == 42 {
				break
			}
		}
	case "trap":
		var v []byte
		i := len(os.Getenv("NEVER")) + 7
		ext.Toast(fmt.Sprint(v[i]))
	case "exit":
		os.Exit(3)
	}
}

func main() {
	if err := rhunext.Run(&test{ticks: make(chan int)}); err != nil {
		os.Exit(1)
	}
}
