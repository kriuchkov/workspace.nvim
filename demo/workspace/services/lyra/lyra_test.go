package main

import "testing"

func TestAverage(t *testing.T) {
	if got := Average([]float64{4, 5, 3}); got != 4 {
		t.Errorf("Average = %v, want 4", got)
	}
	if got := Average(nil); got != 0 {
		t.Errorf("Average(nil) = %v, want 0", got)
	}
}
