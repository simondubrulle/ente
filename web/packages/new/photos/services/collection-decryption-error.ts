export const collectionDecryptionError = (
    collectionID: number,
    cause: unknown,
) =>
    new Error(
        `${cause instanceof Error ? cause.message : String(cause)} (collectionID: ${collectionID})`,
        { cause },
    );
