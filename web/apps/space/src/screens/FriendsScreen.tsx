import {
    ArrowLeft02Icon,
    Cancel01Icon,
    UserAdd02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Skeleton } from "@mui/material";
import {
    spaceActionDoneDurationMs,
    SpaceActionFeedbackIcon,
    type SpaceActionPhase,
} from "components/ActionFeedback";
import { SpaceAddFriendDialog } from "components/AddFriendDialog";
import { SpaceAvatarImage } from "components/AvatarImage";
import { ConfirmationActionSheet } from "components/ConfirmationActionSheet";
import { FriendOrbit } from "components/FriendOrbit";
import { FriendQuickActionsDialog } from "components/FriendQuickActionsDialog";
import { SpaceLoadingSpinner } from "components/RouteFallback";
import { SpaceShareInviteButton } from "components/ShareInviteButton";
import { SpaceSkipLink } from "components/SkipLink";
import type { FriendProfile } from "data/friends";
import log from "ente-base/log";
import React, { useState } from "react";
import type { SpaceFriendRequest } from "services/space";
import {
    spaceAppBackground,
    spaceOnAccent,
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";

const green = "#08C225";
const avatarSkeletonBackground = spaceSurface;
const textBase = spaceText;
const textStrong = spaceText;
const textSoft = spaceTextMuted;
const friendAvatarLoadRootMargin = "800px 0px";

const friendAvatarCacheKey = (friend: FriendProfile) =>
    [
        friend.id,
        friend.avatarKeyVersion ?? "",
        friend.avatarObjectID ?? "",
        friend.avatarUpdatedAt ?? "",
        friend.avatarSize ?? "",
    ].join(":");

interface FriendsScreenProps {
    friendRequests: SpaceFriendRequest[];
    friends: FriendProfile[];
    isLoading: boolean;
    onBack: () => void;
    onAcceptFriendRequest: (requestID: number) => Promise<void>;
    onDeleteFriendRequest: (requestID: number) => Promise<void>;
    onLoadFriendAvatar?: (friend: FriendProfile) => Promise<string | null>;
    onAddFriend: (username: string) => Promise<"friend" | "requested">;
    onMessage?: (friendID: string) => void;
    onPoke?: (friendID: string, requestID: string) => Promise<void>;
    onOpenFriend?: (friendID: string) => void;
    profileLink?: string;
    username: string;
    onUnfriend?: (friendID: string) => Promise<void> | void;
}

interface FriendIdentityProps {
    avatarUrl?: string | null;
    friend: FriendProfile;
    onLoadAvatar?: () => Promise<string | null | undefined>;
    onOpen?: (event: React.MouseEvent<HTMLButtonElement>) => void;
    floating?: boolean;
    primaryText?: string;
    secondaryText?: string;
}

const FriendIdentity: React.FC<FriendIdentityProps> = ({
    avatarUrl,
    friend,
    floating = false,
    onLoadAvatar,
    onOpen,
    primaryText,
    secondaryText = `@${friend.username}`,
}) => {
    const displayName = friend.fullName.trim() || friend.username.trim();
    const avatarRef = React.useRef<HTMLDivElement | null>(null);
    const [shouldLoadAvatar, setShouldLoadAvatar] = useState(
        Boolean(avatarUrl || !friend.avatarObjectID),
    );

    React.useEffect(() => {
        if (avatarUrl) setShouldLoadAvatar(true);
    }, [avatarUrl]);

    React.useEffect(() => {
        if (shouldLoadAvatar || avatarUrl || !friend.avatarObjectID) return;
        const element = avatarRef.current;
        if (!element) return;
        if (
            typeof window == "undefined" ||
            !("IntersectionObserver" in window)
        ) {
            setShouldLoadAvatar(true);
            return;
        }

        const observer = new IntersectionObserver(
            (entries) => {
                if (entries.some((entry) => entry.isIntersecting)) {
                    setShouldLoadAvatar(true);
                    observer.disconnect();
                }
            },
            { rootMargin: friendAvatarLoadRootMargin },
        );
        observer.observe(element);
        return () => observer.disconnect();
    }, [avatarUrl, friend.avatarObjectID, shouldLoadAvatar]);

    React.useEffect(() => {
        if (!shouldLoadAvatar || avatarUrl || !friend.avatarObjectID) return;
        void onLoadAvatar?.().catch((error: unknown) => {
            log.warn("Failed to load friend avatar", error);
        });
    }, [avatarUrl, friend.avatarObjectID, onLoadAvatar, shouldLoadAvatar]);

    return (
        <Box
            component={onOpen ? "button" : "div"}
            type={onOpen ? "button" : undefined}
            onClick={onOpen}
            aria-label={floating ? `Actions for ${displayName}` : undefined}
            aria-haspopup={floating ? "dialog" : undefined}
            sx={{
                alignItems: "center",
                bgcolor: "transparent",
                border: 0,
                borderRadius: floating ? "50%" : "12px",
                cursor: onOpen ? "pointer" : "default",
                display: "flex",
                flexDirection: floating ? "column" : "row",
                gap: floating ? "10px" : "12px",
                maxWidth: "100%",
                minWidth: 0,
                p: 0,
                textAlign: floating ? "center" : "left",
                width: floating ? "100%" : "fit-content",
                position: "relative",
                transition: "scale 180ms ease",
                "&:hover": floating ? { scale: "1.06" } : undefined,
                "@media (prefers-reduced-motion: reduce)": {
                    transition: "none",
                },
                "&:focus-visible": {
                    outline: `2px solid ${green}`,
                    outlineOffset: 2,
                },
            }}
        >
            <Box
                ref={avatarRef}
                sx={{
                    alignItems: "center",
                    bgcolor: avatarSkeletonBackground,
                    border: floating ? "1px solid #454545" : undefined,
                    borderRadius: "50%",
                    display: "flex",
                    flexShrink: 0,
                    height: floating ? "auto" : 44,
                    aspectRatio: "1",
                    justifyContent: "center",
                    overflow: "hidden",
                    width: floating ? "100%" : 44,
                    boxShadow: floating
                        ? "0 8px 28px rgba(0, 0, 0, 0.2)"
                        : undefined,
                }}
            >
                {avatarUrl || !friend.avatarObjectID ? (
                    <SpaceAvatarImage src={avatarUrl} />
                ) : (
                    <Skeleton
                        variant="circular"
                        sx={{
                            bgcolor: avatarSkeletonBackground,
                            height: "100%",
                            transform: "none",
                            width: "100%",
                        }}
                    />
                )}
            </Box>
            {!floating && (
                <Box
                    sx={{
                        display: "flex",
                        flex: "0 1 auto",
                        flexDirection: "column",
                        justifyContent: "center",
                        minWidth: 0,
                    }}
                >
                    <Box
                        sx={{
                            color: textStrong,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 700,
                            lineHeight: "20px",
                            minWidth: 0,
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            whiteSpace: "nowrap",
                        }}
                    >
                        {primaryText ?? displayName}
                    </Box>
                    <Box
                        sx={{
                            color: textSoft,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            fontWeight: 500,
                            lineHeight: "18px",
                            minWidth: 0,
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            whiteSpace: "nowrap",
                        }}
                    >
                        {secondaryText}
                    </Box>
                </Box>
            )}
        </Box>
    );
};

interface FriendRequestRowProps {
    onAccept: (requestID: number) => Promise<void>;
    onDelete: (requestID: number) => Promise<void>;
    request: SpaceFriendRequest;
}

const FriendRequestRow: React.FC<FriendRequestRowProps> = ({
    onAccept,
    onDelete,
    request,
}) => {
    const [action, setAction] = React.useState<"accept" | "delete" | null>(
        null,
    );
    const isReceived = request.direction == "received";
    const isBusy = action != null;
    const displayName =
        request.friend.fullName.trim() || request.friend.username.trim();
    const runAction = (
        nextAction: "accept" | "delete",
        handler: (requestID: number) => Promise<void>,
    ) => {
        if (isBusy) return;
        setAction(nextAction);
        void handler(request.requestId)
            .catch((error: unknown) =>
                log.error("Failed to update friend request", error),
            )
            .finally(() => setAction(null));
    };

    return (
        <Box
            component="li"
            sx={{
                alignItems: "center",
                display: "grid",
                gap: "8px",
                gridTemplateColumns: "minmax(0, 1fr) auto",
                listStyle: "none",
                minHeight: 72,
                px: "18px",
                py: "12px",
                width: "100%",
            }}
        >
            <FriendIdentity
                friend={request.friend}
                primaryText={`@${request.friend.username}`}
                secondaryText={
                    isReceived ? "Sent you a friend request" : "Request sent"
                }
            />
            <Box
                sx={{
                    alignItems: "center",
                    display: "flex",
                    flexShrink: 0,
                    gap: "6px",
                }}
            >
                {isReceived ? (
                    <>
                        <Box
                            className="green-bg"
                            component="button"
                            type="button"
                            disabled={isBusy}
                            onClick={() => runAction("accept", onAccept)}
                            sx={{
                                alignItems: "center",
                                bgcolor: green,
                                border: 0,
                                borderRadius: "12px",
                                color: spaceOnAccent,
                                cursor: isBusy ? "default" : "pointer",
                                display: "flex",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 12,
                                fontWeight: 700,
                                height: 34,
                                justifyContent: "center",
                                minWidth: 64,
                                px: "12px",
                                "&:disabled": { opacity: 0.6 },
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                                "&:hover": isBusy
                                    ? undefined
                                    : { bgcolor: "#07A820" },
                            }}
                        >
                            {action == "accept" ? (
                                <SpaceActionFeedbackIcon
                                    phase="busy"
                                    size={16}
                                />
                            ) : (
                                "Accept"
                            )}
                        </Box>
                        <Box
                            component="button"
                            type="button"
                            aria-label={`Decline friend request from ${displayName}`}
                            disabled={isBusy}
                            onClick={() => runAction("delete", onDelete)}
                            sx={{
                                alignItems: "center",
                                bgcolor: "transparent",
                                border: 0,
                                borderRadius: "50%",
                                color: textBase,
                                cursor: isBusy ? "default" : "pointer",
                                display: "flex",
                                height: 34,
                                justifyContent: "center",
                                p: 0,
                                width: 34,
                                "&:disabled": { opacity: 0.45 },
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                                "&:hover": isBusy
                                    ? undefined
                                    : { bgcolor: spaceSurfaceHover },
                            }}
                        >
                            {action == "delete" ? (
                                <SpaceActionFeedbackIcon
                                    phase="busy"
                                    size={18}
                                />
                            ) : (
                                <HugeiconsIcon
                                    icon={Cancel01Icon}
                                    size={18}
                                    strokeWidth={2}
                                />
                            )}
                        </Box>
                    </>
                ) : (
                    <Box
                        component="button"
                        type="button"
                        aria-label={`Cancel friend request to ${displayName}`}
                        disabled={isBusy}
                        onClick={() => runAction("delete", onDelete)}
                        sx={{
                            alignItems: "center",
                            bgcolor: spaceSurface,
                            border: 0,
                            borderRadius: "12px",
                            color: textBase,
                            cursor: isBusy ? "default" : "pointer",
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 12,
                            fontWeight: 700,
                            height: 34,
                            justifyContent: "center",
                            minWidth: 64,
                            px: "12px",
                            "&:disabled": { opacity: 0.6 },
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                            "&:hover": isBusy
                                ? undefined
                                : { bgcolor: spaceSurfaceHover },
                        }}
                    >
                        {action == "delete" ? (
                            <SpaceActionFeedbackIcon phase="busy" size={16} />
                        ) : (
                            "Cancel"
                        )}
                    </Box>
                )}
            </Box>
        </Box>
    );
};

export const FriendsScreen: React.FC<FriendsScreenProps> = ({
    friendRequests,
    friends,
    isLoading,
    onAcceptFriendRequest,
    onAddFriend,
    onBack,
    onDeleteFriendRequest,
    onLoadFriendAvatar,
    onMessage,
    onPoke,
    onOpenFriend,
    profileLink,
    username,
    onUnfriend,
}) => {
    const [isAddFriendOpen, setIsAddFriendOpen] = React.useState(false);
    const [selectedFriend, setSelectedFriend] = React.useState<{
        friend: FriendProfile;
        anchorRect: DOMRect;
    } | null>(null);
    const pokeRequestIDs = React.useRef(new Map<string, string>());
    const [friendToUnfriend, setFriendToUnfriend] =
        React.useState<FriendProfile | null>(null);
    const [isUnfriendOpen, setIsUnfriendOpen] = React.useState(false);
    const [unfriendActionPhase, setUnfriendActionPhase] =
        React.useState<SpaceActionPhase | null>(null);
    const [unfriendErrorMessage, setUnfriendErrorMessage] = React.useState<
        string | null
    >(null);
    const [loadedAvatarURLsByKey, setLoadedAvatarURLsByKey] = React.useState<
        Record<string, string>
    >({});
    const [isInviteSharing, setIsInviteSharing] = React.useState(false);
    const avatarLoadsInFlightRef = React.useRef<
        Map<string, Promise<string | null | undefined>>
    >(new Map());
    const isUnfriendActionRunning = unfriendActionPhase != null;
    const loadedAvatarURLFor = React.useCallback(
        (friend: FriendProfile) =>
            friend.avatarUrl ??
            loadedAvatarURLsByKey[friendAvatarCacheKey(friend)],
        [loadedAvatarURLsByKey],
    );

    const loadFriendAvatar = React.useCallback(
        (friend: FriendProfile) => {
            const loadedAvatarUrl = loadedAvatarURLFor(friend);
            if (loadedAvatarUrl) return Promise.resolve(loadedAvatarUrl);
            if (!friend.avatarObjectID || !onLoadFriendAvatar) {
                return Promise.resolve(undefined);
            }

            const cacheKey = friendAvatarCacheKey(friend);
            const inFlight = avatarLoadsInFlightRef.current.get(cacheKey);
            if (inFlight) return inFlight;

            const load = onLoadFriendAvatar(friend)
                .then((avatarUrl) => {
                    if (avatarUrl) {
                        setLoadedAvatarURLsByKey((currentURLs) =>
                            currentURLs[cacheKey] == avatarUrl
                                ? currentURLs
                                : { ...currentURLs, [cacheKey]: avatarUrl },
                        );
                    }
                    return avatarUrl;
                })
                .catch((error: unknown) => {
                    log.warn("Failed to load friend avatar", error);
                    return undefined;
                })
                .finally(() => {
                    avatarLoadsInFlightRef.current.delete(cacheKey);
                });
            avatarLoadsInFlightRef.current.set(cacheKey, load);
            return load;
        },
        [loadedAvatarURLFor, onLoadFriendAvatar],
    );

    const cancelUnfriend = () => {
        if (isUnfriendActionRunning) return;
        setUnfriendErrorMessage(null);
        setIsUnfriendOpen(false);
    };

    const confirmUnfriend = () => {
        if (!friendToUnfriend || isUnfriendActionRunning) return;
        setUnfriendErrorMessage(null);
        setUnfriendActionPhase("busy");
        void (async () => {
            try {
                await Promise.resolve(onUnfriend?.(friendToUnfriend.id));
                setUnfriendActionPhase("done");
            } catch (error) {
                log.error("Failed to unfriend space friend", error);
                setUnfriendActionPhase(null);
                setUnfriendErrorMessage("Couldn't unfriend. Please try again.");
            }
        })();
    };

    React.useEffect(() => {
        if (unfriendActionPhase != "done") return;

        const timeoutID = window.setTimeout(() => {
            setIsUnfriendOpen(false);
        }, spaceActionDoneDurationMs);

        return () => window.clearTimeout(timeoutID);
    }, [unfriendActionPhase]);

    const handleUnfriendSheetExited = () => {
        setFriendToUnfriend(null);
        setUnfriendActionPhase(null);
        setUnfriendErrorMessage(null);
    };

    return (
        <Box
            component="main"
            sx={{
                background: spaceAppBackground,
                color: textBase,
                display: "grid",
                boxSizing: "border-box",
                minHeight: "var(--space-page-height, 100svh)",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
            }}
        >
            <SpaceSkipLink />
            <Box
                sx={{
                    bgcolor: "transparent",
                    boxSizing: "border-box",
                    minHeight: "var(--space-page-height, 100svh)",
                    mx: "auto",
                    position: "relative",
                    width: "100%",
                }}
            >
                <Box
                    component="header"
                    sx={{
                        alignItems: "center",
                        display: "grid",
                        gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                        height: 56,
                        maxWidth: 390,
                        mx: "auto",
                        px: 2,
                        width: "100%",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Back"
                        onClick={onBack}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: "pointer",
                            display: "flex",
                            height: spaceTouchTargetSize,
                            justifyContent: "flex-start",
                            ml: "-2px",
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={ArrowLeft02Icon}
                            size={24}
                            strokeWidth={1.8}
                        />
                    </Box>
                    <Box
                        component="h1"
                        sx={{
                            color: textBase,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 18,
                            fontWeight: 700,
                            justifySelf: "center",
                            lineHeight: "24px",
                            m: 0,
                        }}
                    >
                        Friends
                    </Box>
                    <Box
                        component="button"
                        type="button"
                        aria-expanded={isAddFriendOpen}
                        aria-label="Add friend"
                        disabled={isLoading}
                        onClick={() => setIsAddFriendOpen(true)}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: isLoading ? "default" : "pointer",
                            display: "flex",
                            height: spaceTouchTargetSize,
                            justifyContent: "flex-end",
                            justifySelf: "flex-end",
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:disabled": { opacity: 0.45 },
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={UserAdd02Icon}
                            size={22}
                            strokeWidth={1.8}
                        />
                    </Box>
                </Box>

                <SpaceAddFriendDialog
                    friendRequests={friendRequests}
                    friends={friends}
                    onAddFriend={onAddFriend}
                    onClose={() => setIsAddFriendOpen(false)}
                    open={isAddFriendOpen}
                    profileLink={profileLink}
                    username={username}
                />

                <Box
                    component="section"
                    id="space-main-content"
                    aria-label="Friends"
                    tabIndex={-1}
                >
                    {isLoading ? (
                        <Box
                            sx={{
                                display: "grid",
                                inset: 0,
                                placeItems: "center",
                                position: "absolute",
                                pointerEvents: "none",
                            }}
                        >
                            <SpaceLoadingSpinner ariaLabel="Loading friends" />
                        </Box>
                    ) : friends.length > 0 || friendRequests.length > 0 ? (
                        <>
                            {friends.length > 0 && (
                                <FriendOrbit
                                    friends={friends}
                                    renderFriend={(friend) => (
                                        <FriendIdentity
                                            floating
                                            avatarUrl={loadedAvatarURLFor(
                                                friend,
                                            )}
                                            friend={friend}
                                            onLoadAvatar={() =>
                                                loadFriendAvatar(friend)
                                            }
                                            onOpen={(event) =>
                                                setSelectedFriend({
                                                    friend,
                                                    anchorRect:
                                                        event.currentTarget.getBoundingClientRect(),
                                                })
                                            }
                                        />
                                    )}
                                />
                            )}
                            {friendRequests.length > 0 && (
                                <Box
                                    sx={{
                                        maxWidth: 390,
                                        mx: "auto",
                                        py: "24px",
                                    }}
                                >
                                    <Box
                                        component="h2"
                                        sx={{
                                            fontSize: 14,
                                            fontWeight: 600,
                                            m: 0,
                                            px: "18px",
                                            pb: "8px",
                                        }}
                                    >
                                        Friend requests
                                    </Box>
                                    <Box component="ul" sx={{ m: 0, p: 0 }}>
                                        {friendRequests.map((request) => (
                                            <FriendRequestRow
                                                key={request.requestId}
                                                request={request}
                                                onAccept={onAcceptFriendRequest}
                                                onDelete={onDeleteFriendRequest}
                                            />
                                        ))}
                                    </Box>
                                </Box>
                            )}
                        </>
                    ) : (
                        <Box
                            sx={{
                                alignItems: "center",
                                color: textSoft,
                                display: "flex",
                                flexDirection: "column",
                                gap: "22px",
                                inset: 0,
                                justifyContent: "center",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                lineHeight: "20px",
                                pointerEvents: "none",
                                position: "absolute",
                                px: "24px",
                                textAlign: "center",
                            }}
                        >
                            <Box component="p" sx={{ m: 0, maxWidth: 260 }}>
                                Invite your friends and family. Share everyday
                                photos and keep up with each other.
                            </Box>
                            <SpaceShareInviteButton
                                profileLink={profileLink}
                                sharing={isInviteSharing}
                                onShareError={(error) =>
                                    log.error(
                                        "Failed to share Space invite link",
                                        error,
                                    )
                                }
                                onSharingChange={setIsInviteSharing}
                            />
                        </Box>
                    )}
                </Box>
            </Box>
            {selectedFriend && (
                <FriendQuickActionsDialog
                    anchorRect={selectedFriend.anchorRect}
                    avatarUrl={loadedAvatarURLFor(selectedFriend.friend)}
                    friend={selectedFriend.friend}
                    onClose={() => setSelectedFriend(null)}
                    onMessage={
                        onMessage
                            ? () => onMessage(selectedFriend.friend.id)
                            : undefined
                    }
                    onPoke={
                        onPoke
                            ? async () => {
                                  const friendID = selectedFriend.friend.id;
                                  const requestID =
                                      pokeRequestIDs.current.get(friendID) ??
                                      crypto.randomUUID();
                                  pokeRequestIDs.current.set(
                                      friendID,
                                      requestID,
                                  );
                                  await onPoke(friendID, requestID);
                                  pokeRequestIDs.current.delete(friendID);
                              }
                            : undefined
                    }
                    onProfile={
                        onOpenFriend
                            ? () => onOpenFriend(selectedFriend.friend.id)
                            : undefined
                    }
                    onUnfriend={
                        onUnfriend
                            ? () => {
                                  setUnfriendErrorMessage(null);
                                  setFriendToUnfriend(selectedFriend.friend);
                                  setIsUnfriendOpen(true);
                              }
                            : undefined
                    }
                />
            )}
            <ConfirmationActionSheet
                open={isUnfriendOpen}
                title={`Unfriend ${friendToUnfriend?.fullName.trim().split(/\s+/)[0] || friendToUnfriend?.username}?`}
                description="You’ll no longer see each other’s posts or message each other."
                confirmLabel="Unfriend"
                confirmActionPhase={unfriendActionPhase}
                confirmDisabled={isUnfriendActionRunning}
                errorMessage={unfriendErrorMessage}
                cancelDisabled={isUnfriendActionRunning}
                onCancel={cancelUnfriend}
                onConfirm={confirmUnfriend}
                onExited={handleUnfriendSheetExited}
            />
        </Box>
    );
};
