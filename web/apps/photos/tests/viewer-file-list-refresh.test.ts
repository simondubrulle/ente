import type { ItemData } from "ente-gallery/components/viewer/data-source-core";
import {
    FileViewerPhotoSwipe,
    type FileViewerPhotoSwipeDataSource,
} from "ente-gallery/components/viewer/photoswipe-core";
import type { EnteFile } from "ente-media/file";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

const { createPhotoSwipe } = vi.hoisted(() => ({ createPhotoSwipe: vi.fn() }));

vi.mock("photoswipe", () => ({ default: createPhotoSwipe }));
vi.mock("hls-video-element", () => ({}));
vi.mock("media-chrome", () => ({ MediaMuteButton: vi.fn() }));
vi.mock("media-chrome/menu", () => ({
    MediaChromeMenu: vi.fn(),
    MediaChromeMenuButton: vi.fn(),
}));
vi.mock("ente-base/log", () => ({ default: { error: vi.fn() } }));
vi.mock("i18next", () => ({ t: (key: string) => key }));

interface Slide {
    index: number;
    data: ItemData;
}

interface Holder {
    slide: Slide | undefined;
    el: {
        getAttribute: () => null;
        setAttribute: () => void;
        removeAttribute: () => void;
    };
}

// Model PhotoSwipe's preloaded holders: a one-photo viewer has no neighbours,
// and goTo emits change using a neighbour before Ente refreshes its content.
class PhotoSwipeWithEmptyNeighbours {
    currIndex: number;
    currSlide: Slide | undefined;
    viewInfo: (() => void) | undefined;
    mainScroll = {
        itemHolders: Array.from({ length: 3 }, (): Holder => ({
            slide: undefined,
            el: {
                getAttribute: () => null,
                setAttribute: vi.fn(),
                removeAttribute: vi.fn(),
            },
        })),
    };
    ui = {
        uiElementsData: [
            { name: "zoom", order: 0 },
            { name: "preloader", order: 0, onInit: vi.fn() },
        ],
        registerElement: (element: { name: string; onClick?: () => void }) => {
            if (element.name === "info") this.viewInfo = element.onClick;
        },
    };
    private listeners = new Map<string, (() => void)[]>();
    private filters = new Map<
        string,
        (value: unknown, index: number) => unknown
    >();

    constructor({ index }: { index: number }) {
        this.currIndex = index;
    }

    on(name: string, listener: () => void) {
        this.listeners.set(name, [
            ...(this.listeners.get(name) ?? []),
            listener,
        ]);
    }

    addFilter(
        name: string,
        filter: (value: unknown, index: number) => unknown,
    ) {
        this.filters.set(name, filter);
    }

    private emit(name: string) {
        this.listeners.get(name)?.forEach((listener) => listener());
    }

    init() {
        this.mainScroll.itemHolders.forEach((holder, offset) =>
            this.setContent(holder, this.currIndex + offset - 1),
        );
        this.emit("uiRegister");
        this.emit("change");
    }

    setContent(holder: Holder, index: number) {
        const count = Number(this.filters.get("numItems")!(0, 0));
        if (count > 2) index = (index + count) % count;
        if (index < 0 || index >= count) return;
        holder.slide = {
            index,
            data: this.filters.get("itemData")!({}, index) as ItemData,
        };
        if (index === this.currIndex) this.currSlide = holder.slide;
    }

    goTo(index: number) {
        this.currIndex = index;
        this.currSlide = this.mainScroll.itemHolders.find(
            (holder) => holder.slide?.index === index,
        )?.slide;
        this.emit("change");
    }

    refreshSlideContent(index: number) {
        this.mainScroll.itemHolders.forEach((holder) => {
            if (holder.slide?.index === index) this.setContent(holder, index);
        });
        this.emit("change");
    }
}

beforeEach(() => {
    vi.stubGlobal("window", { matchMedia: () => ({ matches: false }) });
});
afterEach(() => vi.unstubAllGlobals());

const file = (id: number) =>
    ({ id, updationTime: 1, metadata: { fileType: 0 } }) as EnteFile;

test.each([
    [1, 0, 1],
    [1, 0, 2],
    [2, 1, 1],
])(
    "preserves a %i-photo list's open index %i after %i earlier uploads",
    (count, index, addedCount) => {
        let files = Array.from({ length: count }, (_, i) => file(i + 1));
        const openFile = files[index]!;
        const pswp = new PhotoSwipeWithEmptyNeighbours({ index });
        createPhotoSwipe.mockImplementation(function () {
            return pswp;
        });
        const dataSource = {
            itemDataForFile: (file: EnteFile) => ({
                fileID: file.id,
                fileType: file.metadata.fileType,
            }),
            fileViewerWillOpen: vi.fn(),
            updateFileInfoExifIfNeeded: vi.fn().mockResolvedValue(undefined),
        } as unknown as FileViewerPhotoSwipeDataSource;
        const onViewInfo = vi.fn();
        const viewer = new FileViewerPhotoSwipe({
            initialIndex: index,
            dataSource,
            haveUser: false,
            showSocialButtons: false,
            enableComment: false,
            delegate: { getFiles: () => files } as ConstructorParameters<
                typeof FileViewerPhotoSwipe
            >[0]["delegate"],
            onAnnotate: (file, itemData) => ({
                file,
                itemData,
                annotation: { showFavorite: false, showDownload: undefined },
            }),
            onViewInfo,
            onClose: vi.fn(),
            onViewComments: vi.fn(),
            onViewLikes: vi.fn(),
            onLikeClick: vi.fn(),
            onDownload: vi.fn(),
            onMore: vi.fn(),
        });
        pswp.viewInfo!();

        files = [
            ...Array.from({ length: addedCount }, (_, i) => file(i + 10)),
            ...files,
        ];
        expect(() => viewer.refreshSlideOnFilesUpdateIfNeeded()).not.toThrow();
        expect(pswp.currSlide?.data.fileID).toBe(openFile.id);
        expect(pswp.currIndex).toBe(index + addedCount);
        pswp.viewInfo!();
        expect(onViewInfo).toHaveBeenLastCalledWith(
            expect.objectContaining({ file: openFile }),
        );
    },
);
