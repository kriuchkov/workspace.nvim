package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/?name=Ada", nil)
	rec := httptest.NewRecorder()
	handler(rec, req)
	if !strings.Contains(rec.Body.String(), "Hello, Ada!") {
		t.Errorf("body = %q", rec.Body.String())
	}
}
