import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppData } from '../model/PlanerModel';
import { freshData, normalizeData } from '../model/PlanerEngine';

export class PlanerStorage {
  private loadedPath: string = '';
  private pending: Promise<void> = Promise.resolve();

  async load(context: common.UIAbilityContext): Promise<AppData> {
    const dataPath = context.filesDir + '/data.json';
    this.loadedPath = '';
    try {
      if (!(await fileIo.access(dataPath))) {
        // 留下的备份或临时文件表示曾有数据，不能把它当成首次启动覆盖。
        if (await fileIo.access(dataPath + '.bak') || await fileIo.access(dataPath + '.tmp')) {
          throw new Error('主数据文件缺失，发现备份或未完成的保存文件，请先恢复 data.json。');
        }
        this.loadedPath = dataPath;
        return freshData();
      }
      const raw: AppData = JSON.parse(await fileIo.readText(dataPath)) as AppData;
      if (!raw || raw.version !== 1 || typeof raw.currentDate !== 'string' ||
        !Array.isArray(raw.todayTasks) || !Array.isArray(raw.futureTasks) ||
        !Array.isArray(raw.history) || !raw.settings) {
        throw new Error('data.json 的结构或版本不受支持。');
      }
      const data = normalizeData(raw);
      this.loadedPath = dataPath;
      return data;
    } catch (error) {
      throw new Error('读取日程失败，原文件已保留。' + String(error));
    }
  }

  // 供主应用比对外部写入：卡片进程可能在后台勾选日程，不能直接用内存状态覆盖文件。
  async readRaw(context: common.UIAbilityContext): Promise<string> {
    const dataPath = context.filesDir + '/data.json';
    try {
      if (!(await fileIo.access(dataPath))) return '';
      return await fileIo.readText(dataPath);
    } catch (error) {
      return '';
    }
  }

  async save(context: common.UIAbilityContext, data: AppData): Promise<void> {
    const dataPath = context.filesDir + '/data.json';
    if (this.loadedPath !== dataPath) {
      throw new Error('日程尚未成功加载，禁止覆盖本地数据。');
    }
    // 调用时即固定快照；串行写入避免较早的保存覆盖后续操作。
    const serialized = JSON.stringify(data);
    const operation = this.pending.then((): Promise<void> => this.writeSnapshot(dataPath, serialized));
    this.pending = operation.catch((): void => {});
    await operation;
  }

  private async writeSnapshot(dataPath: string, serialized: string): Promise<void> {
    const temporaryPath = dataPath + '.tmp';
    let temporaryFile: fileIo.File | null = null;
    try {
      temporaryFile = await fileIo.open(temporaryPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(temporaryFile.fd, serialized);
      await fileIo.fsync(temporaryFile.fd);
      await fileIo.close(temporaryFile);
      temporaryFile = null;
      // 验证完整写入后才替换主文件，失败时保留旧主文件和待恢复临时文件。
      if (await fileIo.readText(temporaryPath) !== serialized) {
        throw new Error('日程文件未完整写入，请检查可用存储空间后重试。');
      }
      if (await fileIo.access(dataPath)) {
        const backupTemporaryPath = dataPath + '.bak.tmp';
        await fileIo.copyFile(dataPath, backupTemporaryPath);
        await fileIo.rename(backupTemporaryPath, dataPath + '.bak');
      }
      await fileIo.rename(temporaryPath, dataPath);
    } catch (error) {
      if (temporaryFile !== null) {
        try {
          await fileIo.close(temporaryFile);
        } catch (closeError) {
          console.error('关闭日程临时文件失败：' + String(closeError));
        }
      }
      throw new Error('保存日程失败，请重试。' + String(error));
    }
  }
}
