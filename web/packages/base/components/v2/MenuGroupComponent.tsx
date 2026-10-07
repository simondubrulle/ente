import { Divider, Stack } from "@mui/material";
import type { ReactNode } from "react";

interface MenuGroupComponentProps {
    children: ReactNode;
    dividerInset?: number;
}

/** A shared rounded surface with inset dividers, like mobile menu groups. */
export function MenuGroupComponent({
    children,
    dividerInset = 16,
}: MenuGroupComponentProps) {
    return (
        <Stack
            divider={
                <Divider
                    sx={{
                        "&&": { ml: `${dividerInset}px` },
                        borderColor: "fill.fainter",
                    }}
                />
            }
            sx={[
                {
                    bgcolor: "background.paper",
                    borderRadius: "20px",
                    overflow: "hidden",
                    "& > button": { borderRadius: 0 },
                },
                // Mobile's fillLight surface contrasts with the drawer background.
                (theme) => theme.applyStyles("dark", { bgcolor: "#212121" }),
            ]}
        >
            {children}
        </Stack>
    );
}
