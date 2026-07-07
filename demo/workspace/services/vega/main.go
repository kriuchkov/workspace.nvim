// Command vega is an HTTP greeting service in the orbit workspace. It depends on
// the shared packages/nebula module (a cross-repo edge the workspace graph
// knows about).
package main

import (
	"fmt"
	"net/http"

	"orbit/nebula"
)

// handler greets the ?name= query param via the shared nebula package.
func handler(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("name")
	fmt.Fprintln(w, nebula.New(name).Hello())
}

func main() {
	http.HandleFunc("/", handler)
	fmt.Println("vega listening on :8080")
	_ = http.ListenAndServe(":8080", nil)
}
