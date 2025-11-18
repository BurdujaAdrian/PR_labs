package main

import (
	"fmt"
	"log"
	"net/http"
	"sync"
	// "io"
)

var (
	kv_map = new(sync.Map)
)

func main() {

	http.HandleFunc("/rep/{key}/{value}", func(w http.ResponseWriter, r *http.Request) {
		key := r.PathValue("key")
		value := r.PathValue("value")

		kv_map.Store(key, value)

		fmt.Printf("Succesfully registered %s=%s\n", key, value)
		fmt.Fprintf(w, "Succesfully registered %s=%s", key, value)

	})

	http.HandleFunc("GET /{key}", func(w http.ResponseWriter, r *http.Request) {
		key := r.PathValue("key")

		val, ok := kv_map.Load(key)

		if ok {
			fmt.Printf("The value of %s is %s\n", key, val)
			fmt.Fprintf(w, "The value of %s is %s", key, val)
			return
		}

		fmt.Fprintf(w, "Failed to retrieve value of %v", key)
	})

	fmt.Println("Server started succesfully")
	log.Fatal(http.ListenAndServe(":8080", nil))
	fmt.Println("Server stopped")
}
