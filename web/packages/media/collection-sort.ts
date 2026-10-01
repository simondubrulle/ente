import type { CollectionPublicMagicMetadataData } from "./collection";
import type { EnteFile } from "./file";
import { fileCreationPhotoSortTime, fileFileName } from "./file-metadata";

export type CollectionSortBy = "date" | "name";

type SortMetadata = Pick<CollectionPublicMagicMetadataData, "sortBy" | "asc">;

export const collectionSortBy = (
    metadata: SortMetadata | undefined,
): CollectionSortBy => (metadata?.sortBy === "name" ? "name" : "date");

const filenameCollator = new Intl.Collator(undefined, {
    numeric: true,
    sensitivity: "base",
});

/** Return a sorted copy, preserving the existing date order for legacy albums. */
export const sortCollectionFiles = (
    files: EnteFile[],
    metadata?: SortMetadata,
): EnteFile[] => {
    const direction = metadata?.asc ? 1 : -1;
    if (collectionSortBy(metadata) === "name") {
        return [...files].sort(
            (a, b) =>
                direction *
                    filenameCollator.compare(
                        fileFileName(a),
                        fileFileName(b),
                    ) || a.id - b.id,
        );
    }
    const dates = new Map<EnteFile, number>();
    const dateForFile = (file: EnteFile) => {
        let date = dates.get(file);
        if (date === undefined) {
            date = fileCreationPhotoSortTime(file);
            dates.set(file, date);
        }
        return date;
    };
    return [...files].sort(
        (a, b) =>
            direction *
            (dateForFile(a) - dateForFile(b) ||
                a.metadata.modificationTime - b.metadata.modificationTime),
    );
};
