import { Box, List, ListItem, Stack, Typography, styled } from "@mui/material";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import log from "ente-base/log";
import type { EnteFile } from "ente-media/file";
import { ItemCard, PreviewItemTile } from "ente-new/photos/components/Tiles";
import { t } from "i18next";
import { useEffect, useState } from "react";
import { listPlaces } from "../../services/places";

export const PlacesList = ({ files }: { files: EnteFile[] }) => {
    const [result, setResult] = useState<{
        files: EnteFile[];
        groups?: Awaited<ReturnType<typeof listPlaces>>;
    }>();

    useEffect(() => {
        let cancelled = false;
        void listPlaces(files)
            .then((groups) => {
                if (!cancelled) setResult({ files, groups });
            })
            .catch((error: unknown) => {
                log.error("Failed to list places", error);
                if (!cancelled) setResult({ files });
            });
        return () => {
            cancelled = true;
        };
    }, [files]);

    const currentResult = result?.files === files ? result : undefined;

    return (
        <Stack sx={{ flex: 1, minHeight: 0, gap: "8px" }}>
            <Stack
                direction="row"
                aria-current="page"
                sx={{
                    ...placeRowSx,
                    flexShrink: 0,
                    bgcolor: "var(--gallery-navigation-surface)",
                }}
            >
                <Box
                    component="img"
                    src="/images/places/your-map.png"
                    alt=""
                    sx={{
                        width: 36,
                        height: 36,
                        flexShrink: 0,
                        borderRadius: "12px",
                    }}
                />
                <Typography sx={placeNameSx}>{t("your_map")}</Typography>
            </Stack>
            {!currentResult ? (
                <Stack role="status" aria-label={t("loading")} sx={{ p: 2 }}>
                    <ActivityIndicator />
                </Stack>
            ) : !currentResult.groups ? (
                <Typography role="alert">{t("generic_error_retry")}</Typography>
            ) : !currentResult.groups.length ? (
                <Typography role="status">{t("no_results")}</Typography>
            ) : (
                <List
                    disablePadding
                    aria-label={t("search_places")}
                    sx={{
                        flex: 1,
                        minHeight: 0,
                        overflow: "auto",
                        display: "flex",
                        flexDirection: "column",
                        gap: "8px",
                    }}
                >
                    {currentResult.groups.map(({ city, coverFile }) => (
                        <ListItem
                            key={`${city.name}-${city.country}-${city.latitude}-${city.longitude}`}
                            disableGutters
                            title={`${city.name}, ${city.country}`}
                            sx={placeRowSx}
                        >
                            <Box aria-hidden sx={{ flexShrink: 0 }}>
                                <ItemCard
                                    coverFile={coverFile}
                                    TileComponent={PlaceCover}
                                />
                            </Box>
                            <Typography noWrap sx={placeNameSx}>
                                {city.name}
                            </Typography>
                        </ListItem>
                    ))}
                </List>
            )}
        </Stack>
    );
};

const placeRowSx = {
    height: 48,
    minHeight: 48,
    px: "12px",
    py: 0,
    gap: "12px",
    alignItems: "center",
    borderRadius: "12px",
};

const placeNameSx = {
    flex: 1,
    minWidth: 0,
    fontFamily: '"Inter Variable", Inter, sans-serif',
    fontSize: 14,
    fontWeight: 500,
    lineHeight: "20px",
};

const PlaceCover = styled(PreviewItemTile)({
    width: 36,
    height: 36,
    borderRadius: "12px",
    cursor: "default",
});
