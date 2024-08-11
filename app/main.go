package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/pprof"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	if false {
		// Get all environment variables
		envs := os.Environ()

		// Print each environment variable
		for _, env := range envs {
			fmt.Println(env)
		}
	}

	if false {
		panic("This is a panic")
	}

	fmt.Println("got args:", os.Args)

	fmt.Println("Starting server on port 8080")

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGINT, syscall.SIGTERM)

	time.Sleep(3 * time.Second)

	mux := http.NewServeMux()

	mux.HandleFunc("/debug/pprof/profile", pprof.Profile)
	mux.HandleFunc("/check", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "with_pgo")
	})
	server := &http.Server{
		Addr:    ":8080",
		Handler: mux,
	}

	go func() {
		err := server.ListenAndServe()
		if err != http.ErrServerClosed {
			fmt.Fprintln(os.Stdout, []any{"Error starting server: ", err}...)
		}
	}()

	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		fmt.Fprintln(os.Stdout, []any{"Error shutting down server: ", err}...)
		os.Exit(1)
	}

	fmt.Println("Pretending to do some cleanup work... for 2 seconds")
	time.Sleep(2 * time.Second)
	fmt.Println("Server stopped")
}
