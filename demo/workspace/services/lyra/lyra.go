// Command lyra is a tiny service in the orbit workspace that averages scores.
// It shares the nebula package with the other services.
package main

import (
	"fmt"

	"orbit/nebula"
)

// Average returns the mean of scores, or 0 for an empty slice.
func Average(scores []float64) float64 {
	if len(scores) == 0 {
		return 0
	}
	var sum float64
	for _, s := range scores {
		sum += s
	}
	return sum / float64(len(scores))
}

func main() {
	avg := Average([]float64{4, 5, 3})
	fmt.Printf("%s Your average rating is %.1f\n", nebula.New("").Hello(), avg)
}
