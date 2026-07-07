package nebula

import "testing"

func TestHello(t *testing.T) {
	if got := New("Ada").Hello(); got != "Hello, Ada! 👋" {
		t.Errorf("Hello() = %q", got)
	}
	if got := New("  ").Hello(); got != "Hello, world! 👋" {
		t.Errorf("default = %q", got)
	}
}
