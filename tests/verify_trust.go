// Verify the same Go x509 trust semantics used by Xray and sing-box.
package main

import (
    "crypto/x509"
    "encoding/pem"
    "fmt"
    "os"
    "path/filepath"
)

func cert(path string) *x509.Certificate {
    data, err := os.ReadFile(path)
    if err != nil { panic(err) }
    block, _ := pem.Decode(data)
    c, err := x509.ParseCertificate(block.Bytes)
    if err != nil { panic(err) }
    return c
}

func main() {
    dir := os.Args[1]
    trusted := cert(filepath.Join(dir, "trusted.pem"))
    other := cert(filepath.Join(dir, "other.pem"))
    roots := x509.NewCertPool()
    roots.AddCert(trusted)
    opts := x509.VerifyOptions{Roots: roots, DNSName: "example.com"}
    if _, err := trusted.Verify(opts); err != nil { panic(err) }
    if _, err := other.Verify(opts); err == nil { panic("accepted substituted certificate") }
    opts.DNSName = "wrong.example"
    if _, err := trusted.Verify(opts); err == nil { panic("accepted wrong SAN") }
    fmt.Println("PASS: explicit certificate trust; substituted certificate and wrong SAN rejected")
}
