// Local-only acceptance fixture. Each observable origin forwards to its own
// owned Go API process. It never logs headers, query strings or request bodies.
package main

import (
	"bufio"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

var output sync.Mutex

func report(value any) {
	output.Lock()
	defer output.Unlock()
	_ = json.NewEncoder(os.Stdout).Encode(value)
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}

func backend(binary string) (string, func()) {
	reservation, err := net.Listen("tcp", "127.0.0.1:0")
	must(err)
	port := reservation.Addr().(*net.TCPAddr).Port
	must(reservation.Close())
	command := exec.Command(binary)
	command.Env = append(os.Environ(), "HOST=127.0.0.1", fmt.Sprintf("PORT=%d", port))
	command.Stdout, command.Stderr = io.Discard, io.Discard
	must(command.Start())
	done := make(chan error, 1)
	go func() { done <- command.Wait() }()
	stop := func() {
		_ = command.Process.Signal(syscall.SIGTERM)
		select {
		case <-done:
		case <-time.After(7 * time.Second):
			_ = command.Process.Kill()
			<-done
		}
	}
	origin := fmt.Sprintf("http://127.0.0.1:%d", port)
	client := &http.Client{Timeout: time.Second}
	for deadline := time.Now().Add(15 * time.Second); time.Now().Before(deadline); {
		response, err := client.Get(origin + "/readyz")
		if err == nil {
			_ = response.Body.Close()
			if response.StatusCode == 200 {
				return origin, stop
			}
		}
		time.Sleep(25 * time.Millisecond)
	}
	stop()
	panic("owned Morse API did not become ready")
}

func certificate(directory string) (tls.Certificate, string) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	must(err)
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	must(err)
	template := &x509.Certificate{
		SerialNumber: serial, Subject: pkix.Name{CommonName: "Morse local acceptance root"},
		NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		BasicConstraintsValid: true, IsCA: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	must(err)
	cert := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	path := filepath.Join(directory, "morse-origin-ca.pem")
	must(os.WriteFile(path, cert, 0600))
	leafKey, err := rsa.GenerateKey(rand.Reader, 2048)
	must(err)
	leaf := &x509.Certificate{
		SerialNumber: new(big.Int).Add(serial, big.NewInt(1)), Subject: pkix.Name{CommonName: "Morse local acceptance server"},
		NotBefore: template.NotBefore, NotAfter: template.NotAfter,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")},
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leaf, template, &leafKey.PublicKey, key)
	must(err)
	chain := append(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: leafDER}), cert...)
	pair, err := tls.X509KeyPair(chain, pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(leafKey)}))
	must(err)
	return pair, path
}

func proxy(target, name string, pair *tls.Certificate) (string, func()) {
	upstream, err := url.Parse(target)
	must(err)
	forward := httputil.NewSingleHostReverseProxy(upstream)
	forward.FlushInterval = -1
	server := &http.Server{ReadHeaderTimeout: 5 * time.Second, ErrorLog: log.New(io.Discard, "", 0), Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		report(map[string]string{"event": "request", "origin": name, "method": r.Method, "path": r.URL.Path})
		forward.ServeHTTP(w, r)
	})}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	must(err)
	scheme := "http"
	if pair != nil {
		listener = tls.NewListener(listener, &tls.Config{Certificates: []tls.Certificate{*pair}, MinVersion: tls.VersionTLS12})
		scheme = "https"
	}
	origin := scheme + "://" + listener.Addr().String()
	go func() { _ = server.Serve(listener) }()
	return origin, func() { _ = server.Close() }
}

func main() {
	if len(os.Args) != 3 {
		panic("expected Morse binary and temporary directory")
	}
	first, stopFirst := backend(os.Args[1])
	defer stopFirst()
	second, stopSecond := backend(os.Args[1])
	defer stopSecond()
	pair, ca := certificate(os.Args[2])
	plain, closePlain := proxy(first, "plain", nil)
	defer closePlain()
	secure, closeSecure := proxy(second, "secure", &pair)
	defer closeSecure()
	report(map[string]string{"event": "ready", "plain": plain, "secure": secure, "ca": ca})
	// EOF also retires owned processes if the test exits unexpectedly.
	commands := bufio.NewScanner(os.Stdin)
	for commands.Scan() {
		if commands.Text() == "stop" {
			return
		}
		if commands.Text() == "barrier" {
			report(map[string]string{"event": "barrier"})
		}
	}
}
