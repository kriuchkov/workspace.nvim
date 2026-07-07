// Command demo is a tiny program used to explore claudespace.nvim:
// LSP, treesitter, the task/test runner, and Claude actions all work on it.
package main

import (
	"fmt"
	"os"
)

func main() {
	name := ""
	if len(os.Args) > 1 {
		name = os.Args[1]
	}
	// TODO: read the name from stdin too — a Claude command could add this.
	g := NewGreeter(name)
	fmt.Println(g.Hello())
}
