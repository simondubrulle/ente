import { useCallback, useEffect, useRef } from "react";

/** Keep the current view until maps are enabled, ignoring superseded requests. */
export const useMapNavigation = ({
    mapEnabled,
    enableMap,
    onError,
}: {
    mapEnabled: boolean;
    enableMap: () => Promise<void>;
    onError: (error: unknown) => void;
}) => {
    const requestID = useRef(0);
    const cancel = useCallback(() => {
        requestID.current += 1;
    }, []);

    useEffect(() => cancel, [cancel]);

    const open = useCallback(
        async (activate: () => void) => {
            const id = ++requestID.current;
            try {
                if (!mapEnabled) await enableMap();
            } catch (error) {
                if (id === requestID.current) onError(error);
                return;
            }
            if (id === requestID.current) activate();
        },
        [mapEnabled, enableMap, onError],
    );

    return { open, cancel };
};
