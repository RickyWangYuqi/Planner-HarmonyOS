// 主应用侧的卡片推送：日程状态每次保存成功后，把同一份视图数据写给桌面上的所有卡片实例。
// 进程不同，卡片清单来自共享首选项（FormBoard），不依赖卡片扩展是否存活。
import { common, Want } from '@kit.AbilityKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { AppData } from '../model/PlanerModel';
import { buildCardData, CardSize, cardSizeForDimension, cardSizeForRect } from './CardData';
import { FormBoard, FormRecord } from './FormBoard';

export class FormSync {
  private static pending: Promise<void> = Promise.resolve();
  private static launchFormId: string = '';

  // 官方 router 事件通过 Want 携带源卡片 ID；冷启动和热启动都要采纳。
  static rememberLaunch(want: Want): void {
    const id = want.parameters ? want.parameters[formInfo.FormParam.IDENTITY_KEY] : undefined;
    FormSync.launchFormId = typeof id === 'string' ? id : '';
  }

  static sync(context: common.Context, data: AppData, dark: boolean): Promise<void> {
    const snapshot = data.clone();
    // 多轮保存 / 前后台推送必须串行，防止较早的异步更新最后到达、覆盖新配色。
    const operation = FormSync.pending.then((): Promise<void> => FormSync.push(context, snapshot, dark));
    FormSync.pending = operation.catch((): void => {});
    return operation;
  }

  private static async push(context: common.Context, data: AppData, dark: boolean): Promise<void> {
    try {
      const records: FormRecord[] = await FormSync.reconciled(context);
      // 来源卡片可能暂未出现在运行列表 / 跨进程缓存中，直接按官方传入 ID 补齐并优先刷新。
      const source = FormSync.launchFormId;
      if (source && !records.some((item: FormRecord): boolean => item.formId === source)) {
        const record = new FormRecord();
        record.formId = source;
        record.dimension = '2*2';
        try {
          const rect = await formProvider.getFormRect(source);
          const size = cardSizeForRect(rect.width, rect.height);
          record.dimension = size === CardSize.LARGE ? '4*4' : (size === CardSize.MEDIUM ? '2*4' : '2*2');
        } catch (error) { console.warn('读取来源卡片尺寸失败，先用小卡数据刷新'); }
        records.unshift(record);
      }
      records.sort((left: FormRecord, right: FormRecord): number =>
        left.formId === source ? -1 : (right.formId === source ? 1 : 0));
      if (records.length === 0) return;
      for (const record of records) {
        try {
          const size: CardSize = cardSizeForDimension(record.dimension);
          const payload = buildCardData(data, size, dark);
          await formProvider.updateForm(record.formId, formBindingData.createFormBindingData(payload));
        } catch (error) {
          // 单个卡片实例已失效时继续推送其余卡片，不因一条旧登记放弃整轮同步。
          console.warn('跳过无法更新的卡片：' + String(error));
        }
      }

    } catch (error) {
      // 卡片刷新失败不影响日程保存，界面已有独立的保存失败提示。
      console.warn('同步桌面卡片失败：' + String(error));
    }
  }

  // 每次推送前都与系统运行中的卡片对账：
  // 注册表可能因覆盖安装、进程重启而漏掉某个实例（那张卡就只能等系统重新绑定才更新），
  // 补齐缺失项、剔除已被移除的实例，保证桌面上每一张卡都收到这次推送。
  private static async reconciled(context: common.Context): Promise<FormRecord[]> {
    const records: FormRecord[] = await FormBoard.records(context);
    try {
      const running: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos();
      if (running.length === 0) return records;
      const found: FormRecord[] = [];
      let changed: boolean = false;
      for (const info of running) {
        const existing = records.find((item: FormRecord): boolean => item.formId === info.formId);
        if (existing) {
          found.push(existing);
          continue;
        }
        const record = new FormRecord();
        record.formId = info.formId;
        record.dimension = FormSync.dimensionText(info.dimension);
        found.push(record);
        changed = true;
      }
      // 记录里多出来的实例说明卡片已被移除，一并清理。
      if (found.length !== records.length) changed = true;
      if (changed) await FormBoard.replace(context, found);
      return found;
    } catch (error) {
      console.warn('无法枚举已添加的卡片，按本地登记推送：' + String(error));
      return records;
    }
  }

  private static dimensionText(dimension: formInfo.FormDimension): string {
    if (dimension === formInfo.FormDimension.Dimension_4_4) return '4*4';
    if (dimension === formInfo.FormDimension.Dimension_2_4) return '2*4';
    if (dimension === formInfo.FormDimension.Dimension_1_2) return '1*2';
    return '2*2';
  }
}
