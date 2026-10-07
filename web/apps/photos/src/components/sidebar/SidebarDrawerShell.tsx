import {
    Box,
    Dialog,
    ThemeProvider,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import { SidebarPanelContext } from "ente-base/components/mui/SidebarDrawerContext";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { t } from "i18next";
import React, { useRef } from "react";

// Keeps the root Photos menu beside its nested settings.
export function SidebarDrawerShell({
    open,
    onClose,
    children,
}: React.PropsWithChildren<ModalVisibilityProps>) {
    const theme = useTheme();
    const wide = useMediaQuery(theme.breakpoints.up("md"));
    const { isInternalUser } = useSettingsSnapshot();
    const panel = useRef<HTMLDivElement>(null);
    const container = () => panel.current;

    if (!isInternalUser || !wide) return children;

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth={false}
            aria-label={t("settings")}
            slotProps={{
                paper: {
                    sx: {
                        width: "min(1200px, calc(100vw - 48px))",
                        height: "calc(100dvh - 48px)",
                        maxHeight: "none",
                        m: 3,
                        borderRadius: 3,
                        overflow: "hidden",
                    },
                },
            }}
        >
            <SidebarPanelContext.Provider value={container}>
                <ThemeProvider
                    theme={{
                        ...theme,
                        components: {
                            ...theme.components,
                            MuiDialog: {
                                ...theme.components?.MuiDialog,
                                defaultProps: {
                                    ...theme.components?.MuiDialog
                                        ?.defaultProps,
                                    container,
                                    disableEnforceFocus: true,
                                },
                                styleOverrides: {
                                    ...theme.components?.MuiDialog
                                        ?.styleOverrides,
                                    root: [
                                        theme.components?.MuiDialog
                                            ?.styleOverrides?.root,
                                        { position: "absolute" },
                                    ],
                                },
                            },
                            MuiBackdrop: {
                                ...theme.components?.MuiBackdrop,
                                styleOverrides: {
                                    ...theme.components?.MuiBackdrop
                                        ?.styleOverrides,
                                    root: [
                                        theme.components?.MuiBackdrop
                                            ?.styleOverrides?.root,
                                        { position: "absolute" },
                                    ],
                                },
                            },
                        },
                    }}
                >
                    {children}
                    <Box
                        ref={panel}
                        sx={{
                            position: "absolute",
                            inset: "0 0 0 360px",
                            bgcolor: "background.default",
                            borderLeft: 1,
                            borderColor: "divider",
                        }}
                    />
                </ThemeProvider>
            </SidebarPanelContext.Provider>
        </Dialog>
    );
}
