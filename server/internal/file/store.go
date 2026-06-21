package file

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

type Store struct {
	BasePath string
}

func NewStore(basePath string) (*Store, error) {
	if err := os.MkdirAll(basePath, 0755); err != nil {
		return nil, fmt.Errorf("create file store: %w", err)
	}
	return &Store{BasePath: basePath}, nil
}

func (s *Store) Save(fileID string, reader io.Reader) error {
	path := filepath.Join(s.BasePath, fileID)
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, reader)
	return err
}

func (s *Store) Get(fileID string) (string, io.ReadCloser, error) {
	path := filepath.Join(s.BasePath, fileID)
	f, err := os.Open(path)
	if err != nil {
		return "", nil, err
	}
	return path, f, nil
}

// Open returns the underlying *os.File so callers can use it as an
// io.ReadSeeker (needed for HTTP Range streaming via http.ServeContent).
func (s *Store) Open(fileID string) (*os.File, error) {
	return os.Open(filepath.Join(s.BasePath, fileID))
}

func (s *Store) Delete(fileID string) error {
	return os.Remove(filepath.Join(s.BasePath, fileID))
}
