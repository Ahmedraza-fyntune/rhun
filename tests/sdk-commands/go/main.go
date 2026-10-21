// The Go SDK's protocol 1.1 commands in rhun (tests/ext-sdk-commands.py): invocations with FROM
// and bodies, a status item with a command reference, run-command, calls and context keys. Each
// line it writes to standard error (the extension's log) is checked by the test.
package main

import (
	"fmt"
	"os"

	"github.com/rhun-editor/extension-protocol/go/rhunext"
)

type sample struct{}

func logf(format string, a ...any) { fmt.Fprintf(os.Stderr, format+"\n", a...) }

func code(err error) string {
	if e, ok := err.(*rhunext.Error); ok {
		return e.Code
	}
	if err != nil {
		return err.Error()
	}
	return "ok"
}

func (sample) Ready(e *rhunext.Ext, _ string) {
	err := e.SetStatusItem(rhunext.StatusItem{Name: "go", Align: "left", Priority: 9, Text: "$(play) Sample",
		Tooltip: "Run the sample", Command: "say", Args: []byte("from the status bar")})
	logf("status %s", code(err))
	logf("context %s", code(e.SetContext("mode", "ready")))
}

func (sample) Run(*rhunext.Ext, string, rhunext.Doc) {}
func (sample) Event(*rhunext.Ext, rhunext.Event)     {}

func (sample) Invoke(e *rhunext.Ext, inv rhunext.Invocation) {
	line := fmt.Sprintf("invoke %s doc=%d from=%s", inv.Name(), inv.Doc, inv.From)
	if t, args, ok := inv.Target(); ok {
		line += fmt.Sprintf(" target=%s path=%s args=%s", t.Kind, t.Path(), args)
	} else {
		line += " body=" + string(inv.Body)
	}
	logf("%s", line)
	switch inv.Name() {
	case "jump":
		_, err := e.RunCommand("goto_line", []byte("2"))
		logf("goto_line %s", code(err))
	case "ask_other":
		res, err := e.RunCommand("bob/other.answer", []byte("question"))
		logf("call result=%s %s", res, code(err))
	case "mode":
		logf("mode %s %s", inv.Body, code(e.SetContext("mode", string(inv.Body))))
	}
}

func (sample) Call(_ *rhunext.Ext, c rhunext.CallRequest) ([]byte, error) {
	logf("call %s from %s args=%s", c.Name(), c.Caller, c.Args)
	return append([]byte("answer to "), c.Args...), nil
}

func main() {
	rhunext.RunWith([]string{rhunext.FeatureCommandArgs, rhunext.FeatureContextKeys, rhunext.FeatureStatusItems}, sample{})
}
