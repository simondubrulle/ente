import {
    DownloadStatusNotifications,
    type DownloadStatusNotificationsProps,
} from "ente-gallery/components/DownloadStatusNotifications";
import { useCallback } from "react";
import { usePhotosNavigation } from "./PhotosNavigationContext";

export const GalleryDownloadStatusNotifications = (
    props: Omit<DownloadStatusNotificationsProps, "onShowCollectionSummary">,
) => {
    const { showCollectionSummary } = usePhotosNavigation();
    const onShowCollectionSummary = useCallback(
        (id: number | undefined, isHidden: boolean | undefined) => {
            void showCollectionSummary(id, isHidden);
        },
        [showCollectionSummary],
    );
    return (
        <DownloadStatusNotifications
            {...props}
            onShowCollectionSummary={onShowCollectionSummary}
        />
    );
};
