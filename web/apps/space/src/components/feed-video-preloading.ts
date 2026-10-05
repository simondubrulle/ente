interface VideoLoad {
    element: HTMLElement;
    load: () => Promise<string>;
    resolve: (url: string) => void;
    reject: (error: unknown) => void;
}

const queued = new Set<VideoLoad>();
let inFlight = 0;
let frame: number | undefined;

const distance = ({ element }: VideoLoad) => {
    const rect = element.getBoundingClientRect();
    const post = element.closest("article")!.getBoundingClientRect();
    return (
        Math.max(0, rect.top - window.innerHeight, -rect.bottom) +
        Math.abs(rect.left - post.left)
    );
};

const schedule = () => {
    if (!queued.size || inFlight >= 2) return;
    frame ??= requestAnimationFrame(() => {
        frame = undefined;
        const next = [...queued].sort((a, b) => distance(a) - distance(b));
        for (const request of next) {
            if (inFlight >= 2) break;
            queued.delete(request);
            inFlight++;
            void (async () => {
                try {
                    request.resolve(await request.load());
                } catch (error) {
                    request.reject(error);
                } finally {
                    inFlight--;
                    schedule();
                }
            })();
        }
    });
};

export const queueFeedVideoLoad = (
    element: HTMLElement,
    load: VideoLoad["load"],
) => {
    let request: VideoLoad;
    const promise = new Promise<string>((resolve, reject) => {
        request = { element, load, resolve, reject };
        queued.add(request);
        schedule();
    });
    return {
        promise,
        cancel: () => {
            if (!queued.delete(request)) return;
            request.reject(
                new DOMException("Video preload canceled", "AbortError"),
            );
            if (!queued.size && frame != undefined) {
                cancelAnimationFrame(frame);
                frame = undefined;
            }
        },
    };
};
