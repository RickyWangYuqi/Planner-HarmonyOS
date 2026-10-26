// 卡片注册表：卡片扩展与主应用分属两个进程，通过同一份用户首选项共享 formId。
// 主应用侧据此推送最新日程，卡片扩展侧在添加 / 移除 / 改尺寸时维护记录。
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export class FormRecord {
  formId: string = '';
  dimension: string = '';
}

const STORE_NAME: string = 'planer_forms';
const KEY_RECORDS: string = 'records';

function parseRecords(raw: string): FormRecord[] {
  const result: FormRecord[] = [];
  if (!raw) return result;
  try {
    const parsed = JSON.parse(raw) as FormRecord[];
    if (!Array.isArray(parsed)) return result;
    parsed.forEach((item: FormRecord): void => {
      if (item && typeof item.formId === 'string' && item.formId.length > 0) {
        const record = new FormRecord();
        record.formId = item.formId;
        record.dimension = typeof item.dimension === 'string' ? item.dimension : '2*2';
        result.push(record);
      }
    });
  } catch (error) {
    console.warn('卡片注册表格式失效，按空列表处理。');
  }
  return result;
}

export class FormBoard {
  private static async open(context: common.Context): Promise<preferences.Preferences> {
    try {
      // 卡片扩展与主应用是两个进程，必须用应用级 context 才能落到同一份首选项。
      return await preferences.getPreferences(context.getApplicationContext(), { name: STORE_NAME });
    } catch (error) {
      throw new Error('打开卡片注册表失败：' + String(error));
    }
  }

  static async records(context: common.Context): Promise<FormRecord[]> {
    try {
      const store = await FormBoard.open(context);
      const value = await store.get(KEY_RECORDS, '');
      return parseRecords(typeof value === 'string' ? value : '');
    } catch (error) {
      console.warn('读取卡片注册表失败：' + String(error));
      return [];
    }
  }

  private static async write(context: common.Context, records: FormRecord[]): Promise<void> {
    try {
      const store = await FormBoard.open(context);
      await store.put(KEY_RECORDS, JSON.stringify(records));
      await store.flush();
    } catch (error) {
      throw new Error('写入卡片注册表失败：' + String(error));
    }
  }

  // 添加与改尺寸共用同一入口：同 formId 只保留一条记录。
  static async upsert(context: common.Context, formId: string, dimension: string): Promise<void> {
    if (!formId) return;
    const records = await FormBoard.records(context);
    const existing = records.find((item: FormRecord): boolean => item.formId === formId);
    if (existing) {
      existing.dimension = dimension || existing.dimension;
    } else {
      const record = new FormRecord();
      record.formId = formId;
      record.dimension = dimension || '2*2';
      records.push(record);
    }
    await FormBoard.write(context, records);
  }

  static async remove(context: common.Context, formId: string): Promise<void> {
    const records = await FormBoard.records(context);
    const rest = records.filter((item: FormRecord): boolean => item.formId !== formId);
    if (rest.length === records.length) return;
    await FormBoard.write(context, rest);
  }

  // 供对账使用：一次写入整份清单，避免逐条 upsert 反复读写首选项。
  static async replace(context: common.Context, records: FormRecord[]): Promise<void> {
    await FormBoard.write(context, records);
  }
}
