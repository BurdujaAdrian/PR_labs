package main

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"testing"
)

var (
	server_lock sync.RWMutex
)

func Test_test(t *testing.T) {
	t.Log("Works")
}

func TestMain(m *testing.M) {

	if !startup_containers() {
		panic("Failed to start containers")
	}
	defer teardown_containers()

	m.Run()

}

func Test_reading_any(t *testing.T) {
	server_lock.RLock()
	defer server_lock.RUnlock()

	unwrap_err(http.Get("http://localhost:8080/any"))
	t.Log("Reading whatever Works")
}

func Test_check(t *testing.T) {
	resp := unwrap_err(http.Get("http://localhost:8080/check"))
	data := unwrap_err(io.ReadAll(resp.Body))

	lines := strings.Split(string(data), "\n")

	for i := 1; i < len(lines); i += 1 {
		line := strings.TrimSpace(lines[i])
		_, num, ok := strings.Cut(line, ":")
		if !ok {
			panic("Line was supposed to have :")
		}

		if num != "0" {
			panic("Rate of errors should have been 0")
		}
	}

}

func Test_healthy(t *testing.T) {
	unwrap_err(http.Get("http://localhost:8080/health"))
}

func Test_writing_then_reading_specific(t *testing.T) {
	server_lock.Lock()
	defer server_lock.Unlock()

	unwrap_err(http.Get("http://localhost:8080/read/exact"))
	resp := unwrap_err(http.Get("http://localhost:8080/read"))
	data := unwrap_err(io.ReadAll(resp.Body))
	expected_slice := "The value of read is exact"
	if string(data[:len(expected_slice)]) != expected_slice {
		panic(fmt.Sprint("Expected to get exactly value of read = exact, got", string(data)))
	}
	t.Log("Reading whatever Works")
}

func Test_writing_then_reading(t *testing.T) {
	server_lock.RLock()
	defer server_lock.RUnlock()

	unwrap_err(http.Get("http://localhost:8080/read/value"))
	resp := unwrap_err(http.Get("http://localhost:8080/read"))
	data := unwrap_err(io.ReadAll(resp.Body))
	expected_slice := "The value of read is"
	if string(data[:len(expected_slice)]) != expected_slice {
		panic(fmt.Sprint("Expected to get any value of read, got", string(data)))
	}
	t.Log("Reading whatever Works")
}

func unwrap_err[T any](s T, err error) T {
	if err == nil {
		return s
	}

	panic(err)
}
