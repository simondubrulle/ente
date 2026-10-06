import {
    generatePasskeyRecovery,
    recoveryKeyMnemonic,
} from "@/services/recovery-key";
import { Stack } from "@mui/material";
import Typography from "@mui/material/Typography";
import { RecoveryKey } from "ente-accounts/components/RecoveryKey";
import { openAccountsManagePasskeysPage } from "ente-accounts/services/passkey";
import { getActiveSessions } from "ente-accounts/services/sessions";
import { isDesktop } from "ente-base/app";
import {
    RowButton,
    RowButtonDivider,
    RowButtonGroup,
} from "ente-base/components/RowButton";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { formattedStorageByteSize } from "ente-gallery/utils/units";
import { useUserDetailsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    reauthenticateWithAppLock,
    suppressAutoLockOnBlurForTrustedPrompt,
} from "ente-new/photos/services/app-lock";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import { get2FAStatus } from "ente-new/photos/services/user";
import {
    familyMemberStorageLimit,
    isFamilyAdmin,
    isPartOfFamily,
    isPartOfFamilyWithOtherMembers,
    isSubscriptionFree,
    pullUserDetails,
    userDetailsSnapshot,
} from "ente-new/photos/services/user-details";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { DeleteAccount } from "../account/DeleteAccount";
import { SessionsSettings } from "../account/SessionsSettings";
import { TwoFactorSettings } from "../account/TwoFactorSettings";
import { ManageMemberSubscription } from "./ManageMemberSubscription";
import { openManageSubscription } from "./subscription";

export type AccountAction = Extract<
    SidebarActionID,
    | "account.subscription"
    | "account.recoveryKey"
    | "account.twoFactor"
    | "account.twoFactor.reconfigure"
    | "account.passkeys"
    | "account.changePassword"
    | "account.changeEmail"
    | "account.deleteAccount"
    | "account.sessions"
>;

type AccountProps = NestedSidebarDrawerVisibilityProps & {
    onAuthenticateUser: () => Promise<boolean>;
    onShowPlanSelector: () => void;
    pendingAction?: AccountAction;
    onActionHandled?: (action?: AccountAction) => void;
};

export const Account: React.FC<AccountProps> = ({
    open,
    onClose,
    onRootClose,
    onAuthenticateUser,
    onShowPlanSelector,
    pendingAction,
    onActionHandled,
}) => {
    const { showMiniDialog } = useBaseContext();
    const userDetails = useUserDetailsSnapshot();
    const [twoFactorEnabled, setTwoFactorEnabled] = useState<boolean>();
    const [sessionCount, setSessionCount] = useState<number>();

    const accountLabel = (label: string, subtext?: string) => (
        <Stack
            sx={{
                gap: 0.5,
                minWidth: 0,
                alignItems: "flex-start",
                textAlign: "left",
            }}
        >
            <Typography sx={{ fontWeight: "medium" }}>{label}</Typography>
            {subtext && (
                <Typography
                    variant="small"
                    sx={{
                        color: "text.muted",
                        fontWeight: 400,
                        overflowWrap: "anywhere",
                    }}
                >
                    {subtext}
                </Typography>
            )}
        </Stack>
    );
    let planSubtext: string | undefined;
    if (userDetails) {
        let storage =
            userDetails.subscription.storage + userDetails.storageBonus;

        if (isPartOfFamilyWithOtherMembers(userDetails)) {
            const memberLimit = familyMemberStorageLimit(userDetails);
            const familyStorage =
                (userDetails.familyData?.storage ?? 0) +
                userDetails.storageBonus;
            storage = memberLimit ?? familyStorage;
        }

        const period = userDetails.subscription.period;
        const canShowBillingPeriod =
            !isSubscriptionFree(userDetails.subscription) &&
            (!isPartOfFamily(userDetails) || isFamilyAdmin(userDetails));
        const billingLabel =
            canShowBillingPeriod && period
                ? t(period == "year" ? "yearly" : "monthly")
                : undefined;

        planSubtext = [formattedStorageByteSize(storage), billingLabel]
            .filter(Boolean)
            .join(" · ");
    }

    const router = useRouter();

    const {
        show: showManageMemberSubscription,
        props: manageMemberSubscriptionVisibilityProps,
    } = useModalVisibility();
    const { show: showRecoveryKey, props: recoveryKeyVisibilityProps } =
        useModalVisibility();
    const { show: showTwoFactor, props: twoFactorVisibilityProps } =
        useModalVisibility();
    const { show: showSessions, props: sessionsVisibilityProps } =
        useModalVisibility();
    const { show: showDeleteAccount, props: deleteAccountVisibilityProps } =
        useModalVisibility();

    useEffect(() => {
        if (
            !open ||
            twoFactorVisibilityProps.open ||
            sessionsVisibilityProps.open
        )
            return;
        let cancelled = false;
        void Promise.all([
            get2FAStatus().catch(() => undefined),
            getActiveSessions().catch(() => undefined),
        ]).then(([twoFactor, sessions]) => {
            if (cancelled) return;
            setTwoFactorEnabled(twoFactor);
            setSessionCount(sessions?.length);
        });
        return () => {
            cancelled = true;
        };
    }, [open, twoFactorVisibilityProps.open, sessionsVisibilityProps.open]);

    const isNonAdminFamilyMember = useMemo(
        () =>
            userDetails &&
            isPartOfFamily(userDetails) &&
            !isFamilyAdmin(userDetails),
        [userDetails],
    );

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const handleChangePassword = useCallback(async () => {
        if (!(await onAuthenticateUser())) return;
        void router.push("/change-password");
    }, [onAuthenticateUser, router]);
    const handleChangeEmail = useCallback(() => {
        void router.push("/change-email");
    }, [router]);

    const handleManageSubscription = useCallback(() => {
        void (async () => {
            if (!userDetails) {
                await pullUserDetails();
            }

            const resolvedUserDetails = userDetails ?? userDetailsSnapshot();
            if (!resolvedUserDetails) return;

            openManageSubscription({
                userDetails: resolvedUserDetails,
                showManageMemberSubscription,
                onShowPlanSelector,
            });
        })();
    }, [onShowPlanSelector, showManageMemberSubscription, userDetails]);

    const handleRecoveryKey = useCallback(async () => {
        if (isDesktop) {
            const reauthResult = await reauthenticateWithAppLock();
            if (reauthResult === "cancelled") return;
            if (reauthResult === "fallback" && !(await onAuthenticateUser()))
                return;
        } else {
            if (!(await onAuthenticateUser())) return;
        }
        showRecoveryKey();
    }, [onAuthenticateUser, showRecoveryKey]);

    const handlePasskeys = useCallback(async () => {
        onRootClose();
        if (isDesktop) {
            suppressAutoLockOnBlurForTrustedPrompt();
        }
        await openAccountsManagePasskeysPage(generatePasskeyRecovery);
    }, [onRootClose]);

    const handleActiveSessions = useCallback(async () => {
        if (isDesktop) {
            const reauthResult = await reauthenticateWithAppLock();
            if (reauthResult === "cancelled") return;
            if (reauthResult === "fallback" && !(await onAuthenticateUser()))
                return;
        } else {
            if (!(await onAuthenticateUser())) return;
        }
        showSessions();
    }, [onAuthenticateUser, showSessions]);

    const handleDeleteAccount = useCallback(() => {
        showDeleteAccount();
    }, [showDeleteAccount]);

    useEffect(() => {
        if (!open || !pendingAction) return;
        switch (pendingAction) {
            case "account.subscription":
                handleManageSubscription();
                break;
            case "account.recoveryKey":
                void handleRecoveryKey();
                break;
            case "account.twoFactor.reconfigure":
            case "account.twoFactor":
                showTwoFactor();
                break;
            case "account.passkeys":
                void handlePasskeys();
                break;
            case "account.changePassword":
                void handleChangePassword();
                break;
            case "account.changeEmail":
                handleChangeEmail();
                break;
            case "account.deleteAccount":
                handleDeleteAccount();
                break;
            case "account.sessions":
                void handleActiveSessions();
                break;
        }
        onActionHandled?.();
    }, [
        handleManageSubscription,
        handleActiveSessions,
        handleChangeEmail,
        handleChangePassword,
        handleDeleteAccount,
        handleRecoveryKey,
        handlePasskeys,
        open,
        onActionHandled,
        pendingAction,
        showTwoFactor,
    ]);

    return (
        <TitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("account")}
        >
            <Stack sx={{ px: 2, py: 1, gap: 3 }}>
                <RowButtonGroup>
                    <RowButton
                        label={accountLabel(t("manage_plan"), planSubtext)}
                        onClick={handleManageSubscription}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        label={t("recovery_key")}
                        onClick={() => void handleRecoveryKey()}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        label={accountLabel(
                            t("two_factor"),
                            twoFactorEnabled === undefined
                                ? undefined
                                : t(twoFactorEnabled ? "on" : "off"),
                        )}
                        onClick={showTwoFactor}
                    />
                    <RowButtonDivider />
                    <RowButton
                        label={accountLabel(t("passkeys"))}
                        onClick={handlePasskeys}
                    />
                    <RowButtonDivider />
                    <RowButton
                        label={accountLabel(
                            t("active_sessions"),
                            sessionCount === undefined
                                ? undefined
                                : t("account_sessions", {
                                      count: sessionCount,
                                  }),
                        )}
                        onClick={handleActiveSessions}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        label={t("change_password")}
                        onClick={handleChangePassword}
                    />
                    <RowButtonDivider />
                    <RowButton
                        label={accountLabel(
                            t("change_email"),
                            userDetails?.email,
                        )}
                        onClick={handleChangeEmail}
                    />
                </RowButtonGroup>
                <RowButtonGroup>
                    <RowButton
                        color="critical"
                        label={t("delete_account")}
                        onClick={handleDeleteAccount}
                    />
                </RowButtonGroup>
            </Stack>
            <RecoveryKey
                {...recoveryKeyVisibilityProps}
                getRecoveryKeyMnemonic={recoveryKeyMnemonic}
                {...{ showMiniDialog }}
            />
            {isNonAdminFamilyMember && userDetails && (
                <ManageMemberSubscription
                    {...manageMemberSubscriptionVisibilityProps}
                    {...{ userDetails }}
                />
            )}
            <TwoFactorSettings
                {...twoFactorVisibilityProps}
                onRootClose={onRootClose}
            />
            <SessionsSettings
                {...sessionsVisibilityProps}
                onRootClose={onRootClose}
            />
            <DeleteAccount
                {...deleteAccountVisibilityProps}
                {...{ onAuthenticateUser }}
            />
        </TitledNestedSidebarDrawer>
    );
};
