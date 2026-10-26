// 桌面日程卡片的提供方：负责创建、刷新、移除卡片实例。
// 卡片进程只在生命周期回调期间存活（回调后约 10 秒退出），因此这里只做读取与推送，
// 需要长时间处理的动作交给主应用；主应用保存日程后会主动调用 formProvider.updateForm。
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Configuration, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { buildCardData, CardSize, cardSizeForRect } from '../services/CardData';
import { CardSnapshot } from '../services/CardSnapshot';
import { CardWriter } from '../services/CardWriter';
import { FormBoard, FormRecord } from '../services/FormBoard';
import { AppData } from '../model/PlanerModel';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryFormAbility';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const dimension: string = this.dimensionText(want);
    const formId: string = this.formIdText(want);
    if (formId) {
      // 桌面长按图标打开卡片列表时会为该卡片调用 onAddForm，先登记，主应用之后即可推送。
      FormBoard.upsert(this.context, formId, dimension).catch((error: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, '登记卡片失败：%{public}s', JSON.stringify(error));
      });
    }
    return this.payload(dimension);
  }

  onUpdateForm(formId: string): void {
    this.refresh(formId);
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, '卡片事件：%{public}s %{public}s', formId, message);
    this.handleEvent(formId, message).catch((error: BusinessError): void => {
      hilog.error(DOMAIN, TAG, '处理卡片事件失败：%{public}s', JSON.stringify(error));
    });
  }

  onRemoveForm(formId: string): void {
    FormBoard.remove(this.context, formId).catch((error: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, '注销卡片失败：%{public}s', JSON.stringify(error));
    });
  }

  // 深浅色或字号等配置变化时，已添加的卡片需要重新取色。
  onConfigurationUpdate(config: Configuration): void {
    hilog.info(DOMAIN, TAG, '配置更新：%{public}s', JSON.stringify(config.colorMode));
    this.refreshAll();
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  private payload(dimension: string): formBindingData.FormBindingData {
    const size: CardSize = this.sizeOf(dimension);
    const data: AppData = CardSnapshot.load(this.context);
    return formBindingData.createFormBindingData(buildCardData(data, size, this.darkOf(data)));
  }

  // 卡片勾选或刷新：勾选写回文件后同步所有卡片，普通刷新只更新当前实例。
  private async handleEvent(formId: string, message: string): Promise<void> {
    try {
      const parsed: Record<string, Object> = JSON.parse(message) as Record<string, Object>;
      // 事件载荷可能被包在 params 里下发，两种形态都接受，避免因封装差异静默不响应。
      const nested = parsed ? parsed['params'] : undefined;
      const body: Record<string, Object> = nested && typeof nested === 'object' ?
        nested as Record<string, Object> : parsed;
      const action: string = body && typeof body['action'] === 'string' ? body['action'] as string : '';
      const id: string = body && typeof body['id'] === 'string' ? body['id'] as string : '';
      if (action === 'toggle' && id) {
        const changed: boolean = await CardWriter.toggleToday(this.context, id);
        if (changed) {
          // 先保证被点的那张卡片立刻回显，再同步其它实例。
          await this.refresh(formId);
          await this.refreshAll();
        } else {
          // 卡片展示的数据可能已过期（该日程被删除或已归档），刷新一次即可回到最新视图。
          hilog.warn(DOMAIN, TAG, '卡片勾选未命中当日日程：%{public}s', id);
          await this.refresh(formId);
        }
        return;
      }
      if (action === 'completeFuture' && id) {
        const done: boolean = await CardWriter.completeFuture(this.context, id);
        if (!done) hilog.warn(DOMAIN, TAG, '卡片勾选未命中未来日程：%{public}s', id);
        await this.refresh(formId);
        await this.refreshAll();
        return;
      }
    } catch (error) {
      hilog.info(DOMAIN, TAG, '卡片事件不是结构化消息：%{public}s', JSON.stringify(error));
    }
    if (message.indexOf('refresh') >= 0) await this.refresh(formId);
  }

  // 尺寸可能在桌面上被拖拽改变：优先读取卡片实际几何，读不到时回落到登记值。
  private async refresh(formId: string): Promise<void> {
    let dimension: string = '2*2';
    try {
      const records: FormRecord[] = await FormBoard.records(this.context);
      const record = records.find((item: FormRecord): boolean => item.formId === formId);
      if (record) dimension = record.dimension;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, '读取卡片登记失败：%{public}s', JSON.stringify(error));
    }
    try {
      const rect: formInfo.Rect = await formProvider.getFormRect(formId);
      if (rect.width > 0 && rect.height > 0) {
        dimension = this.dimensionFromSize(rect.width, rect.height);
        await FormBoard.upsert(this.context, formId, dimension);
      }
    } catch (error) {
      // 低版本或设备不支持 getFormRect 时沿用登记尺寸，卡片仍可正常刷新。
      hilog.info(DOMAIN, TAG, '无法读取卡片尺寸，沿用登记值：%{public}s', JSON.stringify(error));
    }
    try {
      await formProvider.updateForm(formId, this.payload(dimension));
    } catch (error) {
      hilog.error(DOMAIN, TAG, '刷新卡片失败：%{public}s', JSON.stringify(error));
    }
  }

  private async refreshAll(): Promise<void> {
    try {
      const records: FormRecord[] = await FormBoard.records(this.context);
      for (const record of records) {
        await this.refresh(record.formId);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, '批量刷新卡片失败：%{public}s', JSON.stringify(error));
    }
  }

  // 深浅色优先跟应用内主题设置；只有“跟随系统”时才读系统颜色模式。
  // 扩展进程拿到的是系统值，直接用它会让卡片与主应用的手动浅色 / 深色设置不一致。
  private darkOf(data: AppData): boolean {
    const mode: string = data.settings.themeMode;
    if (mode === 'dark') return true;
    if (mode === 'light') return false;
    try {
      return this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (error) {
      return false;
    }
  }

  private sizeOf(dimension: string): CardSize {
    const width: number = parseInt(dimension.split('*')[1], 10);
    if (dimension === '4*4' || dimension === '6*4') return CardSize.LARGE;
    if (!isNaN(width) && width >= 3) return CardSize.MEDIUM;
    return CardSize.SMALL;
  }

  private dimensionFromSize(width: number, height: number): string {
    const size: CardSize = cardSizeForRect(width, height);
    if (size === CardSize.LARGE) return '4*4';
    if (size === CardSize.MEDIUM) return '2*4';
    return '2*2';
  }

  // Want 中的尺寸是 FormDimension 枚举值，转换失败时按默认中卡处理。
  private dimensionText(want: Want): string {
    const raw: Object | undefined = want.parameters ? want.parameters[formInfo.FormParam.DIMENSION_KEY] : undefined;
    let value: number = formInfo.FormDimension.Dimension_2_2 as number;
    if (typeof raw === 'number') value = raw;
    else if (typeof raw === 'string') value = parseInt(raw, 10);
    if (value === (formInfo.FormDimension.Dimension_4_4 as number)) return '4*4';
    if (value === (formInfo.FormDimension.Dimension_2_4 as number)) return '2*4';
    if (value === (formInfo.FormDimension.Dimension_1_2 as number)) return '1*2';
    return '2*2';
  }

  private formIdText(want: Want): string {
    const raw: Object | undefined = want.parameters ? want.parameters[formInfo.FormParam.IDENTITY_KEY] : undefined;
    return typeof raw === 'string' ? raw : '';
  }
}
