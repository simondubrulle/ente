package collections

import (
	"encoding/base64"
	"errors"

	"github.com/ente/museum/ente"
)

const (
	collectionKeyBytes        = 32
	secretboxMACBytes         = 16
	secretboxNonceBytes       = 24
	sealedBoxOverheadBytes    = 48
	encryptedCollectionKeyLen = collectionKeyBytes + secretboxMACBytes
	sealedCollectionKeyLen    = collectionKeyBytes + sealedBoxOverheadBytes
)

func validateOwnedCollectionKey(encryptedKey string, keyDecryptionNonce string) error {
	if err := validateBase64DecodedLength(encryptedKey, encryptedCollectionKeyLen); err != nil {
		return err
	}
	return validateBase64DecodedLength(keyDecryptionNonce, secretboxNonceBytes)
}

func validateSealedCollectionKey(encryptedKey string) error {
	return validateBase64DecodedLength(encryptedKey, sealedCollectionKeyLen)
}

func validateCollectionFileItems(files []ente.CollectionFileItem) error {
	for _, file := range files {
		if file.ID == 0 {
			return ente.NewBadRequestWithMessage("file ID is required")
		}
		if err := validateOwnedCollectionKey(file.EncryptedKey, file.KeyDecryptionNonce); err != nil {
			return ente.NewBadRequestWithMessage(err.Error())
		}
	}
	return nil
}

func validateBase64DecodedLength(value string, expected int) error {
	if len(value) != base64.StdEncoding.EncodedLen(expected) {
		return errors.New("invalid encoded length")
	}
	return ente.ValidateBase64Length(value, expected)
}
