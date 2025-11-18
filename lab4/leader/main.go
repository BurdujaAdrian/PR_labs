package main

import (
	"fmt"
	"log"
	"math/rand/v2"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	// "io"
)

var (
	kv_map      = new(sync.Map)
	writes      = new(atomic.Int64)
	total_delay = new(atomic.Int64)
	quorum      = 0

	fallowers []string
)

func unwrap[T any](s T, ok bool) T {
	if ok {
		return s
	}
	panic("Env variable not set")
}

func main() {

	var err error
	quorum, err = strconv.Atoi(unwrap(os.LookupEnv("QUORUM")))
	if err != nil {
		panic("Invalid quorum variable")
	}

	fallower_string := unwrap(os.LookupEnv("FALLOWERS"))
	fallowers = strings.Split(fallower_string, ",")

	http.HandleFunc("POST /{key}/{value}", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		key := r.PathValue("key")
		value := r.PathValue("value")

		kv_map.Store(key, value)

		resps := make(chan bool, len(fallowers))

		for _, fal := range fallowers {
			go func(fal string) {
				delay := rand.IntN(10000-100) + 100
				time.Sleep(time.Microsecond * time.Duration(delay))

				fmt.Println("Sending rep to", fmt.Sprintf("http://%s:8080/rep/%s/%v", fal, key, value))
				_, err := http.Get(fmt.Sprintf("http://%s:8080/rep/%s/%v", fal, key, value))
				resps <- (err == nil)

			}(fal)
		}

		quota := quorum
		for i := 0; i < len(fallowers); i += 1 {
			if <-resps {
				quota -= 1
				if quota == 0 {
					break
				}
			}

		}

		elapsed := time.Since(start)
		fmt.Fprintf(w, "Succesfully registered %s=%s", key, value)

		if quota > 0 {
			fmt.Println("Failed to send rep at at least", quorum, "fallowers")
		}

		// bookkeeping
		total_delay.Add(elapsed.Milliseconds())
		writes.Add(1)

	})

	http.HandleFunc("GET /{key}", func(w http.ResponseWriter, r *http.Request) {
		key := r.PathValue("key")

		val, ok := kv_map.Load(key)

		if ok {
			fmt.Fprintf(w, "The value of %s is %s", key, val)
			return
		}

		fmt.Fprintf(w, "Failed to retrieve value of %v", key)
	})

	fmt.Println("Server started succesfully")
	log.Fatal(http.ListenAndServe(":8080", nil))
	fmt.Println("Server stopped")
}
