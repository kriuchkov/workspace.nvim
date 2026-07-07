// Package nebula builds greetings. It's the shared package the services depend
// on — `<leader>cwu` would ripple a bump to every dependent repo.
package nebula

import (
	"fmt"
	"strings"
)

// Greeter builds greetings for a name. Try LSP: `gd` on Greeter, `<leader>lm`
// for its methods, the reference lens for uses across the workspace.
type Greeter struct {
	Name string
}

// New returns a Greeter for name, defaulting to "world".
func New(name string) *Greeter {
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
