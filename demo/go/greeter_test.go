package main

import "testing"

func TestGreeterHello(t *testing.T) {
	cases := map[string]string{
		"Ada": "Hello, Ada! 👋",
		"":    "Hello, world! 👋",
		"  ":  "Hello, world! 👋",
	}
	for in, want := range cases {
		if got := NewGreeter(in).Hello(); got != want {
			t.Errorf("NewGreeter(%q).Hello() = %q, want %q", in, got, want)
		}
	}
}

func TestGreeterShout(t *testing.T) {
	if got := NewGreeter("Ada").Shout(); got != "HELLO, ADA! 👋 🎉" {
		t.Errorf("Shout() = %q", got)
	}
}
