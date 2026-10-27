import CheckIcon from "@mui/icons-material/Check";
import ContentCopyIcon from "@mui/icons-material/ContentCopyOutlined";
import { Box, Dialog, Stack, Typography } from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import {
    v2CancelButtonSx,
    v2PaperSx,
    v2SubmitButtonSx,
    v2TitleSx,
} from "ente-base/components/SingleInput.styles";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import { useId } from "react";

type PublicLinkCreatedProps = ModalVisibilityProps & { onCopyLink: () => void };

export const PublicLinkCreated: React.FC<PublicLinkCreatedProps> = ({
    open,
    onClose,
    onCopyLink,
}) => {
    const titleID = useId();
    return (
        <Dialog
            {...{ open, onClose }}
            aria-labelledby={titleID}
            disablePortal
            maxWidth={false}
            slotProps={{
                backdrop: { sx: { position: "absolute" } },
                paper: {
                    sx: (theme) => ({
                        ...v2PaperSx(theme),
                        width: "min(360px, calc(100svw - 32px))",
                        maxWidth: "360px",
                    }),
                },
            }}
            sx={{ position: "absolute" }}
        >
            <Stack sx={{ p: "24px", gap: "24px" }}>
                <Stack sx={{ alignItems: "center", gap: "16px" }}>
                    <Box
                        sx={{
                            width: 48,
                            height: 48,
                            borderRadius: "50%",
                            display: "grid",
                            placeItems: "center",
                            color: "#08c225",
                            bgcolor: "rgba(8, 194, 37, 0.12)",
                        }}
                    >
                        <CheckIcon sx={{ fontSize: 28 }} />
                    </Box>
                    <Typography
                        id={titleID}
                        component="h2"
                        sx={{
                            ...v2TitleSx,
                            fontFamily: "'Outfit Variable', sans-serif",
                            textAlign: "center",
                        }}
                    >
                        {t("public_link_created")}
                    </Typography>
                </Stack>
                <Stack sx={{ gap: "12px" }}>
                    <FocusVisibleButton
                        onClick={() => {
                            onCopyLink();
                            onClose();
                        }}
                        startIcon={<ContentCopyIcon sx={{ fontSize: 18 }} />}
                        fullWidth
                        sx={[v2SubmitButtonSx, { flex: "none", minHeight: 52 }]}
                    >
                        {t("copy_link")}
                    </FocusVisibleButton>
                    <FocusVisibleButton
                        onClick={onClose}
                        fullWidth
                        sx={(theme) => ({
                            ...v2CancelButtonSx(theme),
                            flex: "none",
                            minHeight: 52,
                        })}
                    >
                        {t("done")}
                    </FocusVisibleButton>
                </Stack>
            </Stack>
        </Dialog>
    );
};
