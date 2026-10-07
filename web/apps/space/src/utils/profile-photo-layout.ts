import { minimumPostPhotoFrameAspectRatio } from "../styles/tiles";

export const profilePhotoGap = 6;
const profilePhotoMinRowHeight = 100;
const fixedPhotoMinTileWidth = 100;
const fixedRowPattern = [
    { heightRatio: 0.62, weights: [1.16, 0.84] },
    { heightRatio: 0.34, weights: [0.88, 1.18, 0.94] },
    { heightRatio: 0.49, weights: [0.78, 1.22] },
    { heightRatio: 0.72, weights: [1.28, 0.72] },
    { heightRatio: 0.66, weights: [1] },
    { heightRatio: 0.3, weights: [1.16, 0.8, 1.04] },
    { heightRatio: 0.58, weights: [0.9, 1.1] },
    { heightRatio: 0.9, weights: [1] },
    { heightRatio: 0.46, weights: [1.24, 0.76] },
    { heightRatio: 0.38, weights: [1.03, 1.08, 0.89] },
    { heightRatio: 0.32, weights: [0.82, 1.04, 1.14] },
    { heightRatio: 0.67, weights: [0.76, 1.24] },
    { heightRatio: 0.54, weights: [1] },
    { heightRatio: 0.55, weights: [1.08, 0.92] },
    { heightRatio: 0.36, weights: [1.12, 0.86, 1.02] },
    { heightRatio: 0.76, weights: [0.86, 1.14] },
    { heightRatio: 0.51, weights: [1.3, 0.7] },
    { heightRatio: 0.78, weights: [1] },
    { heightRatio: 0.29, weights: [0.94, 1.22, 0.84] },
    { heightRatio: 0.64, weights: [1.04, 0.96] },
    { heightRatio: 0.6, weights: [1] },
    { heightRatio: 0.48, weights: [0.82, 1.18] },
    { heightRatio: 0.35, weights: [1.2, 0.96, 0.84] },
    { heightRatio: 0.69, weights: [1.2, 0.8] },
];

interface PhotoRow<Tile> {
    aspectRatio: number;
    height: number;
    width: number;
    tiles: Tile[];
}

interface PostPhotoTile {
    id: string;
    aspectRatio: number;
}

interface PostPhotoLayout {
    width: number;
    fixedRows: boolean;
    fullWidth?: boolean;
    rows: PhotoRow<PostPhotoTile>[];
}

export const postPhotoLayout = (
    tiles: PostPhotoTile[],
    width: number,
    previous?: PostPhotoLayout,
    postCount?: number,
    fixedRows = false,
): PostPhotoLayout => {
    const fullWidth =
        previous?.fullWidth ??
        (width > 0 && tiles.length > 0
            ? postCount != undefined && Math.max(postCount, tiles.length) <= 7
            : undefined);
    const rows: PhotoRow<PostPhotoTile>[] = [];
    let retainedCount = 0;
    if (previous?.width == width && previous.fixedRows == fixedRows) {
        for (const row of previous.rows) {
            if (
                !row.tiles.every(
                    (tile, index) =>
                        tiles[retainedCount + index]?.id == tile.id,
                )
            )
                break;
            rows.push(row);
            retainedCount += row.tiles.length;
        }
    }
    const remaining = tiles.slice(retainedCount);
    rows.push(
        ...(fullWidth
            ? remaining.flatMap((tile) => profilePhotoRows([tile], width))
            : fixedRows
              ? fixedPhotoRows(remaining, width, rows.length)
              : profilePhotoRows(remaining, width)),
    );
    return { width, fixedRows, fullWidth, rows };
};

const fixedPhotoRows = (
    tiles: PostPhotoTile[],
    width: number,
    startRow: number,
) => {
    const rows: PhotoRow<PostPhotoTile>[] = [];
    if (width <= 0) return rows;

    const minTileWidth = Math.min(fixedPhotoMinTileWidth, width);
    const maxRowSize = Math.floor(
        (width + profilePhotoGap) / (minTileWidth + profilePhotoGap),
    );
    for (let index = 0; index < tiles.length; ) {
        const pattern =
            fixedRowPattern[(startRow + rows.length) % fixedRowPattern.length]!;
        const rowSize = Math.min(
            pattern.weights.length,
            maxRowSize,
            tiles.length - index,
        );
        const weights = pattern.weights.slice(0, rowSize);
        const totalWeight = weights.reduce((sum, weight) => sum + weight, 0);
        const availableWidth = width - (rowSize - 1) * profilePhotoGap;
        const extraWidths = weights.map((weight) =>
            Math.max(0, (availableWidth * weight) / totalWeight - minTileWidth),
        );
        const totalExtraWidth = extraWidths.reduce(
            (sum, extra) => sum + extra,
            0,
        );
        const remainingWidth = availableWidth - rowSize * minTileWidth;
        const height = width * pattern.heightRatio;
        const aspectRatio = availableWidth / height;
        rows.push({
            aspectRatio,
            height,
            width,
            tiles: tiles
                .slice(index, index + rowSize)
                .map((tile, tileIndex) => ({
                    ...tile,
                    aspectRatio:
                        (minTileWidth +
                            (totalExtraWidth > 0
                                ? (remainingWidth * extraWidths[tileIndex]!) /
                                  totalExtraWidth
                                : 0)) /
                        height,
                })),
        });
        index += rowSize;
    }
    return rows;
};

const profilePhotoRows = <Tile extends { aspectRatio: number }>(
    tiles: Tile[],
    width: number,
) => {
    const rows: PhotoRow<Tile>[] = [];
    if (width <= 0) return rows;

    const targetRowHeight = width / 2;
    const costs = new Array<number>(tiles.length + 1).fill(Infinity);
    const rowSizes = new Array<number>(tiles.length);
    costs[tiles.length] = 0;

    for (let index = tiles.length - 1; index >= 0; index--) {
        let aspectRatio = 0;
        for (
            let rowSize = 1;
            rowSize <= 3 && index + rowSize <= tiles.length;
            rowSize++
        ) {
            aspectRatio += tiles[index + rowSize - 1]!.aspectRatio;
            const height =
                (width - (rowSize - 1) * profilePhotoGap) / aspectRatio;
            if (rowSize > 1 && height < profilePhotoMinRowHeight) continue;

            const cost =
                (height / targetRowHeight - 1) ** 2 + costs[index + rowSize]!;
            if (cost <= costs[index]!) {
                costs[index] = cost;
                rowSizes[index] = rowSize;
            }
        }
    }

    for (let index = 0; index < tiles.length; ) {
        const rowSize = rowSizes[index]!;
        const rowTiles = tiles.slice(index, index + rowSize);
        const aspectRatio = rowTiles.reduce(
            (sum, tile) => sum + tile.aspectRatio,
            0,
        );
        const gaps = (rowSize - 1) * profilePhotoGap;
        let height = (width - gaps) / aspectRatio;
        if (rowSize == 1)
            height = Math.min(
                height,
                tiles.length == 1
                    ? width / minimumPostPhotoFrameAspectRatio
                    : width * 0.75,
            );
        rows.push({
            aspectRatio,
            height,
            width:
                rowSize > 1 || tiles.length == 1 ? width : height * aspectRatio,
            tiles: rowTiles,
        });
        index += rowSize;
    }

    return rows;
};
