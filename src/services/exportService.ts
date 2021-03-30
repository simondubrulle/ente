import { runningInBrowser } from 'utils/common/utilFunctions';
import downloadManager from './downloadManager';
import { file } from './fileService';

enum ExportNotification {
    START = 'export started',
    FINISH = 'export finished',
}
class ExportService {
    ElectronAPIs: any = runningInBrowser() && window['ElectronAPIs'];
    async exportFiles(files: file[]) {
        try {
            const dir = await this.ElectronAPIs.selectDirectory();
            if (!dir) {
                // directory selector closed
                return;
            }
            const exportedFiles: Set<string> = await this.ElectronAPIs.getExportedFiles(
                dir
            );
            this.ElectronAPIs.sendNotification(ExportNotification.START);
            for (let [index, file] of files.entries()) {
                const uid = `${file.id}_${file.metadata.title}`;
                if (!exportedFiles.has(uid)) {
                    await this.downloadAndSave(file, `${dir}/${uid}`);
                    this.ElectronAPIs.updateExportRecord(dir, uid);
                }
                this.ElectronAPIs.showOnTray([
                    { label: `${index + 1} / ${files.length} files exported` },
                ]);
            }
            this.ElectronAPIs.sendNotification(ExportNotification.FINISH);
            this.ElectronAPIs.showOnTray([]);
        } catch (e) {
            console.error(e);
        }
    }

    async downloadAndSave(file: file, path) {
        const fileStream = await downloadManager.downloadFile(file);

        this.ElectronAPIs.saveToDisk(path, fileStream);
    }
}
export default new ExportService();
