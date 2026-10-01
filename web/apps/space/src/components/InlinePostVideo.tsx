import { Box } from "@mui/material";
import { createSpaceVideoContent } from "components/PostVideoContent";
import React, { useEffect, useRef } from "react";
import type { SpacePostAssetURLLoader, SpacePostVideo } from "services/space";

let playingVideo: ReturnType<typeof createSpaceVideoContent> | undefined;

export const SpaceInlinePostVideo: React.FC<{
    imageUrl: string;
    video: SpacePostVideo;
    isActive: boolean;
    onLoadVideo?: SpacePostAssetURLLoader;
}> = ({ imageUrl, video, isActive, onLoadVideo }) => {
    const root = useRef<HTMLDivElement>(null);
    const player = useRef<
        ReturnType<typeof createSpaceVideoContent> | undefined
    >(undefined);

    useEffect(() => {
        const container = root.current!;
        const content = createSpaceVideoContent(
            { imageUrl, video },
            onLoadVideo,
            { inline: true },
        );
        player.current = content;
        container.append(content.element);
        const onPlay = () => {
            if (playingVideo != content) playingVideo?.pause();
            playingVideo = content;
        };
        content.video.addEventListener("play", onPlay);
        const observer = new IntersectionObserver(([entry]) => {
            if (!entry!.isIntersecting) content.deactivate();
        });
        observer.observe(container);
        return () => {
            observer.disconnect();
            content.video.removeEventListener("play", onPlay);
            content.destroy();
            content.element.remove();
            if (playingVideo == content) playingVideo = undefined;
            player.current = undefined;
        };
    }, [imageUrl, onLoadVideo, video]);

    useEffect(() => {
        const content = player.current!;
        if (!isActive) content.deactivate();
        content.video.tabIndex = isActive ? 0 : -1;
        content.element.querySelector("button")!.tabIndex = isActive ? 0 : -1;
    }, [imageUrl, isActive, onLoadVideo, video]);

    return (
        <Box ref={root} sx={{ position: "absolute", inset: 0, zIndex: 1 }} />
    );
};
