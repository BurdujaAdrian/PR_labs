package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
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

	http.HandleFunc("/{key}", func(w http.ResponseWriter, r *http.Request) {
		key := r.PathValue("key")

		val, ok := kv_map.Load(key)

		if ok {
			fmt.Printf("The value of %s is %s\n", key, val)
			fmt.Fprintf(w, "The value of %s is %s", key, val)
			return
		}

		fmt.Fprintf(w, "Failed to retrieve value of %v", key)
	})

	http.HandleFunc("/check", func(w http.ResponseWriter, r *http.Request) {

		new_map := map[string]string{}
		kv_map.Range(func(key, value any) bool {
			new_map[key.(string)] = value.(string)
			return true
		})

		data, err := json.Marshal(new_map)
		if err != nil {
			panic(err)
		}

		fmt.Fprintln(w, string(data))

	})

	fmt.Println("Server started succesfully")
	log.Fatal(http.ListenAndServe(":8080", nil))
	fmt.Println("Server stopped")
}
