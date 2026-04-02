package logger

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	maxFileSize = 10 * 1024 * 1024 // 10 MB per log file
	maxFiles    = 5                 // keep 5 rotated files
	logFileName = "nodeneo.log"
)

// Level enumerates log severities.
type Level int

const (
	LevelDebug Level = iota
	LevelInfo
	LevelWarn
	LevelError
)

func ParseLevel(s string) Level {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "debug":
		return LevelDebug
	case "warn", "warning":
		return LevelWarn
	case "error":
		return LevelError
	default:
		return LevelInfo
	}
}

func (l Level) String() string {
	switch l {
	case LevelDebug:
		return "DEBUG"
	case LevelInfo:
		return "INFO"
	case LevelWarn:
		return "WARN"
	case LevelError:
		return "ERROR"
	default:
		return "INFO"
	}
}

// Logger writes to a rotating log file in dataDir/logs/.
type Logger struct {
	mu      sync.Mutex
	dir     string
	file    *os.File
	written int64
	level   Level
}

var (
	globalMu     sync.Mutex
	globalLogger *Logger
)

// Init creates or opens the log file. Safe to call multiple times.
func Init(dataDir string, level string) error {
	globalMu.Lock()
	defer globalMu.Unlock()

	dir := filepath.Join(dataDir, "logs")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("logger: create dir: %w", err)
	}

	path := filepath.Join(dir, logFileName)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return fmt.Errorf("logger: open: %w", err)
	}

	info, _ := f.Stat()
	var size int64
	if info != nil {
		size = info.Size()
	}

	globalLogger = &Logger{
		dir:     dir,
		file:    f,
		written: size,
		level:   ParseLevel(level),
	}
	return nil
}

// SetLevel changes the active log level at runtime.
func SetLevel(level string) {
	globalMu.Lock()
	defer globalMu.Unlock()
	if globalLogger != nil {
		globalLogger.mu.Lock()
		globalLogger.level = ParseLevel(level)
		globalLogger.mu.Unlock()
	}
}

// GetLevel returns the current log level string.
func GetLevel() string {
	globalMu.Lock()
	defer globalMu.Unlock()
	if globalLogger == nil {
		return "info"
	}
	globalLogger.mu.Lock()
	defer globalLogger.mu.Unlock()
	return strings.ToLower(globalLogger.level.String())
}

// LogDir returns the directory where log files are written.
func LogDir() string {
	globalMu.Lock()
	defer globalMu.Unlock()
	if globalLogger == nil {
		return ""
	}
	return globalLogger.dir
}

// Close flushes and closes the log file.
func Close() {
	globalMu.Lock()
	defer globalMu.Unlock()
	if globalLogger != nil && globalLogger.file != nil {
		globalLogger.file.Close()
		globalLogger.file = nil
	}
	globalLogger = nil
}

func Debug(msg string, args ...interface{}) { log(LevelDebug, msg, args...) }
func Info(msg string, args ...interface{})  { log(LevelInfo, msg, args...) }
func Warn(msg string, args ...interface{})  { log(LevelWarn, msg, args...) }
func Error(msg string, args ...interface{}) { log(LevelError, msg, args...) }

// Writer returns an io.Writer that writes at the given level (for SDK log capture).
func Writer(level Level) io.Writer {
	return &levelWriter{level: level}
}

type levelWriter struct {
	level Level
}

func (w *levelWriter) Write(p []byte) (int, error) {
	log(w.level, strings.TrimRight(string(p), "\n"))
	return len(p), nil
}

func log(level Level, msg string, args ...interface{}) {
	globalMu.Lock()
	l := globalLogger
	globalMu.Unlock()
	if l == nil {
		return
	}

	l.mu.Lock()
	defer l.mu.Unlock()

	if level < l.level {
		return
	}

	if len(args) > 0 {
		msg = fmt.Sprintf(msg, args...)
	}
	ts := time.Now().Format("2006-01-02 15:04:05.000")
	line := fmt.Sprintf("%s [%s] %s\n", ts, level.String(), msg)

	if l.file != nil {
		n, _ := l.file.WriteString(line)
		l.written += int64(n)

		if l.written >= maxFileSize {
			l.rotate()
		}
	}
}

func (l *Logger) rotate() {
	if l.file != nil {
		l.file.Close()
	}

	base := filepath.Join(l.dir, logFileName)
	ts := time.Now().Format("20060102-150405")
	rotated := filepath.Join(l.dir, fmt.Sprintf("nodeneo-%s.log", ts))
	os.Rename(base, rotated)

	l.pruneOld()

	f, err := os.OpenFile(base, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		l.file = nil
		return
	}
	l.file = f
	l.written = 0
}

func (l *Logger) pruneOld() {
	entries, err := os.ReadDir(l.dir)
	if err != nil {
		return
	}
	var logs []string
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "nodeneo-") && strings.HasSuffix(e.Name(), ".log") {
			logs = append(logs, e.Name())
		}
	}
	sort.Strings(logs)
	for len(logs) > maxFiles-1 {
		os.Remove(filepath.Join(l.dir, logs[0]))
		logs = logs[1:]
	}
}
