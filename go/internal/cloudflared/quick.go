// Package cloudflared runs the official cloudflared CLI to expose a local HTTP
// service via a Cloudflare quick tunnel (trycloudflare.com). TLS is used on the
// public URL; the tunnel connection from cloudflared to Cloudflare is encrypted.
//
// This does not provide confidentiality of prompts from Cursor's servers when
// Cursor is the HTTP client — see docs on the gateway / Expert screen.
package cloudflared

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

var tryCloudflareURL = regexp.MustCompile(`https://[a-zA-Z0-9][-a-zA-Z0-9]*\.trycloudflare\.com`)

// LocalHTTPOrigin returns an http:// URL suitable for cloudflared --url, using
// 127.0.0.1 when the server binds to all interfaces.
func LocalHTTPOrigin(listenAddr string) (string, error) {
	host, port, err := net.SplitHostPort(listenAddr)
	if err != nil {
		return "", fmt.Errorf("parse listen address: %w", err)
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	// [::] etc. — cloudflared should reach loopback
	if host == "::1" {
		host = "127.0.0.1"
	}
	return fmt.Sprintf("http://%s", net.JoinHostPort(host, port)), nil
}

// QuickTunnel runs `cloudflared tunnel --url <origin>` and captures the public HTTPS URL.
type QuickTunnel struct {
	cmd *exec.Cmd
	URL string
}

// StartQuickTunnel starts cloudflared and waits until the trycloudflare URL appears
// in its output or ctx is done. cloudflared must be on PATH.
func StartQuickTunnel(ctx context.Context, origin string) (*QuickTunnel, error) {
	if _, err := exec.LookPath("cloudflared"); err != nil {
		return nil, fmt.Errorf("cloudflared not found in PATH (install: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/): %w", err)
	}

	ctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "cloudflared", "tunnel", "--url", origin)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return nil, err
	}

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start cloudflared: %w", err)
	}

	combined := io.MultiReader(stdout, stderr)
	scan := bufio.NewScanner(combined)
	// Very long lines (banners)
	scan.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	urlCh := make(chan string, 1)
	errCh := make(chan error, 1)
	go func() {
		for scan.Scan() {
			line := scan.Text()
			if u := tryCloudflareURL.FindString(line); u != "" {
				urlCh <- u
				return
			}
		}
		if err := scan.Err(); err != nil {
			errCh <- err
			return
		}
		errCh <- fmt.Errorf("cloudflared exited before printing a trycloudflare URL")
	}()

	var public string
	select {
	case public = <-urlCh:
	case err := <-errCh:
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
		return nil, err
	case <-ctx.Done():
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
		return nil, fmt.Errorf("wait for tunnel URL: %w", ctx.Err())
	}

	return &QuickTunnel{cmd: cmd, URL: strings.TrimSpace(public)}, nil
}

// Stop terminates the cloudflared process.
func (q *QuickTunnel) Stop() error {
	if q == nil || q.cmd == nil || q.cmd.Process == nil {
		return nil
	}
	_ = q.cmd.Process.Kill()
	_, err := q.cmd.Process.Wait()
	if err != nil && !strings.Contains(err.Error(), "signal: killed") {
		return err
	}
	return nil
}
