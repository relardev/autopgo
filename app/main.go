package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	err := http.ListenAndServe(
		":8080",
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprintf(w, "Hello, saretnirasn")
		}),
	)
	if err != nil {
		fmt.Fprintln(os.Stdout, []any{"Error starting server: ", err}...)
		os.Exit(1)
	}
}
