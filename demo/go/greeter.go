package main

import (
	"fmt"
	"strings"
)

// Greeter builds greetings for a name. Try LSP here: `gd` on Greeter jumps to
// this type, `<leader>lm` lists its methods, and the reference lens shows uses.
type Greeter struct {
	Name string
}

// NewGreeter returns a Greeter for name, defaulting to "world".
func NewGreeter(name string) *Greeter {
	name = strings.TrimSpace(name)
	if name == "" {
		name = "world"
	}
	return &Greeter{Name: name}
}

// Hello returns a friendly greeting.
func (g *Greeter) Hello() string {
	return fmt.Sprintf("Hello, %s! 👋", g.Name)
}

// Shout returns an emphatic greeting.
func (g *Greeter) Shout() string {
	return strings.ToUpper(g.Hello()) + " 🎉"
}
