import { Stack } from "@mui/material";
import {
    RowButton,
    RowButtonDivider,
    RowButtonGroup,
} from "ente-base/components/RowButton";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect } from "react";

export type FreeUpSpaceAction = Extract<
    SidebarActionID,
    "freeUpSpace.deduplicate" | "freeUpSpace.largeFiles"
>;

type FreeUpSpaceProps = NestedSidebarDrawerVisibilityProps & {
    pendingAction?: FreeUpSpaceAction;
    onActionHandled?: (action?: FreeUpSpaceAction) => void;
};

export const FreeUpSpace: React.FC<FreeUpSpaceProps> = ({
    open,
    onClose,
    onRootClose,
    pendingAction,
    onActionHandled,
}) => {
    const router = useRouter();

    const handleRootClose = useCallback(() => {
        onClose();
        onRootClose();
    }, [onClose, onRootClose]);

    const handleDeduplicate = useCallback(() => {
        onRootClose();
        void router.push("/duplicates");
    }, [onRootClose, router]);

    const handleLargeFiles = useCallback(() => {
        onRootClose();
        void router.push("/large-files");
    }, [onRootClose, router]);

    useEffect(() => {
        if (!open || !pendingAction) return;
        switch (pendingAction) {
            case "freeUpSpace.deduplicate":
                handleDeduplicate();
                break;
            case "freeUpSpace.largeFiles":
                handleLargeFiles();
                break;
        }
        onActionHandled?.();
    }, [
        handleDeduplicate,
        handleLargeFiles,
        open,
        onActionHandled,
        pendingAction,
    ]);

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("free_up_space")}
        >
            <Stack sx={{ px: 2, py: 1, gap: 3 }}>
                <RowButtonGroup>
                    <RowButton
                        label={t("deduplicate_files")}
                        onClick={handleDeduplicate}
                    />
                    <RowButtonDivider />
                    <RowButton
                        label={t("large_files_title")}
                        onClick={handleLargeFiles}
                    />
                </RowButtonGroup>
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};
