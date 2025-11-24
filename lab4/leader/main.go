package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand/v2"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
	// "io"
)

var (
	kv_map   = new(sync.Map)
	quorum   = 0
	Mindelay = 0
	Maxdelay = 0

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

	q_string := unwrap(os.LookupEnv("QUORUM"))
	quorum, err = strconv.Atoi(q_string)
	if err != nil {
		panic("Invalid quorum variable")
	}

	mn_string := unwrap(os.LookupEnv("MIN_DELAY"))
	Mindelay, err = strconv.Atoi(mn_string)
	mx_string := unwrap(os.LookupEnv("MAX_DELAY"))
	Maxdelay, err = strconv.Atoi(mx_string)

	if err != nil {
		panic("Failed to convert string to int")
	}
	fallower_string := unwrap(os.LookupEnv("FALLOWERS"))
	fallowers = strings.Split(fallower_string, ",")

	fmt.Println(q_string)
	fmt.Println(mn_string)
	fmt.Println(mx_string)
	fmt.Println(fallower_string)

	http.HandleFunc("/{key}/{value}", func(w http.ResponseWriter, r *http.Request) {
		key := r.PathValue("key")
		value := r.PathValue("value")

		kv_map.Store(key, value)

		resps := make(chan bool, len(fallowers))

		for _, fal := range fallowers {
			go func(fal string) {
				delay := rand.IntN(Maxdelay-Mindelay) + Mindelay
				time.Sleep(time.Millisecond * time.Duration(delay))

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

	})

	http.HandleFunc("/{key}", func(w http.ResponseWriter, r *http.Request) {
		key := r.PathValue("key")

		val, ok := kv_map.Load(key)

		if ok {
			fmt.Fprintf(w, "The value of %s is %s", key, val)
			return
		}

		fmt.Fprintf(w, "Failed to retrieve value of %v", key)
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {})

	http.HandleFunc("/check_all", func(w http.ResponseWriter, r *http.Request) {
		for _, fal := range fallowers {
			delay := rand.IntN(Maxdelay-Mindelay) + Mindelay
			time.Sleep(time.Millisecond * time.Duration(delay))

			resp, err := http.Get(fmt.Sprintf("http://%s:8080/check", fal))
			if err != nil {
				panic(err)
			}

			fal_data := make(map[string]string)

			data, err := io.ReadAll(resp.Body)

			if err := json.Unmarshal(data, &fal_data); err != nil {
				panic(err)
			}

			// check against leader data only, fallower cannot have data leader doesn't
			tests := 0
			fails := 0
			kv_map.Range(func(key, value any) bool {
				tests += 1

				fal_val, exists := fal_data[key.(string)]
				if !exists {
					fails += 1
				} else if fal_val != value {
					fails += 1
				}

				return true
			})

			fmt.Fprintf(w, "%s rate:%d\n", fal, fails/tests)
		}

	})

	fmt.Println("Server started succesfully")
	log.Fatal(http.ListenAndServe(":8080", nil))
	fmt.Println("Server stopped")
}
