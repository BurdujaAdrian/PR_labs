package main

import (
	"fmt"
	"image/color"
	"io"
	"math/rand/v2"
	"net/http"
	"os"
	"os/exec"
	"slices"
	"time"

	"gonum.org/v1/plot"
	"gonum.org/v1/plot/plotter"
	"gonum.org/v1/plot/vg"
)

func main() {

	data := [5][100]time.Duration{}
	keys := [10]string{"apple", "board", "cap", "dinosaur", "elf", "gay", "hash", "incense", "joy", "koala"}

	defer func(data *[5][100]time.Duration) {
		p := plot.New()
		p.Title.Text = "Performance test"
		p.X.Label.Text = "Quorum"
		p.Y.Label.Text = "Delay in ms"

		p.X.Max = 6
		p.X.Min = 0
		p.Y.Min = 0

		fmt.Println("Starting plotting process")

		median_plt := plotter.XYs{}
		average_plt := plotter.XYs{}
		for i := range 5 {
			average_data := int64(0)

			for k := range data[i] {
				average_data += data[i][k].Microseconds()
			}
			average_data /= 100

			slices.Sort(data[i][:])
			median_data := data[i][50].Microseconds()

			median_plt = append(median_plt, plotter.XY{X: float64(i + 1), Y: float64(median_data) / 1000})
			average_plt = append(average_plt, plotter.XY{X: float64(i + 1), Y: float64(average_data) / 1000})
		}
		fmt.Println("Calculated data")

		median_line, err := plotter.NewLine(median_plt)
		if err != nil {
			panic(err)
		}
		median_line.Color = color.RGBA{R: 255, A: 255}

		average_line, err := plotter.NewLine(average_plt)
		if err != nil {
			panic(err)
		}
		average_line.Color = color.RGBA{G: 255, A: 255}

		p.Add(median_line, average_line)

		p.Legend.Add("Median", median_line)
		p.Legend.Add("Average", average_line)

		fmt.Println("Defined lines")

		if err := p.Save(8*vg.Inch, 6*vg.Inch, "performance.png"); err != nil {
			fmt.Printf("Error saving plot: %v", err)
			return
		}

		fmt.Println("Succesfully wrote to a file")

	}(&data)

	for quorum := range data {
		byte_buff := []byte{}
		if err := os.WriteFile("./.env", fmt.Appendf(byte_buff, "quorum=%d", quorum+1), 0644); err != nil {
			fmt.Print(err)
			return
		}
		fmt.Println("Succesfully wrote to the file", quorum+1)

		startup_containers()

		fmt.Println("Succesfully started the containers, quorum = ", quorum+1)

		for i := range 10 {
			time_chan := make(chan time.Duration, 10)

			for k := range 10 {
				go func(key, rand_key string, time_chan chan time.Duration) {
					start := time.Now()

					_, _ = http.Get(fmt.Sprintf("http://localhost:8080/%s/%v", key, rand_key))

					elapsed := time.Since(start)
					time_chan <- elapsed

				}(keys[k], keys[rand.IntN(len(keys))], time_chan)
			}

			for k := range 10 {
				elapsed := <-time_chan
				if elapsed <= 0 {
					panic("Elapsed should not be 0")
				}
				data[quorum][i*10+k] = elapsed
			}

			close(time_chan)

		}

		fmt.Println("Checking data integrity")

		resp, err := http.Get("http://localhost:8080/check_all")
		if err != nil {
			fmt.Println("Failed to check data")
			panic(err)
		}

		data, _ := io.ReadAll(resp.Body)
		fmt.Println("Checking results:\n", string(data))

		teardown_containers()

		fmt.Println("Succesfully stopped the containers")

	}
}

func startup_containers() bool {
	cmd := exec.Command("docker", "compose", "up", "-d")
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		fmt.Print(err)
		return false
	}
	if err := cmd.Wait(); err != nil {
		fmt.Print(err)
		return false
	}

	return true
}

func teardown_containers() bool {
	end_cmd := exec.Command("docker", "compose", "down")

	if err := end_cmd.Start(); err != nil {
		fmt.Print(err)
		return false
	}
	if err := end_cmd.Wait(); err != nil {
		fmt.Print(err)
		return false
	}

	return true

}
