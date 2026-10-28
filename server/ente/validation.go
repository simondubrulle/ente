package ente

import (
	"encoding/base64"
	"errors"
)

func ValidateBase64Length(value string, size int) error {
	decoded, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		return errors.New("invalid base64")
	}
	if len(decoded) != size {
		return errors.New("invalid decoded length")
	}
	return nil
}
