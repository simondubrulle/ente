import { expose } from "comlink";
import { logUnhandledErrorsAndRejectionsInWorker } from "ente-base/log-web";
import * as kdf from "./kdf";

export class KDFWorker {
    deriveKey = kdf.deriveKey;
    generateAccountKeys = kdf.generateAccountKeys;
    generateInteractiveKeyAttributes = kdf.generateInteractiveKeyAttributes;
}

expose(KDFWorker);

logUnhandledErrorsAndRejectionsInWorker();
